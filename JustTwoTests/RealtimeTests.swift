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
            #expect(payload.messageID?.uuidString == messageID.uppercased())
        } else {
            Issue.record("Expected conversation.read")
        }

        if case .conversationDelivered(_, let payload) = try decodeEvent(conversationDeliveredJSON()) {
            #expect(payload.profileID.uuidString == profileID.uppercased())
            #expect(payload.lastDeliveredAt != nil)
            #expect(payload.messageID?.uuidString == messageID.uppercased())
        } else {
            Issue.record("Expected conversation.delivered")
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
        let context = RealtimeConnectionContext(
            connectionID: UUID(),
            connectionEpoch: 1,
            sessionGeneration: 0
        )

        router.route(.pong, context: context)
        let routed = await iterator.next()

        #expect(routed?.event.type == "pong")

        router.route(.unknown(type: "future.event"), context: context)
        let unknown = await iterator.next()

        #expect(unknown?.event.type == "future.event")
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
        #expect(viewModel.applyRealtimeMessage(edited, currentProfileID: currentProfileID))
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
        #expect(!viewModel.applyRealtimeReactionAdded(addPayload))
        #expect(viewModel.messages.first?.reactions.count == 1)
        #expect(viewModel.messages.first?.reactions.first?.count == 1)
        #expect(viewModel.messages.first?.reactions.first?.reactedByMe == true)

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

    @MainActor
    @Test("message delivery status decodes and maps for outgoing only")
    func messageDeliveryStatusDecodesAndMapsForOutgoingOnly() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()

        for status in ["sent", "delivered", "read"] {
            let dto = try makeMessageDTO(
                id: UUID(),
                conversationID: conversationID,
                senderProfileID: currentProfileID,
                body: "Status",
                deliveryStatus: status
            )
            #expect(dto.deliveryStatus?.rawValue == status)
            #expect(ChatUIMapping.message(from: dto, currentProfileID: currentProfileID).deliveryStatus?.rawValue == status)
        }

        let omitted = try makeMessageDTO(
            id: UUID(),
            conversationID: conversationID,
            senderProfileID: currentProfileID,
            body: "Default"
        )
        #expect(ChatUIMapping.message(from: omitted, currentProfileID: currentProfileID).deliveryStatus == .sent)

        let incoming = try makeMessageDTO(
            id: UUID(),
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "Incoming",
            deliveryStatus: "read"
        )
        #expect(ChatUIMapping.message(from: incoming, currentProfileID: currentProfileID).deliveryStatus == nil)

        let unknown = try makeMessageDTO(
            id: UUID(),
            conversationID: conversationID,
            senderProfileID: currentProfileID,
            body: "Future",
            deliveryStatus: "future-status"
        )
        #expect(unknown.deliveryStatus == .sent)
    }

    @MainActor
    @Test("receipt events update outgoing messages without downgrade")
    func receiptEventsUpdateOutgoingMessagesWithoutDowngrade() {
        let conversationID = fixedConversationID()
        let firstID = UUID(uuidString: "AAAAAAA1-1111-4111-8111-111111111111")!
        let secondID = UUID(uuidString: "AAAAAAA2-2222-4222-8222-222222222222")!
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: [
                makeChatMessage(id: firstID, createdAt: firstDate, isMine: true, status: .sent),
                makeChatMessage(id: secondID, createdAt: secondDate, isMine: true, status: .sent),
                makeChatMessage(id: UUID(), createdAt: secondDate.addingTimeInterval(1), isMine: false, status: nil)
            ]
        )

        #expect(viewModel.applyDeliveryStatus(.delivered, messageID: secondID, cutoffDate: nil))
        #expect(viewModel.messages[0].deliveryStatus == .delivered)
        #expect(viewModel.messages[1].deliveryStatus == .delivered)
        #expect(viewModel.messages[2].deliveryStatus == nil)

        #expect(viewModel.applyDeliveryStatus(.read, messageID: nil, cutoffDate: firstDate))
        #expect(viewModel.messages[0].deliveryStatus == .read)
        #expect(viewModel.messages[1].deliveryStatus == .delivered)

        #expect(!viewModel.applyDeliveryStatus(.delivered, messageID: firstID, cutoffDate: nil))
        #expect(viewModel.messages[0].deliveryStatus == .read)
    }

    @MainActor
    @Test("coordinator applies message.created through cache when active chat view model is nil")
    func coordinatorAppliesMessageCreatedThroughCacheWhenActiveViewModelNil() async throws {
        let conversationID = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
        let currentProfileID = fixedCurrentProfileID()
        let message = try makeMessageDTO(
            id: UUID(uuidString: "A3333333-3333-4333-8333-333333333333")!,
            conversationID: conversationID,
            senderProfileID: fixedOtherProfileID(),
            body: "Fallback hello"
        )

        MessageCacheStore.shared.reset()
        MessengerDiagnosticsStore.shared.clear()

        let presenceStore = PresenceStore.makeForTesting()
        let eventRouter = RealtimeEventRouter.makeForTesting()
        let coordinator = MessengerRealtimeCoordinator(
            realtimeClient: makeTestRealtimeClient(),
            eventRouter: eventRouter,
            presenceStore: presenceStore
        )

        let session = SessionStore.shared
        let previousProfile = session.currentProfile
        defer {
            session.updateCurrentProfile(previousProfile)
            coordinator.stop()
            MessageCacheStore.shared.reset()
        }

        session.updateCurrentProfile(try makeProfile(id: currentProfileID))
        coordinator.activateConversationList(
            ConversationListViewModel.preview(conversations: [makeConversation(id: conversationID)]),
            session: session,
            router: AppRouter.shared
        )
        coordinator.testing_simulateActiveConversationWithoutViewModel(conversationID: conversationID)

        // Let auto-connect from activateConversationList settle, then isolate transport context.
        try await Task.sleep(for: .milliseconds(200))
        RealtimeClient.shared.disconnect()
        RealtimeTransportGuard.resetForTesting()
        let context = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)

        eventRouter.route(.messageCreated(conversationID: conversationID, message: message), context: context)

        let applied = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            MessageCacheStore.shared.messages(for: conversationID)?.contains(where: { $0.id == message.id }) == true
        }

        #expect(applied)
        let cachedMessage = MessageCacheStore.shared.messages(for: conversationID)?
            .first(where: { $0.id == message.id })
        #expect(cachedMessage?.displayText == "Fallback hello")
    }

    @MainActor
    private func makeTestRealtimeClient() -> RealtimeClient {
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

    @MainActor
    private func makeProfile(id: UUID) throws -> UserProfileDTO {
        try JSONCoding.decoder.decode(UserProfileDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "displayName": "Me",
          "birthDate": "1990-01-01",
          "gender": "other",
          "bio": null,
          "city": null,
          "latitude": null,
          "longitude": null,
          "moodModeEnabled": false,
          "activityModeEnabled": false,
          "isVisibleInDiscovery": true
        }
        """.utf8))
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return condition()
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
        deliveryStatus: String? = nil,
        editedAt: String? = nil,
        deletedAt: String? = nil
    ) throws -> MessageDTO {
        let bodyJSON = body.map { #""\#($0)""# } ?? "null"
        let deliveryStatusJSON = deliveryStatus.map { #""\#($0)""# } ?? "null"
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
          "deliveryStatus": \(deliveryStatusJSON),
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
            otherParticipantProfileID: nil,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: nil,
            lastSenderName: nil,
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount
        )
    }

    private func makeChatMessage(
        id: UUID,
        createdAt: Date,
        isMine: Bool,
        status: MessageDeliveryStatus?
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            displayText: "Message",
            rawBody: "Message",
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: status
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
    @Test("receive timeout with notifications enabled schedules reconnect")
    func receiveTimeoutWithNotificationsEnabledSchedulesReconnect() {
        let previous = MessageNotificationPreferences.messagesEnabled
        defer { MessageNotificationPreferences.messagesEnabled = previous }

        MessageNotificationPreferences.messagesEnabled = true
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.simulateReceiveErrorForTesting(URLError(.timedOut))

        guard case .reconnecting(let attempt) = client.state else {
            Issue.record("Expected reconnecting state")
            return
        }

        #expect(attempt == 1)
        #expect(client.hasPendingReconnectForTesting)
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
            "lastReadAt": "2026-06-26T13:18:31Z",
            "messageID": "33333333-3333-3333-3333-333333333333"
          }
        }
        """
    }

    private func conversationDeliveredJSON() -> String {
        """
        {
          "type": "conversation.delivered",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "profileID": "44444444-4444-4444-4444-444444444444",
            "lastDeliveredAt": "2026-06-26T13:18:31Z",
            "messageID": "33333333-3333-3333-3333-333333333333"
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
