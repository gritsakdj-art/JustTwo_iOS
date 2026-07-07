import Foundation

@MainActor
final class ConversationsStartupLoader {

    static let shared = ConversationsStartupLoader()

    private var singleFlight = StartupSingleFlight()
    private var networkSingleFlight = StartupSingleFlight()

    private init() {}

    func loadIfNeeded(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        let key = session.currentUser?.id.uuidString ?? "anonymous"
        await singleFlight.run(key: key, force: force) {
            _ = await ConversationListViewModel.shared.loadLocalWarmupIfNeeded(session: session)
            await ConversationListViewModel.shared.refreshNetworkIfNeeded(
                session: session,
                router: router,
                force: force
            )
        }
    }

    @discardableResult
    func loadLocalWarmupIfNeeded(
        session: SessionStore,
        router: AppRouter
    ) async -> Int {
        let key = session.currentUser?.id.uuidString ?? "anonymous"
        if singleFlight.loadedKey == key {
            return ConversationListViewModel.shared.conversations.count
        }

        var cachedCount = 0
        await singleFlight.run(key: key, force: false) {
            cachedCount = await ConversationListViewModel.shared.loadLocalWarmupIfNeeded(session: session)
        }
        return cachedCount > 0 ? cachedCount : ConversationListViewModel.shared.conversations.count
    }

    func refreshNetworkIfNeeded(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        let key = session.currentUser?.id.uuidString ?? "anonymous"
        await networkSingleFlight.run(key: key, force: force) {
            await ConversationListViewModel.shared.refreshNetworkIfNeeded(
                session: session,
                router: router,
                force: force
            )
        }
    }

    func activateRealtime(session: SessionStore, router: AppRouter) {
        ConversationListViewModel.shared.activateRealtime(session: session, router: router)
    }

    func reset() {
        singleFlight.reset()
        networkSingleFlight.reset()
    }
}
