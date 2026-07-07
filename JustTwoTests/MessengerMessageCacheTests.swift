import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerMessageCacheTests {
    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let profileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private let otherProfileID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
    private let attachmentID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!

    @Test
    func emptyCacheHydrationReturnsNil() async {
        let store = makeStore()
        let messages = await MessengerMessageCacheService.hydrateCachedMessages(
            conversationID: conversationID,
            currentProfileID: profileID,
            limit: 20
        )
        #expect(messages == nil)
        _ = store
    }

    @Test
    func textMessagePersistsAndHydratesIntoChatMessage() async throws {
        let store = makeStore()
        let dto = try makeTextMessageDTO()

        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )

        #expect(hydrated.count == 1)
        #expect(hydrated[0].id == messageID)
        #expect(hydrated[0].displayText == "Hello")
        #expect(hydrated[0].isMine)
        #expect(hydrated[0].deliveryStatus == .sent)

        let snapshots = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].body == "Hello")
    }

    @Test
    func imageMessagePersistsAttachmentMetadataWithoutSignedURL() async throws {
        let store = makeStore()
        let dto = makeImageMessageDTO()

        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: otherProfileID,
                limit: 20
            )
        )

        #expect(hydrated[0].kind == .image)
        #expect(hydrated[0].imageAttachment?.id == attachmentID.uuidString)
        #expect(hydrated[0].imageAttachment?.downloadURL == nil)

        let snapshot = try #require(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first)
        let attachment = try #require(snapshot.attachments.first)
        #expect(attachment.localCacheKey == attachmentID.uuidString)
        let encoded = String(describing: attachment)
        #expect(!encoded.contains("downloadUrl"))
        #expect(!encoded.contains("X-Amz-Signature"))
    }

    @Test
    func deletedImageMessageHydratesWithoutRenderableAttachment() async throws {
        let store = makeStore()
        let dto = makeImageMessageDTO(deleted: true)

        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: otherProfileID,
                limit: 20
            )
        )

        #expect(hydrated[0].isDeleted)
        #expect(hydrated[0].imageAttachment == nil)
        _ = store
    }

    @Test
    func editedMessageUpdatesBodyOnPersist() async throws {
        let store = makeStore()
        let original = try makeTextMessageDTO()
        let edited = try makeTextMessageDTO(body: "Updated", editedAt: "2026-07-02T14:00:00Z")

        await MessengerMessageCacheService.persistRESTMessages([original], conversationID: conversationID)
        await MessengerMessageCacheService.persistDeltaMessage(edited, eventType: "message.edited")

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )

        #expect(hydrated[0].rawBody == "Updated")
        #expect(hydrated[0].isEdited)
        _ = store
    }

    @Test
    func reactionAggregatesPersistAndHydrate() async throws {
        let store = makeStore()
        let dto = try makeTextMessageDTO(
            reactions: """
            [{ "emoji": "👍", "count": 2, "reactedByMe": true }]
            """
        )

        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )

        #expect(hydrated[0].reactions.count == 1)
        #expect(hydrated[0].reactions[0].count == 2)
        #expect(hydrated[0].reactions[0].reactedByMe)
        _ = store
    }

    @Test
    func duplicateServerMessageDoesNotDuplicateOnHydrate() async throws {
        let store = makeStore()
        let dto = try makeTextMessageDTO()

        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)
        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )

        #expect(hydrated.count == 1)
        _ = store
    }

    @Test
    func clientMessageIDReconcilesOnPersist() async throws {
        let store = makeStore()
        let optimistic = try makeTextMessageDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            clientMessageID: "client-optimistic"
        )
        let confirmed = try makeTextMessageDTO(
            clientMessageID: "client-optimistic",
            body: "Confirmed"
        )

        await MessengerMessageCacheService.persistRESTMessages([optimistic], conversationID: conversationID)
        await MessengerMessageCacheService.persistRealtimeMessage(confirmed, eventType: "message.created")

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )

        #expect(hydrated.count == 1)
        #expect(hydrated[0].id == messageID)
        #expect(hydrated[0].clientMessageID == "client-optimistic")
        _ = store
    }

    @Test
    func cachedMessagesSortChronologicallyAscending() async throws {
        let store = makeStore()
        let older = try makeTextMessageDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            clientMessageID: "client-older",
            createdAt: "2026-06-26T10:00:00Z"
        )
        let newer = try makeTextMessageDTO(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            clientMessageID: "client-newer",
            createdAt: "2026-06-26T13:00:00Z"
        )

        await MessengerMessageCacheService.persistRESTMessages([older, newer], conversationID: conversationID)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )

        #expect(hydrated.count == 2)
        #expect(hydrated[0].createdAt < hydrated[1].createdAt)
        _ = store
    }

    @Test
    func cacheHydrateMergePreservesOptimisticMessage() {
        let store = MessageCacheStore.shared
        let conversationID = UUID()
        let clientMessageID = UUID().uuidString
        let pending = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Pending",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 5_000)
        )
        store.setMessages([pending], for: conversationID)

        let cached = ChatMessage(
            id: messageID,
            displayText: "Cached",
            rawBody: "Cached",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )

        store.mergeLoadedMessages([cached], for: conversationID)

        let merged = store.messages(for: conversationID) ?? []
        #expect(merged.count == 2)
        #expect(merged.contains(where: { $0.clientMessageID == clientMessageID && $0.localSendState != nil }))
    }

    @Test
    func networkFailurePreservesCachedMessagesInMemory() async {
        let cache = MessageCacheStore.shared
        let conversationID = UUID()
        let existing = ChatMessage(
            id: messageID,
            displayText: "Cached",
            rawBody: "Cached",
            createdAt: .now,
            isMine: false,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )
        cache.setMessages([existing], for: conversationID)
        cache.cancelLoad(for: conversationID)

        #expect(cache.messages(for: conversationID)?.count == 1)
        #expect(cache.entry(for: conversationID)?.isLoading == false)
    }

    @Test
    func deltaMessageDeletedClearsLocalAttachments() async throws {
        let store = makeStore()
        try await store.upsertMessages([makeImageMessageDTO()], conversationID: conversationID)

        await MessengerMessageCacheService.persistMessageDeleted(
            messageID: messageID,
            deletedAt: isoDate("2026-07-02T13:45:00Z")
        )

        let snapshot = try #require(
            try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first
        )
        #expect(snapshot.localState == .deleted)
        #expect(snapshot.attachments.isEmpty)
    }

    @Test
    func receiptAdvancesMonotonicallyInMapping() throws {
        let earlier = try makeReceiptDTO(
            deliveredAt: "2026-07-02T13:40:00Z",
            readAt: nil
        )
        let laterRead = try makeReceiptDTO(
            deliveredAt: "2026-07-02T13:39:00Z",
            readAt: "2026-07-02T13:41:00Z"
        )
        let regressive = try makeReceiptDTO(
            deliveredAt: "2026-07-02T13:30:00Z",
            readAt: "2026-07-02T13:35:00Z"
        )

        let existing = MessengerLocalMapping.mapReceipt(from: earlier)
        let incoming = MessengerLocalMapping.mapReceipt(from: laterRead)
        MessengerLocalMapping.applyReceipt(incoming, to: existing)
        let regressiveMapped = MessengerLocalMapping.mapReceipt(from: regressive)
        MessengerLocalMapping.applyReceipt(regressiveMapped, to: existing)

        #expect(existing.lastDeliveredAt == isoDate("2026-07-02T13:41:00Z"))
        #expect(existing.lastReadAt == isoDate("2026-07-02T13:41:00Z"))
    }

    @Test
    func deliveryStatusDoesNotRegressOnMerge() {
        let cache = MessageCacheStore.shared
        let conversationID = UUID()
        let message = ChatMessage(
            id: messageID,
            displayText: "Mine",
            rawBody: "Mine",
            createdAt: .now,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: .read
        )
        cache.setMessages([message], for: conversationID)

        let restOlder = ChatMessage(
            id: messageID,
            displayText: "Mine",
            rawBody: "Mine",
            createdAt: .now,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: .sent
        )
        cache.mergeLoadedMessages([restOlder], for: conversationID)

        let merged = cache.messages(for: conversationID)?.first
        #expect(merged?.deliveryStatus == .read)
    }

    @Test
    func logoutResetClearsCachedMessages() async throws {
        let store = makeStore()
        let dto = try makeTextMessageDTO()
        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        try await store.resetAllMessengerData()

        let hydrated = await MessengerMessageCacheService.hydrateCachedMessages(
            conversationID: conversationID,
            currentProfileID: profileID,
            limit: 20
        )
        #expect(hydrated == nil)
    }

    @Test
    func messageCacheDiagnosticsDoNotExportSensitiveFields() async throws {
        MessengerDiagnosticsStore.shared.clear()
        let store = makeStore()
        defer { MessengerMessageCacheService.testingStore = nil }

        let dto = makeImageMessageDTO()
        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)
        _ = await MessengerMessageCacheService.hydrateCachedMessages(
            conversationID: conversationID,
            currentProfileID: otherProfileID,
            limit: 20
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        let export = MessengerDiagnostics.exportTextForClipboard().lowercased()
        #expect(!export.contains("x-amz-signature"))
        #expect(!export.contains("downloadurl"))
        #expect(!export.contains("uploadurl"))
        #expect(!export.contains("bearer"))
        #expect(!export.contains("authorization"))
        #expect(!export.contains("jwt"))
        #expect(!export.contains("storagekey"))
        #expect(!export.contains("/tmp/"))
        _ = store
    }

    @Test
    func cachedImageMessageWithoutDownloadURLMapsSafely() async throws {
        let store = makeStore()
        await MessengerMessageCacheService.persistRESTMessages(
            [makeImageMessageDTO()],
            conversationID: conversationID
        )

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: otherProfileID,
                limit: 20
            )
        )

        #expect(hydrated.count == 1)
        #expect(hydrated[0].kind == .image)
        #expect(hydrated[0].imageAttachment?.downloadURL == nil)
        #expect(hydrated[0].imageAttachment?.id == attachmentID.uuidString)
        _ = store
    }

    @Test
    func deleteViaPersistDeltaMessageClearsImageAttachments() async throws {
        let store = makeStore()
        try await store.upsertMessages([makeImageMessageDTO()], conversationID: conversationID)

        await MessengerMessageCacheService.persistDeltaMessage(
            makeImageMessageDTO(deleted: true),
            eventType: "message.deleted"
        )

        let snapshot = try #require(
            try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first
        )
        #expect(snapshot.localState == .deleted)
        #expect(snapshot.attachments.isEmpty)

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: otherProfileID,
                limit: 20
            )
        )
        #expect(hydrated[0].isDeleted)
        #expect(hydrated[0].imageAttachment == nil)
    }

    @Test
    func editedMessagePersistsViaDeltaEvent() async throws {
        let store = makeStore()
        let original = try makeTextMessageDTO()
        let edited = try makeTextMessageDTO(body: "Edited body", editedAt: "2026-07-02T15:00:00Z")

        await MessengerMessageCacheService.persistRESTMessages([original], conversationID: conversationID)
        await MessengerMessageCacheService.persistDeltaMessage(edited, eventType: "message.edited")

        let hydrated = try #require(
            await MessengerMessageCacheService.hydrateCachedMessages(
                conversationID: conversationID,
                currentProfileID: profileID,
                limit: 20
            )
        )
        #expect(hydrated[0].rawBody == "Edited body")
        #expect(hydrated[0].isEdited)
        _ = store
    }
}

// MARK: - Fixtures

private extension MessengerMessageCacheTests {
    func makeStore() -> MessengerLocalStore {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        MessengerMessageCacheService.testingStore = store
        return store
    }

    func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func makeTextMessageDTO(
        id: UUID? = nil,
        clientMessageID: String = "client-1",
        body: String = "Hello",
        editedAt: String? = nil,
        createdAt: String = "2026-06-26T13:18:31Z",
        reactions: String = "[]"
    ) throws -> MessageDTO {
        try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\((id ?? messageID).uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "\(profileID.uuidString)",
          "kind": "text",
          "body": "\(body)",
          "attachments": [],
          "replyTo": null,
          "reactions": \(reactions),
          "deliveryStatus": "sent",
          "clientMessageID": "\(clientMessageID)",
          "createdAt": "\(createdAt)",
          "editedAt": \(editedAt == nil ? "null" : "\"\(editedAt!)\""),
          "deletedAt": null
        }
        """.utf8))
    }

    func makeImageMessageDTO(deleted: Bool = false) -> MessageDTO {
        try! JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(messageID.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "\(otherProfileID.uuidString)",
          "kind": "image",
          "body": null,
          "attachments": [{
            "id": "\(attachmentID.uuidString)",
            "contentType": "image/jpeg",
            "byteSize": 12345,
            "width": 800,
            "height": 600,
            "downloadUrl": "https://storage.test/photo.jpg?X-Amz-Signature=secret",
            "downloadUrlExpiresAt": "2026-07-02T14:00:00Z"
          }],
          "replyTo": null,
          "reactions": [],
          "deliveryStatus": "sent",
          "clientMessageID": "client-image",
          "createdAt": "2026-06-26T13:18:31Z",
          "editedAt": null,
          "deletedAt": \(deleted ? "\"2026-07-02T13:45:00Z\"" : "null")
        }
        """.utf8))
    }

    func makeReceiptDTO(deliveredAt: String?, readAt: String?) throws -> MessengerReceiptDTO {
        let deliveredJSON = deliveredAt == nil ? "null" : "\"\(deliveredAt!)\""
        let readJSON = readAt == nil ? "null" : "\"\(readAt!)\""
        return try JSONCoding.decoder.decode(MessengerReceiptDTO.self, from: Data("""
        {
          "profileID": "\(otherProfileID.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "messageID": "\(messageID.uuidString)",
          "deliveredAt": \(deliveredJSON),
          "readAt": \(readJSON)
        }
        """.utf8))
    }
}
