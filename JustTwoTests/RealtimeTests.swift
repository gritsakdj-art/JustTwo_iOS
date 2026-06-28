@testable import JustTwo
import Foundation
import Testing

@Suite("Realtime Client Foundation Tests")
struct RealtimeTests {

    @Test("client messages encode backend field names")
    func clientMessagesEncodeBackendFieldNames() throws {
        let conversationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let ping = try jsonObject(for: RealtimeClientMessageDTO.ping())
        #expect(ping["type"] as? String == "ping")
        #expect(ping["conversationID"] == nil)

        let subscribe = try jsonObject(for: RealtimeClientMessageDTO.subscribe(conversationID: conversationID))
        #expect(subscribe["type"] as? String == "subscribe.conversation")
        #expect(subscribe["conversationID"] as? String == conversationID.uuidString)

        let unsubscribe = try jsonObject(for: RealtimeClientMessageDTO.unsubscribe(conversationID: conversationID))
        #expect(unsubscribe["type"] as? String == "unsubscribe.conversation")
        #expect(unsubscribe["conversationID"] as? String == conversationID.uuidString)
    }

    @Test("server events decode PR2 PR3 and PR4 event types")
    func serverEventsDecodeKnownTypes() throws {
        let conversationID = "22222222-2222-2222-2222-222222222222"
        let messageID = "33333333-3333-3333-3333-333333333333"
        let profileID = "44444444-4444-4444-4444-444444444444"

        #expect(try decodeEvent(connectionReadyJSON()).type == "connection.ready")
        #expect(try decodeEvent(pongJSON()).type == "pong")
        #expect(try decodeEvent(errorJSON()).type == "error")

        if case .subscriptionReady(let id) = try decodeEvent(subscriptionReadyJSON(conversationID)) {
            #expect(id.uuidString == conversationID.uppercased())
        } else {
            Issue.record("Expected subscription.ready")
        }

        if case .subscriptionRemoved(let id) = try decodeEvent(subscriptionRemovedJSON(conversationID)) {
            #expect(id.uuidString == conversationID.uppercased())
        } else {
            Issue.record("Expected subscription.removed")
        }

        if case .messageCreated(let id, let message) = try decodeEvent(messageEventJSON("message.created")) {
            #expect(id.uuidString == conversationID.uppercased())
            #expect(message.id.uuidString == messageID.uppercased())
            #expect(message.body == "Hello")
        } else {
            Issue.record("Expected message.created")
        }

        if case .messageEdited(let id, let message) = try decodeEvent(messageEventJSON("message.edited")) {
            #expect(id.uuidString == conversationID.uppercased())
            #expect(message.id.uuidString == messageID.uppercased())
        } else {
            Issue.record("Expected message.edited")
        }

        if case .reactionAdded(_, let payload) = try decodeEvent(reactionAddedJSON()) {
            #expect(payload.messageID.uuidString == messageID.uppercased())
            #expect(payload.reaction.emoji == "❤️")
            #expect(payload.reaction.count == .bool(true))
            #expect(payload.reaction.reactedByMe)
        } else {
            Issue.record("Expected reaction.added")
        }

        if case .reactionRemoved(_, let payload) = try decodeEvent(reactionRemovedJSON()) {
            #expect(payload.messageID.uuidString == messageID.uppercased())
            #expect(payload.profileID?.uuidString == profileID.uppercased())
            #expect(payload.emoji == "❤️")
        } else {
            Issue.record("Expected reaction.removed")
        }

        if case .conversationRead(_, let payload) = try decodeEvent(conversationReadJSON()) {
            #expect(payload.profileID.uuidString == profileID.uppercased())
            #expect(payload.lastReadAt != nil)
        } else {
            Issue.record("Expected conversation.read")
        }

        if case .conversationUpdated(let id, let payload) = try decodeEvent(conversationUpdatedJSON()) {
            #expect(id.uuidString == conversationID.uppercased())
            #expect(payload.conversationID.uuidString == conversationID.uppercased())
            #expect(payload.updatedAt != nil)
        } else {
            Issue.record("Expected conversation.updated")
        }
    }

    @Test("message deleted decodes without body")
    func messageDeletedDecodesWithoutBody() throws {
        guard case .messageDeleted(_, let payload) = try decodeEvent(messageDeletedJSON()) else {
            Issue.record("Expected message.deleted")
            return
        }

        #expect(payload.messageID.uuidString == "33333333-3333-3333-3333-333333333333".uppercased())
        #expect(payload.deletedAt != nil)
        #expect(payload.isDeleted)
    }

    @Test("unknown event does not crash")
    func unknownEventDoesNotCrash() throws {
        guard case .unknown(let type) = try decodeEvent("""
        {
          "type": "future.event",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {"unexpected": true}
        }
        """) else {
            Issue.record("Expected unknown event")
            return
        }

        #expect(type == "future.event")
    }

    @Test("reconnect policy increases and caps")
    func reconnectPolicyIncreasesAndCaps() {
        let policy = RealtimeReconnectPolicy(initialDelay: 1, multiplier: 2, maxDelay: 15)

        #expect(policy.delay(forAttempt: 1) == 1)
        #expect(policy.delay(forAttempt: 2) == 2)
        #expect(policy.delay(forAttempt: 3) == 4)
        #expect(policy.delay(forAttempt: 8) == 15)
    }

    @MainActor
    @Test("intentional disconnect suppresses receive error reconnect")
    func intentionalDisconnectSuppressesReceiveErrorReconnect() {
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.disconnect()
        client.simulateReceiveErrorForTesting(URLError(.networkConnectionLost))

        #expect(client.state == .disconnected)
        #expect(!client.hasPendingReconnectForTesting)
    }

    @MainActor
    @Test("logout style disconnect cancels pending reconnect")
    func logoutStyleDisconnectCancelsPendingReconnect() {
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.simulateReceiveErrorForTesting(URLError(.networkConnectionLost))

        guard case .reconnecting(let attempt) = client.state else {
            Issue.record("Expected reconnecting state")
            return
        }

        #expect(attempt == 1)
        #expect(client.hasPendingReconnectForTesting)

        client.disconnect()

        #expect(client.state == .disconnected)
        #expect(!client.hasPendingReconnectForTesting)
    }

    @MainActor
    @Test("network failure while authenticated schedules reconnect")
    func networkFailureWhileAuthenticatedSchedulesReconnect() {
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.simulateReceiveErrorForTesting(URLError(.networkConnectionLost))

        guard case .reconnecting(let attempt) = client.state else {
            Issue.record("Expected reconnecting state")
            return
        }

        #expect(attempt == 1)
        #expect(client.hasPendingReconnectForTesting)

        client.disconnect()
    }

    @MainActor
    @Test("router routes known and unknown events")
    func routerRoutesEvents() async {
        let router = RealtimeEventRouter.shared
        var iterator = router.stream().makeAsyncIterator()

        router.route(.pong)
        let event = await iterator.next()

        #expect(event?.type == "pong")

        router.route(.unknown(type: "future.event"))
        let unknown = await iterator.next()

        #expect(unknown?.type == "future.event")
    }

    @MainActor
    @Test("messenger realtime message created deduplicates websocket echo")
    func messengerRealtimeMessageCreatedDeduplicatesEcho() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "Realtime hello"
        )
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )

        #expect(viewModel.applyRealtimeMessage(message, currentProfileID: currentProfileID))
        #expect(!viewModel.applyRealtimeMessage(message, currentProfileID: currentProfileID))
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.displayText == "Realtime hello")
    }

    @MainActor
    @Test("messenger realtime edited message replaces existing body")
    func messengerRealtimeEditedMessageReplacesExistingBody() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let original = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "Before"
        )
        let edited = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "After",
            editedAt: "2026-06-26T13:19:00Z"
        )
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )

        #expect(viewModel.applyRealtimeMessage(original, currentProfileID: currentProfileID))
        #expect(!viewModel.applyRealtimeMessage(edited, currentProfileID: currentProfileID))
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.displayText == "After")
        #expect(viewModel.messages.first?.isEdited == true)
    }

    @MainActor
    @Test("messenger realtime deleted message hides body")
    func messengerRealtimeDeletedMessageHidesBody() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: currentProfileID,
            body: "Secret"
        )
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )

        _ = viewModel.applyRealtimeMessage(message, currentProfileID: currentProfileID)
        #expect(viewModel.applyRealtimeDeletedMessage(
            MessageDeletedPayload(
                messageID: fixedMessageID(),
                deletedAt: ISO8601DateFormatter().date(from: "2026-06-26T13:20:00Z"),
                isDeleted: true
            )
        ))

        #expect(viewModel.messages.first?.isDeleted == true)
        #expect(viewModel.messages.first?.rawBody == nil)
    }

    @MainActor
    @Test("messenger realtime reactions are idempotent and removable")
    func messengerRealtimeReactionsAreIdempotentAndRemovable() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "React to me"
        )
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )
        let addPayload = ReactionAddedPayload(
            messageID: fixedMessageID(),
            reaction: RealtimeReactionDTO(emoji: "❤️", count: .bool(true), reactedByMe: true)
        )

        _ = viewModel.applyRealtimeMessage(message, currentProfileID: currentProfileID)
        #expect(viewModel.applyRealtimeReactionAdded(addPayload))
        #expect(viewModel.applyRealtimeReactionAdded(addPayload))
        #expect(viewModel.messages.first?.reactions.count == 1)
        #expect(viewModel.messages.first?.reactions.first?.count == 1)

        #expect(viewModel.applyRealtimeReactionRemoved(
            ReactionRemovedPayload(
                messageID: fixedMessageID(),
                profileID: currentProfileID,
                emoji: "❤️"
            ),
            currentProfileID: currentProfileID
        ))
        #expect(viewModel.messages.first?.reactions.isEmpty == true)
    }

    @MainActor
    @Test("messenger realtime conversation list applies read and reorder")
    func messengerRealtimeConversationListAppliesReadAndReorder() {
        let firstID = fixedConversationID()
        let secondID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let currentProfileID = fixedCurrentProfileID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let viewModel = ConversationListViewModel.preview(conversations: [
            makeConversation(id: firstID, title: "First", lastMessageAt: newer, unreadCount: 3),
            makeConversation(id: secondID, title: "Second", lastMessageAt: older, unreadCount: 1)
        ])

        #expect(viewModel.applyRealtimeConversationRead(
            conversationID: firstID,
            profileID: currentProfileID,
            currentProfileID: currentProfileID
        ))
        #expect(viewModel.conversations.first(where: { $0.id == firstID })?.unreadCount == 0)

        #expect(viewModel.applyRealtimeConversationUpdated(
            ConversationUpdatedPayload(
                conversationID: secondID,
                updatedAt: Date(timeIntervalSince1970: 3_000),
                lastMessageAt: Date(timeIntervalSince1970: 3_000)
            )
        ))
        #expect(viewModel.conversations.first?.id == secondID)
    }

    @MainActor
    @Test("messenger realtime conversation list updates preview and unread once")
    func messengerRealtimeConversationListUpdatesPreviewAndUnreadOnce() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "New realtime message"
        )
        let viewModel = ConversationListViewModel.preview(conversations: [
            makeConversation(id: conversationID, title: "Taylor", unreadCount: 2)
        ])

        #expect(viewModel.applyRealtimeMessage(
            message,
            currentProfileID: currentProfileID,
            activeConversationID: nil
        ))
        #expect(viewModel.conversations.first?.lastMessageText == "New realtime message")
        #expect(viewModel.conversations.first?.lastSenderName == "Taylor")
        #expect(viewModel.conversations.first?.unreadCount == 3)

        #expect(viewModel.applyRealtimeMessage(
            message,
            currentProfileID: currentProfileID,
            activeConversationID: nil
        ))
        #expect(viewModel.conversations.first?.unreadCount == 3)
    }

    @MainActor
    @Test("messenger realtime active conversation does not increment unread")
    func messengerRealtimeActiveConversationDoesNotIncrementUnread() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "Open chat message"
        )
        let viewModel = ConversationListViewModel.preview(conversations: [
            makeConversation(id: conversationID, title: "Taylor", unreadCount: 2)
        ])

        #expect(viewModel.applyRealtimeMessage(
            message,
            currentProfileID: currentProfileID,
            activeConversationID: conversationID
        ))
        #expect(viewModel.conversations.first?.lastMessageText == "Open chat message")
        #expect(viewModel.conversations.first?.unreadCount == 2)
    }

    @MainActor
    @Test("messenger realtime unknown conversation returns false for REST refresh fallback")
    func messengerRealtimeUnknownConversationReturnsFalseForRefreshFallback() throws {
        let currentProfileID = fixedCurrentProfileID()
        let knownConversationID = fixedConversationID()
        let unknownConversationID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: unknownConversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "Unknown conversation"
        )
        let viewModel = ConversationListViewModel.preview(conversations: [
            makeConversation(id: knownConversationID)
        ])

        #expect(!viewModel.applyRealtimeMessage(
            message,
            currentProfileID: currentProfileID,
            activeConversationID: nil
        ))
    }

    private func jsonObject(for message: RealtimeClientMessageDTO) throws -> [String: Any] {
        let data = try JSONCoding.encoder.encode(message)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func decodeEvent(_ json: String) throws -> RealtimeEvent {
        try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(json.utf8)).event
    }

    private func makeMessageDTO(
        id: UUID,
        conversationID: UUID,
        senderProfileID: UUID,
        body: String?,
        editedAt: String? = nil,
        deletedAt: String? = nil
    ) throws -> MessageDTO {
        let bodyJSON = body.map { #""\#($0)""# } ?? "null"
        let editedAtJSON = editedAt.map { #""\#($0)""# } ?? "null"
        let deletedAtJSON = deletedAt.map { #""\#($0)""# } ?? "null"

        return try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "\(senderProfileID.uuidString)",
          "kind": "text",
          "body": \(bodyJSON),
          "replyTo": null,
          "reactions": [],
          "createdAt": "2026-06-26T13:18:31Z",
          "editedAt": \(editedAtJSON),
          "deletedAt": \(deletedAtJSON)
        }
        """.utf8))
    }

    private func makeConversation(
        id: UUID,
        title: String = "Taylor",
        lastMessageAt: Date? = Date(timeIntervalSince1970: 1_000),
        unreadCount: Int = 0
    ) -> ChatConversationPreview {
        ChatConversationPreview(
            id: id,
            title: title,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: nil,
            lastSenderName: nil,
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount
        )
    }

    private func fixedConversationID() -> UUID {
        UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    }

    private func fixedMessageID() -> UUID {
        UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    }

    private func fixedCurrentProfileID() -> UUID {
        UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    }

    private func fixedOtherProfileID() -> UUID {
        UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    }

    @MainActor
    private func makeRealtimeClientForLifecycleTests() -> RealtimeClient {
        RealtimeClient(
            router: .shared,
            reconnectPolicy: RealtimeReconnectPolicy(
                initialDelay: 60,
                multiplier: 2,
                maxDelay: 60
            ),
            tokenProvider: { "test-token" }
        )
    }

    private func connectionReadyJSON() -> String {
        """
        {
          "type": "connection.ready",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {
            "userID": "44444444-4444-4444-4444-444444444444",
            "connectionID": "55555555-5555-5555-5555-555555555555"
          }
        }
        """
    }

    private func pongJSON() -> String {
        """
        {
          "type": "pong",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {}
        }
        """
    }

    private func errorJSON() -> String {
        """
        {
          "type": "error",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "code": "invalid_message",
          "message": "Invalid message",
          "payload": {}
        }
        """
    }

    private func subscriptionReadyJSON(_ conversationID: String) -> String {
        """
        {
          "type": "subscription.ready",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "\(conversationID)",
          "payload": {}
        }
        """
    }

    private func subscriptionRemovedJSON(_ conversationID: String) -> String {
        """
        {
          "type": "subscription.removed",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "\(conversationID)",
          "payload": {}
        }
        """
    }

    private func messageEventJSON(_ type: String) -> String {
        """
        {
          "type": "\(type)",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "message": {
              "id": "33333333-3333-3333-3333-333333333333",
              "conversationID": "22222222-2222-2222-2222-222222222222",
              "senderProfileID": "44444444-4444-4444-4444-444444444444",
              "kind": "text",
              "body": "Hello",
              "replyTo": null,
              "reactions": [],
              "createdAt": "2026-06-26T13:18:31Z",
              "editedAt": null,
              "deletedAt": null
            }
          }
        }
        """
    }

    private func messageDeletedJSON() -> String {
        """
        {
          "type": "message.deleted",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "messageID": "33333333-3333-3333-3333-333333333333",
            "deletedAt": "2026-06-26T13:18:31Z",
            "isDeleted": true
          }
        }
        """
    }

    private func reactionAddedJSON() -> String {
        """
        {
          "type": "reaction.added",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "messageID": "33333333-3333-3333-3333-333333333333",
            "reaction": {
              "emoji": "❤️",
              "count": true,
              "reactedByMe": true
            }
          }
        }
        """
    }

    private func reactionRemovedJSON() -> String {
        """
        {
          "type": "reaction.removed",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "messageID": "33333333-3333-3333-3333-333333333333",
            "profileID": "44444444-4444-4444-4444-444444444444",
            "emoji": "❤️"
          }
        }
        """
    }

    private func conversationReadJSON() -> String {
        """
        {
          "type": "conversation.read",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "profileID": "44444444-4444-4444-4444-444444444444",
            "lastReadAt": "2026-06-26T13:18:31Z"
          }
        }
        """
    }

    private func conversationUpdatedJSON() -> String {
        """
        {
          "type": "conversation.updated",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "conversationID": "22222222-2222-2222-2222-222222222222",
            "updatedAt": "2026-06-26T13:18:31Z",
            "lastMessageAt": "2026-06-26T13:18:31Z"
          }
        }
        """
    }
}
