import Foundation

@MainActor
@Observable
final class MessengerSyncEngine {

    static let shared = MessengerSyncEngine()

    private(set) var state: MessengerSyncEngineState = .idle

    private let deltaSync: MessengerDeltaSyncService
    private let syncState: MessengerSyncStateStore
    private let conversationList: ConversationListViewModel
    private let realtimeCoordinator: MessengerRealtimeCoordinator

    private var sessionGeneration = 0
    private var isGlobalSyncInFlight = false
    private var pendingGlobalSync = false
    private var backgroundSyncWaiters: [CheckedContinuation<MessengerSyncRunResult, Never>] = []
    private var failureCount = 0
    private var scheduledBackoffTask: Task<Void, Never>?
    private var networkHandlerID: UUID?
    private var debouncedNetworkTask: Task<Void, Never>?

    private let networkRestoreDebounceMilliseconds = 750

    init(
        deltaSync: MessengerDeltaSyncService? = nil,
        syncState: MessengerSyncStateStore? = nil,
        conversationList: ConversationListViewModel? = nil,
        realtimeCoordinator: MessengerRealtimeCoordinator? = nil
    ) {
        self.deltaSync = deltaSync ?? .shared
        self.syncState = syncState ?? .shared
        self.conversationList = conversationList ?? .shared
        self.realtimeCoordinator = realtimeCoordinator ?? .shared
        self.deltaSync.autoFullRefreshFallback = false
        self.deltaSync.onGlobalCursorAdvanced = { [weak self] revision in
            await self?.handleGlobalCursorAdvanced(revision)
        }
    }

    func activate(session: SessionStore, router: AppRouter) {
        guard networkHandlerID == nil else { return }
        networkHandlerID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleNetworkPathChange(session: session, router: router)
            }
        }
    }

    func deactivate() {
        debouncedNetworkTask?.cancel()
        debouncedNetworkTask = nil
        scheduledBackoffTask?.cancel()
        scheduledBackoffTask = nil
        if let networkHandlerID {
            NetworkPathMonitor.shared.unregisterHandler(networkHandlerID)
            self.networkHandlerID = nil
        }
    }

    func hydrateFromLocalStore() async {
        do {
            guard let metadata = try await localStore.fetchSyncMetadata() else {
                transition(to: .idle)
                return
            }

            syncState.hydrate(
                revision: metadata.lastAppliedRevision,
                lastSyncAt: metadata.lastSuccessfulSyncAt
            )

            if metadata.needsFullRefresh {
                transition(to: .needsFullRefresh)
            } else if let persistedState = metadata.state,
                      let engineState = MessengerSyncEngineState(rawValue: persistedState) {
                transition(to: engineState == .syncing ? .idle : engineState)
            } else {
                transition(to: .idle)
            }

            MessengerDiagnostics.event(
                .syncBootstrapSucceeded,
                metadata: [
                    "oldRevision": metadata.lastAppliedRevision.map { "\($0)" } ?? "none",
                    "state": state.rawValue,
                    "trigger": "hydrate"
                ]
            )
        } catch {
            transition(to: .idle)
            MessengerDiagnostics.event(
                .syncBootstrapFailed,
                metadata: [
                    "errorCode": MessengerDiagnostics.sanitizeError(error),
                    "trigger": "hydrate"
                ]
            )
        }
    }

    func prepareStartupBaselineIfNeeded(
        session: SessionStore,
        router: AppRouter
    ) async -> Int64? {
        guard session.isFullyAuthenticated else { return nil }

        await hydrateFromLocalStore()

        if state == .needsFullRefresh || syncState.currentRevision == nil {
            transition(to: .bootstrapping)
            MessengerDiagnostics.event(.syncBootstrapStarted, metadata: ["trigger": "startup"])

            do {
                let serverState = try await MessengerSyncService.fetchSyncState()
                await persistMetadata(
                    revision: syncState.currentRevision,
                    serverRevision: serverState.revision,
                    attempted: true
                )

                if let localRevision = syncState.currentRevision, localRevision > serverState.revision {
                    transition(to: .needsFullRefresh)
                    MessengerDiagnostics.event(
                        .syncNeedsFullRefresh,
                        metadata: [
                            "reason": "cursorAheadOfServer",
                            "oldRevision": "\(localRevision)",
                            "serverRevision": "\(serverState.revision)"
                        ]
                    )
                    return nil
                }

                let baseline = try await deltaSync.prepareBaselineRevision()
                await persistMetadata(
                    revision: syncState.currentRevision,
                    serverRevision: serverState.revision,
                    bootstrapAt: Date()
                )
                return baseline
            } catch {
                transition(to: .failed)
                await persistMetadata(
                    revision: syncState.currentRevision,
                    errorCode: MessengerDiagnostics.sanitizeError(error),
                    failed: true
                )
                MessengerDiagnostics.event(
                    .syncBootstrapFailed,
                    metadata: [
                        "errorCode": MessengerDiagnostics.sanitizeError(error),
                        "trigger": "startup"
                    ]
                )
                return nil
            }
        }

        await validatePersistedCursorAgainstServer()
        return nil
    }

    func finishBootstrap(revision: Int64) async {
        deltaSync.finishBaseline(revision: revision)
        failureCount = 0
        transition(to: .idle)
        await persistMetadata(
            revision: syncState.currentRevision ?? revision,
            successful: true,
            bootstrapAt: Date()
        )
        MessengerDiagnostics.event(
            .syncBootstrapSucceeded,
            metadata: [
                "newRevision": "\(revision)",
                "trigger": "finishBootstrap"
            ]
        )
    }

    func runGlobalSync(
        reason: MessengerDeltaSyncReason,
        session: SessionStore,
        router: AppRouter
    ) async {
        guard session.isFullyAuthenticated else {
            MessengerDiagnostics.event(
                .syncEngineSkipped,
                metadata: ["reason": "notAuthenticated", "trigger": reason.rawValue]
            )
            return
        }

        if NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline {
            MessengerDiagnostics.event(.syncNetworkUnavailable, metadata: ["trigger": reason.rawValue])
            return
        }

        if isGlobalSyncInFlight {
            pendingGlobalSync = true
            MessengerDiagnostics.event(
                .syncEngineSkipped,
                metadata: ["reason": "alreadyInFlight", "trigger": reason.rawValue]
            )
            return
        }

        let generation = sessionGeneration
        isGlobalSyncInFlight = true
        transition(to: .syncing)
        let startedAt = Date()

        MessengerDiagnostics.event(
            .syncEngineStarted,
            metadata: [
                "trigger": reason.rawValue,
                "oldRevision": syncState.currentRevision.map { "\($0)" } ?? "none",
                "state": state.rawValue
            ]
        )

        defer {
            if generation == sessionGeneration {
                isGlobalSyncInFlight = false
                if state == .syncing {
                    transition(to: .idle)
                }
                if pendingGlobalSync, reason != .backgroundPush {
                    pendingGlobalSync = false
                    Task {
                        await self.runGlobalSync(reason: .appForeground, session: session, router: router)
                    }
                }
                if !backgroundSyncWaiters.isEmpty {
                    fulfillBackgroundSyncWaiters(with: makeSyncRunResult())
                }
            }
        }

        guard generation == sessionGeneration else {
            MessengerDiagnostics.event(.syncGenerationMismatchIgnored, metadata: ["trigger": reason.rawValue])
            return
        }

        if state == .needsFullRefresh || syncState.currentRevision == nil {
            let refreshed = await performFullRefresh(
                reason: reason,
                session: session,
                router: router,
                generation: generation
            )
            guard refreshed, generation == sessionGeneration else { return }
        }

        await persistMetadata(revision: syncState.currentRevision, attempted: true)

        let succeeded = await deltaSync.syncDeltas(
            reason: reason,
            session: session,
            router: router
        )

        guard generation == sessionGeneration else { return }

        if succeeded {
            failureCount = 0
            transition(to: .idle)
            await persistMetadata(
                revision: syncState.currentRevision,
                successful: true
            )
            if deltaSync.lastRunHadMorePages {
                pendingGlobalSync = true
            }
            MessengerDiagnostics.event(
                .syncDeltaPageApplied,
                metadata: [
                    "trigger": reason.rawValue,
                    "newRevision": syncState.currentRevision.map { "\($0)" } ?? "none",
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
        } else {
            await handleSyncFailure(
                error: deltaSync.lastFailureError,
                reason: reason,
                session: session,
                router: router,
                generation: generation
            )
        }
    }

    func repairConversation(
        conversationID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async {
        guard session.isFullyAuthenticated else { return }
        if NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline {
            MessengerDiagnostics.event(.syncNetworkUnavailable, metadata: ["trigger": "conversationRepair"])
            return
        }

        _ = await deltaSync.syncConversationRepair(
            conversationID: conversationID,
            session: session,
            router: router
        )
    }

    /// Background-capable global sync used by PR20D3B push wake reconciliation.
    /// Coalesces with an in-flight foreground sync and performs at most one trailing cycle.
    func runGlobalSyncForBackground(
        session: SessionStore,
        router: AppRouter
    ) async -> MessengerSyncRunResult {
        if isGlobalSyncInFlight {
            return await withCheckedContinuation { continuation in
                backgroundSyncWaiters.append(continuation)
            }
        }

        await runGlobalSync(reason: .backgroundPush, session: session, router: router)
        var result = makeSyncRunResult()

        if pendingGlobalSync {
            pendingGlobalSync = false
            await runGlobalSync(reason: .backgroundPush, session: session, router: router)
            result = mergeSyncRunResults(result, makeSyncRunResult())
        }

        fulfillBackgroundSyncWaiters(with: result)
        return result
    }

    func reset() {
        sessionGeneration += 1
        scheduledBackoffTask?.cancel()
        scheduledBackoffTask = nil
        debouncedNetworkTask?.cancel()
        debouncedNetworkTask = nil
        isGlobalSyncInFlight = false
        pendingGlobalSync = false
        backgroundSyncWaiters.removeAll()
        failureCount = 0
        transition(to: .idle)
        deltaSync.reset()
        deactivate()
    }

    internal var sessionGenerationForTests: Int {
        sessionGeneration
    }

    internal func transitionForTests(_ newState: MessengerSyncEngineState) {
        transition(to: newState)
    }

    internal func mergeSyncRunResultsForTests(
        _ first: MessengerSyncRunResult,
        _ second: MessengerSyncRunResult
    ) -> MessengerSyncRunResult {
        mergeSyncRunResults(first, second)
    }

    private func validatePersistedCursorAgainstServer() async {
        do {
            let serverState = try await MessengerSyncService.fetchSyncState()
            await persistMetadata(
                revision: syncState.currentRevision,
                serverRevision: serverState.revision
            )

            if let localRevision = syncState.currentRevision, localRevision > serverState.revision {
                transition(to: .needsFullRefresh)
                await persistMetadata(
                    revision: localRevision,
                    serverRevision: serverState.revision,
                    needsFullRefresh: true
                )
                MessengerDiagnostics.event(
                    .syncNeedsFullRefresh,
                    metadata: [
                        "reason": "cursorAheadOfServer",
                        "oldRevision": "\(localRevision)",
                        "serverRevision": "\(serverState.revision)"
                    ]
                )
            }
        } catch {
            MessengerDiagnostics.event(
                .syncBootstrapFailed,
                metadata: [
                    "errorCode": MessengerDiagnostics.sanitizeError(error),
                    "trigger": "validatePersistedCursor"
                ]
            )
        }
    }

    private func performFullRefresh(
        reason: MessengerDeltaSyncReason,
        session: SessionStore,
        router: AppRouter,
        generation: Int
    ) async -> Bool {
        transition(to: .needsFullRefresh)
        MessengerDiagnostics.event(
            .syncFullRefreshStarted,
            metadata: ["trigger": reason.rawValue]
        )

        var baselineRevision: Int64?
        do {
            baselineRevision = try await deltaSync.prepareBaselineRevision()
        } catch {
            MessengerDiagnostics.event(
                .syncFullRefreshFailed,
                metadata: [
                    "errorCode": MessengerDiagnostics.sanitizeError(error),
                    "phase": "prepareBaseline"
                ]
            )
            return false
        }

        guard generation == sessionGeneration else { return false }

        await conversationList.refreshFromRealtime(session: session, router: router)
        if let activeChat = realtimeCoordinator.activeChatForDeltaSync {
            await activeChat.refreshFromRealtime(session: session, router: router)
        }

        if let baselineRevision {
            deltaSync.finishBaseline(revision: baselineRevision)
            await persistMetadata(
                revision: baselineRevision,
                successful: true,
                fullRefresh: true,
                bootstrapAt: Date()
            )
        }

        guard generation == sessionGeneration else { return false }

        transition(to: .idle)
        MessengerDiagnostics.event(
            .syncFullRefreshSucceeded,
            metadata: [
                "newRevision": baselineRevision.map { "\($0)" } ?? "none",
                "trigger": reason.rawValue
            ]
        )
        return true
    }

    private func handleSyncFailure(
        error: Error?,
        reason: MessengerDeltaSyncReason,
        session: SessionStore,
        router: AppRouter,
        generation: Int
    ) async {
        failureCount += 1
        let sanitized = error.map { MessengerDiagnostics.sanitizeError($0) } ?? "syncFailed"
        transition(to: .failed)
        await persistMetadata(
            revision: syncState.currentRevision,
            errorCode: sanitized,
            failed: true
        )

        MessengerDiagnostics.event(
            .syncApplyFailed,
            metadata: [
                "errorCode": sanitized,
                "trigger": reason.rawValue,
                "attemptCount": "\(failureCount)"
            ]
        )

        if sanitized == "unauthorized" {
            return
        }

        if error is MessengerSyncEngineError {
            transition(to: .needsFullRefresh)
            await persistMetadata(
                revision: syncState.currentRevision,
                errorCode: sanitized,
                failed: true,
                needsFullRefresh: true
            )
            MessengerDiagnostics.event(.syncNeedsFullRefresh, metadata: ["reason": sanitized])
            _ = await performFullRefresh(
                reason: .fullRefreshFallback,
                session: session,
                router: router,
                generation: generation
            )
            return
        }

        scheduleBackoff(session: session, router: router, generation: generation)
    }

    private func scheduleBackoff(session: SessionStore, router: AppRouter, generation: Int) {
        transition(to: .backoff)
        let delay = MessengerSyncEngineLimits.backoffDelay(forFailureCount: failureCount)
        scheduledBackoffTask?.cancel()
        scheduledBackoffTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard !Task.isCancelled, generation == self.sessionGeneration else { return }
            MessengerDiagnostics.event(
                .syncBackoffScheduled,
                metadata: [
                    "delaySeconds": "\(Int(delay))",
                    "attemptCount": "\(failureCount)"
                ]
            )
            await self.runGlobalSync(reason: .appForeground, session: session, router: router)
        }
    }

    private func handleGlobalCursorAdvanced(_ revision: Int64) async {
        await persistMetadata(revision: revision)
        MessengerDiagnostics.event(
            .syncCursorAdvanced,
            metadata: [
                "newRevision": "\(revision)",
                "state": state.rawValue
            ]
        )
    }

    private func handleNetworkPathChange(session: SessionStore, router: AppRouter) async {
        if NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline {
            MessengerDiagnostics.event(.syncNetworkUnavailable, metadata: ["networkState": "offline"])
            return
        }

        debouncedNetworkTask?.cancel()
        debouncedNetworkTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(networkRestoreDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            await self.runGlobalSync(reason: .appForeground, session: session, router: router)
        }
    }

    private func transition(to newState: MessengerSyncEngineState) {
        guard state != newState else { return }
        state = newState
        Task {
            await persistMetadata(revision: syncState.currentRevision, engineState: newState)
        }
        MessengerDiagnostics.event(
            .syncStateChanged,
            metadata: ["state": newState.rawValue]
        )
    }

    private func persistMetadata(
        revision: Int64?,
        serverRevision: Int64? = nil,
        engineState: MessengerSyncEngineState? = nil,
        errorCode: String? = nil,
        attempted: Bool = false,
        successful: Bool = false,
        failed: Bool = false,
        fullRefresh: Bool = false,
        bootstrapAt: Date? = nil,
        needsFullRefresh: Bool? = nil
    ) async {
        let now = Date()
        let existing = try? await localStore.fetchSyncMetadata()

        let snapshot = LocalMessengerSyncMetadataSnapshot(
            id: MessengerPersistence.syncMetadataGlobalID,
            lastAppliedRevision: revision ?? existing?.lastAppliedRevision,
            lastSuccessfulSyncAt: successful ? now : existing?.lastSuccessfulSyncAt,
            lastFullRefreshAt: fullRefresh ? now : existing?.lastFullRefreshAt,
            lastAttemptedSyncAt: attempted ? now : existing?.lastAttemptedSyncAt,
            lastFailedAt: failed ? now : existing?.lastFailedAt,
            lastErrorCode: errorCode ?? (failed ? existing?.lastErrorCode : nil),
            state: (engineState ?? state).rawValue,
            needsFullRefresh: needsFullRefresh ?? existing?.needsFullRefresh ?? false,
            lastBootstrapAt: bootstrapAt ?? existing?.lastBootstrapAt,
            lastKnownServerRevision: serverRevision ?? existing?.lastKnownServerRevision,
            schemaVersion: MessengerPersistence.schemaVersion,
            localUpdatedAt: now
        )

        do {
            try await localStore.upsertSyncMetadata(snapshot)
            MessengerDiagnostics.event(
                .messengerLocalSyncMetadataUpdated,
                metadata: [
                    "revision": snapshot.lastAppliedRevision.map { "\($0)" } ?? "none",
                    "state": snapshot.state ?? "unknown"
                ]
            )
        } catch {
            MessengerDiagnostics.event(
                .messengerLocalSyncMetadataUpdated,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "phase": "persistFailed"
                ]
            )
        }
    }

    private var localStore: MessengerLocalStore {
        #if DEBUG
        if let testingStore = MessengerMessageCacheService.testingStore {
            return testingStore
        }
        #endif
        return .shared
    }

    private func durationMilliseconds(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    private func makeSyncRunResult() -> MessengerSyncRunResult {
        let applied = deltaSync.lastRunAppliedEventCount
        let advanced = deltaSync.lastRunAdvancedRevision
        let pendingAckCount = ConversationDeliveryAckCoordinator.shared.pendingDeliveryAckCountForTests

        if let error = deltaSync.lastFailureError {
            return .failed(MessengerDiagnostics.sanitizeError(error))
        }

        let didApply = applied > 0 || advanced
        let outcome: MessengerBackgroundSyncRunOutcome = didApply
            ? .newData(
                appliedEventCount: applied,
                advancedRevision: advanced,
                pendingDeliveryAckCount: pendingAckCount
            )
            : .noData

        return MessengerSyncRunResult(
            outcome: outcome,
            didApplyChanges: didApply,
            appliedEventCount: applied,
            advancedRevision: advanced,
            pendingDeliveryAckCount: pendingAckCount
        )
    }

    private func mergeSyncRunResults(
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
            ? .newData(
                appliedEventCount: applied,
                advancedRevision: advanced,
                pendingDeliveryAckCount: pending
            )
            : .noData

        return MessengerSyncRunResult(
            outcome: outcome,
            didApplyChanges: didApply,
            appliedEventCount: applied,
            advancedRevision: advanced,
            pendingDeliveryAckCount: pending
        )
    }

    private func fulfillBackgroundSyncWaiters(with result: MessengerSyncRunResult) {
        let waiters = backgroundSyncWaiters
        backgroundSyncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }
}
