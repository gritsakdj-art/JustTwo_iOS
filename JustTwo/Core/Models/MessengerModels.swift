import Foundation

nonisolated struct ConversationsResponseDTO: Decodable, Sendable {
    let conversations: [ConversationDTO]
    let nextCursor: String?
}

nonisolated struct ConversationResponseDTO: Decodable, Sendable {
    let conversation: ConversationDTO
}

nonisolated struct ConversationDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let type: String
    let status: String
    let connectionID: UUID?
    let otherParticipant: ConversationParticipantDTO?
    let lastMessage: MessageDTO?
    let unreadCount: Int
    let lastReadAt: Date?
    let lastMessageAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

nonisolated struct ConversationParticipantDTO: Decodable, Sendable {
    let profile: MessengerProfileSummaryDTO
    let role: String
    let joinedAt: Date
    let lastReadAt: Date?
    let lastDeliveredAt: Date?
}

nonisolated struct PresenceSummaryDTO: Decodable, Sendable, Equatable {
    let isOnline: Bool
    let lastSeenAt: Date?
}

nonisolated struct MessengerProfileSummaryDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let bio: String?
    let city: String?
    let primaryPhoto: MessengerProfilePhotoSummaryDTO?
    let presence: PresenceSummaryDTO?
}

nonisolated struct MessengerProfilePhotoSummaryDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let downloadUrl: String
    let avatarPresentation: AvatarPresentationDTO
}

nonisolated struct MessagesResponseDTO: Decodable, Sendable {
    let messages: [MessageDTO]
    let nextCursor: String?
}

nonisolated struct MessageResponseDTO: Decodable, Sendable {
    let message: MessageDTO
}

nonisolated enum MessageKind: Equatable, Hashable, Sendable, Codable {
    case text
    case image
    case unknown(String)

    var rawValue: String {
        switch self {
        case .text: return "text"
        case .image: return "image"
        case .unknown(let value): return value
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "text": self = .text
        case "image": self = .image
        default: self = .unknown(rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct MessageAttachmentDTO: Decodable, Equatable, Sendable {
    let id: UUID
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
    let downloadUrl: URL?
    let downloadUrlExpiresAt: Date?
}

nonisolated struct MessageDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderProfileID: UUID
    let kind: MessageKind
    let body: String?
    let attachments: [MessageAttachmentDTO]
    let replyTo: MessageReplyDTO?
    let reactions: [MessageReactionDTO]
    let deliveryStatus: MessageDeliveryStatus?
    let clientMessageID: String?
    let createdAt: Date?
    let editedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID
        case senderProfileID
        case kind
        case body
        case attachments
        case replyTo
        case reactions
        case deliveryStatus
        case clientMessageID
        case createdAt
        case editedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        senderProfileID = try container.decode(UUID.self, forKey: .senderProfileID)
        kind = try container.decodeIfPresent(MessageKind.self, forKey: .kind) ?? .text
        body = try container.decodeIfPresent(String.self, forKey: .body)
        attachments = try container.decodeIfPresent([MessageAttachmentDTO].self, forKey: .attachments) ?? []
        replyTo = try container.decodeIfPresent(MessageReplyDTO.self, forKey: .replyTo)
        reactions = try container.decodeIfPresent([MessageReactionDTO].self, forKey: .reactions) ?? []
        deliveryStatus = try container.decodeIfPresent(MessageDeliveryStatus.self, forKey: .deliveryStatus)
        clientMessageID = try container.decodeIfPresent(String.self, forKey: .clientMessageID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

enum MessageDeliveryStatus: String, Codable, Equatable, Sendable, Hashable {
    case sent
    case delivered
    case read

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = MessageDeliveryStatus(rawValue: rawValue) ?? .sent
    }

    var rank: Int {
        switch self {
        case .sent: return 0
        case .delivered: return 1
        case .read: return 2
        }
    }
}

nonisolated struct MessageReplyDTO: Decodable, Sendable {
    let id: UUID
    let body: String?
    let senderProfileID: UUID
}

nonisolated struct MessageReactionDTO: Decodable, Sendable, Hashable {
    let emoji: String
    let count: Int
    let reactedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case emoji
        case count
        case reactedByMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = ReactionEmoji.normalized(try container.decode(String.self, forKey: .emoji))
        count = try container.decode(Int.self, forKey: .count)
        reactedByMe = try container.decode(Bool.self, forKey: .reactedByMe)
    }
}

enum ReactionEmoji {
    /// Raw emoji for models, UI, and URL path components. HTTPClient encodes path segments.
    nonisolated static func normalized(_ emoji: String) -> String {
        emoji.removingPercentEncoding ?? emoji
    }

    /// Defensive display fallback for legacy/local percent-encoded values.
    nonisolated static func display(_ emoji: String) -> String {
        normalized(emoji)
    }
}

nonisolated struct SendMessageRequestBody: Encodable, Sendable {
    let kind: MessageKind?
    let body: String?
    let replyToID: UUID?
    let clientMessageID: String
    let attachmentUploadID: UUID?

    enum CodingKeys: String, CodingKey {
        case kind
        case body
        case replyToID
        case clientMessageID
        case attachmentUploadID
    }

    init(
        kind: MessageKind? = nil,
        body: String?,
        replyToID: UUID?,
        clientMessageID: String,
        attachmentUploadID: UUID? = nil
    ) {
        self.kind = kind
        self.body = body
        self.replyToID = replyToID
        self.clientMessageID = clientMessageID
        self.attachmentUploadID = attachmentUploadID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(kind, forKey: .kind)
        if body == nil, kind == .image {
            try container.encodeNil(forKey: .body)
        } else {
            try container.encodeIfPresent(body, forKey: .body)
        }
        try container.encodeIfPresent(replyToID, forKey: .replyToID)
        try container.encode(clientMessageID, forKey: .clientMessageID)
        try container.encodeIfPresent(attachmentUploadID, forKey: .attachmentUploadID)
    }
}

nonisolated struct CreateMessageAttachmentUploadRequestBody: Encodable, Sendable {
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
}

nonisolated struct CreateMessageAttachmentUploadResponse: Decodable, Sendable {
    let upload: MessageAttachmentUploadDTO
}

nonisolated struct MessageAttachmentUploadDTO: Decodable, Sendable {
    let id: UUID
    let uploadUrl: URL
    let method: String
    let headers: [String: String]
    let expiresAt: Date
}

nonisolated struct EditMessageRequestBody: Encodable, Sendable {
    let body: String
}

nonisolated struct MarkConversationReadRequestBody: Encodable, Sendable {
    let lastReadMessageID: UUID?
}

nonisolated struct MarkConversationDeliveredRequestBody: Encodable, Sendable {
    let messageID: UUID
}

nonisolated struct MessageSearchResponseDTO: Decodable, Sendable {
    let messages: [MessageDTO]
    let nextCursor: String?
}

nonisolated struct InviteDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let type: String
    let status: String
    let inviteURL: String?
    let expiresAt: Date?
    let maxUses: Int
    let useCount: Int
    let createdAt: Date?
}

nonisolated struct InviteResponseDTO: Decodable, Sendable {
    let invite: InviteDTO
}

nonisolated struct InvitePreviewDTO: Decodable, Sendable {
    let type: String
    let status: String
    let expiresAt: Date?
    let creatorProfile: MessengerProfileSummaryDTO
}

nonisolated struct InvitePreviewResponseDTO: Decodable, Sendable {
    let invite: InvitePreviewDTO
}

nonisolated struct AcceptInviteResponseDTO: Decodable, Sendable {
    let connection: ConnectionDTO
    let conversation: ConversationDTO
}

nonisolated struct ConnectionDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let profileAID: UUID
    let profileBID: UUID
    let source: String
    let status: String
    let createdAt: Date?
    let updatedAt: Date?
    let endedAt: Date?
}

nonisolated struct CreateInviteRequestBody: Encodable, Sendable {
    let expiresInSeconds: Int?
    let maxUses: Int?
}

enum MessengerLimits {
    nonisolated static let maxMessageLength = 4_000
    nonisolated static let maxImageBytes = 10_485_760
    nonisolated static let defaultConversationPageSize = 30
    nonisolated static let defaultMessagePageSize = 50
}
