import Foundation

/// Centralized freshness rules for messenger REST request skipping (PR15F).
enum MessengerCacheFreshnessPolicy {

    /// Memory cache TTL before a background REST refresh is considered useful.
    nonisolated static let messageMemoryTTL: TimeInterval = 180

    /// Conversation list REST refresh TTL after a successful network fetch.
    nonisolated static let conversationListRefreshTTL: TimeInterval = 120

    nonisolated static func isMemoryEntryFresh(
        loadedAt: Date,
        now: Date = .now
    ) -> Bool {
        now.timeIntervalSince(loadedAt) < messageMemoryTTL
    }

    /// Returns `true` when local messages cover the conversation's latest activity.
    nonisolated static func isMessageCacheFresh(
        newestLocalMessageAt: Date?,
        conversationLastMessageAt: Date?
    ) -> Bool {
        guard let newestLocalMessageAt else { return false }
        guard let conversationLastMessageAt else { return true }
        return newestLocalMessageAt >= conversationLastMessageAt.addingTimeInterval(-1)
    }

    nonisolated static func isConversationListRefreshFresh(
        lastNetworkRefreshAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard let lastNetworkRefreshAt else { return false }
        return now.timeIntervalSince(lastNetworkRefreshAt) < conversationListRefreshTTL
    }

    nonisolated static func newestMessageDate(in messages: [ChatMessage]) -> Date? {
        messages.map(\.createdAt).max()
    }

    nonisolated static func cacheAgeMilliseconds(loadedAt: Date, now: Date = .now) -> Int {
        max(0, Int(now.timeIntervalSince(loadedAt) * 1_000))
    }
}

enum MessageLoadReason: String, Sendable {
    case open
    case startupPreload
    case manualRefresh
    case pagination
    case reconnectRepair
}
