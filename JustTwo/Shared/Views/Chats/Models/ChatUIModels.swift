import Foundation

struct ChatMessage: Identifiable, Equatable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date
    let isMine: Bool
}

struct ChatConversationPreview: Identifiable, Equatable, Hashable {
    let id: UUID
    let title: String
    let lastMessageText: String?
    let lastSenderName: String?
    let lastMessageAt: Date?
    let unreadCount: Int
}
