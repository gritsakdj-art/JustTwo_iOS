import Foundation
import CoreGraphics
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

struct ChatMessageAttachment: Identifiable, Equatable, Hashable {
    let id: String
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
    let localFileURL: URL?
    let downloadURL: URL?
    let downloadUrlExpiresAt: Date?
    let hasLocalDiskThumbnail: Bool
    let hasLocalDiskFull: Bool

    var hasLocalDiskCache: Bool {
        hasLocalDiskThumbnail || hasLocalDiskFull
    }

    nonisolated var aspectRatio: CGFloat {
        ChatImageBubbleLayout.aspectRatio(width: width, height: height)
    }

    nonisolated init(
        id: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int,
        localFileURL: URL?,
        downloadURL: URL?,
        downloadUrlExpiresAt: Date?,
        hasLocalDiskThumbnail: Bool = false,
        hasLocalDiskFull: Bool = false
    ) {
        self.id = id
        self.contentType = contentType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.localFileURL = localFileURL
        self.downloadURL = downloadURL
        self.downloadUrlExpiresAt = downloadUrlExpiresAt
        self.hasLocalDiskThumbnail = hasLocalDiskThumbnail
        self.hasLocalDiskFull = hasLocalDiskFull
    }

    nonisolated static func local(
        clientMessageID: String,
        prepared: PreparedChatImage
    ) -> ChatMessageAttachment {
        ChatMessageAttachment(
            id: "local-\(clientMessageID)",
            contentType: prepared.contentType,
            byteSize: prepared.byteSize,
            width: prepared.width,
            height: prepared.height,
            localFileURL: prepared.localFileURL,
            downloadURL: nil,
            downloadUrlExpiresAt: nil
        )
    }

    nonisolated static func remote(_ dto: MessageAttachmentDTO) -> ChatMessageAttachment {
        ChatMessageAttachment(
            id: dto.id.uuidString.lowercased(),
            contentType: dto.contentType,
            byteSize: dto.byteSize,
            width: dto.width,
            height: dto.height,
            localFileURL: nil,
            downloadURL: dto.downloadUrl,
            downloadUrlExpiresAt: dto.downloadUrlExpiresAt
        )
    }

    /// Cached attachment metadata without signed download URL. `localCacheKey` is stable for image cache lookup.
    nonisolated static func cached(_ snapshot: LocalAttachmentSnapshot) -> ChatMessageAttachment {
        ChatMessageAttachment(
            id: snapshot.localCacheKey ?? snapshot.id,
            contentType: snapshot.contentType ?? "image/jpeg",
            byteSize: snapshot.byteSize ?? 0,
            width: snapshot.width ?? 1,
            height: snapshot.height ?? 1,
            localFileURL: nil,
            downloadURL: nil,
            downloadUrlExpiresAt: snapshot.downloadURLExpiresAt,
            hasLocalDiskThumbnail: snapshot.hasLocalThumbnail,
            hasLocalDiskFull: snapshot.hasLocalFullImage
        )
    }
}

struct ChatMessage: Identifiable, Equatable, Hashable {
    let id: UUID
    let clientMessageID: String?
    let localSendState: MessageLocalSendState?
    let kind: MessageKind
    let displayText: String
    let rawBody: String?
    let imageAttachment: ChatMessageAttachment?
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
        kind: MessageKind = .text,
        displayText: String,
        rawBody: String?,
        imageAttachment: ChatMessageAttachment? = nil,
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
        self.kind = kind
        self.displayText = displayText
        self.rawBody = rawBody
        self.imageAttachment = imageAttachment
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
    var canEdit: Bool { isMine && kind == .text && !isDeleted && localSendState == nil }
    var canDelete: Bool { isMine && !isDeleted && localSendState == nil }
    var canReact: Bool { !isDeleted && localSendState == nil }
    var canRetrySend: Bool { isMine && localSendState == .failed }
}

enum ChatImageRenderSource: Equatable {
    case localFile
    case remote(attachmentID: String)
    case diskCache(attachmentID: String)
}

extension ChatMessage {
    /// Describes whether an image bubble should render and which source it uses.
    var imageRenderSource: ChatImageRenderSource? {
        guard !isDeleted, imageAttachment != nil else { return nil }
        guard let attachment = imageAttachment else { return nil }

        if attachment.localFileURL != nil {
            return .localFile
        }
        if attachment.hasLocalDiskCache {
            return .diskCache(attachmentID: attachment.id)
        }
        if attachment.downloadURL != nil {
            return .remote(attachmentID: attachment.id)
        }
        return nil
    }
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
            kind: .text,
            displayText: body,
            rawBody: body,
            imageAttachment: nil,
            createdAt: createdAt,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: replyPreview,
            reactions: [],
            deliveryStatus: nil
        )
    }

    static func optimisticOutgoingImage(
        clientMessageID: String,
        prepared: PreparedChatImage,
        replyPreview: ChatReplyPreview?,
        caption: String? = nil,
        createdAt: Date = .now
    ) -> ChatMessage {
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayText: String
        let rawBody: String?
        if trimmedCaption.isEmpty {
            displayText = ChatUIMapping.imageMessagePreviewText
            rawBody = nil
        } else {
            displayText = trimmedCaption
            rawBody = trimmedCaption
        }

        return ChatMessage(
            id: OptimisticMessageIdentity.localMessageID(for: clientMessageID),
            clientMessageID: clientMessageID,
            localSendState: .sending,
            kind: .image,
            displayText: displayText,
            rawBody: rawBody,
            imageAttachment: .local(clientMessageID: clientMessageID, prepared: prepared),
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
            kind: kind,
            displayText: displayText,
            rawBody: rawBody,
            imageAttachment: imageAttachment,
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
            kind: kind,
            displayText: String(localized: "chats.messageDeleted"),
            rawBody: nil,
            imageAttachment: nil,
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
            kind: kind,
            displayText: displayText,
            rawBody: rawBody,
            imageAttachment: imageAttachment,
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
            kind: kind,
            displayText: displayText,
            rawBody: rawBody,
            imageAttachment: imageAttachment,
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

    static func conversationPreview(
        from snapshot: LocalConversationSnapshot,
        currentProfileID: UUID
    ) -> ChatConversationPreview? {
        guard let conversationID = UUID(uuidString: snapshot.id) else { return nil }

        let otherName = snapshot.otherParticipantDisplayName
            ?? String(localized: "chats.unknownParticipant")
        let otherProfileID = snapshot.otherParticipantProfileID.flatMap(UUID.init(uuidString:))
        let avatarPhotoID = snapshot.otherParticipantPrimaryPhotoID.flatMap(UUID.init(uuidString:))

        return ChatConversationPreview(
            id: conversationID,
            title: otherName,
            otherParticipantProfileID: otherProfileID,
            avatarURL: nil,
            avatarPhotoID: avatarPhotoID,
            lastMessageText: cachedLastMessagePreview(from: snapshot),
            lastSenderName: cachedLastSenderLabel(
                from: snapshot,
                currentProfileID: currentProfileID,
                otherName: otherName
            ),
            lastMessageAt: snapshot.lastMessageAt ?? snapshot.lastMessageCreatedAt,
            unreadCount: snapshot.unreadCount
        )
    }

    private static func cachedLastMessagePreview(from snapshot: LocalConversationSnapshot) -> String? {
        if snapshot.lastMessageDeletedAt != nil {
            return String(localized: "chats.messageDeleted")
        }
        if snapshot.lastMessageKind == MessageKind.image.rawValue {
            return imageMessagePreviewText
        }
        return snapshot.lastMessageBody
    }

    private static func cachedLastSenderLabel(
        from snapshot: LocalConversationSnapshot,
        currentProfileID: UUID,
        otherName: String
    ) -> String? {
        guard snapshot.lastMessageID != nil else { return nil }
        guard let senderID = snapshot.lastMessageSenderProfileID,
              let senderUUID = UUID(uuidString: senderID) else {
            return otherName
        }
        return senderUUID == currentProfileID
            ? String(localized: "chats.you")
            : otherName
    }

    static let imageMessagePreviewText = String(localized: "chats.message.photo", defaultValue: "Photo")

    static func message(
        from dto: MessageDTO,
        currentProfileID: UUID
    ) -> ChatMessage {
        let isDeleted = dto.deletedAt != nil
        let imageAttachment = isDeleted ? nil : dto.attachments.first.map(ChatMessageAttachment.remote)
        let displayText: String
        if isDeleted {
            displayText = String(localized: "chats.messageDeleted")
        } else if dto.kind == .image, (dto.body?.isEmpty ?? true) {
            displayText = imageMessagePreviewText
        } else {
            displayText = dto.body ?? ""
        }

        let replyPreview: ChatReplyPreview?
        if let reply = dto.replyTo {
            if reply.body == nil {
                // Backend nils out the body only for deleted originals.
                replyPreview = ChatReplyPreview(
                    id: reply.id,
                    body: String(localized: "chats.messageDeleted"),
                    isDeleted: true
                )
            } else if let body = reply.body, !body.isEmpty {
                replyPreview = ChatReplyPreview(id: reply.id, body: body, isDeleted: false)
            } else {
                // Empty (non-nil) body means the original is an image message without
                // a caption — backend stores "" for those. Keep the quote alive so the
                // reply bubble can show the photo thumbnail and placeholder text.
                replyPreview = ChatReplyPreview(
                    id: reply.id,
                    body: imageMessagePreviewText,
                    isDeleted: false
                )
            }
        } else {
            replyPreview = nil
        }

        let isMine = dto.senderProfileID == currentProfileID

        return ChatMessage(
            id: dto.id,
            clientMessageID: dto.clientMessageID,
            localSendState: nil,
            kind: dto.kind,
            displayText: displayText,
            rawBody: isDeleted ? nil : dto.body,
            imageAttachment: imageAttachment,
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

    static func message(
        from snapshot: LocalMessageSnapshot,
        currentProfileID: UUID
    ) -> ChatMessage {
        let isDeleted = snapshot.localState == .deleted || snapshot.deletedAt != nil
        let kind = MessageKind(rawValue: snapshot.kind)
        let imageAttachment: ChatMessageAttachment?
        if isDeleted {
            imageAttachment = nil
        } else if kind == .image, let attachment = snapshot.attachments.first {
            imageAttachment = ChatMessageAttachment.cached(attachment)
        } else {
            imageAttachment = nil
        }

        let displayText: String
        if isDeleted {
            displayText = String(localized: "chats.messageDeleted")
        } else if kind == .image, (snapshot.body?.isEmpty ?? true) {
            displayText = imageMessagePreviewText
        } else {
            displayText = snapshot.body ?? ""
        }

        let replyPreview: ChatReplyPreview?
        if let replyIDString = snapshot.replyToMessageID,
           let replyID = UUID(uuidString: replyIDString) {
            if snapshot.replyToBody == nil {
                replyPreview = ChatReplyPreview(
                    id: replyID,
                    body: String(localized: "chats.messageDeleted"),
                    isDeleted: true
                )
            } else if let body = snapshot.replyToBody, !body.isEmpty {
                replyPreview = ChatReplyPreview(id: replyID, body: body, isDeleted: false)
            } else {
                replyPreview = ChatReplyPreview(
                    id: replyID,
                    body: imageMessagePreviewText,
                    isDeleted: false
                )
            }
        } else {
            replyPreview = nil
        }

        let senderUUID = UUID(uuidString: snapshot.senderProfileID)
        let isMine = senderUUID == currentProfileID
        let messageID = UUID(uuidString: snapshot.id) ?? UUID()

        let localSendState: MessageLocalSendState?
        switch snapshot.localState {
        case .sending:
            localSendState = .sending
        case .failed:
            localSendState = .failed
        case .pendingUpload:
            localSendState = .sending
        case .serverConfirmed, .deleted:
            localSendState = nil
        }

        let deliveryStatus: MessageDeliveryStatus?
        if isMine, !isDeleted, localSendState == nil, let statusString = snapshot.deliveryStatus {
            deliveryStatus = MessageDeliveryStatus(rawValue: statusString) ?? .sent
        } else {
            deliveryStatus = nil
        }

        return ChatMessage(
            id: messageID,
            clientMessageID: snapshot.clientMessageID,
            localSendState: localSendState,
            kind: kind,
            displayText: displayText,
            rawBody: isDeleted ? nil : snapshot.body,
            imageAttachment: imageAttachment,
            createdAt: snapshot.createdAt,
            isMine: isMine,
            isDeleted: isDeleted,
            isEdited: snapshot.editedAt != nil && !isDeleted,
            replyPreview: replyPreview,
            reactions: snapshot.reactions.map {
                ChatMessageReaction(
                    emoji: ReactionEmoji.normalized($0.emoji),
                    count: $0.count,
                    reactedByMe: $0.reactedByMe
                )
            },
            deliveryStatus: deliveryStatus
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
        if message.kind == .image {
            return imageMessagePreviewText
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
        if dto.kind == .image {
            return imageMessagePreviewText
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
