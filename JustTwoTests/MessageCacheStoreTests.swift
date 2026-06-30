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
            reactions: [],
            deliveryStatus: .sent
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
            reactions: [],
            deliveryStatus: .sent
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
            reactions: [],
            deliveryStatus: .sent
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
            reactions: [],
            deliveryStatus: nil
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
    func receiptStatusUpdatesOutgoingMessagesWithoutDowngrade() {
        let store = MessageCacheStore.shared
        store.reset()
        let firstID = UUID()
        let secondID = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)

        store.setMessages([
            makeMessage(id: firstID, createdAt: firstDate, isMine: true, status: .sent),
            makeMessage(id: secondID, createdAt: secondDate, isMine: true, status: .sent),
            makeMessage(id: UUID(), createdAt: secondDate.addingTimeInterval(1), isMine: false, status: nil)
        ], for: conversationID)

        #expect(store.applyDeliveryStatus(
            conversationID: conversationID,
            status: .delivered,
            messageID: secondID,
            cutoffDate: nil
        ))
        #expect(store.messages(for: conversationID)?[0].deliveryStatus == .delivered)
        #expect(store.messages(for: conversationID)?[1].deliveryStatus == .delivered)
        #expect(store.messages(for: conversationID)?[2].deliveryStatus == nil)

        #expect(store.applyDeliveryStatus(
            conversationID: conversationID,
            status: .read,
            messageID: nil,
            cutoffDate: firstDate
        ))
        #expect(store.messages(for: conversationID)?[0].deliveryStatus == .read)
        #expect(store.messages(for: conversationID)?[1].deliveryStatus == .delivered)

        #expect(!store.applyDeliveryStatus(
            conversationID: conversationID,
            status: .delivered,
            messageID: firstID,
            cutoffDate: nil
        ))
        #expect(store.messages(for: conversationID)?[0].deliveryStatus == .read)
    }

    @Test
    func resetClearsCache() {
        let store = MessageCacheStore.shared
        store.setMessages([], for: conversationID)
        store.reset()

        #expect(store.messages(for: conversationID) == nil)
    }

    private func makeMessage(
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
}
