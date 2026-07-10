import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerConversationCacheTests {
    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let profileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private let otherProfileID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

    @Test
    func emptyCacheHydrationReturnsNil() async {
        let store = makeStore()
        let previews = await MessengerConversationCacheService.hydrateCachedPreviews(
            currentProfileID: profileID
        )
        #expect(previews == nil)
    }

    @Test
    func cachedConversationsMapToViewItemsSortedByLastMessageAt() async throws {
        let store = makeStore()
        let older = makeConversationDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            lastMessageAt: "2026-06-26T10:00:00Z",
            unreadCount: 1,
            messageID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let newer = makeConversationDTO(
            id: conversationID,
            lastMessageAt: "2026-06-26T13:18:31Z",
            unreadCount: 3,
            messageID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )

        try await store.upsertConversations([older, newer])

        let snapshots = try await store.fetchLocalConversations()
        let newestSnapshot = try #require(snapshots.first(where: { $0.id == conversationID.uuidString }))
        #expect(newestSnapshot.lastMessageBody == "Hello")
        #expect(newestSnapshot.lastMessageDeletedAt == nil)

        let previews = snapshots.compactMap {
            ChatUIMapping.conversationPreview(from: $0, currentProfileID: profileID)
        }
        let newestPreview = try #require(
            ChatUIMapping.conversationPreview(from: newestSnapshot, currentProfileID: profileID)
        )

        #expect(previews.count == 2)
        #expect(newestPreview.id == conversationID)
        #expect(newestPreview.unreadCount == 3)
        #expect(newestPreview.lastMessageText == "Hello")
        #expect(previews.first?.id == conversationID)
        #expect(previews[0].unreadCount == 3)
        #expect(previews[0].lastMessageText == "Hello")
        #expect(previews[0].avatarURL == nil)
        #expect(previews[1].unreadCount == 1)
    }

    @Test
    func restUpsertPersistsConversationCache() async throws {
        let store = makeStore()
        let dto = makeConversationDTO()

        await MessengerConversationCacheService.persistRESTConversations([dto])

        let snapshots = try await store.fetchLocalConversations()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].lastMessageBody == "Hello")
        #expect(snapshots[0].lastMessageKind == MessageKind.text.rawValue)
    }

    @Test
    func deltaConversationUpsertUpdatesLocalCache() async throws {
        let store = makeStore()
        let dto = makeConversationDTO(unreadCount: 2)

        await MessengerConversationCacheService.persistDeltaConversation(
            dto,
            eventType: MessengerSyncEventType.conversationUpdated.rawValue
        )

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        #expect(snapshot.unreadCount == 2)
    }

    @Test
    func messageDeletedUpdatesCachedLastMessagePreview() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO()])

        let deletedMessage = try makeMessageDTO(deletedAt: "2026-07-02T13:45:00Z")
        await MessengerConversationCacheService.persistRealtimeMessage(
            deletedMessage,
            unreadCount: 0
        )

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        #expect(snapshot.lastMessageDeletedAt != nil)
        #expect(snapshot.lastMessageBody == nil)
    }

    @Test
    func conversationReadPatchClearsUnreadInCache() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO(unreadCount: 4)])

        await MessengerConversationCacheService.persistRealtimeConversationRead(
            conversationID: conversationID
        )

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        #expect(snapshot.unreadCount == 0)
    }

    @Test
    func logoutResetClearsCachedConversations() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO()])
        #expect(try await store.fetchLocalConversations().isEmpty == false)

        try await store.resetAllMessengerData()

        #expect(try await store.fetchLocalConversations().isEmpty)
        let previews = await MessengerConversationCacheService.hydrateCachedPreviews(
            currentProfileID: profileID
        )
        #expect(previews == nil)
    }

    @Test
    func cachedConversationDoesNotPersistSignedPhotoURL() async throws {
        let store = makeStore()
        defer { MessengerConversationCacheService.testingStore = nil }
        let dto = makeConversationDTO(includeSignedPhotoURL: true)

        await MessengerConversationCacheService.persistRESTConversations([dto])

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        let encoded = String(describing: snapshot)
        #expect(!encoded.contains("X-Amz-Signature"))
        #expect(!encoded.contains("downloadUrl"))
    }

    @Test
    func conversationCacheDiagnosticsDoNotExportSensitiveFields() async throws {
        MessengerDiagnosticsStore.shared.clear()
        let store = makeStore()
        defer { MessengerConversationCacheService.testingStore = nil }
        let dto = makeConversationDTO(includeSignedPhotoURL: true)

        await MessengerConversationCacheService.persistRESTConversations([dto])
        _ = await MessengerConversationCacheService.hydrateCachedPreviews(currentProfileID: profileID)
        try await Task.sleep(nanoseconds: 100_000_000)

        let export = (await MessengerDiagnostics.exportTextForClipboard()).lowercased()
        #expect(!export.contains("x-amz-signature"))
        #expect(!export.contains("downloadurl"))
        #expect(!export.contains("bearer"))
        #expect(!export.contains("authorization"))
        #expect(!export.contains("jwt"))
        #expect(!export.contains("storagekey"))
        #expect(!export.contains("localpath"))
    }
}

@MainActor
private extension MessengerConversationCacheTests {
    func makeStore() -> MessengerLocalStore {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        MessengerConversationCacheService.testingStore = store
        return store
    }

    @Test("cached lastSeenAt persists without online")
    func cachedLastSeenAtPersists() async throws {
        let store = makeStore()
        let dto = makeConversationDTO(
            presenceJSON: """
            "presence": {
              "isOnline": true,
              "lastSeenAt": "2026-07-10T12:00:00Z"
            }
            """
        )

        await MessengerConversationCacheService.persistRESTConversations([dto])

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        #expect(snapshot.otherParticipantLastSeenAt != nil)
    }

    @Test("old cached conversation without lastSeenAt still loads")
    func oldCacheWithoutLastSeenLoads() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO()])

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        #expect(snapshot.otherParticipantLastSeenAt == nil)
    }

    @Test("newer lastSeenAt is not decreased by older async merge")
    func newerLastSeenNotDecreasedByOlderMerge() async throws {
        let store = makeStore()
        let newer = makeConversationDTO(
            presenceJSON: """
            "presence": {
              "isOnline": false,
              "lastSeenAt": "2026-07-10T14:00:00Z"
            }
            """
        )
        let older = makeConversationDTO(
            presenceJSON: """
            "presence": {
              "isOnline": false,
              "lastSeenAt": "2026-07-10T12:00:00Z"
            }
            """
        )

        await MessengerConversationCacheService.persistRESTConversations([newer])
        await MessengerConversationCacheService.persistRESTConversations([older])

        let snapshot = try #require(try await store.fetchLocalConversations().first)
        let stored = try #require(snapshot.otherParticipantLastSeenAt)
        #expect(stored > Date(timeIntervalSince1970: 1_752_153_600)) // after 12:00Z
    }

    @Test("cache hydrate shows lastSeen without online")
    func cacheHydrateShowsLastSeenWithoutOnline() async throws {
        let store = PresenceStore.makeForTesting()
        let profileID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let lastSeen = Date(timeIntervalSince1970: 1_752_160_000)

        store.hydrateFromCacheSnapshots([
            LocalConversationSnapshot(
                id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                type: "direct",
                status: "active",
                connectionID: nil,
                createdAt: lastSeen,
                updatedAt: lastSeen,
                lastMessageAt: lastSeen,
                lastReadAt: nil,
                unreadCount: 0,
                otherParticipantProfileID: profileID.uuidString,
                otherParticipantDisplayName: "Taylor",
                otherParticipantPrimaryPhotoID: nil,
                otherParticipantPrimaryPhotoDownloadURLExpiresAt: nil,
                otherParticipantLastSeenAt: lastSeen,
                lastMessageID: nil,
                lastMessageKind: nil,
                lastMessageBody: nil,
                lastMessageSenderProfileID: nil,
                lastMessageCreatedAt: nil,
                lastMessageDeletedAt: nil,
                lastSyncedAt: lastSeen,
                localUpdatedAt: lastSeen
            )
        ])

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == lastSeen)
    }

    func makeConversationDTO(
        id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        lastMessageAt: String = "2026-06-26T13:18:31Z",
        unreadCount: Int = 0,
        includeSignedPhotoURL: Bool = false,
        presenceJSON: String = "",
        messageID: UUID? = nil
    ) -> ConversationDTO {
        let resolvedMessageID = messageID ?? self.messageID
        let photoJSON: String
        if includeSignedPhotoURL {
            photoJSON = """
            "primaryPhoto": {
              "id": "\(UUID().uuidString)",
              "downloadUrl": "https://storage.test/private/photo.jpg?X-Amz-Signature=secret",
              "avatarPresentation": { "offsetX": 0.1, "offsetY": 0.2, "scale": 1.0 }
            }
            """
        } else {
            photoJSON = """
            "primaryPhoto": null
            """
        }

        let presenceField = presenceJSON.isEmpty ? "" : "\(presenceJSON),"

        return try! JSONCoding.decoder.decode(ConversationDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "type": "direct",
          "status": "active",
          "connectionID": null,
          "otherParticipant": {
            "profile": {
              "id": "\(otherProfileID.uuidString)",
              "displayName": "Taylor",
              "bio": null,
              "city": null,
              \(photoJSON)\(presenceJSON.isEmpty ? "" : ",\n              \(presenceJSON)")
            },
            "role": "member",
            "joinedAt": "2026-06-26T13:18:31Z",
            "lastReadAt": null,
            "lastDeliveredAt": null
          },
          "lastMessage": {
            "id": "\(resolvedMessageID.uuidString)",
            "conversationID": "\(id.uuidString)",
            "senderProfileID": "\(otherProfileID.uuidString)",
            "kind": "text",
            "body": "Hello",
            "attachments": [],
            "replyTo": null,
            "reactions": [],
            "deliveryStatus": "sent",
            "clientMessageID": "client-preview",
            "createdAt": "\(lastMessageAt)",
            "editedAt": null,
            "deletedAt": null
          },
          "unreadCount": \(unreadCount),
          "lastReadAt": null,
          "lastMessageAt": "\(lastMessageAt)",
          "createdAt": "2026-06-26T13:18:31Z",
          "updatedAt": "2026-06-26T13:18:31Z"
        }
        """.utf8))
    }

    func makeMessageDTO(deletedAt: String?) throws -> MessageDTO {
        try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(messageID.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "\(otherProfileID.uuidString)",
          "kind": "text",
          "body": "Hello",
          "attachments": [],
          "replyTo": null,
          "reactions": [],
          "deliveryStatus": "sent",
          "clientMessageID": "client-preview",
          "createdAt": "2026-06-26T13:18:31Z",
          "editedAt": null,
          "deletedAt": \(deletedAt == nil ? "null" : "\"\(deletedAt!)\"")
        }
        """.utf8))
    }
}
