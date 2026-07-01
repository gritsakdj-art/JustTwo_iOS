@testable import JustTwo
import CoreGraphics
import Foundation
import Testing

@MainActor
@Suite("Conversation Delivery Ack Tests")
struct ConversationDeliveryAckTests {

    @Test("dedup prevents repeated delivered ack for same message")
    func dedupPreventsRepeatedDeliveredAck() {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        let conversationID = fixedConversationID()
        let messageID = fixedMessageID()

        #expect(coordinator.shouldSendDelivered(conversationID: conversationID, messageID: messageID))
        coordinator.markDeliveredAcked(conversationID: conversationID, messageID: messageID)
        #expect(!coordinator.shouldSendDelivered(conversationID: conversationID, messageID: messageID))
    }

    @Test("read ack suppresses delivered ack")
    func readAckSuppressesDeliveredAck() {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        let conversationID = fixedConversationID()
        let messageID = fixedMessageID()

        coordinator.markReadAcked(conversationID: conversationID, messageID: messageID)
        #expect(!coordinator.shouldSendDelivered(conversationID: conversationID, messageID: messageID))
        #expect(!coordinator.shouldSendRead(conversationID: conversationID, messageID: messageID))
    }

    @Test("conversation list load sends delivered ack for inbound last message")
    func conversationListLoadSendsDeliveredAck() async throws {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        var deliveredCalls: [(UUID, UUID)] = []
        coordinator.markDeliveredHandler = { conversationID, messageID in
            deliveredCalls.append((conversationID, messageID))
        }

        let conversation = try makeConversationDTO(
            conversationID: fixedConversationID(),
            lastMessageSenderID: fixedOtherProfileID(),
            lastMessageID: fixedMessageID()
        )

        await coordinator.acknowledgeDeliveredForConversations(
            [conversation],
            currentProfileID: fixedCurrentProfileID(),
            session: makeAuthenticatedSession(),
            router: AppRouter.shared
        )

        #expect(deliveredCalls.count == 1)
        #expect(deliveredCalls[0].0 == fixedConversationID())
        #expect(deliveredCalls[0].1 == fixedMessageID())
    }

    @Test("conversation list load does not send delivered ack for own last message")
    func conversationListSkipsOwnLastMessage() async throws {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        var deliveredCalls = 0
        coordinator.markDeliveredHandler = { _, _ in
            deliveredCalls += 1
        }

        let conversation = try makeConversationDTO(
            conversationID: fixedConversationID(),
            lastMessageSenderID: fixedCurrentProfileID(),
            lastMessageID: fixedMessageID()
        )

        await coordinator.acknowledgeDeliveredForConversations(
            [conversation],
            currentProfileID: fixedCurrentProfileID(),
            session: makeAuthenticatedSession(),
            router: AppRouter.shared
        )

        #expect(deliveredCalls == 0)
    }

    @Test("duplicate list refresh does not repeat delivered ack")
    func duplicateListRefreshDoesNotRepeatDeliveredAck() async throws {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        var deliveredCalls = 0
        coordinator.markDeliveredHandler = { _, _ in
            deliveredCalls += 1
        }

        let conversation = try makeConversationDTO(
            conversationID: fixedConversationID(),
            lastMessageSenderID: fixedOtherProfileID(),
            lastMessageID: fixedMessageID()
        )
        let session = makeAuthenticatedSession()

        await coordinator.acknowledgeDeliveredForConversations(
            [conversation],
            currentProfileID: fixedCurrentProfileID(),
            session: session,
            router: AppRouter.shared
        )
        await coordinator.acknowledgeDeliveredForConversations(
            [conversation],
            currentProfileID: fixedCurrentProfileID(),
            session: session,
            router: AppRouter.shared
        )

        #expect(deliveredCalls == 1)
    }

    @Test("realtime inactive conversation sends delivered ack")
    func realtimeInactiveConversationSendsDeliveredAck() async throws {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        var deliveredCalls: [(UUID, UUID)] = []
        coordinator.markDeliveredHandler = { conversationID, messageID in
            deliveredCalls.append((conversationID, messageID))
        }

        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: fixedConversationID(),
            senderProfileID: fixedOtherProfileID()
        )

        await coordinator.acknowledgeDeliveredIfNeeded(
            conversationID: fixedConversationID(),
            message: message,
            currentProfileID: fixedCurrentProfileID(),
            session: makeAuthenticatedSession(),
            router: AppRouter.shared
        )

        #expect(deliveredCalls.count == 1)
    }

    @Test("initial scroll target opens at bottom when unread exists")
    func initialScrollTargetOpensAtBottomWithUnread() {
        let conversation = makeConversation(unreadCount: 2)
        let messages = [
            makeChatMessage(id: fixedMessageID(offset: 1), isMine: false, body: "older"),
            makeChatMessage(id: fixedMessageID(offset: 2), isMine: true, body: "read"),
            makeChatMessage(id: fixedMessageID(offset: 3), isMine: false, body: "unread 1"),
            makeChatMessage(id: fixedMessageID(offset: 4), isMine: false, body: "unread 2")
        ]
        let viewModel = ChatViewModel.preview(conversation: conversation, messages: messages)

        #expect(viewModel.initialScrollTarget(pushTargetMessageID: nil) == .bottom)
        #expect(viewModel.firstUnreadMessageID == fixedMessageID(offset: 3))
    }

    @Test("initial scroll target opens at bottom when no unread exists")
    func initialScrollTargetOpensAtBottomWithoutUnread() {
        let conversation = makeConversation(unreadCount: 0)
        let messageID = fixedMessageID()
        let viewModel = ChatViewModel.preview(
            conversation: conversation,
            messages: [makeChatMessage(id: messageID, isMine: false, body: "hello")]
        )

        #expect(viewModel.initialScrollTarget(pushTargetMessageID: nil) == .bottom)
    }

    @Test("initial scroll target uses push message when provided")
    func initialScrollTargetUsesPushMessage() {
        let conversation = makeConversation(unreadCount: 0)
        let targetID = fixedMessageID(offset: 2)
        let viewModel = ChatViewModel.preview(
            conversation: conversation,
            messages: [
                makeChatMessage(id: fixedMessageID(offset: 1), isMine: false, body: "older"),
                makeChatMessage(id: targetID, isMine: false, body: "target")
            ]
        )

        #expect(viewModel.initialScrollTarget(pushTargetMessageID: targetID) == .targetMessage(targetID))
    }

    @Test("down button visibility tracks last read message frame")
    func downButtonVisibilityTracksLastReadMessage() {
        let visible = ChatViewModel.isMessageVisibleInViewport(
            frame: CGRect(x: 0, y: 380, width: 320, height: 44),
            viewportHeight: 500
        )
        let hidden = ChatViewModel.isMessageVisibleInViewport(
            frame: CGRect(x: 0, y: 520, width: 320, height: 44),
            viewportHeight: 500
        )

        #expect(visible)
        #expect(!hidden)
    }

    private func makeAuthenticatedSession() -> SessionStore {
        let session = SessionStore.shared
        if let profile = try? makeProfile(id: fixedCurrentProfileID()) {
            session.updateCurrentProfile(profile)
        }
        return session
    }

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

    private func makeConversationDTO(
        conversationID: UUID,
        lastMessageSenderID: UUID,
        lastMessageID: UUID
    ) throws -> ConversationDTO {
        try JSONCoding.decoder.decode(ConversationDTO.self, from: Data("""
        {
          "id": "\(conversationID.uuidString)",
          "type": "direct",
          "status": "active",
          "connectionID": null,
          "otherParticipant": null,
          "lastMessage": {
            "id": "\(lastMessageID.uuidString)",
            "conversationID": "\(conversationID.uuidString)",
            "senderProfileID": "\(lastMessageSenderID.uuidString)",
            "kind": "text",
            "body": "Hello",
            "replyTo": null,
            "reactions": [],
            "createdAt": "2026-06-26T13:18:31Z",
            "editedAt": null,
            "deletedAt": null
          },
          "unreadCount": 1,
          "lastReadAt": null,
          "lastMessageAt": "2026-06-26T13:18:31Z",
          "createdAt": "2026-06-26T13:18:31Z",
          "updatedAt": "2026-06-26T13:18:31Z"
        }
        """.utf8))
    }

    private func makeMessageDTO(
        id: UUID,
        conversationID: UUID,
        senderProfileID: UUID
    ) throws -> MessageDTO {
        try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "\(senderProfileID.uuidString)",
          "kind": "text",
          "body": "Hello",
          "replyTo": null,
          "reactions": [],
          "createdAt": "2026-06-26T13:18:31Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))
    }

    private func makeConversation(unreadCount: Int) -> ChatConversationPreview {
        ChatConversationPreview(
            id: fixedConversationID(),
            title: "Taylor",
            otherParticipantProfileID: fixedOtherProfileID(),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Hello",
            lastSenderName: nil,
            lastMessageAt: Date(),
            unreadCount: unreadCount
        )
    }

    private func makeChatMessage(id: UUID, isMine: Bool, body: String) -> ChatMessage {
        ChatMessage(
            id: id,
            displayText: body,
            rawBody: body,
            createdAt: Date(),
            isMine: isMine,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: isMine ? .sent : nil
        )
    }

    private func fixedConversationID() -> UUID {
        UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    }

    private func fixedMessageID(offset: Int = 0) -> UUID {
        UUID(uuidString: String(format: "33333333-3333-4333-8333-33333333%04X", offset))!
    }

    private func fixedCurrentProfileID() -> UUID {
        UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    }

    private func fixedOtherProfileID() -> UUID {
        UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    }
}
