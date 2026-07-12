import Foundation
import UIKit

/// Orchestrates best-effort messenger reconciliation after hybrid or silent
/// background-capable pushes (PR20D3B). Reuses the authoritative PR20D2 delta-sync
/// and delivery-ACK pipeline; never ACKs directly from push payload hints.
///
/// Concurrency model:
/// - Pushes are grouped into *batches* (cohorts). A batch has at most one active
///   plus one trailing sync cycle.
/// - A push arriving before the trailing cycle starts joins the current batch and
///   is covered by its trailing cycle. A push arriving after the trailing cycle has
///   started forms the *next* batch and is never completed by the current batch.
/// - Exactly one sync runs globally at a time; batches drain sequentially.
/// - Each callback carries its own absolute deadline (`receivedAt + operationDeadline`).
///   A batch uses the earliest waiter deadline; a promoted next batch keeps its own
///   (later) deadline rather than inheriting the previous, possibly expired, one.
actor MessengerBackgroundSyncCoordinator {

    static let shared = MessengerBackgroundSyncCoordinator()

    private let parser: PushNotificationPayloadParser
    private let clock: ContinuousClock
    private var configuration: MessengerBackgroundSyncConfiguration
    private let cycleRunner: MessengerBackgroundCycleRunning
    private var dependenciesReady = false

    private enum Phase {
        case idle
        case active
        case trailing
    }

    private struct Batch {
        let id: UInt64
        var waiters: [BackgroundFetchCompletionToken]
        var deadline: ContinuousClock.Instant
        var pushCount: Int
    }

    private var phase: Phase = .idle
    private var currentBatch: Batch?
    private var pendingBatch: Batch?
    private var currentBatchNeedsTrailing = false
    private var drainInProgress = false
    private var nextBatchID: UInt64 = 0

    init(
        parser: PushNotificationPayloadParser = PushNotificationPayloadParser(),
        clock: ContinuousClock = ContinuousClock(),
        configuration: MessengerBackgroundSyncConfiguration = .production,
        cycleRunner: MessengerBackgroundCycleRunning? = nil
    ) {
        self.parser = parser
        self.clock = clock
        self.configuration = configuration
        self.cycleRunner = cycleRunner
            ?? MessengerBackgroundProductionCycleRunner(ackFlushBudget: configuration.ackFlushSubDeadline)
    }

    func markDependenciesReady() {
        dependenciesReady = true
    }

    #if DEBUG
    func configureForTesting(configuration: MessengerBackgroundSyncConfiguration) {
        self.configuration = configuration
    }
    #endif

    func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        completion: BackgroundFetchCompletionToken
    ) async {
        guard let intent = parser.parseWakeIntent(userInfo: userInfo) else {
            if looksLikeMalformedMessengerPayload(userInfo) {
                MessengerDiagnostics.event(.messengerBackgroundPushMalformed)
            } else {
                MessengerDiagnostics.event(
                    .messengerBackgroundPushIgnored,
                    metadata: ["reason": "nonMessenger"]
                )
            }
            completion.finish(.noData)
            return
        }

        MessengerDiagnostics.event(
            .messengerBackgroundPushReceived,
            conversationID: intent.conversationID,
            messageID: intent.messageID,
            metadata: ["eventType": PushDeliveryEvent.messageCreated, "source": "remoteNotification"]
        )

        let deadline = clock.now.advanced(by: configuration.operationDeadline)
        enqueue(completion, deadline: deadline, intent: intent)

        // Only the first push that finds no drain running services the batches.
        // Concurrent pushes enqueue into the correct cohort during this call's
        // suspension points and return; their tokens are finished by the drain.
        if !drainInProgress {
            await drain()
        }
    }

    // MARK: - Enqueue / cohort assignment

    private func enqueue(
        _ token: BackgroundFetchCompletionToken,
        deadline: ContinuousClock.Instant,
        intent: MessengerBackgroundWakeIntent
    ) {
        switch phase {
        case .idle:
            nextBatchID += 1
            currentBatch = Batch(id: nextBatchID, waiters: [token], deadline: deadline, pushCount: 1)

        case .active:
            // Arrived while the active cycle runs: cover it with a trailing cycle.
            currentBatchNeedsTrailing = true
            currentBatch?.waiters.append(token)
            if let existing = currentBatch?.deadline {
                currentBatch?.deadline = min(existing, deadline)
            }
            currentBatch?.pushCount += 1
            MessengerDiagnostics.event(
                .messengerBackgroundSyncCoalesced,
                conversationID: intent.conversationID,
                messageID: intent.messageID
            )

        case .trailing:
            // Arrived after the trailing cycle started: it belongs to the next batch
            // and must not be completed by the current batch result.
            appendToPendingBatch(token, deadline: deadline)
            MessengerDiagnostics.event(
                .messengerBackgroundSyncNextBatchQueued,
                conversationID: intent.conversationID,
                messageID: intent.messageID
            )
        }
    }

    private func appendToPendingBatch(
        _ token: BackgroundFetchCompletionToken,
        deadline: ContinuousClock.Instant
    ) {
        if pendingBatch == nil {
            nextBatchID += 1
            pendingBatch = Batch(id: nextBatchID, waiters: [token], deadline: deadline, pushCount: 1)
        } else {
            pendingBatch?.waiters.append(token)
            if let existing = pendingBatch?.deadline {
                pendingBatch?.deadline = min(existing, deadline)
            }
            pendingBatch?.pushCount += 1
        }
    }

    // MARK: - Drain loop

    private func drain() async {
        guard !drainInProgress else { return }
        drainInProgress = true
        defer { drainInProgress = false }

        while currentBatch != nil {
            let batchID = currentBatch?.id ?? 0
            currentBatchNeedsTrailing = false
            phase = .active
            MessengerDiagnostics.event(
                .messengerBackgroundSyncBatchStarted,
                metadata: ["batchID": "\(batchID)"]
            )
            MessengerDiagnostics.event(.messengerBackgroundSyncStarted)

            var result = await runCycle(deadline: currentBatchDeadline())

            if currentBatchNeedsTrailing, !isTerminalFailure(result) {
                phase = .trailing
                currentBatchNeedsTrailing = false
                MessengerDiagnostics.event(.messengerBackgroundSyncTrailingRequested)
                let trailing = await runCycle(deadline: currentBatchDeadline())
                result = mergeResults(result, trailing)
            }

            // Capture the batch (including any waiters appended during the active
            // cycle, which are covered by this batch/trailing) and finish it.
            guard let finished = currentBatch else { break }
            currentBatch = nil
            phase = .idle
            finishBatch(finished, with: result)

            // Promote the next batch, if any, honoring its own deadline.
            if let pending = pendingBatch {
                pendingBatch = nil
                if clock.now >= pending.deadline {
                    expireBatch(pending)
                } else {
                    currentBatch = pending
                }
            }
        }
    }

    private func currentBatchDeadline() -> ContinuousClock.Instant {
        currentBatch?.deadline ?? clock.now
    }

    private func runCycle(deadline: ContinuousClock.Instant) async -> MessengerSyncRunResult {
        let readinessDeadline = min(deadline, clock.now.advanced(by: configuration.dependencyReadinessDeadline))
        guard await waitForDependencies(until: readinessDeadline, absoluteDeadline: deadline) else {
            MessengerDiagnostics.event(
                .messengerBackgroundDependenciesUnavailable,
                metadata: ["reason": "readinessDeadlineExceeded"]
            )
            return .failed("dependenciesUnavailable")
        }

        if clock.now >= deadline {
            MessengerDiagnostics.event(.messengerBackgroundSyncExpired)
            return .failed("expiredBeforeSync")
        }

        let result = await cycleRunner.runCycle(deadline: deadline, clock: clock)

        if case .failed(let reason) = result.outcome {
            MessengerDiagnostics.event(
                .messengerBackgroundSyncFailed,
                metadata: ["reason": reason]
            )
        }

        return result
    }

    private func waitForDependencies(
        until readinessDeadline: ContinuousClock.Instant,
        absoluteDeadline: ContinuousClock.Instant
    ) async -> Bool {
        if dependenciesReady { return true }

        MessengerDiagnostics.event(.messengerBackgroundSyncQueued)

        let effectiveDeadline = min(readinessDeadline, absoluteDeadline)
        while clock.now < effectiveDeadline {
            if dependenciesReady { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }

        return dependenciesReady
    }

    // MARK: - Completion

    private func finishBatch(_ batch: Batch, with result: MessengerSyncRunResult) {
        let fetchResult = mapToFetchResult(result.outcome)
        MessengerDiagnostics.event(
            .messengerBackgroundSyncCompleted,
            metadata: [
                "batchID": "\(batch.id)",
                "pushCount": "\(batch.pushCount)",
                "result": fetchResultName(fetchResult)
            ]
        )
        for waiter in batch.waiters where !waiter.hasFinished {
            waiter.finish(fetchResult)
        }
    }

    private func expireBatch(_ batch: Batch) {
        MessengerDiagnostics.event(
            .messengerBackgroundSyncBatchExpired,
            metadata: ["batchID": "\(batch.id)", "pushCount": "\(batch.pushCount)"]
        )
        for waiter in batch.waiters where !waiter.hasFinished {
            waiter.finish(.failed)
        }
    }

    // MARK: - Helpers

    private func looksLikeMalformedMessengerPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        if let event = userInfo["event"] as? String, event == PushDeliveryEvent.messageCreated {
            return true
        }
        if let type = userInfo["type"] as? String, type == PushDeliveryEvent.messageCreated {
            return true
        }
        return false
    }

    private func isTerminalFailure(_ result: MessengerSyncRunResult) -> Bool {
        if case .failed = result.outcome { return true }
        return false
    }

    private func mapToFetchResult(_ outcome: MessengerBackgroundSyncRunOutcome) -> UIBackgroundFetchResult {
        switch outcome {
        case .newData:
            return .newData
        case .noData:
            return .noData
        case .failed:
            return .failed
        }
    }

    private func mergeResults(
        _ first: MessengerSyncRunResult,
        _ second: MessengerSyncRunResult
    ) -> MessengerSyncRunResult {
        if case .failed(let reason) = first.outcome { return .failed(reason) }
        if case .failed(let reason) = second.outcome { return .failed(reason) }

        let applied = first.appliedEventCount + second.appliedEventCount
        let advanced = first.advancedRevision || second.advancedRevision
        let pending = max(first.pendingDeliveryAckCount, second.pendingDeliveryAckCount)
        let didApply = first.didApplyChanges || second.didApplyChanges

        let outcome: MessengerBackgroundSyncRunOutcome = didApply
            ? .newData(appliedEventCount: applied, advancedRevision: advanced, pendingDeliveryAckCount: pending)
            : .noData

        return MessengerSyncRunResult(
            outcome: outcome,
            didApplyChanges: didApply,
            appliedEventCount: applied,
            advancedRevision: advanced,
            pendingDeliveryAckCount: pending
        )
    }

    private func fetchResultName(_ result: UIBackgroundFetchResult) -> String {
        switch result {
        case .newData: return "newData"
        case .noData: return "noData"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }
}

/// Production reconciliation cycle: reuses the authoritative PR20D2 pipeline and
/// singletons. Bounded by the shared absolute `deadline`.
struct MessengerBackgroundProductionCycleRunner: MessengerBackgroundCycleRunning {
    let ackFlushBudget: Duration

    func runCycle(
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) async -> MessengerSyncRunResult {
        await MessengerBackgroundSyncExecutor.performCycle(
            operationDeadline: deadline,
            ackFlushDuration: ackFlushBudget,
            clock: clock
        )
    }
}

@MainActor
private enum MessengerBackgroundSyncExecutor {
    static func performCycle(
        operationDeadline: ContinuousClock.Instant,
        ackFlushDuration: Duration,
        clock: ContinuousClock
    ) async -> MessengerSyncRunResult {
        let session = SessionStore.shared
        let router = AppRouter.shared

        guard let context = await MessengerBackgroundSessionPreparer.prepare(session: session) else {
            if APIAuth.accessToken == nil {
                MessengerDiagnostics.event(
                    .messengerBackgroundPushIgnored,
                    metadata: ["reason": "loggedOut"]
                )
                return .noData
            }
            return .failed("sessionUnavailable")
        }

        if NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline {
            MessengerDiagnostics.event(
                .messengerBackgroundSyncFailed,
                metadata: ["reason": "offline"]
            )
            return .failed("offline")
        }

        if clock.now >= operationDeadline {
            MessengerDiagnostics.event(.messengerBackgroundSyncExpired)
            return .failed("expiredBeforeSync")
        }

        let syncResult = await MessengerSyncEngine.shared.runGlobalSyncForBackground(
            session: session,
            router: router
        )

        guard MessengerBackgroundSessionPreparer.isContextStillValid(context, session: session) else {
            MessengerDiagnostics.event(
                .messengerBackgroundSessionStale,
                metadata: ["phase": "afterSync"]
            )
            return .failed("staleSession")
        }

        if case .failed = syncResult.outcome {
            return syncResult
        }

        // Load durably persisted proven-safe boundaries for this owner before the
        // ACK flush so a cold background launch (no prior chat open) can still ACK.
        await ConversationDeliveryAckCoordinator.shared.bootstrapPersistedBoundaries(
            ownerProfileID: context.ownerProfileID,
            session: session,
            router: router
        )

        guard MessengerBackgroundSessionPreparer.isContextStillValid(context, session: session) else {
            MessengerDiagnostics.event(
                .messengerBackgroundSessionStale,
                metadata: ["phase": "afterBootstrap"]
            )
            // Data was applied/committed; the durable pending boundary is retained
            // and will be replayed later. Report the sync result rather than failing.
            return syncResult
        }

        if clock.now < operationDeadline {
            let ackCandidate = clock.now.advanced(by: ackFlushDuration)
            let ackDeadline = ackCandidate < operationDeadline ? ackCandidate : operationDeadline
            _ = await ConversationDeliveryAckCoordinator.shared.flushPendingAcknowledgements(
                ownerProfileID: context.ownerProfileID,
                deadline: ackDeadline,
                sessionGeneration: context.ackCoordinatorGeneration
            )
        }

        return syncResult
    }
}
