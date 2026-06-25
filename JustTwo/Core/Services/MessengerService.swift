import Foundation

enum ConversationService {

    nonisolated static func fetchConversations(
        limit: Int = MessengerLimits.defaultConversationPageSize,
        before: String? = nil
    ) async throws -> ConversationsResponseDTO {
        try await NetworkExecutor.shared.send(
            ListConversationsRequest(limit: limit, before: before)
        )
    }

    nonisolated static func markRead(
        conversationID: UUID,
        lastReadMessageID: UUID? = nil
    ) async throws -> ConversationDTO {
        let response = try await NetworkExecutor.shared.send(
            MarkConversationReadRequest(
                conversationID: conversationID,
                lastReadMessageID: lastReadMessageID
            )
        )
        return response.conversation
    }
}

enum MessageService {

    nonisolated static func fetchMessages(
        conversationID: UUID,
        limit: Int = MessengerLimits.defaultMessagePageSize,
        before: String? = nil
    ) async throws -> MessagesResponseDTO {
        try await NetworkExecutor.shared.send(
            GetMessagesRequest(
                conversationID: conversationID,
                limit: limit,
                before: before
            )
        )
    }

    nonisolated static func sendMessage(
        conversationID: UUID,
        body: String,
        replyToID: UUID? = nil,
        clientMessageID: String
    ) async throws -> MessageDTO {
        let response = try await NetworkExecutor.shared.send(
            SendMessageRequest(
                conversationID: conversationID,
                body: body,
                replyToID: replyToID,
                clientMessageID: clientMessageID
            )
        )
        return response.message
    }

    nonisolated static func editMessage(messageID: UUID, body: String) async throws -> MessageDTO {
        let response = try await NetworkExecutor.shared.send(
            EditMessageRequest(messageID: messageID, body: body)
        )
        return response.message
    }

    nonisolated static func deleteMessage(messageID: UUID) async throws -> MessageDTO {
        try await NetworkExecutor.shared.send(DeleteMessageRequest(messageID: messageID)).message
    }

    nonisolated static func addReaction(messageID: UUID, emoji: String) async throws -> MessageDTO {
        try await NetworkExecutor.shared.send(
            AddMessageReactionRequest(
                messageID: messageID,
                emoji: ReactionEmoji.normalized(emoji)
            )
        ).message
    }

    nonisolated static func removeReaction(messageID: UUID, emoji: String) async throws -> MessageDTO {
        try await NetworkExecutor.shared.send(
            RemoveMessageReactionRequest(
                messageID: messageID,
                emoji: ReactionEmoji.normalized(emoji)
            )
        ).message
    }

    nonisolated static func searchMessages(
        conversationID: UUID,
        query: String,
        limit: Int = 30
    ) async throws -> MessageSearchResponseDTO {
        try await NetworkExecutor.shared.send(
            SearchConversationMessagesRequest(
                conversationID: conversationID,
                query: query,
                limit: limit
            )
        )
    }
}

enum InviteService {

    nonisolated static func createDirectInvite(
        expiresInSeconds: Int? = nil,
        maxUses: Int? = nil
    ) async throws -> InviteDTO {
        try await NetworkExecutor.shared.send(
            CreateDirectInviteRequest(expiresInSeconds: expiresInSeconds, maxUses: maxUses)
        ).invite
    }

    nonisolated static func previewInvite(token: String) async throws -> InvitePreviewDTO {
        try await NetworkExecutor.shared.send(InvitePreviewRequest(token: token)).invite
    }

    nonisolated static func acceptInvite(token: String) async throws -> AcceptInviteResponseDTO {
        try await NetworkExecutor.shared.send(AcceptInviteRequest(token: token))
    }

    nonisolated static func deleteInvite(inviteID: UUID) async throws -> InviteDTO {
        try await NetworkExecutor.shared.send(DeleteInviteRequest(inviteID: inviteID)).invite
    }
}
