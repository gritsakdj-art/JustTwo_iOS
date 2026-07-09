import Foundation
import Testing
@testable import JustTwo
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct OptimisticSendTests {

    @Test
    func optimisticImageMessageIncludesOptionalCaption() throws {
        #if canImport(UIKit)
        let clientMessageID = "client-image-caption"
        let data = makeTestJPEGData()
        let relativePath = try MessengerPendingMediaStore.storeJPEG(
            data: data,
            pendingMediaID: "pending-caption",
            clientMessageID: clientMessageID
        )
        let prepared = try MessengerPendingMediaStore.preparedImage(
            relativePath: relativePath,
            contentType: "image/jpeg",
            byteSize: data.count,
            width: 10,
            height: 10
        )

        let message = ChatMessage.optimisticOutgoingImage(
            clientMessageID: clientMessageID,
            prepared: prepared,
            replyPreview: nil,
            caption: "Nice sunset"
        )

        #expect(message.kind == .image)
        #expect(message.rawBody == "Nice sunset")
        #expect(message.displayText == "Nice sunset")

        MessengerPendingMediaStore.delete(relativePath: relativePath)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    #if canImport(UIKit)
    private func makeTestJPEGData() -> Data {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
    #endif

    private let conversationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func optimisticMessageUsesStableClientMessageID() {
        let clientMessageID = "client-stable-1"
        let message = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Hello",
            replyPreview: nil
        )

        #expect(message.clientMessageID == clientMessageID)
        #expect(message.localSendState == .sending)
        #expect(message.listIdentity == "pending-\(clientMessageID)")
    }

    @Test
    func optimisticMessageDoesNotExposeDeliveryStatus() {
        let message = ChatMessage.optimisticOutgoing(
            clientMessageID: UUID().uuidString,
            body: "Hello",
            replyPreview: nil
        )

        #expect(message.deliveryStatus == nil)
        #expect(message.isMine)
    }

    @Test
    func localMessageIDIsStableForClientMessageID() {
        let clientMessageID = "client-stable-2"
        let first = OptimisticMessageIdentity.localMessageID(for: clientMessageID)
        let second = OptimisticMessageIdentity.localMessageID(for: clientMessageID)
        #expect(first == second)
    }

    @Test
    func insertOptimisticMessageAppearsImmediatelyInCache() {
        let store = MessageCacheStore.shared
        store.reset()
        MessengerOutbox.shared.clear()

        let clientMessageID = UUID().uuidString
        let optimistic = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Pending",
            replyPreview: nil
        )

        store.insertOptimisticMessage(optimistic, for: conversationID)

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 1)
        #expect(messages[0].clientMessageID == clientMessageID)
        #expect(messages[0].localSendState == .sending)
    }

    @Test
    func replaceOptimisticMessageSwapsPendingForServerMessage() {
        let store = MessageCacheStore.shared
        store.reset()

        let clientMessageID = UUID().uuidString
        let optimistic = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Pending",
            replyPreview: nil
        )
        store.insertOptimisticMessage(optimistic, for: conversationID)

        let server = makeServerMessage(
            id: UUID(),
            clientMessageID: clientMessageID,
            body: "Pending",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(store.replaceOptimisticMessage(
            clientMessageID: clientMessageID,
            with: server,
            conversationID: conversationID,
            source: .rest
        ))

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 1)
        #expect(messages[0].id == server.id)
        #expect(messages[0].localSendState == nil)
        #expect(messages[0].deliveryStatus == .sent)
        #expect(messages[0].clientMessageID == clientMessageID)
    }

    @Test
    func failedOptimisticMessageCanBeMarkedFailed() {
        let store = MessageCacheStore.shared
        store.reset()

        let clientMessageID = UUID().uuidString
        store.insertOptimisticMessage(
            ChatMessage.optimisticOutgoing(
                clientMessageID: clientMessageID,
                body: "Pending",
                replyPreview: nil
            ),
            for: conversationID
        )

        #expect(store.updateOptimisticMessageState(
            clientMessageID: clientMessageID,
            conversationID: conversationID,
            state: .failed
        ))

        #expect(store.messages(for: conversationID)?.first?.localSendState == .failed)
    }

    @Test
    func mergeLoadedMessagesPreservesPendingMissingFromFetch() {
        let store = MessageCacheStore.shared
        store.reset()

        let clientMessageID = UUID().uuidString
        let pending = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Still sending",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let fetched = makeServerMessage(
            id: UUID(),
            clientMessageID: nil,
            body: "Older",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        store.setMessages([pending], for: conversationID)
        store.mergeLoadedMessages([fetched], for: conversationID)

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 2)
        #expect(messages.contains(where: { $0.clientMessageID == clientMessageID && $0.localSendState == .sending }))
    }

    @Test
    func mergeLoadedMessagesPreservesFailedMissingFromFetch() {
        let store = MessageCacheStore.shared
        store.reset()

        let clientMessageID = UUID().uuidString
        var failed = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Failed",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        failed = failed.replacingLocalSendState(.failed)

        store.setMessages([failed], for: conversationID)
        store.mergeLoadedMessages([], for: conversationID)

        #expect(store.messages(for: conversationID)?.contains(where: { $0.localSendState == .failed }) == true)
    }

    @Test
    func mergeLoadedMessagesReconcilesPendingByClientMessageID() {
        let store = MessageCacheStore.shared
        store.reset()
        MessengerOutbox.shared.clear()

        let clientMessageID = UUID().uuidString
        let pending = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Hello",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 1_500)
        )
        store.setMessages([pending], for: conversationID)

        let server = makeServerMessage(
            id: UUID(),
            clientMessageID: clientMessageID,
            body: "Hello",
            createdAt: Date(timeIntervalSince1970: 1_500)
        )

        store.mergeLoadedMessages([server], for: conversationID)

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 1)
        #expect(messages[0].id == server.id)
        #expect(messages[0].localSendState == nil)
    }

    @Test
    func mergeLoadedMessagesDoesNotDowngradeDeliveryStatus() {
        let store = MessageCacheStore.shared
        store.reset()

        let messageID = UUID()
        let read = makeServerMessage(
            id: messageID,
            clientMessageID: nil,
            body: "Read",
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .read
        )
        let fetched = makeServerMessage(
            id: messageID,
            clientMessageID: nil,
            body: "Read",
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .sent
        )

        store.setMessages([read], for: conversationID)
        store.mergeLoadedMessages([fetched], for: conversationID)

        #expect(store.messages(for: conversationID)?.first?.deliveryStatus == .read)
    }

    @Test
    func realtimeUpsertReconcilesSinglePendingOutgoing() {
        let store = MessageCacheStore.shared
        store.reset()

        let clientMessageID = UUID().uuidString
        store.insertOptimisticMessage(
            ChatMessage.optimisticOutgoing(
                clientMessageID: clientMessageID,
                body: "Hello",
                replyPreview: nil
            ),
            for: conversationID
        )

        let server = makeServerMessage(
            id: UUID(),
            clientMessageID: nil,
            body: "Hello",
            createdAt: .now
        )

        #expect(store.upsertMessage(server, conversationID: conversationID))

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 1)
        #expect(messages[0].id == server.id)
        #expect(messages[0].localSendState == nil)
    }

    @Test
    func unrelatedRealtimeMessageStillAppends() {
        let store = MessageCacheStore.shared
        store.reset()

        let incoming = makeServerMessage(
            id: UUID(),
            clientMessageID: nil,
            body: "Incoming",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: false
        )

        store.setMessages([], for: conversationID)
        #expect(store.upsertMessage(incoming, conversationID: conversationID))
        #expect(store.messages(for: conversationID)?.count == 1)
    }

    @Test
    func realtimeDoesNotReconcileWhenMultiplePendingWithoutClientMessageID() {
        let store = MessageCacheStore.shared
        store.reset()

        let firstPending = ChatMessage.optimisticOutgoing(
            clientMessageID: "client-1",
            body: "First",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let secondPending = ChatMessage.optimisticOutgoing(
            clientMessageID: "client-2",
            body: "Second",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        store.setMessages([firstPending, secondPending], for: conversationID)

        let serverEcho = makeServerMessage(
            id: UUID(),
            clientMessageID: nil,
            body: "First",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(!store.upsertMessage(serverEcho, conversationID: conversationID))

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.localSendState != nil })
    }

    @Test
    func realtimeReconcilesMatchingClientMessageIDAmongMultiplePending() {
        let store = MessageCacheStore.shared
        store.reset()

        let firstPending = ChatMessage.optimisticOutgoing(
            clientMessageID: "client-1",
            body: "First",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let secondPending = ChatMessage.optimisticOutgoing(
            clientMessageID: "client-2",
            body: "Second",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        store.setMessages([firstPending, secondPending], for: conversationID)

        let serverEcho = makeServerMessage(
            id: UUID(),
            clientMessageID: "client-2",
            body: "Second",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(store.upsertMessage(serverEcho, conversationID: conversationID))

        let messages = store.messages(for: conversationID) ?? []
        #expect(messages.count == 2)
        #expect(messages.contains(where: { $0.id == serverEcho.id && $0.localSendState == nil }))
        #expect(messages.contains(where: { $0.clientMessageID == "client-1" && $0.localSendState == .sending }))
    }

    @Test
    func outboxClearRemovesEntries() {
        MessengerOutbox.shared.clear(reason: "test")
        #expect(MessengerOutbox.shared.entries(for: conversationID).isEmpty)
    }

    @Test
    func diagnosticsDoNotIncludeMessageBody() async {
        MessengerDiagnosticsStore.shared.clear()
        MessengerDiagnostics.event(
            .outboxEnqueued,
            conversationID: conversationID,
            clientMessageID: "client-1",
            metadata: ["state": "queued", "pendingCount": "1"]
        )

        try? await Task.sleep(for: .milliseconds(100))

        let export = MessengerDiagnosticsStore.shared.exportText()
        #expect(!export.contains("Hello"))
        #expect(export.contains("clientMessageID=client-1"))
        #expect(export.contains("outboxEnqueued"))
    }

    private func makeServerMessage(
        id: UUID,
        clientMessageID: String?,
        body: String,
        createdAt: Date,
        isMine: Bool = true,
        status: MessageDeliveryStatus? = .sent
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            clientMessageID: clientMessageID,
            localSendState: nil,
            displayText: body,
            rawBody: body,
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: isMine ? status : nil
        )
    }
}
