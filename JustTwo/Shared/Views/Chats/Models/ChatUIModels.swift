import Foundation
import CryptoKit

enum MessageLocalSendState: Equatable, Hashable {
    case sending
    case failed
}

enum OptimisticMessageIdentity {
    static func localMessageID(for clientMessageID: String) -> UUID {
        let seed = "justtwo.outgoing.\(clientMessageID)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct ChatMessageReaction: Identifiable, Equatable, Hashable {
    let emoji: String
    let count: Int
    let reactedByMe: Bool

    var displayEmoji: String { ReactionEmoji.display(emoji) }

    var id: String { displayEmoji }
}

extension ChatMessageReaction {
    func replacing(count: Int? = nil, reactedByMe: Bool? = nil) -> ChatMessageReaction {
        ChatMessageReaction(
            emoji: emoji,
            count: max(0, count ?? self.count),
            reactedByMe: reactedByMe ?? self.reactedByMe
        )
    }
}

struct ChatReplyPreview: Equatable, Hashable {
    let id: UUID
    let body: String
    let isDeleted: Bool
}

struct ChatMessage: Identifiable, Equatable, Hashable {
    let id: UUID
    let clientMessageID: String?
    let localSendState: MessageLocalSendState?
    let displayText: String
    let rawBody: String?
    let createdAt: Date
    let isMine: Bool
    let isDeleted: Bool
    let isEdited: Bool
    let replyPreview: ChatReplyPreview?
    let reactions: [ChatMessageReaction]
    let deliveryStatus: MessageDeliveryStatus?

    var listIdentity: String {
        if let clientMessageID, localSendState != nil {
            return "pending-\(clientMessageID)"
        }
        return id.uuidString
    }

    var isPendingOutgoing: Bool { localSendState != nil }

    init(
        id: UUID,
        clientMessageID: String? = nil,
        localSendState: MessageLocalSendState? = nil,
        displayText: String,
        rawBody: String?,
        createdAt: Date,
        isMine: Bool,
        isDeleted: Bool,
        isEdited: Bool,
        replyPreview: ChatReplyPreview?,
        reactions: [ChatMessageReaction],
        deliveryStatus: MessageDeliveryStatus? = nil
    ) {
        self.id = id
        self.clientMessageID = clientMessageID
        self.localSendState = localSendState
        self.displayText = displayText
        self.rawBody = rawBody
        self.createdAt = createdAt
        self.isMine = isMine
        self.isDeleted = isDeleted
        self.isEdited = isEdited
        self.replyPreview = replyPreview
        self.reactions = reactions
        self.deliveryStatus = localSendState == nil ? deliveryStatus : nil
    }

    var text: String { displayText }

    var canReply: Bool { !isDeleted && localSendState == nil }
    var canCopy: Bool { rawBody != nil && !(rawBody?.isEmpty ?? true) }
    var canEdit: Bool { isMine && !isDeleted && localSendState == nil }
    var canDelete: Bool { isMine && !isDeleted && localSendState == nil }
    var canReact: Bool { !isDeleted && localSendState == nil }
    var canRetrySend: Bool { isMine && localSendState == .failed }
}

extension ChatMessage {
    static func optimisticOutgoing(
        clientMessageID: String,
        body: String,
        replyPreview: ChatReplyPreview?,
        createdAt: Date = .now
    ) -> ChatMessage {
        ChatMessage(
            id: OptimisticMessageIdentity.localMessageID(for: clientMessageID),
            clientMessageID: clientMessageID,
            localSendState: .sending,
            displayText: body,
            rawBody: body,
            createdAt: createdAt,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: replyPreview,
            reactions: [],
            deliveryStatus: nil
        )
    }

    func serverConfirmed(from dto: MessageDTO, currentProfileID: UUID) -> ChatMessage {
        ChatUIMapping.message(from: dto, currentProfileID: currentProfileID)
    }

    func replacingLocalSendState(_ state: MessageLocalSendState?) -> ChatMessage {
        ChatMessage(
            id: id,
            clientMessageID: clientMessageID,
            localSendState: state,
            displayText: displayText,
            rawBody: rawBody,
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: isDeleted,
            isEdited: isEdited,
            replyPreview: replyPreview,
            reactions: reactions,
            deliveryStatus: state == nil ? deliveryStatus : nil
        )
    }
}

extension ChatMessage {
    func markingDeleted(deletedAt: Date?) -> ChatMessage {
        ChatMessage(
            id: id,
            clientMessageID: clientMessageID,
            localSendState: nil,
            displayText: String(localized: "chats.messageDeleted"),
            rawBody: nil,
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: true,
            isEdited: false,
            replyPreview: replyPreview,
            reactions: reactions,
            deliveryStatus: nil
        )
    }

    func replacingReactions(_ reactions: [ChatMessageReaction]) -> ChatMessage {
        ChatMessage(
            id: id,
            clientMessageID: clientMessageID,
            localSendState: localSendState,
            displayText: displayText,
            rawBody: rawBody,
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: isDeleted,
            isEdited: isEdited,
            replyPreview: replyPreview,
            reactions: reactions,
            deliveryStatus: deliveryStatus
        )
    }

    func replacingDeliveryStatus(_ status: MessageDeliveryStatus?) -> ChatMessage {
        let nextStatus: MessageDeliveryStatus?
        if !isMine || isDeleted {
            nextStatus = nil
        } else if let current = deliveryStatus, let status {
            nextStatus = status.rank > current.rank ? status : current
        } else {
            nextStatus = status ?? deliveryStatus
        }

        guard nextStatus != deliveryStatus else { return self }

        return ChatMessage(
            id: id,
            clientMessageID: clientMessageID,
            localSendState: localSendState,
            displayText: displayText,
            rawBody: rawBody,
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: isDeleted,
            isEdited: isEdited,
            replyPreview: replyPreview,
            reactions: reactions,
            deliveryStatus: nextStatus
        )
    }
}

struct ChatConversationPreview: Identifiable, Equatable, Hashable {
    let id: UUID
    let title: String
    let otherParticipantProfileID: UUID?
    let avatarURL: URL?
    let avatarPhotoID: UUID?
    let lastMessageText: String?
    let lastSenderName: String?
    let lastMessageAt: Date?
    let unreadCount: Int
}

extension ChatConversationPreview {
    func replacingActivity(
        lastMessageText: String? = nil,
        lastSenderName: String? = nil,
        lastMessageAt: Date? = nil,
        unreadCount: Int? = nil,
        otherParticipantProfileID: UUID? = nil
    ) -> ChatConversationPreview {
        ChatConversationPreview(
            id: id,
            title: title,
            otherParticipantProfileID: otherParticipantProfileID ?? self.otherParticipantProfileID,
            avatarURL: avatarURL,
            avatarPhotoID: avatarPhotoID,
            lastMessageText: lastMessageText ?? self.lastMessageText,
            lastSenderName: lastSenderName ?? self.lastSenderName,
            lastMessageAt: lastMessageAt ?? self.lastMessageAt,
            unreadCount: max(0, unreadCount ?? self.unreadCount)
        )
    }
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
            otherParticipantProfileID: conversation.otherParticipant?.profile.id,
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

        let isMine = dto.senderProfileID == currentProfileID

        return ChatMessage(
            id: dto.id,
            clientMessageID: dto.clientMessageID,
            localSendState: nil,
            displayText: displayText,
            rawBody: isDeleted ? nil : dto.body,
            createdAt: dto.createdAt ?? .distantPast,
            isMine: isMine,
            isDeleted: isDeleted,
            isEdited: dto.editedAt != nil && !isDeleted,
            replyPreview: replyPreview,
            reactions: dto.reactions.map {
                ChatMessageReaction(
                    emoji: ReactionEmoji.normalized($0.emoji),
                    count: $0.count,
                    reactedByMe: $0.reactedByMe
                )
            },
            deliveryStatus: isMine && !isDeleted ? (dto.deliveryStatus ?? .sent) : nil
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

    static func realtimeLastMessageText(from dto: MessageDTO) -> String? {
        if dto.deletedAt != nil {
            return String(localized: "chats.messageDeleted")
        }
        return dto.body
    }

    static func realtimeLastSenderName(
        from dto: MessageDTO,
        currentProfileID: UUID,
        fallbackOtherName: String
    ) -> String {
        dto.senderProfileID == currentProfileID
            ? String(localized: "chats.you")
            : fallbackOtherName
    }
}

enum ChatMessageDateFormatting {
    static func metadataText(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "\(String(localized: "chats.date.yesterday")), \(time)"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let dayMonth = date.formatted(.dateTime.day().month(.abbreviated))
            return "\(dayMonth), \(time)"
        }

        let fullDate = date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
        return "\(fullDate), \(time)"
    }

    static func daySeparatorTitle(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        if calendar.isDateInToday(date) {
            return String(localized: "chats.date.today")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "chats.date.yesterday")
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInToday(date)
    }

    static func isDifferentDay(
        _ lhs: Date,
        from rhs: Date,
        calendar: Calendar = .current
    ) -> Bool {
        !calendar.isDate(lhs, inSameDayAs: rhs)
    }
}

enum ChatQuickReactions {
    static let rows: [[String]] = [
        ["👍", "❤️", "😂", "😮", "😢", "🙏"],
        ["🔥", "👏", "🎉", "🤔", "😍", "🥰"],
        ["😡", "👎", "💯", "✨", "🫶", "😭"],
    ]

    static let compactPreviewCount = 5

    static var compactPreview: [String] {
        Array(rows[0].prefix(compactPreviewCount))
    }

    static var allEmojis: [String] {
        rows.flatMap { $0 }
    }
}
