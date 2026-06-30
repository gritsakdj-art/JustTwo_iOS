import Foundation

struct RealtimeEventDTO: Decodable, Sendable {
    let type: String
    let eventID: UUID?
    let occurredAt: Date?
    let conversationID: UUID?
    let payload: RealtimePayload
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case eventID
        case occurredAt
        case conversationID
        case payload
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decode(String.self, forKey: .type)
        eventID = try container.decodeIfPresent(UUID.self, forKey: .eventID)
        occurredAt = try container.decodeIfPresent(Date.self, forKey: .occurredAt)
        conversationID = try container.decodeIfPresent(UUID.self, forKey: .conversationID)
        payload = try container.decodeIfPresent(RealtimePayload.self, forKey: .payload) ?? RealtimePayload()
        code = try container.decodeIfPresent(String.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    var event: RealtimeEvent {
        switch type {
        case "connection.ready":
            return .connectionReady(
                ConnectionReadyPayload(
                    userID: payload.userID,
                    connectionID: payload.connectionID
                )
            )

        case "pong":
            return .pong

        case "error":
            return .error(
                RealtimeErrorPayload(
                    code: code ?? payload.code ?? "unknown",
                    message: message ?? payload.messageText ?? "Realtime error"
                )
            )

        case "subscription.ready":
            guard let id = conversationID ?? payload.conversationID else {
                return .unknown(type: type)
            }
            return .subscriptionReady(conversationID: id)

        case "subscription.removed":
            guard let id = conversationID ?? payload.conversationID else {
                return .unknown(type: type)
            }
            return .subscriptionRemoved(conversationID: id)

        case "message.created":
            guard let message = payload.message else {
                return .unknown(type: type)
            }
            return .messageCreated(
                conversationID: conversationID ?? payload.conversationID ?? message.conversationID,
                message: message
            )

        case "message.edited":
            guard let message = payload.message else {
                return .unknown(type: type)
            }
            return .messageEdited(
                conversationID: conversationID ?? payload.conversationID ?? message.conversationID,
                message: message
            )

        case "message.deleted":
            guard let id = conversationID ?? payload.conversationID,
                  let messageID = payload.messageID else {
                return .unknown(type: type)
            }
            return .messageDeleted(
                conversationID: id,
                payload: MessageDeletedPayload(
                    messageID: messageID,
                    deletedAt: payload.deletedAt,
                    isDeleted: payload.isDeleted ?? true
                )
            )

        case "reaction.added":
            guard let id = conversationID ?? payload.conversationID,
                  let messageID = payload.messageID,
                  let reaction = payload.reaction else {
                return .unknown(type: type)
            }
            return .reactionAdded(
                conversationID: id,
                payload: ReactionAddedPayload(
                    messageID: messageID,
                    reaction: reaction
                )
            )

        case "reaction.removed":
            guard let id = conversationID ?? payload.conversationID,
                  let messageID = payload.messageID,
                  let emoji = payload.emoji else {
                return .unknown(type: type)
            }
            return .reactionRemoved(
                conversationID: id,
                payload: ReactionRemovedPayload(
                    messageID: messageID,
                    profileID: payload.profileID,
                    emoji: ReactionEmoji.normalized(emoji)
                )
            )

        case "conversation.read":
            guard let id = conversationID ?? payload.conversationID,
                  let profileID = payload.profileID else {
                return .unknown(type: type)
            }
            return .conversationRead(
                conversationID: id,
                payload: ConversationReadPayload(
                    profileID: profileID,
                    lastReadAt: payload.lastReadAt
                )
            )

        case "conversation.updated":
            guard let id = conversationID ?? payload.conversationID else {
                return .unknown(type: type)
            }
            return .conversationUpdated(
                conversationID: id,
                payload: ConversationUpdatedPayload(
                    conversationID: id,
                    updatedAt: payload.updatedAt,
                    lastMessageAt: payload.lastMessageAt
                )
            )

        case "typing.started":
            guard let id = conversationID ?? payload.conversationID,
                  let profileID = payload.profileID else {
                return .unknown(type: type)
            }
            return .typingStarted(conversationID: id, profileID: profileID)

        case "typing.stopped":
            guard let id = conversationID ?? payload.conversationID,
                  let profileID = payload.profileID else {
                return .unknown(type: type)
            }
            return .typingStopped(conversationID: id, profileID: profileID)

        case "presence.changed":
            guard let profileID = payload.profileID,
                  let statusRaw = payload.status else {
                return .unknown(type: type)
            }
            return .presenceChanged(
                payload: PresenceChangedPayload(
                    profileID: profileID,
                    status: PresenceStatus(serverValue: statusRaw),
                    lastSeenAt: payload.lastSeenAt
                )
            )

        default:
            return .unknown(type: type)
        }
    }
}

enum RealtimeEvent: Sendable {
    case connectionReady(ConnectionReadyPayload)
    case pong
    case error(RealtimeErrorPayload)
    case subscriptionReady(conversationID: UUID)
    case subscriptionRemoved(conversationID: UUID)
    case messageCreated(conversationID: UUID, message: MessageDTO)
    case messageEdited(conversationID: UUID, message: MessageDTO)
    case messageDeleted(conversationID: UUID, payload: MessageDeletedPayload)
    case reactionAdded(conversationID: UUID, payload: ReactionAddedPayload)
    case reactionRemoved(conversationID: UUID, payload: ReactionRemovedPayload)
    case conversationRead(conversationID: UUID, payload: ConversationReadPayload)
    case conversationUpdated(conversationID: UUID, payload: ConversationUpdatedPayload)
    case typingStarted(conversationID: UUID, profileID: UUID)
    case typingStopped(conversationID: UUID, profileID: UUID)
    case presenceChanged(payload: PresenceChangedPayload)
    case unknown(type: String)

    var type: String {
        switch self {
        case .connectionReady:
            return "connection.ready"
        case .pong:
            return "pong"
        case .error:
            return "error"
        case .subscriptionReady:
            return "subscription.ready"
        case .subscriptionRemoved:
            return "subscription.removed"
        case .messageCreated:
            return "message.created"
        case .messageEdited:
            return "message.edited"
        case .messageDeleted:
            return "message.deleted"
        case .reactionAdded:
            return "reaction.added"
        case .reactionRemoved:
            return "reaction.removed"
        case .conversationRead:
            return "conversation.read"
        case .conversationUpdated:
            return "conversation.updated"
        case .typingStarted:
            return "typing.started"
        case .typingStopped:
            return "typing.stopped"
        case .presenceChanged:
            return "presence.changed"
        case .unknown(let type):
            return type
        }
    }
}

struct ConnectionReadyPayload: Equatable, Sendable {
    let userID: UUID?
    let connectionID: UUID?
}

struct RealtimeErrorPayload: Equatable, Sendable {
    let code: String
    let message: String
}

struct MessageDeletedPayload: Equatable, Sendable {
    let messageID: UUID
    let deletedAt: Date?
    let isDeleted: Bool
}

struct ReactionAddedPayload: Equatable, Sendable {
    let messageID: UUID
    let reaction: RealtimeReactionDTO
}

struct ReactionRemovedPayload: Equatable, Sendable {
    let messageID: UUID
    let profileID: UUID?
    let emoji: String
}

struct ConversationReadPayload: Equatable, Sendable {
    let profileID: UUID
    let lastReadAt: Date?
}

struct ConversationUpdatedPayload: Equatable, Sendable {
    let conversationID: UUID
    let updatedAt: Date?
    let lastMessageAt: Date?
}

struct RealtimeReactionDTO: Decodable, Equatable, Sendable {
    let emoji: String
    let count: RealtimeReactionCount
    let reactedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case emoji
        case count
        case reactedByMe
    }

    init(emoji: String, count: RealtimeReactionCount, reactedByMe: Bool) {
        self.emoji = ReactionEmoji.normalized(emoji)
        self.count = count
        self.reactedByMe = reactedByMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        emoji = ReactionEmoji.normalized(try container.decode(String.self, forKey: .emoji))
        count = try container.decode(RealtimeReactionCount.self, forKey: .count)
        reactedByMe = try container.decode(Bool.self, forKey: .reactedByMe)
    }
}

enum RealtimeReactionCount: Decodable, Equatable, Sendable {
    case int(Int)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }

        self = .bool(try container.decode(Bool.self))
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .bool:
            return nil
        }
    }
}

struct RealtimePayload: Decodable, Sendable {
    let userID: UUID?
    let connectionID: UUID?
    let conversationID: UUID?
    let message: MessageDTO?
    let messageID: UUID?
    let deletedAt: Date?
    let isDeleted: Bool?
    let reaction: RealtimeReactionDTO?
    let profileID: UUID?
    let emoji: String?
    let lastReadAt: Date?
    let lastSeenAt: Date?
    let updatedAt: Date?
    let lastMessageAt: Date?
    let status: String?
    let code: String?
    let messageText: String?

    var messageValue: MessageDTO? { message }
    var errorMessage: String? { messageText }

    init() {
        userID = nil
        connectionID = nil
        conversationID = nil
        message = nil
        messageID = nil
        deletedAt = nil
        isDeleted = nil
        reaction = nil
        profileID = nil
        emoji = nil
        lastReadAt = nil
        lastSeenAt = nil
        updatedAt = nil
        lastMessageAt = nil
        status = nil
        code = nil
        messageText = nil
    }

    enum CodingKeys: String, CodingKey {
        case userID
        case connectionID
        case conversationID
        case message
        case messageID
        case deletedAt
        case isDeleted
        case reaction
        case profileID
        case emoji
        case lastReadAt
        case lastSeenAt
        case updatedAt
        case lastMessageAt
        case status
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userID = try container.decodeIfPresent(UUID.self, forKey: .userID)
        connectionID = try container.decodeIfPresent(UUID.self, forKey: .connectionID)
        conversationID = try container.decodeIfPresent(UUID.self, forKey: .conversationID)
        message = try? container.decode(MessageDTO.self, forKey: .message)
        messageID = try container.decodeIfPresent(UUID.self, forKey: .messageID)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
        reaction = try container.decodeIfPresent(RealtimeReactionDTO.self, forKey: .reaction)
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        messageText = try? container.decode(String.self, forKey: .message)
    }
}
