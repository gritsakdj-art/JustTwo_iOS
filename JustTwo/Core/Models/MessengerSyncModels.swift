import Foundation

struct MessengerSyncStateResponse: Decodable, Sendable {
    let revision: Int64
    let serverTime: Date
}

struct MessengerSyncEventsResponse: Decodable, Sendable {
    let events: [MessengerSyncEventDTO]
    let nextRevision: Int64
    let currentRevision: Int64
    let hasMore: Bool
}

struct MessengerSyncEventDTO: Decodable, Sendable, Identifiable {
    var id: Int64 { revision }

    let revision: Int64
    let type: MessengerSyncEventType
    let conversationID: UUID
    let messageID: UUID?
    let actorProfileID: UUID?
    let occurredAt: Date
    let conversation: ConversationDTO?
    let message: MessageDTO?
    let receipt: MessengerReceiptDTO?

    enum CodingKeys: String, CodingKey {
        case revision
        case type
        case conversationID
        case messageID
        case actorProfileID
        case occurredAt
        case conversation
        case message
        case receipt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int64.self, forKey: .revision)
        type = try container.decode(MessengerSyncEventType.self, forKey: .type)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        messageID = try container.decodeIfPresent(UUID.self, forKey: .messageID)
        actorProfileID = try container.decodeIfPresent(UUID.self, forKey: .actorProfileID)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        conversation = try container.decodeIfPresent(ConversationDTO.self, forKey: .conversation)
        message = try container.decodeIfPresent(MessageDTO.self, forKey: .message)
        receipt = try container.decodeIfPresent(MessengerReceiptDTO.self, forKey: .receipt)
    }
}

enum MessengerSyncEventType: String, Decodable, Sendable {
    case messageCreated = "message.created"
    case messageEdited = "message.edited"
    case messageDeleted = "message.deleted"
    case reactionAdded = "reaction.added"
    case reactionRemoved = "reaction.removed"
    case conversationRead = "conversation.read"
    case conversationDelivered = "conversation.delivered"
    case conversationUpdated = "conversation.updated"
}

struct MessengerReceiptDTO: Decodable, Sendable {
    let profileID: UUID
    let conversationID: UUID
    let messageID: UUID?
    let deliveredAt: Date?
    let readAt: Date?
}

enum MessengerDeltaSyncReason: String, Sendable {
    case bootstrap
    case appForeground
    case realtimeReconnect
    case chatOpened
    case fullRefreshFallback
}

enum MessengerSyncLimits {
    nonisolated static let defaultEventPageSize = 200
    nonisolated static let maximumEventPageSize = 500
}
