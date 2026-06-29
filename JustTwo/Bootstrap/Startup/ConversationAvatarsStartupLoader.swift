import Foundation

@MainActor
final class ConversationAvatarsStartupLoader {

    static let shared = ConversationAvatarsStartupLoader()

    private var backgroundTask: Task<Void, Never>?

    private init() {}

    func preloadCritical(for conversations: [ChatConversationPreview]) async {
        let targets = Array(conversations.prefix(StartupLoadingLimits.preloadCriticalAvatarCount))
        await preloadAvatars(for: targets)
    }

    func preloadRemainingIfNeeded(for conversations: [ChatConversationPreview]) {
        let remaining = Array(conversations.dropFirst(StartupLoadingLimits.preloadCriticalAvatarCount))
        guard !remaining.isEmpty else { return }

        if let backgroundTask {
            backgroundTask.cancel()
        }

        backgroundTask = Task { @MainActor in
            await preloadAvatars(for: remaining)
            if !Task.isCancelled {
                backgroundTask = nil
            }
        }
    }

    func reset() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    private func preloadAvatars(for conversations: [ChatConversationPreview]) async {
        await withTaskGroup(of: Void.self) { group in
            for conversation in conversations {
                group.addTask {
                    await ChatPartnerAvatarCache.preload(conversation)
                }
            }
            await group.waitForAll()
        }
    }
}
