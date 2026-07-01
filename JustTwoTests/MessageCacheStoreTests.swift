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
    func mergeLoadedMessagesPreservesRealtimeMessageNotInFetchResponse() {
        let store = MessageCacheStore.shared
        store.reset()
        let fetched = makeMessage(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: false,
            status: nil
        )
        let realtime = makeMessage(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 2_000),
            isMine: false,
            status: nil
        )

        store.setMessages([realtime], for: conversationID)
        store.mergeLoadedMessages([fetched], for: conversationID)

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.map(\.id) == [fetched.id, realtime.id])
    }

    @Test
    func mergeLoadedMessagesDoesNotRollbackRealtimeDelete() {
        let store = MessageCacheStore.shared
        store.reset()
        let messageID = UUID()
        let staleFetched = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: false,
            status: nil,
            text: "Original"
        )
        let realtimeDeleted = staleFetched.markingDeleted(deletedAt: .now)

        store.setMessages([realtimeDeleted], for: conversationID)
        store.mergeLoadedMessages([staleFetched], for: conversationID)

        let message = store.messages(for: conversationID)?.first
        #expect(message?.isDeleted == true)
        #expect(message?.rawBody == nil)
    }

    @Test
    func mergeLoadedMessagesDoesNotRollbackRealtimeEdit() {
        let store = MessageCacheStore.shared
        store.reset()
        let messageID = UUID()
        let staleFetched = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: false,
            status: nil,
            text: "Original"
        )
        let realtimeEdited = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: false,
            status: nil,
            text: "Edited",
            isEdited: true
        )

        store.setMessages([realtimeEdited], for: conversationID)
        store.mergeLoadedMessages([staleFetched], for: conversationID)

        let message = store.messages(for: conversationID)?.first
        #expect(message?.displayText == "Edited")
        #expect(message?.isEdited == true)
    }

    @Test
    func mergeLoadedMessagesDoesNotDowngradeRealtimeReceipt() {
        let store = MessageCacheStore.shared
        store.reset()
        let messageID = UUID()
        let staleFetched = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: true,
            status: .sent
        )
        let realtimeRead = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: true,
            status: .read
        )

        store.setMessages([realtimeRead], for: conversationID)
        store.mergeLoadedMessages([staleFetched], for: conversationID)

        #expect(store.messages(for: conversationID)?.first?.deliveryStatus == .read)
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
    func mergeLoadedMessagesPreservesOlderMessagesCursor() {
        let store = MessageCacheStore.shared
        store.reset()
        let message = makeMessage(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: false,
            status: nil
        )

        store.setMessages([message], for: conversationID)
        store.setOlderMessagesCursorForTesting("older-cursor", for: conversationID)

        store.mergeLoadedMessages([
            makeMessage(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 2_000),
                isMine: false,
                status: nil
            )
        ], for: conversationID)

        #expect(store.entry(for: conversationID)?.olderMessagesCursor == "older-cursor")
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
        status: MessageDeliveryStatus?,
        text: String = "Message",
        isEdited: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            displayText: text,
            rawBody: text,
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: false,
            isEdited: isEdited,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: status
        )
    }
}
