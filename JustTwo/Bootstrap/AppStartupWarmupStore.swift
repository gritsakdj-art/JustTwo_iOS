import Foundation

@MainActor
@Observable
final class AppStartupWarmupStore {

    static let shared = AppStartupWarmupStore()

    private(set) var isWarmingUp = false
    private(set) var warmedUserID: UUID?

    private var warmupTask: Task<Void, Never>?

    private init() {}

    func warmupAuthenticatedHome(session: SessionStore, router: AppRouter, force: Bool = false) async {
        guard let userID = session.currentUser?.id else { return }

        if force {
            warmupTask?.cancel()
            warmupTask = nil
            warmedUserID = nil
        }

        if !force, warmedUserID == userID {
            return
        }

        if let warmupTask, !force {
            await warmupTask.value
            return
        }

        isWarmingUp = true
        defer { isWarmingUp = false }

        let task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    await ProfilePhotoStore.shared.loadPhotos()
                }
                group.addTask { @MainActor in
                    await ConversationListViewModel.shared.loadIfNeeded(session: session, router: router)
                }

                await group.waitForAll()
            }

            ConversationListViewModel.shared.activateRealtime(session: session, router: router)
        }

        warmupTask = task
        await task.value

        if warmupTask == task {
            warmupTask = nil
        }

        warmedUserID = userID
    }

    func reset() {
        warmupTask?.cancel()
        warmupTask = nil
        isWarmingUp = false
        warmedUserID = nil
        ConversationListViewModel.shared.reset()
    }
}
