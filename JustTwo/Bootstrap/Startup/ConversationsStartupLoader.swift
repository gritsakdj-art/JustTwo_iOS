import Foundation

@MainActor
final class ConversationsStartupLoader {

    static let shared = ConversationsStartupLoader()

    private var singleFlight = StartupSingleFlight()

    private init() {}

    func loadIfNeeded(
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async {
        let key = session.currentUser?.id.uuidString ?? "anonymous"
        await singleFlight.run(key: key, force: force) {
            await ConversationListViewModel.shared.loadIfNeeded(session: session, router: router)
        }
    }

    func activateRealtime(session: SessionStore, router: AppRouter) {
        ConversationListViewModel.shared.activateRealtime(session: session, router: router)
    }

    func reset() {
        singleFlight.reset()
    }
}
