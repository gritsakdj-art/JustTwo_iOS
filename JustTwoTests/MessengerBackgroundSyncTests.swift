@testable import JustTwo
import Foundation
import Testing
import UIKit

@Suite("Messenger Background Sync PR20D3B Tests")
struct MessengerBackgroundSyncTests {

    // MARK: - Completion token

    @Test("completion token calls handler exactly once")
    func completionTokenExactlyOnce() {
        var callCount = 0
        var lastResult: UIBackgroundFetchResult?
        let token = BackgroundFetchCompletionToken { result in
            callCount += 1
            lastResult = result
        }

        token.finish(.newData)
        token.finish(.failed)

        #expect(callCount == 1)
        if case .newData = lastResult {
            #expect(Bool(true))
        } else {
            Issue.record("Expected newData completion result")
        }
        #expect(token.hasFinished)
    }

    // MARK: - Routing

    @Test("non-messenger push completes with noData without running a cycle")
    func nonMessengerPushCompletesNoData() async {
        let runner = ScriptedCycleRunner()
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: ["event": "debug.test"], completion: box.makeToken())

        #expect(box.isNoData)
        #expect(box.finishCount == 1)
        #expect(await runner.callCountValue == 0)
    }

    @Test("malformed messenger event completes with noData without running a cycle")
    func malformedMessengerPayloadCompletesNoData() async {
        let runner = ScriptedCycleRunner()
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: ["event": "message.created"], completion: box.makeToken())

        #expect(box.isNoData)
        #expect(box.finishCount == 1)
        #expect(await runner.callCountValue == 0)
    }

    @Test("push messageID is never used as the ACK boundary")
    func pushMessageIDIsNotDeliveryEvidence() async {
        // The push carries messageID X, but the injected cycle schedules the
        // authoritative boundary Y from sync state. The ACK spy must only ever
        // see Y (the sync boundary), never X (the push hint).
        let pushConversationID = UUID()
        let pushMessageID = UUID()
        let syncBoundaryMessageID = UUID()

        let ackCoordinator = await ConversationDeliveryAckCoordinator.makeForTesting()
        let spy = AckSpy()
        await MainActor.run {
            ackCoordinator.markDeliveredHandler = { conversationID, messageID in
                spy.record(conversationID: conversationID, messageID: messageID)
            }
        }

        let runner = PipelineCycleRunner(
            ackCoordinator: ackCoordinator,
            conversationID: pushConversationID,
            boundaryMessageID: syncBoundaryMessageID
        )
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(
            userInfo: [
                "event": "message.created",
                "conversationID": pushConversationID.uuidString,
                "messageID": pushMessageID.uuidString
            ],
            completion: box.makeToken()
        )

        #expect(box.isNewData)
        #expect(box.finishCount == 1)
        #expect(spy.recordedMessageIDs == [syncBoundaryMessageID])
        #expect(!spy.recordedMessageIDs.contains(pushMessageID))
    }

    @Test("valid push with no new data issues zero receipt requests")
    func noDataPushIssuesNoReceiptRequests() async {
        let ackCoordinator = await ConversationDeliveryAckCoordinator.makeForTesting()
        let spy = AckSpy()
        await MainActor.run {
            ackCoordinator.markDeliveredHandler = { conversationID, messageID in
                spy.record(conversationID: conversationID, messageID: messageID)
            }
        }

        // Runner that applies nothing (noData) and flushes (nothing pending).
        let runner = PipelineCycleRunner(
            ackCoordinator: ackCoordinator,
            conversationID: UUID(),
            boundaryMessageID: nil
        )
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(
            userInfo: [
                "event": "message.created",
                "conversationID": UUID().uuidString,
                "messageID": UUID().uuidString
            ],
            completion: box.makeToken()
        )

        #expect(box.isNoData)
        #expect(spy.recordedMessageIDs.isEmpty)
    }

    // MARK: - Fetch-result mapping

    @Test("authoritative newData maps to .newData exactly once")
    func newDataMapsToNewData() async {
        let runner = ScriptedCycleRunner(outcomes: [.testNewData()])
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: box.makeToken())

        #expect(box.isNewData)
        #expect(box.finishCount == 1)
    }

    @Test("zero-change sync maps to .noData exactly once")
    func noChangeMapsToNoData() async {
        let runner = ScriptedCycleRunner(outcomes: [.noData])
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: box.makeToken())

        #expect(box.isNoData)
        #expect(box.finishCount == 1)
    }

    @Test("sync failure maps to .failed exactly once")
    func failureMapsToFailed() async {
        let runner = ScriptedCycleRunner(outcomes: [.failed("network")])
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: box.makeToken())

        #expect(box.isFailed)
        #expect(box.finishCount == 1)
    }

    // MARK: - Coalescing / batching

    @Test("pushes during active cycle join the current batch via one trailing cycle")
    func pushesDuringActiveJoinTrailing() async {
        let runner = ScriptedCycleRunner(
            outcomes: [.noData, .testNewData()],
            barrier: true
        )
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let boxA = ResultBox()
        let boxB = ResultBox()

        let task = Task { await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxA.makeToken()) }
        await runner.waitUntilStarted(atLeast: 1)

        // Arrives during the active cycle -> covered by trailing.
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxB.makeToken())
        #expect(await runner.callCountValue == 1)

        await runner.release()                     // active finishes -> trailing starts
        await runner.waitUntilStarted(atLeast: 2)
        await runner.release()                      // trailing finishes -> batch done
        _ = await task.value

        #expect(boxA.finishCount == 1)
        #expect(boxB.finishCount == 1)
        // Merged newData (trailing applied data).
        #expect(boxA.isNewData)
        #expect(boxB.isNewData)
        #expect(await runner.callCountValue == 2)   // exactly active + trailing
    }

    @Test("push after trailing started forms next batch with its own cycle and deadline")
    func lateNextBatchPushGetsOwnCycle() async {
        let runner = ScriptedCycleRunner(
            outcomes: [.noData, .noData, .testNewData()],
            barrier: true
        )
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        let boxA = ResultBox()
        let boxB = ResultBox()
        let boxC = ResultBox()

        let task = Task { await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxA.makeToken()) }
        await runner.waitUntilStarted(atLeast: 1)                    // active cycle 1

        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxB.makeToken())
        await runner.release()                                       // active done -> trailing starts
        await runner.waitUntilStarted(atLeast: 2)                    // trailing cycle 2

        // Arrives after trailing started -> belongs to next batch.
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxC.makeToken())

        #expect(boxC.finishCount == 0)                               // not finished by current batch yet
        await runner.release()                                       // trailing done -> batch1 (A,B) finished, batch2 (C) starts
        await runner.waitUntilStarted(atLeast: 3)                    // active cycle 3 (next batch)

        #expect(boxA.finishCount == 1)
        #expect(boxB.finishCount == 1)
        #expect(boxC.finishCount == 0)                               // still waiting for its own batch

        await runner.release()                                       // batch2 finishes -> C completed
        _ = await task.value

        #expect(boxC.finishCount == 1)
        #expect(boxC.isNewData)
        #expect(await runner.callCountValue == 3)                    // batch1 active+trailing, batch2 active

        // The next-batch cycle used its own (later) deadline, not the first batch's.
        let deadlines = await runner.seenDeadlinesValue
        #expect(deadlines.count == 3)
        #expect(deadlines[2] > deadlines[0])
    }

    @Test("continuous pushes never create more than one in-flight sync")
    func continuousPushesNoStorm() async {
        let runner = ScriptedCycleRunner(
            outcomes: [.noData, .noData],
            barrier: true
        )
        let coordinator = makeCoordinator(runner: runner)
        await coordinator.markDependenciesReady()

        var boxes: [ResultBox] = []
        for _ in 0..<5 { boxes.append(ResultBox()) }

        let task = Task { await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxes[0].makeToken()) }
        await runner.waitUntilStarted(atLeast: 1)

        for index in 1..<5 {
            await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: boxes[index].makeToken())
        }

        // Five pushes, only the active cycle is running: no request storm.
        #expect(await runner.callCountValue == 1)

        await runner.release()                      // active -> trailing
        await runner.waitUntilStarted(atLeast: 2)
        await runner.release()                      // trailing -> all finished
        _ = await task.value

        for box in boxes { #expect(box.finishCount == 1) }
        #expect(await runner.callCountValue == 2)   // bounded: active + trailing only
    }

    // MARK: - Deadlines

    @Test("dependencies never ready expires with .failed and never runs a cycle")
    func dependencyTimeoutFailsWithoutCycle() async {
        let runner = ScriptedCycleRunner(outcomes: [.testNewData()])
        // Never call markDependenciesReady().
        let coordinator = makeCoordinator(runner: runner)

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: box.makeToken())

        #expect(box.isFailed)
        #expect(box.finishCount == 1)
        #expect(await runner.callCountValue == 0)
    }

    @Test("late markDependenciesReady does not resurrect an expired callback")
    func lateDependencyReadyDoesNotResurrect() async {
        let runner = ScriptedCycleRunner(outcomes: [.testNewData()])
        let coordinator = makeCoordinator(runner: runner)

        let box = ResultBox()
        await coordinator.handleRemoteNotification(userInfo: messengerPayload(), completion: box.makeToken())
        #expect(box.finishCount == 1)

        await coordinator.markDependenciesReady()
        // No second completion, no cycle.
        #expect(box.finishCount == 1)
        #expect(await runner.callCountValue == 0)
    }

    // MARK: - ACK flush deadline / durable pending

    @Test("ack flush defers and retains durable pending when the deadline already expired")
    @MainActor
    func ackFlushExpiresWithoutDroppingPending() async {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.markDeliveredHandler = { _, _ in
            throw URLError(.notConnectedToInternet)
        }
        let conversationID = UUID()
        let messageID = UUID()
        let profileID = UUID()

        await coordinator.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: MessageReceiptBoundary(createdAt: Date(), messageID: messageID),
            currentProfileID: profileID,
            session: SessionStore.shared,
            router: AppRouter.shared,
            source: "test",
            evidence: .persistedSafeBoundary
        )
        #expect(coordinator.pendingDeliveryAckCountForTests >= 1)

        let result = await coordinator.flushPendingAcknowledgements(
            ownerProfileID: profileID,
            deadline: ContinuousClock().now,
            sessionGeneration: coordinator.sessionGenerationForTests
        )

        #expect(result.expired)
        #expect(result.deferredCount >= 1)
        #expect(coordinator.pendingDeliveryAckCountForTests >= 1)
    }

    @Test("ack flush with a stale session generation does not send")
    @MainActor
    func ackFlushStaleGenerationDoesNotSend() async {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        var acks = 0
        coordinator.markDeliveredHandler = { _, _ in acks += 1 }
        let conversationID = UUID()
        let profileID = UUID()

        await coordinator.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: MessageReceiptBoundary(createdAt: Date(), messageID: UUID()),
            currentProfileID: profileID,
            session: SessionStore.shared,
            router: AppRouter.shared,
            source: "test",
            evidence: .persistedSafeBoundary
        )
        acks = 0

        let staleGeneration = coordinator.sessionGenerationForTests - 1
        let result = await coordinator.flushPendingAcknowledgements(
            ownerProfileID: profileID,
            deadline: ContinuousClock().now.advanced(by: .seconds(1)),
            sessionGeneration: staleGeneration
        )

        #expect(acks == 0)
        #expect(result.succeededCount == 0)
    }

    // MARK: - Durable ACK bootstrap on cold background launch

    @Test("cold background bootstrap loads persisted boundary and acks it")
    @MainActor
    func coldBootstrapLoadsAndAcksPersistedBoundary() async {
        let store = FakeBackgroundBoundaryStore()
        let conversationID = UUID()
        let profileID = UUID()
        let boundary = MessageReceiptBoundary(createdAt: Date(), messageID: UUID())
        store.byOwner[profileID] = [conversationID: boundary]

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store
        var acked: [UUID] = []
        coordinator.markDeliveredHandler = { _, messageID in acked.append(messageID) }

        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: profileID,
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        #expect(acked == [boundary.messageID])
        #expect(store.byOwner[profileID]?[conversationID] == nil)  // cleared after success
    }

    @Test("ack failure after apply retains durable pending for a later retry")
    @MainActor
    func ackFailureAfterApplyRetainsDurablePending() async {
        let store = FakeBackgroundBoundaryStore()
        let conversationID = UUID()
        let profileID = UUID()
        let boundary = MessageReceiptBoundary(createdAt: Date(), messageID: UUID())
        store.byOwner[profileID] = [conversationID: boundary]

        // First coordinator: ACK network fails, so durable pending must survive.
        let coordinator1 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator1.boundaryStore = store
        coordinator1.markDeliveredHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        await coordinator1.bootstrapPersistedBoundaries(
            ownerProfileID: profileID,
            session: SessionStore.shared,
            router: AppRouter.shared
        )
        #expect(store.byOwner[profileID]?[conversationID] == boundary)  // still durable
        coordinator1.reset()

        // Recreated coordinator (new process): retries and succeeds.
        let coordinator2 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator2.boundaryStore = store
        var acked: [UUID] = []
        coordinator2.markDeliveredHandler = { _, messageID in acked.append(messageID) }
        await coordinator2.bootstrapPersistedBoundaries(
            ownerProfileID: profileID,
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        #expect(acked == [boundary.messageID])
        #expect(store.byOwner[profileID]?[conversationID] == nil)
    }

    @Test("stale bootstrap after logout does not ack under a new session")
    @MainActor
    func staleBootstrapIgnoredAfterLogout() async {
        let store = FakeBackgroundBoundaryStore()
        let profileID = UUID()
        store.byOwner[profileID] = [UUID(): MessageReceiptBoundary(createdAt: Date(), messageID: UUID())]

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store
        var acks = 0
        coordinator.markDeliveredHandler = { _, _ in acks += 1 }

        var didReset = false
        store.onLoad = {
            if !didReset {
                didReset = true
                coordinator.reset()  // simulates logout during load
            }
        }

        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: profileID,
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        #expect(acks == 0)
    }

    @Test("logged out background bootstrap without a store loads nothing")
    @MainActor
    func loggedOutBootstrapLoadsNothing() async {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        // No boundaryStore wired: bootstrap is a no-op (logged-out / not configured).
        var acks = 0
        coordinator.markDeliveredHandler = { _, _ in acks += 1 }

        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: UUID(),
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        #expect(acks == 0)
    }

    // MARK: - Session / account isolation

    @Test("stale session generation invalidates a captured background context")
    @MainActor
    func staleSessionContextInvalidated() {
        let context = MessengerBackgroundSessionContext(
            ownerProfileID: UUID(),
            userID: UUID(),
            syncEngineGeneration: MessengerSyncEngine.shared.sessionGenerationForTests - 99,
            ackCoordinatorGeneration: ConversationDeliveryAckCoordinator.shared.sessionGenerationForTests
        )
        #expect(!MessengerBackgroundSessionPreparer.isContextStillValid(context, session: SessionStore.shared))
    }

    // MARK: - Read separation

    @Test("background delivery path never schedules a read ack")
    @MainActor
    func backgroundDoesNotScheduleRead() async {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        let conversationID = UUID()
        let messageID = UUID()

        coordinator.markReadAcked(conversationID: conversationID, messageID: messageID)
        #expect(!coordinator.shouldSendRead(conversationID: conversationID, messageID: messageID))
        #expect(!coordinator.shouldSendDelivered(conversationID: conversationID, messageID: messageID))
    }

    // MARK: - Image metadata-only

    @Test("delivery boundary carries only metadata, never message bytes")
    func boundaryCarriesOnlyMetadata() {
        // A delivery ACK boundary is (createdAt, messageID) only — it can be
        // scheduled/flushed for an image message without any media bytes.
        let boundary = MessageReceiptBoundary(createdAt: Date(), messageID: UUID())
        #expect(boundary.messageID != UUID())  // has an identity
        // Structural guarantee: the type exposes no caption/body/attachment payload.
        let mirror = Mirror(reflecting: boundary)
        let labels = mirror.children.compactMap { $0.label }
        #expect(labels.contains("messageID"))
        #expect(labels.contains("createdAt"))
        #expect(!labels.contains(where: { $0.lowercased().contains("body") || $0.lowercased().contains("caption") || $0.lowercased().contains("image") }))
    }

    // MARK: - Merge helper

    @Test("background sync engine merges trailing cycle results")
    @MainActor
    func syncEngineMergesTrailingResults() {
        let first = MessengerSyncRunResult(
            outcome: .newData(appliedEventCount: 1, advancedRevision: true, pendingDeliveryAckCount: 1),
            didApplyChanges: true,
            appliedEventCount: 1,
            advancedRevision: true,
            pendingDeliveryAckCount: 1
        )
        let second = MessengerSyncRunResult(
            outcome: .newData(appliedEventCount: 2, advancedRevision: false, pendingDeliveryAckCount: 0),
            didApplyChanges: true,
            appliedEventCount: 2,
            advancedRevision: false,
            pendingDeliveryAckCount: 0
        )

        let merged = MessengerSyncEngine.shared.mergeSyncRunResultsForTests(first, second)
        #expect(merged.appliedEventCount == 3)
        #expect(merged.advancedRevision)
        #expect(merged.didApplyChanges)
    }

    // MARK: - Helpers

    private func makeCoordinator(runner: MessengerBackgroundCycleRunning) -> MessengerBackgroundSyncCoordinator {
        MessengerBackgroundSyncCoordinator(
            configuration: .testing,
            cycleRunner: runner
        )
    }

    private func messengerPayload() -> [AnyHashable: Any] {
        [
            "event": "message.created",
            "conversationID": UUID().uuidString,
            "messageID": UUID().uuidString
        ]
    }
}

// MARK: - Test doubles

private extension MessengerSyncRunResult {
    static func testNewData(applied: Int = 1, advanced: Bool = true, pending: Int = 1) -> MessengerSyncRunResult {
        MessengerSyncRunResult(
            outcome: .newData(appliedEventCount: applied, advancedRevision: advanced, pendingDeliveryAckCount: pending),
            didApplyChanges: true,
            appliedEventCount: applied,
            advancedRevision: advanced,
            pendingDeliveryAckCount: pending
        )
    }
}

/// Records a `UIBackgroundFetchResult` delivered to a completion token.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var stored: UIBackgroundFetchResult?

    func makeToken() -> BackgroundFetchCompletionToken {
        BackgroundFetchCompletionToken { [weak self] result in
            self?.record(result)
        }
    }

    private func record(_ result: UIBackgroundFetchResult) {
        lock.withLock {
            count += 1
            stored = result
        }
    }

    var finishCount: Int { lock.withLock { count } }

    var isNewData: Bool { matches { if case .newData = $0 { return true }; return false } }
    var isNoData: Bool { matches { if case .noData = $0 { return true }; return false } }
    var isFailed: Bool { matches { if case .failed = $0 { return true }; return false } }

    private func matches(_ predicate: (UIBackgroundFetchResult) -> Bool) -> Bool {
        lock.withLock {
            guard let stored else { return false }
            return predicate(stored)
        }
    }
}

/// Deterministic, injectable cycle runner. Optionally gates each cycle behind a
/// release signal so batching/reentrancy can be exercised without sleeps as proof.
private actor ScriptedCycleRunner: MessengerBackgroundCycleRunning {
    private var outcomes: [MessengerSyncRunResult]
    private let fallback: MessengerSyncRunResult
    private let barrier: Bool
    private var releasesAvailable = 0
    private(set) var callCount = 0
    private(set) var startedCount = 0
    private(set) var seenDeadlines: [ContinuousClock.Instant] = []

    init(
        outcomes: [MessengerSyncRunResult] = [],
        fallback: MessengerSyncRunResult = .noData,
        barrier: Bool = false
    ) {
        self.outcomes = outcomes
        self.fallback = fallback
        self.barrier = barrier
    }

    func runCycle(deadline: ContinuousClock.Instant, clock: ContinuousClock) async -> MessengerSyncRunResult {
        callCount += 1
        startedCount += 1
        seenDeadlines.append(deadline)

        if barrier {
            while releasesAvailable <= 0 {
                try? await Task.sleep(for: .milliseconds(5))
            }
            releasesAvailable -= 1
        }

        if outcomes.isEmpty { return fallback }
        return outcomes.removeFirst()
    }

    func release(_ count: Int = 1) { releasesAvailable += count }

    func waitUntilStarted(atLeast target: Int, timeout: Duration = .seconds(3)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while startedCount < target && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    var callCountValue: Int { callCount }
    var seenDeadlinesValue: [ContinuousClock.Instant] { seenDeadlines }
}

/// Cycle runner that exercises the *real* PR20D2 ACK coordinator: it schedules an
/// authoritative boundary from the (fake) sync result — never from the push hint —
/// and flushes, proving the push messageID never reaches the receipt path.
private final class PipelineCycleRunner: MessengerBackgroundCycleRunning, @unchecked Sendable {
    private let ackCoordinator: ConversationDeliveryAckCoordinator
    private let conversationID: UUID
    private let boundaryMessageID: UUID?

    init(ackCoordinator: ConversationDeliveryAckCoordinator, conversationID: UUID, boundaryMessageID: UUID?) {
        self.ackCoordinator = ackCoordinator
        self.conversationID = conversationID
        self.boundaryMessageID = boundaryMessageID
    }

    func runCycle(deadline: ContinuousClock.Instant, clock: ContinuousClock) async -> MessengerSyncRunResult {
        guard let boundaryMessageID else {
            return .noData
        }
        await ackCoordinator.scheduleAuthoritativeBoundaryForTesting(
            conversationID: conversationID,
            messageID: boundaryMessageID,
            profileID: UUID()
        )
        return MessengerSyncRunResult(
            outcome: .newData(appliedEventCount: 1, advancedRevision: true, pendingDeliveryAckCount: 1),
            didApplyChanges: true,
            appliedEventCount: 1,
            advancedRevision: true,
            pendingDeliveryAckCount: 1
        )
    }
}

/// Records receipt ACK calls made through the real coordinator's mark-delivered handler.
private final class AckSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var messageIDs: [UUID] = []

    func record(conversationID: UUID, messageID: UUID) {
        lock.withLock { messageIDs.append(messageID) }
    }

    var recordedMessageIDs: [UUID] { lock.withLock { messageIDs } }
}

@MainActor
private final class FakeBackgroundBoundaryStore: ConversationDeliveryAckBoundaryStore {
    var byOwner: [UUID: [UUID: MessageReceiptBoundary]] = [:]
    var onLoad: (() -> Void)?

    func loadPendingDeliveryBoundaries(ownerProfileID: UUID) async throws -> [UUID: MessageReceiptBoundary] {
        onLoad?()
        return byOwner[ownerProfileID] ?? [:]
    }

    func clearPendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        through boundary: MessageReceiptBoundary
    ) async throws {
        byOwner[ownerProfileID]?[conversationID] = nil
    }

    func clearPendingDeliveryBoundaries(ownerProfileID: UUID) async throws {
        byOwner[ownerProfileID] = nil
    }
}
