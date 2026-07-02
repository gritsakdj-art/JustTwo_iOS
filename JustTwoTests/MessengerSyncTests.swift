import Foundation
import Testing
@testable import JustTwo

struct MessengerSyncDTOTests {

    @Test
    func syncStateDecodes() throws {
        let json = """
        {
          "revision": 103,
          "serverTime": "2026-07-02T13:39:26Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.justTwoAPI.decode(MessengerSyncStateResponse.self, from: json)
        #expect(response.revision == 103)
    }

    @Test
    func syncEventsPageDecodes() throws {
        let conversationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let messageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let profileID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        let json = """
        {
          "events": [
            {
              "revision": 104,
              "type": "message.created",
              "conversationID": "\(conversationID.uuidString)",
              "messageID": "\(messageID.uuidString)",
              "actorProfileID": "\(profileID.uuidString)",
              "occurredAt": "2026-07-02T13:39:35Z",
              "conversation": null,
              "message": {
                "id": "\(messageID.uuidString)",
                "conversationID": "\(conversationID.uuidString)",
                "senderProfileID": "\(profileID.uuidString)",
                "kind": "text",
                "body": "hello",
                "attachments": [],
                "replyTo": null,
                "reactions": [],
                "deliveryStatus": "sent",
                "clientMessageID": "client-1",
                "createdAt": "2026-07-02T13:39:35Z",
                "editedAt": null,
                "deletedAt": null
              },
              "receipt": null
            }
          ],
          "nextRevision": 104,
          "currentRevision": 109,
          "hasMore": true
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.justTwoAPI.decode(MessengerSyncEventsResponse.self, from: json)
        #expect(response.events.count == 1)
        #expect(response.events[0].type == .messageCreated)
        #expect(response.events[0].message?.body == "hello")
        #expect(response.hasMore == true)
    }

    @Test
    func imageMessageCreatedEventDecodes() throws {
        let conversationID = UUID()
        let messageID = UUID()
        let profileID = UUID()
        let attachmentID = UUID()

        let json = """
        {
          "events": [
            {
              "revision": 200,
              "type": "message.created",
              "conversationID": "\(conversationID.uuidString)",
              "messageID": "\(messageID.uuidString)",
              "actorProfileID": "\(profileID.uuidString)",
              "occurredAt": "2026-07-02T13:39:35Z",
              "conversation": null,
              "message": {
                "id": "\(messageID.uuidString)",
                "conversationID": "\(conversationID.uuidString)",
                "senderProfileID": "\(profileID.uuidString)",
                "kind": "image",
                "body": null,
                "attachments": [
                  {
                    "id": "\(attachmentID.uuidString)",
                    "contentType": "image/jpeg",
                    "byteSize": 12345,
                    "width": 800,
                    "height": 600,
                    "downloadUrl": "https://storage.test/private/photo.jpg?X-Amz-Signature=secret",
                    "downloadUrlExpiresAt": "2026-07-02T14:00:00Z"
                  }
                ],
                "replyTo": null,
                "reactions": [],
                "deliveryStatus": "sent",
                "clientMessageID": "image-client",
                "createdAt": "2026-07-02T13:39:35Z",
                "editedAt": null,
                "deletedAt": null
              },
              "receipt": null
            }
          ],
          "nextRevision": 200,
          "currentRevision": 200,
          "hasMore": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.justTwoAPI.decode(MessengerSyncEventsResponse.self, from: json)
        let message = try #require(response.events.first?.message)
        #expect(message.kind == .image)
        #expect(message.attachments.count == 1)
        #expect(message.attachments[0].downloadUrl != nil)
    }

    @Test
    func deletedImageMessageEventDecodesWithoutAttachments() throws {
        let conversationID = UUID()
        let messageID = UUID()
        let profileID = UUID()

        let json = """
        {
          "events": [
            {
              "revision": 201,
              "type": "message.deleted",
              "conversationID": "\(conversationID.uuidString)",
              "messageID": "\(messageID.uuidString)",
              "actorProfileID": "\(profileID.uuidString)",
              "occurredAt": "2026-07-02T13:40:00Z",
              "conversation": null,
              "message": {
                "id": "\(messageID.uuidString)",
                "conversationID": "\(conversationID.uuidString)",
                "senderProfileID": "\(profileID.uuidString)",
                "kind": "image",
                "body": null,
                "attachments": [],
                "replyTo": null,
                "reactions": [],
                "deliveryStatus": null,
                "clientMessageID": "image-client",
                "createdAt": "2026-07-02T13:39:35Z",
                "editedAt": null,
                "deletedAt": "2026-07-02T13:40:00Z"
              },
              "receipt": null
            }
          ],
          "nextRevision": 201,
          "currentRevision": 201,
          "hasMore": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.justTwoAPI.decode(MessengerSyncEventsResponse.self, from: json)
        let message = try #require(response.events.first?.message)
        #expect(message.deletedAt != nil)
        #expect(message.attachments.isEmpty)
        #expect(message.body == nil)
    }

    @Test
    func receiptEventDecodes() throws {
        let conversationID = UUID()
        let profileID = UUID()
        let messageID = UUID()

        let json = """
        {
          "events": [
            {
              "revision": 300,
              "type": "conversation.read",
              "conversationID": "\(conversationID.uuidString)",
              "messageID": "\(messageID.uuidString)",
              "actorProfileID": "\(profileID.uuidString)",
              "occurredAt": "2026-07-02T13:41:00Z",
              "conversation": null,
              "message": null,
              "receipt": {
                "profileID": "\(profileID.uuidString)",
                "conversationID": "\(conversationID.uuidString)",
                "messageID": "\(messageID.uuidString)",
                "deliveredAt": "2026-07-02T13:40:30Z",
                "readAt": "2026-07-02T13:41:00Z"
              }
            }
          ],
          "nextRevision": 300,
          "currentRevision": 300,
          "hasMore": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.justTwoAPI.decode(MessengerSyncEventsResponse.self, from: json)
        let receipt = try #require(response.events.first?.receipt)
        #expect(receipt.readAt != nil)
        #expect(receipt.deliveredAt != nil)
    }
}

@MainActor
struct MessengerSyncStateStoreTests {

    @Test
    func cursorStartsNil() {
        let store = MessengerSyncStateStore.shared
        store.reset()
        #expect(store.currentRevision == nil)
    }

    @Test
    func cursorAdvancesMonotonically() {
        let store = MessengerSyncStateStore.shared
        store.reset()
        store.setRevision(10)
        store.advance(to: 20)
        store.advance(to: 15)
        #expect(store.currentRevision == 20)
    }

    @Test
    func cursorDoesNotMoveBackwardsOnSet() {
        let store = MessengerSyncStateStore.shared
        store.reset()
        store.setRevision(50)
        store.setRevision(40)
        #expect(store.currentRevision == 50)
    }

    @Test
    func resetClearsCursorAndAppliedRevisions() {
        let store = MessengerSyncStateStore.shared
        store.setRevision(12)
        store.markRevisionApplied(12)
        store.reset()
        #expect(store.currentRevision == nil)
        #expect(store.hasAppliedRevision(12) == false)
    }
}

@MainActor
struct MessengerDeltaDiagnosticsTests {

    @Test
    func deltaImageDiagnosticsDoNotExportSignedURL() {
        let entry = MessengerDiagnostics.makeEntry(
            .deltaImageAttachmentDecoded,
            conversationID: UUID(),
            messageID: UUID(),
            metadata: [
                "downloadPresent": "true",
                "downloadUrl": "https://storage.test/file?X-Amz-Signature=secret",
                "attachmentID": UUID().uuidString
            ]
        )

        #expect(entry.metadata["downloadUrl"] == nil)
        #expect(!entry.exportLine.contains("X-Amz-Signature"))
        #expect(!entry.exportLine.contains("Bearer"))
    }

    @Test
    func deltaSyncDiagnosticsAllowDownloadPresentFlag() {
        let entry = MessengerDiagnostics.makeEntry(
            .deltaImageDownloadURLPresent,
            metadata: ["downloadPresent": "true"]
        )

        #expect(entry.metadata["downloadPresent"] == "true")
    }

    @Test
    func diagnosticsExportStripsSensitiveMediaAndAuthMetadata() {
        let store = MessengerDiagnosticsStore(limit: 20)
        store.append(
            MessengerDiagnostics.makeEntry(
                .deltaImageAttachmentDecoded,
                metadata: [
                    "downloadUrl": "https://storage.test/file?X-Amz-Signature=secret",
                    "uploadUrl": "https://storage.test/upload?sig=1",
                    "Authorization": "Bearer abc.def.ghi",
                    "storageKey": "messages/secret-key",
                    "localPath": "/Users/me/Library/Caches/justtwo/photo.jpg",
                    "downloadPresent": "true",
                    "attachmentID": UUID().uuidString
                ]
            )
        )

        let export = store.exportText()
        #expect(!export.contains("downloadUrl="))
        #expect(!export.contains("uploadUrl="))
        #expect(!export.contains("X-Amz-Signature"))
        #expect(!export.contains("Bearer"))
        #expect(!export.contains("Authorization="))
        #expect(!export.contains("storageKey="))
        #expect(!export.contains("/Users/me/Library"))
        #expect(export.contains("downloadPresent=true"))
    }
}

@MainActor
struct MessengerDeltaSyncBehaviorTests {

    @Test
    func finishBaselineUsesPendingRevisionFromPrepare() {
        let store = MessengerSyncStateStore.shared
        store.reset()
        let service = MessengerDeltaSyncService(syncState: store)
        service.setPendingBaselineRevisionForTesting(88)
        service.finishBaseline(revision: 1)
        #expect(store.currentRevision == 88)
        #expect(service.pendingBaselineRevisionForTests == nil)
    }

    @Test
    func deltaReceiptApplyUpdatesCacheWithoutNetworkWrites() async throws {
        let store = MessengerSyncStateStore.shared
        store.reset()
        let cache = MessageCacheStore.shared
        cache.reset()
        let list = ConversationListViewModel.shared
        list.reset()

        let service = MessengerDeltaSyncService(
            syncState: store,
            messageCache: cache,
            conversationList: list
        )

        let conversationID = UUID()
        let messageID = UUID()
        let senderID = UUID()
        let recipientID = UUID()
        let deliveredAt = Date(timeIntervalSince1970: 2_000)

        let outgoing = ChatMessage(
            id: messageID,
            displayText: "hello",
            rawBody: "hello",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: .sent
        )
        cache.setMessages([outgoing], for: conversationID)

        let event = try decodeSyncEvent(
            revision: 501,
            type: "conversation.delivered",
            conversationID: conversationID,
            messageID: messageID,
            actorProfileID: recipientID,
            receiptProfileID: recipientID,
            deliveredAt: deliveredAt,
            readAt: nil
        )

        try await service.applyEventsForTesting(
            [event],
            profileID: senderID,
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        let updated = try #require(cache.messages(for: conversationID)?.first)
        #expect(updated.deliveryStatus == .delivered)
        #expect(store.hasAppliedRevision(501))
    }

    @Test
    func resetIncrementsSessionGenerationAndClearsPendingBaseline() {
        let store = MessengerSyncStateStore.shared
        store.reset()
        let service = MessengerDeltaSyncService(syncState: store)
        service.setPendingBaselineRevisionForTesting(77)
        store.setRevision(10)

        let before = service.sessionGenerationForTests
        service.reset()

        #expect(service.sessionGenerationForTests == before + 1)
        #expect(service.pendingBaselineRevisionForTests == nil)
        #expect(store.currentRevision == nil)
    }

    @Test
    func applyAbortsWhenSessionResetBeforeApply() async throws {
        let store = MessengerSyncStateStore.shared
        store.reset()
        let cache = MessageCacheStore.shared
        cache.reset()
        let list = ConversationListViewModel.shared
        list.reset()

        let service = MessengerDeltaSyncService(
            syncState: store,
            messageCache: cache,
            conversationList: list
        )

        let conversationID = UUID()
        let messageID = UUID()
        let senderID = UUID()

        cache.setMessages(
            [
                ChatMessage(
                    id: messageID,
                    displayText: "hello",
                    rawBody: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    isMine: true,
                    isDeleted: false,
                    isEdited: false,
                    replyPreview: nil,
                    reactions: [],
                    deliveryStatus: .sent
                )
            ],
            for: conversationID
        )

        let event = try decodeSyncEvent(
            revision: 777,
            type: "conversation.delivered",
            conversationID: conversationID,
            messageID: messageID,
            actorProfileID: UUID(),
            receiptProfileID: UUID(),
            deliveredAt: Date(),
            readAt: nil
        )

        service.reset()

        let staleGeneration = service.sessionGenerationForTests - 1
        try await service.applyEventsForTesting(
            [event],
            profileID: senderID,
            session: SessionStore.shared,
            router: AppRouter.shared,
            sessionGeneration: staleGeneration
        )

        #expect(store.hasAppliedRevision(777) == false)
        #expect(cache.messages(for: conversationID)?.first?.deliveryStatus == .sent)
    }

    @Test
    func reconnectSyncIsNotThrottledByForegroundInterval() {
        let service = MessengerDeltaSyncService()
        service.markSyncStartedForTesting()
        #expect(service.wouldThrottleForTests(reason: .realtimeReconnect) == false)
        #expect(service.wouldThrottleForTests(reason: .chatOpened) == true)
    }

    @Test
    func defaultSyncEventsRequestDoesNotFilterByConversation() {
        let request = GetMessengerSyncEventsRequest(afterRevision: 12)
        #expect(request.queryItems.contains { $0.name == "conversationID" } == false)
    }

    private func decodeSyncEvent(
        revision: Int64,
        type: String,
        conversationID: UUID,
        messageID: UUID,
        actorProfileID: UUID,
        receiptProfileID: UUID,
        deliveredAt: Date?,
        readAt: Date?
    ) throws -> MessengerSyncEventDTO {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let deliveredAtJSON: String
        if let deliveredAt {
            deliveredAtJSON = "\"\(formatter.string(from: deliveredAt))\""
        } else {
            deliveredAtJSON = "null"
        }

        let readAtJSON: String
        if let readAt {
            readAtJSON = "\"\(formatter.string(from: readAt))\""
        } else {
            readAtJSON = "null"
        }

        let json = """
        {
          "revision": \(revision),
          "type": "\(type)",
          "conversationID": "\(conversationID.uuidString)",
          "messageID": "\(messageID.uuidString)",
          "actorProfileID": "\(actorProfileID.uuidString)",
          "occurredAt": "2026-07-02T13:39:35Z",
          "conversation": null,
          "message": null,
          "receipt": {
            "profileID": "\(receiptProfileID.uuidString)",
            "conversationID": "\(conversationID.uuidString)",
            "messageID": "\(messageID.uuidString)",
            "deliveredAt": \(deliveredAtJSON),
            "readAt": \(readAtJSON)
          }
        }
        """.data(using: .utf8)!

        return try JSONDecoder.justTwoAPI.decode(MessengerSyncEventDTO.self, from: json)
    }
}
