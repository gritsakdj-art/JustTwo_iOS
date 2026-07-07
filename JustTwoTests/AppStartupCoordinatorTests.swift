import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct AppStartupCoordinatorTests {

    @Test
    func resetClearsWarmupStateAndStores() async {
        let coordinator = AppStartupCoordinator.shared
        await coordinator.reset()

        #expect(coordinator.warmedUserID == nil)
        #expect(coordinator.isRunningCritical == false)
        #expect(ConversationListViewModel.shared.conversations.isEmpty)
        #expect(MessageCacheStore.shared.messages(for: UUID()) == nil)
    }

    @Test
    func waitForLogoutResetBlocksUntilLocalStoreIsCleared() async throws {
        let coordinator = AppStartupCoordinator.shared
        await coordinator.reset()

        try await MessengerLocalStore.shared.upsertConversations([
            try makeConversationDTOForResetTest()
        ])
        #expect(try await MessengerLocalStore.shared.fetchLocalConversations().isEmpty == false)

        coordinator.scheduleLogoutReset()
        await coordinator.waitForLogoutReset()

        #expect(try await MessengerLocalStore.shared.fetchLocalConversations().isEmpty)
    }
}

private func makeConversationDTOForResetTest() throws -> ConversationDTO {
    let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    let profileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

    return try JSONCoding.decoder.decode(ConversationDTO.self, from: Data("""
    {
      "id": "\(conversationID.uuidString)",
      "type": "direct",
      "status": "active",
      "connectionID": null,
      "otherParticipant": null,
      "lastMessage": {
        "id": "\(messageID.uuidString)",
        "conversationID": "\(conversationID.uuidString)",
        "senderProfileID": "\(profileID.uuidString)",
        "kind": "text",
        "body": "Preview",
        "attachments": [],
        "replyTo": null,
        "reactions": [],
        "deliveryStatus": "sent",
        "clientMessageID": "client-preview",
        "createdAt": "2026-06-26T13:18:31Z",
        "editedAt": null,
        "deletedAt": null
      },
      "unreadCount": 0,
      "lastReadAt": null,
      "lastMessageAt": "2026-06-26T13:18:31Z",
      "createdAt": "2026-06-26T13:18:31Z",
      "updatedAt": "2026-06-26T13:18:31Z"
    }
    """.utf8))
}
