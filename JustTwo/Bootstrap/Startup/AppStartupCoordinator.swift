import Foundation

@MainActor
@Observable
final class AppStartupCoordinator {

    static let shared = AppStartupCoordinator()

    private(set) var isRunningCritical = false
    private(set) var warmedUserID: UUID?

    private var criticalTask: Task<Void, Never>?
    private var backgroundNetworkTask: Task<Void, Never>?

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
            warmedUserID = nil
        }

        isRunningCritical = true
        defer { isRunningCritical = false }

        let startedAt = Date()
        MessengerDiagnostics.event(.startupCriticalLocalWarmupStarted)

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

        if criticalTask == task {
            criticalTask = nil
            warmedUserID = userID
            scheduleBackgroundNetworkWarmup(session: session, router: router, force: force)
        }
    }

    func scheduleBackgroundNetworkWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) {
        backgroundNetworkTask?.cancel()
        backgroundNetworkTask = Task { @MainActor in
            await self.runBackgroundNetworkWarmup(session: session, router: router, force: force)
            self.backgroundNetworkTask = nil
        }
    }

    func runBackgroundNetworkWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        guard let userID = session.currentUser?.id else { return }

        let startedAt = Date()
        MessengerDiagnostics.event(.startupBackgroundNetworkWarmupScheduled)

        var baselineRevision: Int64?
        do {
            baselineRevision = try await MessengerDeltaSyncService.shared.prepareBaselineRevision()
        } catch {
            NetworkDebug.logError(error, prefix: "Startup sync baseline failed")
        }

        MessengerDiagnostics.event(.startupProfilePhotosDeferred)
        MessengerDiagnostics.event(.startupConversationAvatarsDeferred)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await ProfilePhotosStartupLoader.shared.loadIfNeeded(force: force)
            }
            group.addTask {
                await ConversationsStartupLoader.shared.refreshNetworkIfNeeded(
                    session: session,
                    router: router,
                    force: force
                )
            }
            await group.waitForAll()
        }

        if let baselineRevision {
            MessengerDeltaSyncService.shared.finishBaseline(revision: baselineRevision)
        }

        ConversationsStartupLoader.shared.activateRealtime(session: session, router: router)
        session.connectRealtimeIfEligible()
        session.syncPushRegistrationIfEligible()

        let conversations = ConversationListViewModel.shared.conversations
        await ConversationAvatarsStartupLoader.shared.preloadCritical(for: conversations)

        Task {
            await MessengerDeltaSyncService.shared.syncDeltas(
                reason: .bootstrap,
                session: session,
                router: router
            )
        }

        ConversationAvatarsStartupLoader.shared.preloadRemainingIfNeeded(for: conversations)
        MessagesStartupLoader.shared.preloadIfNeeded(
            conversations: conversations,
            session: session,
            router: router,
            force: force
        )

        MessengerOutboxProcessor.shared.activate(session: session, router: router)
        Task {
            await MessengerOutboxProcessor.shared.processReadyItems(session: session, router: router)
        }

        Task {
            await MessengerMediaCacheService.runCleanupIfNeeded()
        }

        MessengerDiagnostics.event(
            .startupBackgroundNetworkWarmupSucceeded,
            metadata: [
                "userID": MessengerDiagnostics.sanitizeID(userID),
                "durationMs": "\(durationMilliseconds(since: startedAt))"
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
        backgroundNetworkTask?.cancel()
        backgroundNetworkTask = nil
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
        MessengerDeltaSyncService.shared.reset()
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
