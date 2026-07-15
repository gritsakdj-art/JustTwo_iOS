import Foundation

@MainActor
@Observable
final class AppStartupCoordinator {

    static let shared = AppStartupCoordinator()

    private(set) var isRunningCritical = false
    private(set) var warmedUserID: UUID?

    private var criticalTask: Task<Void, Never>?
    private var criticalOperationID: UUID?
    private var backgroundNetworkTask: Task<Void, Never>?
    private var backgroundOperationID: UUID?
    private let backgroundWarmupFlight = StartupSingleFlight()

    private init() {}

    func runCriticalWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        await runCriticalLocalWarmup(session: session, router: router, force: force)
    }

    func runCriticalLocalWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        await waitForLogoutReset()
        guard let userID = session.currentUser?.id else { return }

        if !force, warmedUserID == userID {
            return
        }

        if let criticalTask, !force {
            await criticalTask.value
            return
        }

        if force {
            criticalTask?.cancel()
            criticalTask = nil
            criticalOperationID = nil
            warmedUserID = nil
        }

        isRunningCritical = true
        defer { isRunningCritical = false }

        let startedAt = Date()
        MessengerDiagnostics.event(.startupCriticalLocalWarmupStarted)

        let operationID = UUID()
        criticalOperationID = operationID

        let task = Task { @MainActor in
            await MessengerOutboxProcessor.shared.recoverOnLaunch()

            let cachedConversationCount = await ConversationsStartupLoader.shared.loadLocalWarmupIfNeeded(
                session: session,
                router: router
            )

            if cachedConversationCount > 0 {
                MessengerDiagnostics.event(
                    .startupSkippedNetworkCriticalBecauseCacheAvailable,
                    metadata: ["cachedConversationCount": "\(cachedConversationCount)"]
                )
            }

            MessengerDiagnostics.event(
                .startupCriticalLocalWarmupSucceeded,
                metadata: [
                    "cachedConversationCount": "\(cachedConversationCount)",
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
        }

        criticalTask = task
        await task.value

        guard criticalOperationID == operationID, !task.isCancelled else { return }
        criticalTask = nil
        criticalOperationID = nil
        warmedUserID = userID
        scheduleBackgroundNetworkWarmup(session: session, router: router, force: force)
    }

    func scheduleBackgroundNetworkWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) {
        backgroundNetworkTask?.cancel()
        let operationID = UUID()
        backgroundOperationID = operationID
        let task = Task { @MainActor in
            await self.runBackgroundNetworkWarmup(session: session, router: router, force: force)
            guard self.backgroundOperationID == operationID else { return }
            self.backgroundNetworkTask = nil
            self.backgroundOperationID = nil
        }
        backgroundNetworkTask = task
    }

    func runBackgroundNetworkWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        guard let userID = session.currentUser?.id else { return }
        let warmupKey = userID.uuidString

        if !force, backgroundWarmupFlight.loadedKey == warmupKey {
            MessengerDiagnostics.event(
                .startupBackgroundNetworkWarmupSkippedDuplicate,
                metadata: ["userID": MessengerDiagnostics.sanitizeID(userID)]
            )
            return
        }

        await backgroundWarmupFlight.runReportingCompletion(key: warmupKey, force: force) {
            await self.performBackgroundNetworkWarmup(
                session: session,
                router: router,
                expectedUserID: userID,
                force: force
            )
        }
    }

    private func performBackgroundNetworkWarmup(
        session: SessionStore,
        router: AppRouter,
        expectedUserID: UUID,
        force: Bool
    ) async -> Bool {
        guard !Task.isCancelled else {
            logStaleWarmupAbort(expectedUserID: expectedUserID, reason: "cancelledBeforeStart")
            return false
        }
        guard isSessionStillValid(expectedUserID, session: session) else {
            logStaleWarmupAbort(expectedUserID: expectedUserID, reason: "sessionChangedBeforeStart")
            return false
        }

        let startedAt = Date()
        MessengerDiagnostics.event(.startupBackgroundNetworkWarmupScheduled)

        await MessengerSyncEngine.shared.hydrateFromLocalStore()
        guard !shouldAbortWarmup(expectedUserID: expectedUserID, session: session, reason: "afterHydrate") else { return false }

        let baselineRevision = await MessengerSyncEngine.shared.prepareStartupBaselineIfNeeded(
            session: session,
            router: router
        )
        guard !shouldAbortWarmup(expectedUserID: expectedUserID, session: session, reason: "afterBaseline") else { return false }

        MessengerDiagnostics.event(.startupProfilePhotosDeferred)
        MessengerDiagnostics.event(.startupConversationAvatarsDeferred)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await ProfilePhotosStartupLoader.shared.loadIfNeeded(force: force)
            }
            group.addTask { @MainActor in
                await ConversationsStartupLoader.shared.refreshNetworkIfNeeded(
                    session: session,
                    router: router,
                    force: force
                )
            }
            await group.waitForAll()
        }
        guard !shouldAbortWarmup(expectedUserID: expectedUserID, session: session, reason: "afterNetworkRefresh") else { return false }

        if MessengerSyncStateStore.shared.currentRevision == nil, let baselineRevision {
            await MessengerSyncEngine.shared.finishBootstrap(revision: baselineRevision)
        }
        guard !shouldAbortWarmup(expectedUserID: expectedUserID, session: session, reason: "afterBootstrap") else { return false }

        ConversationsStartupLoader.shared.activateRealtime(session: session, router: router)
        session.connectRealtimeIfEligible()
        session.syncPushRegistrationIfEligible()

        let conversations = ConversationListViewModel.shared.conversations
        await ConversationAvatarsStartupLoader.shared.preloadCritical(for: conversations)
        guard !shouldAbortWarmup(expectedUserID: expectedUserID, session: session, reason: "afterAvatarPreload") else { return false }

        MessengerSyncEngine.shared.activate(session: session, router: router)
        MessengerOutboxProcessor.shared.activate(session: session, router: router)

        await bootstrapDurableDeliveryAcks(
            session: session,
            router: router,
            expectedUserID: expectedUserID
        )
        guard !shouldAbortWarmup(expectedUserID: expectedUserID, session: session, reason: "afterDeliveryAckBootstrap") else { return false }

        Task { @MainActor [weak self] in
            guard let self, self.isSessionStillValid(expectedUserID, session: session) else { return }
            await MessengerSyncEngine.shared.runGlobalSync(
                reason: .bootstrap,
                session: session,
                router: router
            )
        }
        Task { @MainActor [weak self] in
            guard let self, self.isSessionStillValid(expectedUserID, session: session) else { return }
            await MessengerOutboxProcessor.shared.processReadyItems(session: session, router: router)
        }

        ConversationAvatarsStartupLoader.shared.preloadRemainingIfNeeded(for: conversations)
        MessagesStartupLoader.shared.preloadIfNeeded(
            conversations: conversations,
            session: session,
            router: router,
            force: force
        )

        Task { @MainActor [weak self] in
            guard let self, self.isSessionStillValid(expectedUserID, session: session) else { return }
            await MessengerMediaCacheService.runCleanupIfNeeded()
        }

        guard isSessionStillValid(expectedUserID, session: session) else {
            logStaleWarmupAbort(expectedUserID: expectedUserID, reason: "beforeSuccess")
            return false
        }

        MessengerDiagnostics.event(
            .startupBackgroundNetworkWarmupSucceeded,
            metadata: [
                "userID": MessengerDiagnostics.sanitizeID(expectedUserID),
                "durationMs": "\(durationMilliseconds(since: startedAt))"
            ]
        )
        return true
    }

    /// Cold-start recovery of durable pending delivery ACKs for the authenticated
    /// owner. Runs during background warmup so a proven-safe boundary that failed
    /// to ACK (or was interrupted by process termination) is replayed without
    /// requiring any chat view to open.
    private func bootstrapDurableDeliveryAcks(
        session: SessionStore,
        router: AppRouter,
        expectedUserID: UUID
    ) async {
        ConversationDeliveryAckCoordinator.shared.boundaryStore = MessengerLocalStore.shared

        guard let profileID = try? await MessengerSessionSupport.resolveCurrentProfileID(session: session) else {
            return
        }
        guard isSessionStillValid(expectedUserID, session: session) else { return }

        await ConversationDeliveryAckCoordinator.shared.bootstrapPersistedBoundaries(
            ownerProfileID: profileID,
            session: session,
            router: router
        )
    }

    private func isSessionStillValid(_ expectedUserID: UUID, session: SessionStore) -> Bool {
        session.currentUser?.id == expectedUserID
    }

    @discardableResult
    private func shouldAbortWarmup(
        expectedUserID: UUID,
        session: SessionStore,
        reason: String
    ) -> Bool {
        if Task.isCancelled {
            logStaleWarmupAbort(expectedUserID: expectedUserID, reason: "cancelled:\(reason)")
            return true
        }
        guard isSessionStillValid(expectedUserID, session: session) else {
            logStaleWarmupAbort(expectedUserID: expectedUserID, reason: reason)
            return true
        }
        return false
    }

    private func logStaleWarmupAbort(expectedUserID: UUID, reason: String) {
        MessengerDiagnostics.event(
            .startupBackgroundNetworkWarmupStaleSessionAborted,
            metadata: [
                "userID": MessengerDiagnostics.sanitizeID(expectedUserID),
                "reason": reason
            ]
        )
    }

    func scheduleAuthenticatedHomeWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) {
        Task { @MainActor in
            await runCriticalLocalWarmup(session: session, router: router, force: force)
        }
    }

    func reset() async {
        await performReset()
    }

    func scheduleLogoutReset() {
        logoutResetTask = Task { @MainActor in
            await self.performReset()
        }
    }

    func waitForLogoutReset() async {
        await logoutResetTask?.value
        logoutResetTask = nil
    }

    private var logoutResetTask: Task<Void, Never>?

    private func performReset() async {
        criticalTask?.cancel()
        criticalTask = nil
        criticalOperationID = nil
        backgroundNetworkTask?.cancel()
        backgroundNetworkTask = nil
        backgroundOperationID = nil
        backgroundWarmupFlight.reset()
        isRunningCritical = false
        warmedUserID = nil

        ProfileStartupLoader.shared.reset()
        ProfilePhotosStartupLoader.shared.reset()
        ConversationsStartupLoader.shared.reset()
        ConversationAvatarsStartupLoader.shared.reset()
        MessagesStartupLoader.shared.reset()
        MessageCacheStore.shared.reset()
        MessengerOutbox.shared.clear()
        MessengerOutboxProcessor.shared.deactivate()
        MessengerSyncEngine.shared.reset()
        ConversationListViewModel.shared.reset()

        await StartupSessionSnapshotStore.shared.clear()
        await MessengerMediaCacheService.clearAll()

        do {
            try await MessengerLocalStore.shared.resetAllMessengerData()
        } catch {
            MessengerDiagnostics.event(
                .messengerLocalStoreResetFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "source": "AppStartupCoordinator.performReset"
                ]
            )
        }
    }

    private func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
