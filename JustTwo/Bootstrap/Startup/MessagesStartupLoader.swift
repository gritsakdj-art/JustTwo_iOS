import Foundation

@MainActor
final class MessagesStartupLoader {

    static let shared = MessagesStartupLoader()

    private var preloadTask: Task<Void, Never>?
    private var preloadedForUserID: UUID?

    private init() {}

    func preloadIfNeeded(
        conversations: [ChatConversationPreview],
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) {
        guard let userID = session.currentUser?.id else { return }

        if !force, preloadedForUserID == userID {
            return
        }

        if preloadTask != nil, !force {
            return
        }

        preloadTask?.cancel()
        preloadTask = Task { @MainActor in
            await MessageCacheStore.shared.preloadRecentMessages(
                for: conversations,
                session: session,
                router: router
            )

            if !Task.isCancelled {
                preloadedForUserID = userID
                preloadTask = nil
            }
        }
    }

    func reset() {
        preloadTask?.cancel()
        preloadTask = nil
        preloadedForUserID = nil
    }
}
