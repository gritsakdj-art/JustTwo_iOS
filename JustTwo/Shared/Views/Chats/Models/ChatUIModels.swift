import Foundation

struct ChatMessageReaction: Identifiable, Equatable, Hashable {
    let emoji: String
    let count: Int
    let reactedByMe: Bool

    var displayEmoji: String { ReactionEmoji.display(emoji) }

    var id: String { displayEmoji }
}

struct ChatReplyPreview: Equatable, Hashable {
    let id: UUID
    let body: String
    let isDeleted: Bool
}

struct ChatMessage: Identifiable, Equatable, Hashable {
    let id: UUID
    let displayText: String
    let rawBody: String?
    let createdAt: Date
    let isMine: Bool
    let isDeleted: Bool
    let isEdited: Bool
    let replyPreview: ChatReplyPreview?
    let reactions: [ChatMessageReaction]

    var text: String { displayText }

    var canReply: Bool { !isDeleted }
    var canCopy: Bool { rawBody != nil && !(rawBody?.isEmpty ?? true) }
    var canEdit: Bool { isMine && !isDeleted }
    var canDelete: Bool { isMine && !isDeleted }
    var canReact: Bool { !isDeleted }
}

struct ChatConversationPreview: Identifiable, Equatable, Hashable {
    let id: UUID
    let title: String
    let avatarURL: URL?
    let avatarPhotoID: UUID?
    let lastMessageText: String?
    let lastSenderName: String?
    let lastMessageAt: Date?
    let unreadCount: Int
}

enum ChatUIMapping {

    static func conversationPreview(
        from conversation: ConversationDTO,
        currentProfileID: UUID
    ) -> ChatConversationPreview {
        let otherName = conversation.otherParticipant?.profile.displayName
            ?? String(localized: "chats.unknownParticipant")

        return ChatConversationPreview(
            id: conversation.id,
            title: otherName,
            avatarURL: avatarURL(from: conversation.otherParticipant?.profile.primaryPhoto),
            avatarPhotoID: conversation.otherParticipant?.profile.primaryPhoto?.id,
            lastMessageText: lastMessagePreview(
                conversation.lastMessage,
                currentProfileID: currentProfileID
            ),
            lastSenderName: lastSenderLabel(
                conversation.lastMessage,
                currentProfileID: currentProfileID,
                otherName: otherName
            ),
            lastMessageAt: conversation.lastMessageAt ?? conversation.lastMessage?.createdAt,
            unreadCount: conversation.unreadCount
        )
    }

    static func message(
        from dto: MessageDTO,
        currentProfileID: UUID
    ) -> ChatMessage {
        let isDeleted = dto.deletedAt != nil
        let displayText: String
        if isDeleted {
            displayText = String(localized: "chats.messageDeleted")
        } else {
            displayText = dto.body ?? ""
        }

        let replyPreview: ChatReplyPreview?
        if let reply = dto.replyTo {
            if reply.body == nil {
                replyPreview = ChatReplyPreview(
                    id: reply.id,
                    body: String(localized: "chats.messageDeleted"),
                    isDeleted: true
                )
            } else if let body = reply.body, !body.isEmpty {
                replyPreview = ChatReplyPreview(id: reply.id, body: body, isDeleted: false)
            } else {
                replyPreview = nil
            }
        } else {
            replyPreview = nil
        }

        return ChatMessage(
            id: dto.id,
            displayText: displayText,
            rawBody: isDeleted ? nil : dto.body,
            createdAt: dto.createdAt ?? .distantPast,
            isMine: dto.senderProfileID == currentProfileID,
            isDeleted: isDeleted,
            isEdited: dto.editedAt != nil && !isDeleted,
            replyPreview: replyPreview,
            reactions: dto.reactions.map {
                ChatMessageReaction(
                    emoji: ReactionEmoji.normalized($0.emoji),
                    count: $0.count,
                    reactedByMe: $0.reactedByMe
                )
            }
        )
    }

    private static func lastMessagePreview(
        _ message: MessageDTO?,
        currentProfileID: UUID
    ) -> String? {
        guard let message else { return nil }
        if message.deletedAt != nil {
            return String(localized: "chats.messageDeleted")
        }
        return message.body
    }

    private static func lastSenderLabel(
        _ message: MessageDTO?,
        currentProfileID: UUID,
        otherName: String
    ) -> String? {
        guard let message else { return nil }
        if message.senderProfileID == currentProfileID {
            return String(localized: "chats.you")
        }
        return otherName
    }

    static func avatarURL(from photo: MessengerProfilePhotoSummaryDTO?) -> URL? {
        guard let photo else { return nil }
        return URL(string: photo.downloadUrl)
    }
}

enum ChatQuickReactions {
    static let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
}
