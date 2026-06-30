import Foundation

struct ListConversationsRequest: APIRequest {
    typealias Response = ConversationsResponseDTO

    let limit: Int
    let before: String?

    var path: String { "conversations" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let before, !before.isEmpty {
            items.append(URLQueryItem(name: "before", value: before))
        }
        return items
    }

    init(limit: Int = MessengerLimits.defaultConversationPageSize, before: String? = nil) {
        self.limit = limit
        self.before = before
    }
}

struct MarkConversationReadRequest: EncodableAPIRequest {
    typealias Response = ConversationResponseDTO
    typealias Body = MarkConversationReadRequestBody

    let conversationID: UUID
    let bodyValue: MarkConversationReadRequestBody?

    var path: String { "conversations/\(conversationID.uuidString)/read" }
    var method: HTTPMethod { .patch }
    var requiresAuth: Bool { true }

    init(conversationID: UUID, lastReadMessageID: UUID? = nil) {
        self.conversationID = conversationID
        bodyValue = MarkConversationReadRequestBody(lastReadMessageID: lastReadMessageID)
    }
}

struct MarkConversationDeliveredRequest: EncodableAPIRequest {
    typealias Response = ConversationResponseDTO
    typealias Body = MarkConversationDeliveredRequestBody

    let conversationID: UUID
    let bodyValue: MarkConversationDeliveredRequestBody?

    var path: String { "conversations/\(conversationID.uuidString)/delivered" }
    var method: HTTPMethod { .patch }
    var requiresAuth: Bool { true }

    init(conversationID: UUID, messageID: UUID) {
        self.conversationID = conversationID
        bodyValue = MarkConversationDeliveredRequestBody(messageID: messageID)
    }
}

struct GetMessagesRequest: APIRequest {
    typealias Response = MessagesResponseDTO

    let conversationID: UUID
    let limit: Int
    let before: String?

    var path: String { "conversations/\(conversationID.uuidString)/messages" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let before, !before.isEmpty {
            items.append(URLQueryItem(name: "before", value: before))
        }
        return items
    }

    init(
        conversationID: UUID,
        limit: Int = MessengerLimits.defaultMessagePageSize,
        before: String? = nil
    ) {
        self.conversationID = conversationID
        self.limit = limit
        self.before = before
    }
}

struct SendMessageRequest: EncodableAPIRequest {
    typealias Response = MessageResponseDTO
    typealias Body = SendMessageRequestBody

    let conversationID: UUID
    let bodyValue: SendMessageRequestBody?

    var path: String { "conversations/\(conversationID.uuidString)/messages" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }

    init(
        conversationID: UUID,
        body: String,
        replyToID: UUID? = nil,
        clientMessageID: String
    ) {
        self.conversationID = conversationID
        bodyValue = SendMessageRequestBody(
            body: body,
            replyToID: replyToID,
            clientMessageID: clientMessageID
        )
    }
}

struct EditMessageRequest: EncodableAPIRequest {
    typealias Response = MessageResponseDTO
    typealias Body = EditMessageRequestBody

    let messageID: UUID
    let bodyValue: EditMessageRequestBody?

    var path: String { "messages/\(messageID.uuidString)" }
    var method: HTTPMethod { .patch }
    var requiresAuth: Bool { true }

    init(messageID: UUID, body: String) {
        self.messageID = messageID
        bodyValue = EditMessageRequestBody(body: body)
    }
}

struct DeleteMessageRequest: APIRequest {
    typealias Response = MessageResponseDTO

    let messageID: UUID

    var path: String { "messages/\(messageID.uuidString)" }
    var method: HTTPMethod { .delete }
    var requiresAuth: Bool { true }
}

struct AddMessageReactionRequest: APIRequest {
    typealias Response = MessageResponseDTO

    let messageID: UUID
    let emoji: String

    var path: String {
        "messages/\(messageID.uuidString)/reactions/\(ReactionEmoji.normalized(emoji))"
    }

    var method: HTTPMethod { .put }
    var requiresAuth: Bool { true }
}

struct RemoveMessageReactionRequest: APIRequest {
    typealias Response = MessageResponseDTO

    let messageID: UUID
    let emoji: String

    var path: String {
        "messages/\(messageID.uuidString)/reactions/\(ReactionEmoji.normalized(emoji))"
    }

    var method: HTTPMethod { .delete }
    var requiresAuth: Bool { true }
}

struct SearchConversationMessagesRequest: APIRequest {
    typealias Response = MessageSearchResponseDTO

    let conversationID: UUID
    let query: String
    let limit: Int

    var path: String { "conversations/\(conversationID.uuidString)/search" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
    }
}

struct CreateDirectInviteRequest: EncodableAPIRequest {
    typealias Response = InviteResponseDTO
    typealias Body = CreateInviteRequestBody

    let bodyValue: CreateInviteRequestBody?

    var path: String { "invites/direct" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }

    init(expiresInSeconds: Int? = nil, maxUses: Int? = nil) {
        bodyValue = CreateInviteRequestBody(expiresInSeconds: expiresInSeconds, maxUses: maxUses)
    }
}

struct InvitePreviewRequest: APIRequest {
    typealias Response = InvitePreviewResponseDTO

    let token: String

    var path: String { "invites/\(token)/preview" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}

struct AcceptInviteRequest: APIRequest {
    typealias Response = AcceptInviteResponseDTO

    let token: String

    var path: String { "invites/\(token)/accept" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }
}

struct DeleteInviteRequest: APIRequest {
    typealias Response = InviteResponseDTO

    let inviteID: UUID

    var path: String { "invites/\(inviteID.uuidString)" }
    var method: HTTPMethod { .delete }
    var requiresAuth: Bool { true }
}
