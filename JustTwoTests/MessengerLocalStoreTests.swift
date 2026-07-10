import Foundation
import SwiftData
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerLocalStoreTests {
    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let profileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private let attachmentID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
    private let photoID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!

    @Test
    func resetBlocksConcurrentWritesUntilComplete() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO()])

        store.testingSuspendResetAfterLock = true

        var resetTask: Task<Void, Error>!
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            store.testingOnResetSuspended = { ready.resume() }
            resetTask = Task {
                try await store.resetAllMessengerData()
            }
        }

        await #expect(throws: MessengerLocalStoreError.storeUnavailable) {
            try await store.upsertConversations([makeConversationDTO()])
        }

        store.testingResumeSuspendedResetForTests()
        try await resetTask.value
        #expect(try await store.fetchLocalConversations().isEmpty)

        try await store.upsertConversations([makeConversationDTO()])
        #expect(try await store.fetchLocalConversations().count == 1)
    }

    @Test
    func sessionGenerationIncrementsOnEachReset() async throws {
        let store = makeStore()
        let initialGeneration = store.sessionGenerationForTests

        try await store.resetAllMessengerData()
        #expect(store.sessionGenerationForTests == initialGeneration + 1)

        try await store.upsertConversations([makeConversationDTO()])
        try await store.resetAllMessengerData()
        #expect(store.sessionGenerationForTests == initialGeneration + 2)
        #expect(try await store.fetchLocalConversations().isEmpty)
    }

    @Test
    func storeInitializesInMemoryAndResetSucceeds() async throws {
        let store = makeStore()

        try await store.upsertConversations([makeConversationDTO()])
        #expect(try await store.fetchLocalConversations().count == 1)

        try await store.resetAllMessengerData()
        #expect(try await store.fetchLocalConversations().isEmpty)
        #expect(try await store.fetchSyncMetadata() == nil)
    }

    @Test
    func conversationDTOMapsWithoutPersistingSignedPhotoURL() async throws {
        let store = makeStore()
        let dto = makeConversationDTO(includeSignedPhotoURL: true)

        try await store.upsertConversations([dto])
        let snapshot = try #require(try await store.fetchLocalConversations().first)

        #expect(snapshot.id == conversationID.uuidString)
        #expect(snapshot.lastMessageID == messageID.uuidString)
        #expect(snapshot.otherParticipantProfileID == profileID.uuidString)
        #expect(snapshot.otherParticipantDisplayName == "Taylor")
        #expect(snapshot.otherParticipantPrimaryPhotoID == photoID.uuidString)
        #expect(snapshot.otherParticipantPrimaryPhotoDownloadURLExpiresAt == nil)

        let encoded = String(describing: snapshot)
        #expect(!encoded.contains("X-Amz-Signature"))
        #expect(!encoded.contains("downloadUrl"))
    }

    @Test
    func textMessageMapsAndUpsertsWithoutDuplication() async throws {
        let store = makeStore()
        let dto = try makeTextMessageDTO()

        try await store.upsertMessages([dto], conversationID: conversationID)
        try await store.upsertMessages([dto], conversationID: conversationID)

        let messages = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        #expect(messages.count == 1)
        #expect(messages[0].kind == "text")
        #expect(messages[0].body == "Hello")
        #expect(messages[0].localState == .serverConfirmed)
    }

    @Test
    func imageMessageMapsAttachmentMetadataWithoutSignedURL() async throws {
        let store = makeStore()
        let dto = makeImageMessageDTO()

        try await store.upsertMessages([dto], conversationID: conversationID)
        let message = try #require(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first)

        #expect(message.kind == "image")
        #expect(message.attachments.count == 1)
        let attachment = try #require(message.attachments.first)
        #expect(attachment.id == attachmentID.uuidString.lowercased())
        #expect(attachment.localCacheKey == attachmentID.uuidString.lowercased())
        #expect(attachment.contentType == "image/jpeg")
        #expect(attachment.byteSize == 12_345)

        let encoded = String(describing: attachment)
        #expect(!encoded.contains("X-Amz-Signature"))
        #expect(!encoded.contains("downloadUrl"))
        #expect(!encoded.contains("uploadUrl"))
    }

    @Test
    func deletedImageMessageBecomesTombstoneWithoutAttachments() async throws {
        let store = makeStore()
        let dto = makeImageMessageDTO(deleted: true)

        try await store.upsertMessages([dto], conversationID: conversationID)
        let message = try #require(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first)

        #expect(message.localState == .deleted)
        #expect(message.body == nil)
        #expect(message.deletedAt != nil)
        #expect(message.attachments.isEmpty)
    }

    @Test
    func editedMessagePreservesEditedAt() async throws {
        let store = makeStore()
        let original = try makeTextMessageDTO()
        let edited = try makeTextMessageDTO(
            body: "Updated",
            editedAt: "2026-07-02T14:00:00Z"
        )

        try await store.upsertMessages([original], conversationID: conversationID)
        try await store.upsertMessages([edited], conversationID: conversationID)

        let message = try #require(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first)
        #expect(message.body == "Updated")
        #expect(message.editedAt != nil)
    }

    @Test
    func clientMessageIDReconcilesToServerID() async throws {
        let store = makeStore()
        let optimistic = try makeTextMessageDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            clientMessageID: "client-optimistic"
        )
        let confirmed = try makeTextMessageDTO(
            id: messageID,
            clientMessageID: "client-optimistic",
            body: "Confirmed"
        )

        try await store.upsertMessages([optimistic], conversationID: conversationID)
        try await store.upsertMessages([confirmed], conversationID: conversationID)

        let messages = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        #expect(messages.count == 1)
        #expect(messages[0].id == messageID.uuidString)
        #expect(messages[0].clientMessageID == "client-optimistic")
        #expect(messages[0].body == "Confirmed")
    }

    @Test
    func fetchLocalMessagesWithNilBeforeReturnsNewestLimit() async throws {
        let store = makeStore()
        let seeded = try await seedPaginatedMessages(count: 25, store: store)

        let page = try await store.fetchLocalMessages(
            conversationID: conversationID,
            limit: 5,
            before: nil
        )

        #expect(page.count == 5)
        let expectedNewestIDs = Array(seeded.suffix(5).reversed()).map(\.uuidString)
        #expect(page.map(\.id) == expectedNewestIDs)
    }

    @Test
    func fetchLocalMessagesWithBeforeReturnsPageOlderThanCutoff() async throws {
        let store = makeStore()
        let seeded = try await seedPaginatedMessages(count: 25, store: store)
        let cutoffMessage = seeded[15]
        let cutoff = isoDate("2026-06-26T10:\(String(format: "%02d", 15)):00Z")

        let page = try await store.fetchLocalMessages(
            conversationID: conversationID,
            limit: 5,
            before: cutoff
        )

        #expect(page.count == 5)
        #expect(page.allSatisfy { $0.createdAt < cutoff })
        let expectedOlderIDs = (10...14).reversed().map { seeded[$0].uuidString }
        #expect(page.map(\.id) == expectedOlderIDs)
        #expect(!page.contains(where: { $0.id == cutoffMessage.uuidString }))
    }

    @Test
    func fetchLocalMessagesWithBeforeReturnsFullEligiblePageNotNewestWindow() async throws {
        let store = makeStore()
        let seeded = try await seedPaginatedMessages(count: 25, store: store)
        let cutoff = isoDate("2026-06-26T10:10:00Z")

        let page = try await store.fetchLocalMessages(
            conversationID: conversationID,
            limit: 20,
            before: cutoff
        )

        #expect(page.count == 10)
        #expect(page.allSatisfy { $0.createdAt < cutoff })
        let expectedEligibleIDs = (0...9).reversed().map { seeded[$0].uuidString }
        #expect(page.map(\.id) == expectedEligibleIDs)
    }

    @Test
    func fetchLocalMessagesBatchLoadsAttachmentsForMultipleMessages() async throws {
        let store = makeStore()
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let thirdID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let firstAttachmentID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let secondAttachmentID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let thirdAttachmentID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

        try await store.upsertMessages([
            makeImageMessageDTO(id: firstID, attachmentID: firstAttachmentID, createdAt: "2026-06-26T10:22:00Z"),
            makeImageMessageDTO(id: secondID, attachmentID: secondAttachmentID, createdAt: "2026-06-26T10:21:00Z"),
            makeImageMessageDTO(id: thirdID, attachmentID: thirdAttachmentID, createdAt: "2026-06-26T10:20:00Z")
        ], conversationID: conversationID)

        let page = try await store.fetchLocalMessages(
            conversationID: conversationID,
            limit: 3,
            before: nil
        )

        #expect(page.count == 3)
        #expect(page[0].attachments.first?.id == firstAttachmentID.uuidString.lowercased())
        #expect(page[1].attachments.first?.id == secondAttachmentID.uuidString.lowercased())
        #expect(page[2].attachments.first?.id == thirdAttachmentID.uuidString.lowercased())
    }

    @Test
    func fetchLocalMessagesBatchLoadsReactionsForMultipleMessages() async throws {
        let store = makeStore()
        let firstID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let secondID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let thirdID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let first = try makeTextMessageDTO(
            id: firstID,
            clientMessageID: "reaction-client-1",
            body: "First",
            createdAt: "2026-06-26T10:32:00Z",
            reactions: """
            [
              { "emoji": "👍", "count": 3, "reactedByMe": true }
            ]
            """
        )
        let second = try makeTextMessageDTO(
            id: secondID,
            clientMessageID: "reaction-client-2",
            body: "Second",
            createdAt: "2026-06-26T10:31:00Z",
            reactions: """
            [
              { "emoji": "❤️", "count": 2, "reactedByMe": false },
              { "emoji": "😂", "count": 1, "reactedByMe": true }
            ]
            """
        )
        let third = try makeTextMessageDTO(
            id: thirdID,
            clientMessageID: "reaction-client-3",
            body: "Third",
            createdAt: "2026-06-26T10:30:00Z",
            reactions: """
            [
              { "emoji": "🔥", "count": 4, "reactedByMe": false }
            ]
            """
        )

        try await store.upsertMessages([first, second, third], conversationID: conversationID)
        try await store.upsertReactions(from: first)
        try await store.upsertReactions(from: second)
        try await store.upsertReactions(from: third)

        let page = try await store.fetchLocalMessages(
            conversationID: conversationID,
            limit: 3,
            before: nil
        )

        #expect(page.count == 3)
        let reactionsByMessageID = Dictionary(uniqueKeysWithValues: page.map { ($0.id, $0.reactions) })

        let firstReactions = try #require(reactionsByMessageID[firstID.uuidString])
        #expect(firstReactions.count == 1)
        let thumbsUp = try #require(firstReactions.first { $0.emoji == "👍" })
        #expect(thumbsUp.count == 3)
        #expect(thumbsUp.reactedByMe == true)
        #expect(thumbsUp.id == "\(firstID.uuidString):👍")

        let secondReactions = try #require(reactionsByMessageID[secondID.uuidString])
        #expect(secondReactions.count == 2)
        let heart = try #require(secondReactions.first { $0.emoji == "❤️" })
        #expect(heart.count == 2)
        #expect(heart.reactedByMe == false)
        #expect(heart.id == "\(secondID.uuidString):❤️")
        let joy = try #require(secondReactions.first { $0.emoji == "😂" })
        #expect(joy.count == 1)
        #expect(joy.reactedByMe == true)
        #expect(joy.id == "\(secondID.uuidString):😂")

        let thirdReactions = try #require(reactionsByMessageID[thirdID.uuidString])
        #expect(thirdReactions.count == 1)
        let fire = try #require(thirdReactions.first { $0.emoji == "🔥" })
        #expect(fire.count == 4)
        #expect(fire.reactedByMe == false)
        #expect(fire.id == "\(thirdID.uuidString):🔥")
    }

    @Test
    func reactionAggregatesMapEmojiCountAndReactedByMe() async throws {
        let store = makeStore()
        let dto = try makeTextMessageDTO(
            reactions: """
            [
              { "emoji": "👍", "count": 2, "reactedByMe": true },
              { "emoji": "❤️", "count": 1, "reactedByMe": false }
            ]
            """
        )

        try await store.upsertMessages([dto], conversationID: conversationID)
        try await store.upsertReactions(from: dto)

        let message = try #require(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first)
        #expect(message.reactions.count == 2)

        let thumbsUp = try #require(message.reactions.first { $0.emoji == "👍" })
        #expect(thumbsUp.count == 2)
        #expect(thumbsUp.reactedByMe == true)
        #expect(thumbsUp.id == "\(messageID.uuidString):👍")

        let heart = try #require(message.reactions.first { $0.emoji == "❤️" })
        #expect(heart.count == 1)
        #expect(heart.reactedByMe == false)
        #expect(heart.id == "\(messageID.uuidString):❤️")
    }

    @Test
    func receiptAdvancesMonotonicallyAndReadImpliesDelivered() async throws {
        let store = makeStore()
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

        try await store.applyReceipt(earlier)
        try await store.applyReceipt(laterRead)
        try await store.applyReceipt(regressive)

        let existing = MessengerLocalMapping.mapReceipt(from: earlier)
        let incoming = MessengerLocalMapping.mapReceipt(from: laterRead)
        MessengerLocalMapping.applyReceipt(incoming, to: existing)

        #expect(existing.lastDeliveredAt == isoDate("2026-07-02T13:41:00Z"))
        #expect(existing.lastReadAt == isoDate("2026-07-02T13:41:00Z"))
    }

    @Test
    func syncMetadataDoesNotMoveRevisionBackwards() async throws {
        let store = makeStore()
        let newer = LocalMessengerSyncMetadataSnapshot(
            id: MessengerPersistence.syncMetadataGlobalID,
            lastAppliedRevision: 200,
            lastSuccessfulSyncAt: Date(),
            lastFullRefreshAt: nil,
            lastAttemptedSyncAt: nil,
            lastFailedAt: nil,
            lastErrorCode: nil,
            state: MessengerSyncEngineState.idle.rawValue,
            needsFullRefresh: false,
            lastBootstrapAt: nil,
            lastKnownServerRevision: nil,
            schemaVersion: MessengerPersistence.schemaVersion,
            localUpdatedAt: Date()
        )
        let older = LocalMessengerSyncMetadataSnapshot(
            id: MessengerPersistence.syncMetadataGlobalID,
            lastAppliedRevision: 150,
            lastSuccessfulSyncAt: Date(),
            lastFullRefreshAt: nil,
            lastAttemptedSyncAt: nil,
            lastFailedAt: nil,
            lastErrorCode: nil,
            state: MessengerSyncEngineState.idle.rawValue,
            needsFullRefresh: false,
            lastBootstrapAt: nil,
            lastKnownServerRevision: nil,
            schemaVersion: MessengerPersistence.schemaVersion,
            localUpdatedAt: Date()
        )

        try await store.upsertSyncMetadata(newer)
        try await store.upsertSyncMetadata(older)

        let snapshot = try #require(try await store.fetchSyncMetadata())
        #expect(snapshot.lastAppliedRevision == 200)
    }

    @Test
    func resetRemovesAllMessengerEntities() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO()])
        try await store.upsertMessages([try makeTextMessageDTO()], conversationID: conversationID)
        try await store.upsertSyncMetadata(
            LocalMessengerSyncMetadataSnapshot(
                id: MessengerPersistence.syncMetadataGlobalID,
                lastAppliedRevision: 10,
                lastSuccessfulSyncAt: Date(),
                lastFullRefreshAt: nil,
                lastAttemptedSyncAt: nil,
                lastFailedAt: nil,
                lastErrorCode: nil,
                state: MessengerSyncEngineState.idle.rawValue,
                needsFullRefresh: false,
                lastBootstrapAt: nil,
                lastKnownServerRevision: nil,
                schemaVersion: MessengerPersistence.schemaVersion,
                localUpdatedAt: Date()
            )
        )

        try await store.resetAllMessengerData()

        #expect(try await store.fetchLocalConversations().isEmpty)
        #expect(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).isEmpty)
        #expect(try await store.fetchSyncMetadata() == nil)
    }

    @Test
    func localStoreDiagnosticsDoNotExportSensitiveFields() {
        let entry = MessengerDiagnostics.makeEntry(
            .messengerLocalMessagesUpserted,
            conversationID: conversationID,
            messageID: messageID,
            metadata: [
                "count": "1",
                "downloadUrl": "https://storage.test/photo.jpg?X-Amz-Signature=secret",
                "uploadUrl": "https://storage.test/upload?X-Amz-Signature=secret",
                "Authorization": "Bearer secret",
                "JWT": "secret",
                "storageKey": "secret",
                "localPath": "/tmp/secret.jpg",
                "attachmentCount": "1"
            ]
        )

        let export = entry.exportLine
        #expect(entry.metadata["downloadUrl"] == nil)
        #expect(entry.metadata["uploadUrl"] == nil)
        #expect(entry.metadata["Authorization"] == nil)
        #expect(entry.metadata["JWT"] == nil)
        #expect(entry.metadata["storageKey"] == nil)
        #expect(entry.metadata["localPath"] == nil)
        #expect(entry.metadata["attachmentCount"] == "1")
        #expect(!export.contains("X-Amz-Signature"))
        #expect(!export.contains("Bearer"))
    }

    @Test
    func markMessageDeletedClearsRenderableAttachments() async throws {
        let store = makeStore()
        try await store.upsertMessages([makeImageMessageDTO()], conversationID: conversationID)
        try await store.markMessageDeleted(messageID: messageID, deletedAt: isoDate("2026-07-02T13:45:00Z"))

        let message = try #require(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first)
        #expect(message.localState == .deleted)
        #expect(message.attachments.isEmpty)
    }
}

// MARK: - Fixtures

private extension MessengerLocalStoreTests {
    func makeStore() -> MessengerLocalStore {
        MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
    }

    func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func makeConversationDTO(includeSignedPhotoURL: Bool = false) -> ConversationDTO {
        let photoJSON: String
        if includeSignedPhotoURL {
            photoJSON = """
            "primaryPhoto": {
              "id": "\(photoID.uuidString)",
              "downloadUrl": "https://storage.test/avatar.jpg?X-Amz-Signature=secret",
              "avatarPresentation": { "offsetX": 0.1, "offsetY": 0.2, "scale": 1.0 }
            }
            """
        } else {
            photoJSON = """
            "primaryPhoto": null
            """
        }

        return try! JSONCoding.decoder.decode(ConversationDTO.self, from: Data("""
        {
          "id": "\(conversationID.uuidString)",
          "type": "direct",
          "status": "active",
          "connectionID": null,
          "otherParticipant": {
            "profile": {
              "id": "\(profileID.uuidString)",
              "displayName": "Taylor",
              "bio": null,
              "city": null,
              \(photoJSON)
            },
            "role": "member",
            "joinedAt": "2026-06-26T13:18:31Z",
            "lastReadAt": null,
            "lastDeliveredAt": null
          },
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
          "unreadCount": 2,
          "lastReadAt": null,
          "lastMessageAt": "2026-06-26T13:18:31Z",
          "createdAt": "2026-06-26T13:18:31Z",
          "updatedAt": "2026-06-26T13:18:31Z"
        }
        """.utf8))
    }

    func makeTextMessageDTO(
        id: UUID? = nil,
        clientMessageID: String = "client-1",
        body: String = "Hello",
        createdAt: String = "2026-06-26T13:18:31Z",
        editedAt: String? = nil,
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
          "replyTo": {
            "id": "\(UUID().uuidString)",
            "body": "Quoted",
            "senderProfileID": "\(profileID.uuidString)"
          },
          "reactions": \(reactions),
          "deliveryStatus": "sent",
          "clientMessageID": "\(clientMessageID)",
          "createdAt": "\(createdAt)",
          "editedAt": \(editedAt == nil ? "null" : "\"\(editedAt!)\""),
          "deletedAt": null
        }
        """.utf8))
    }

    func seedPaginatedMessages(count: Int, store: MessengerLocalStore) async throws -> [UUID] {
        var ids: [UUID] = []
        var dtos: [MessageDTO] = []

        for index in 0..<count {
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index))!
            ids.append(id)
            dtos.append(try makeTextMessageDTO(
                id: id,
                clientMessageID: "client-\(index)",
                body: "Message \(index)",
                createdAt: "2026-06-26T10:\(String(format: "%02d", index)):00Z"
            ))
        }

        try await store.upsertMessages(dtos, conversationID: conversationID)
        return ids
    }

    func makeImageMessageDTO(
        id: UUID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
        attachmentID: UUID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
        createdAt: String = "2026-06-26T13:18:31Z",
        deleted: Bool = false
    ) -> MessageDTO {
        try! JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
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
          "clientMessageID": "image-client-\(id.uuidString)",
          "createdAt": "\(createdAt)",
          "editedAt": null,
          "deletedAt": \(deleted ? "\"2026-07-02T13:45:00Z\"" : "null")
        }
        """.utf8))
    }

    func makeReceiptDTO(deliveredAt: String?, readAt: String?) throws -> MessengerReceiptDTO {
        try JSONCoding.decoder.decode(MessengerReceiptDTO.self, from: Data("""
        {
          "profileID": "\(profileID.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "messageID": "\(messageID.uuidString)",
          "deliveredAt": \(deliveredAt == nil ? "null" : "\"\(deliveredAt!)\""),
          "readAt": \(readAt == nil ? "null" : "\"\(readAt!)\"") 
        }
        """.utf8))
    }
}
