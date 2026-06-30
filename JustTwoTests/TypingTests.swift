@testable import JustTwo
import Foundation
import Testing

@Suite("Typing Indicators PR7 Tests")
struct TypingTests {

    @Test("client messages encode typing started and stopped")
    func clientMessagesEncodeTyping() throws {
        let conversationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let started = try jsonObject(for: RealtimeClientMessageDTO.typingStarted(conversationID: conversationID))
        #expect(started["type"] as? String == "typing.started")
        #expect(started["conversationID"] as? String == conversationID.uuidString)

        let stopped = try jsonObject(for: RealtimeClientMessageDTO.typingStopped(conversationID: conversationID))
        #expect(stopped["type"] as? String == "typing.stopped")
        #expect(stopped["conversationID"] as? String == conversationID.uuidString)
    }

    @Test("server events decode typing started and stopped")
    func serverEventsDecodeTyping() throws {
        if case .typingStarted(let conversationID, let profileID) = try decodeEvent(typingStartedJSON()) {
            #expect(conversationID.uuidString == "22222222-2222-2222-2222-222222222222".uppercased())
            #expect(profileID.uuidString == "44444444-4444-4444-4444-444444444444".uppercased())
        } else {
            Issue.record("Expected typing.started")
        }

        if case .typingStopped(let conversationID, let profileID) = try decodeEvent(typingStoppedJSON()) {
            #expect(conversationID.uuidString == "22222222-2222-2222-2222-222222222222".uppercased())
            #expect(profileID.uuidString == "44444444-4444-4444-4444-444444444444".uppercased())
        } else {
            Issue.record("Expected typing.stopped")
        }
    }

    @MainActor
    @Test("chat view model applies typing started and stopped")
    func chatViewModelTypingState() {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let otherProfileID = fixedOtherProfileID()
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )

        viewModel.applyTypingStarted(profileID: otherProfileID)
        #expect(viewModel.isOtherParticipantTyping)
        #expect(viewModel.typingProfileIDs.contains(otherProfileID))

        viewModel.applyTypingStopped(profileID: otherProfileID)
        #expect(!viewModel.isOtherParticipantTyping)
        #expect(viewModel.typingProfileIDs.isEmpty)
    }

    @MainActor
    @Test("typing indicator hides for current user profile")
    func chatViewModelIgnoresSelfTyping() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )
        let ownMessage = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: currentProfileID,
            body: "mine"
        )
        _ = viewModel.applyRealtimeMessage(ownMessage, currentProfileID: currentProfileID)

        viewModel.applyTypingStarted(profileID: currentProfileID)
        #expect(!viewModel.isOtherParticipantTyping)
    }

    @MainActor
    @Test("message received clears typing for sender profile")
    func messageReceivedClearsTyping() throws {
        let conversationID = fixedConversationID()
        let currentProfileID = fixedCurrentProfileID()
        let otherProfileID = fixedOtherProfileID()
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )
        let message = try makeMessageDTO(
            id: fixedMessageID(),
            conversationID: conversationID,
            senderProfileID: otherProfileID,
            body: "Hello"
        )

        viewModel.applyTypingStarted(profileID: otherProfileID)
        _ = viewModel.applyRealtimeMessage(message, currentProfileID: currentProfileID)

        #expect(viewModel.typingProfileIDs.isEmpty)
    }

    @MainActor
    @Test("typing timeout clears typing state")
    func typingTimeoutClearsState() async {
        let conversationID = fixedConversationID()
        let otherProfileID = fixedOtherProfileID()
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: conversationID),
            messages: []
        )

        viewModel.applyTypingStarted(profileID: otherProfileID)
        #expect(viewModel.isOtherParticipantTyping)

        try? await Task.sleep(for: .seconds(5.2))
        #expect(!viewModel.isOtherParticipantTyping)
    }

    @MainActor
    @Test("stop typing clears state")
    func stopTypingClearsState() {
        let viewModel = ChatViewModel.preview(
            conversation: makeConversation(id: fixedConversationID()),
            messages: []
        )
        viewModel.applyTypingStarted(profileID: fixedOtherProfileID())
        viewModel.stopTyping()
        #expect(viewModel.typingProfileIDs.isEmpty)
    }

    private func jsonObject(for message: RealtimeClientMessageDTO) throws -> [String: Any] {
        let data = try JSONCoding.encoder.encode(message)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func decodeEvent(_ json: String) throws -> RealtimeEvent {
        try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(json.utf8)).event
    }

    private func typingStartedJSON() -> String {
        """
        {
          "type": "typing.started",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "profileID": "44444444-4444-4444-4444-444444444444"
          }
        }
        """
    }

    private func typingStoppedJSON() -> String {
        """
        {
          "type": "typing.stopped",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "profileID": "44444444-4444-4444-4444-444444444444"
          }
        }
        """
    }

    private func makeMessageDTO(
        id: UUID,
        conversationID: UUID,
        senderProfileID: UUID,
        body: String?
    ) throws -> MessageDTO {
        let bodyJSON = body.map { #""\#($0)""# } ?? "null"
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
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))
    }

    private func makeConversation(id: UUID) -> ChatConversationPreview {
        ChatConversationPreview(
            id: id,
            title: "Taylor",
            otherParticipantProfileID: fixedOtherProfileID(),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: nil,
            lastSenderName: nil,
            lastMessageAt: nil,
            unreadCount: 0
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
}
