import Foundation

struct ConversationsResponseDTO: Decodable, Sendable {
    let conversations: [ConversationDTO]
    let nextCursor: String?
}

struct ConversationResponseDTO: Decodable, Sendable {
    let conversation: ConversationDTO
}

struct ConversationDTO: Decodable, Identifiable, Sendable {
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

struct ConversationParticipantDTO: Decodable, Sendable {
    let profile: MessengerProfileSummaryDTO
    let role: String
    let joinedAt: Date
    let lastReadAt: Date?
    let lastDeliveredAt: Date?
}

struct MessengerProfileSummaryDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let bio: String?
    let city: String?
    let primaryPhoto: MessengerProfilePhotoSummaryDTO?
}

struct MessengerProfilePhotoSummaryDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let downloadUrl: String
    let avatarPresentation: AvatarPresentationDTO
}

struct MessagesResponseDTO: Decodable, Sendable {
    let messages: [MessageDTO]
    let nextCursor: String?
}

struct MessageResponseDTO: Decodable, Sendable {
    let message: MessageDTO
}

struct MessageDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderProfileID: UUID
    let kind: String
    let body: String?
    let replyTo: MessageReplyDTO?
    let reactions: [MessageReactionDTO]
    let deliveryStatus: MessageDeliveryStatus?
    let createdAt: Date?
    let editedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID
        case senderProfileID
        case kind
        case body
        case replyTo
        case reactions
        case deliveryStatus
        case createdAt
        case editedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        senderProfileID = try container.decode(UUID.self, forKey: .senderProfileID)
        kind = try container.decode(String.self, forKey: .kind)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        replyTo = try container.decodeIfPresent(MessageReplyDTO.self, forKey: .replyTo)
        reactions = try container.decodeIfPresent([MessageReactionDTO].self, forKey: .reactions) ?? []
        deliveryStatus = try container.decodeIfPresent(MessageDeliveryStatus.self, forKey: .deliveryStatus)
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

struct MessageReplyDTO: Decodable, Sendable {
    let id: UUID
    let body: String?
    let senderProfileID: UUID
}

struct MessageReactionDTO: Decodable, Sendable, Hashable {
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
    static func normalized(_ emoji: String) -> String {
        emoji.removingPercentEncoding ?? emoji
    }

    /// Defensive display fallback for legacy/local percent-encoded values.
    static func display(_ emoji: String) -> String {
        normalized(emoji)
    }
}

struct SendMessageRequestBody: Encodable, Sendable {
    let body: String
    let replyToID: UUID?
    let clientMessageID: String
}

struct EditMessageRequestBody: Encodable, Sendable {
    let body: String
}

struct MarkConversationReadRequestBody: Encodable, Sendable {
    let lastReadMessageID: UUID?
}

struct MarkConversationDeliveredRequestBody: Encodable, Sendable {
    let messageID: UUID
}

struct MessageSearchResponseDTO: Decodable, Sendable {
    let messages: [MessageDTO]
    let nextCursor: String?
}

struct InviteDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let type: String
    let status: String
    let inviteURL: String?
    let expiresAt: Date?
    let maxUses: Int
    let useCount: Int
    let createdAt: Date?
}

struct InviteResponseDTO: Decodable, Sendable {
    let invite: InviteDTO
}

struct InvitePreviewDTO: Decodable, Sendable {
    let type: String
    let status: String
    let expiresAt: Date?
    let creatorProfile: MessengerProfileSummaryDTO
}

struct InvitePreviewResponseDTO: Decodable, Sendable {
    let invite: InvitePreviewDTO
}

struct AcceptInviteResponseDTO: Decodable, Sendable {
    let connection: ConnectionDTO
    let conversation: ConversationDTO
}

struct ConnectionDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let profileAID: UUID
    let profileBID: UUID
    let source: String
    let status: String
    let createdAt: Date?
    let updatedAt: Date?
    let endedAt: Date?
}

struct CreateInviteRequestBody: Encodable, Sendable {
    let expiresInSeconds: Int?
    let maxUses: Int?
}

enum MessengerLimits {
    nonisolated static let maxMessageLength = 4_000
    nonisolated static let defaultConversationPageSize = 30
    nonisolated static let defaultMessagePageSize = 50
}
