import Foundation
import Testing
@testable import JustTwo

@MainActor
struct MessageCacheStoreTests {

    private let conversationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func returnsPreloadedMessages() {
        let store = MessageCacheStore.shared
        store.reset()
        let message = ChatMessage(
            id: UUID(),
            displayText: "Hello",
            rawBody: "Hello",
            createdAt: .now,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )

        store.setMessages([message], for: conversationID)

        #expect(store.messages(for: conversationID)?.count == 1)
        #expect(store.hasCachedMessages(for: conversationID))
    }

    @Test
    func upsertReplacesExistingMessage() {
        let store = MessageCacheStore.shared
        store.reset()
        let messageID = UUID()
        let original = ChatMessage(
            id: messageID,
            displayText: "Draft",
            rawBody: "Draft",
            createdAt: .now,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )
        let edited = ChatMessage(
            id: messageID,
            displayText: "Edited",
            rawBody: "Edited",
            createdAt: original.createdAt,
            isMine: true,
            isDeleted: false,
            isEdited: true,
            replyPreview: nil,
            reactions: []
        )

        store.setMessages([original], for: conversationID)
        store.upsertMessage(edited, conversationID: conversationID)

        #expect(store.messages(for: conversationID)?.first?.displayText == "Edited")
        #expect(store.messages(for: conversationID)?.first?.isEdited == true)
    }

    @Test
    func markMessageDeletedUpdatesCache() {
        let store = MessageCacheStore.shared
        store.reset()
        let messageID = UUID()
        let message = ChatMessage(
            id: messageID,
            displayText: "Secret",
            rawBody: "Secret",
            createdAt: .now,
            isMine: false,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )

        store.setMessages([message], for: conversationID)
        let applied = store.markMessageDeleted(
            conversationID: conversationID,
            messageID: messageID,
            deletedAt: .now
        )

        #expect(applied)
        #expect(store.messages(for: conversationID)?.first?.isDeleted == true)
    }

    @Test
    func resetClearsCache() {
        let store = MessageCacheStore.shared
        store.setMessages([], for: conversationID)
        store.reset()

        #expect(store.messages(for: conversationID) == nil)
    }
}
