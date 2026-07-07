import Foundation

@MainActor
@Observable
final class AppStartupCoordinator {

    static let shared = AppStartupCoordinator()

    private(set) var isRunningCritical = false
    private(set) var warmedUserID: UUID?

    private var criticalTask: Task<Void, Never>?

    private init() {}

    func runCriticalWarmup(
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

        NetworkDebug.log("Startup critical warmup started user=\(userID)")

        var baselineRevision: Int64?
        do {
            baselineRevision = try await MessengerDeltaSyncService.shared.prepareBaselineRevision()
        } catch {
            NetworkDebug.logError(error, prefix: "Startup sync baseline failed")
        }

        let task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await ProfilePhotosStartupLoader.shared.loadIfNeeded(force: force)
                }
                group.addTask {
                    await ConversationsStartupLoader.shared.loadIfNeeded(
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

            let conversations = ConversationListViewModel.shared.conversations
            await ConversationAvatarsStartupLoader.shared.preloadCritical(for: conversations)

            Task {
                await MessengerDeltaSyncService.shared.syncDeltas(
                    reason: .bootstrap,
                    session: session,
                    router: router
                )
            }

            NetworkDebug.log("Startup critical warmup finished user=\(userID)")
        }

        criticalTask = task
        await task.value

        if criticalTask == task {
            criticalTask = nil
            warmedUserID = userID
            scheduleBackgroundWarmup(session: session, router: router, force: force)
        }
    }

    func scheduleAuthenticatedHomeWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) {
        Task { @MainActor in
            await runCriticalWarmup(session: session, router: router, force: force)
        }
    }

    func scheduleBackgroundWarmup(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) {
        let conversations = ConversationListViewModel.shared.conversations
        ConversationAvatarsStartupLoader.shared.preloadRemainingIfNeeded(for: conversations)
        MessagesStartupLoader.shared.preloadIfNeeded(
            conversations: conversations,
            session: session,
            router: router,
            force: force
        )
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
        isRunningCritical = false
        warmedUserID = nil

        ProfileStartupLoader.shared.reset()
        ProfilePhotosStartupLoader.shared.reset()
        ConversationsStartupLoader.shared.reset()
        ConversationAvatarsStartupLoader.shared.reset()
        MessagesStartupLoader.shared.reset()
        MessageCacheStore.shared.reset()
        MessengerOutbox.shared.clear()
        MessengerDeltaSyncService.shared.reset()
        ConversationListViewModel.shared.reset()

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
}
