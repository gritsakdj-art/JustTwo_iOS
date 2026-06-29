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

            ConversationsStartupLoader.shared.activateRealtime(session: session, router: router)

            let conversations = ConversationListViewModel.shared.conversations
            await ConversationAvatarsStartupLoader.shared.preloadCritical(for: conversations)
        }

        criticalTask = task
        await task.value

        if criticalTask == task {
            criticalTask = nil
            warmedUserID = userID
            scheduleBackgroundWarmup(session: session, router: router, force: force)
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

    func reset() {
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
        ConversationListViewModel.shared.reset()
    }
}
