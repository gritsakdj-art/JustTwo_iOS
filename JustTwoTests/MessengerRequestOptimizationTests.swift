import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerRequestOptimizationTests {

    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let profileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

    // MARK: - Freshness policy

    @Test
    func memoryFreshnessUsesTTL() {
        let loadedAt = Date().addingTimeInterval(-60)
        #expect(MessengerCacheFreshnessPolicy.isMemoryEntryFresh(loadedAt: loadedAt))
        let stale = Date().addingTimeInterval(-300)
        #expect(!MessengerCacheFreshnessPolicy.isMemoryEntryFresh(loadedAt: stale))
    }

    @Test
    func messageCacheFreshWhenNewestCoversConversationActivity() {
        let lastActivity = Date(timeIntervalSince1970: 2_000)
        let newestLocal = Date(timeIntervalSince1970: 2_001)
        #expect(
            MessengerCacheFreshnessPolicy.isMessageCacheFresh(
                newestLocalMessageAt: newestLocal,
                conversationLastMessageAt: lastActivity
            )
        )
    }

    @Test
    func messageCacheStaleWhenConversationHasNewerActivity() {
        let lastActivity = Date(timeIntervalSince1970: 3_000)
        let newestLocal = Date(timeIntervalSince1970: 2_000)
        #expect(
            !MessengerCacheFreshnessPolicy.isMessageCacheFresh(
                newestLocalMessageAt: newestLocal,
                conversationLastMessageAt: lastActivity
            )
        )
    }

    @Test
    func conversationListRefreshFreshnessUsesTTL() {
        let recent = Date().addingTimeInterval(-30)
        #expect(MessengerCacheFreshnessPolicy.isConversationListRefreshFresh(lastNetworkRefreshAt: recent))
        let stale = Date().addingTimeInterval(-200)
        #expect(!MessengerCacheFreshnessPolicy.isConversationListRefreshFresh(lastNetworkRefreshAt: stale))
    }

    // MARK: - MessageCacheStore

    @Test
    func freshMemoryCacheSkipsNetworkOnOpen() async {
        MessengerDiagnosticsStore.shared.clear()
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        let message = makeMessage(createdAt: Date(timeIntervalSince1970: 5_000))
        store.setMessages([message], for: conversationID)

        let result = await store.loadRecentMessagesIfNeeded(
            conversationID: conversationID,
            session: SessionStore.shared,
            router: AppRouter.shared,
            force: false,
            reason: .open,
            conversationLastMessageAt: Date(timeIntervalSince1970: 4_900)
        )

        await waitForDiagnostics(event: MessengerDiagnosticEvent.messengerChatOpenNetworkRefreshSkippedFreshCache.rawValue)

        #expect(result.count == 1)
        #expect(
            MessengerDiagnosticsStore.shared.events.contains {
                $0.event == MessengerDiagnosticEvent.messengerChatOpenNetworkRefreshSkippedFreshCache.rawValue
            }
        )
    }

    @Test
    func startupPreloadSkipsNetworkWhenMemoryAlreadyFresh() async {
        MessengerDiagnosticsStore.shared.clear()
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        let lastMessageAt = Date(timeIntervalSince1970: 5_000)
        store.setMessages([makeMessage(createdAt: lastMessageAt)], for: conversationID)

        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }

        await store.preloadConversationMessages(
            conversation: makeConversationPreview(lastMessageAt: lastMessageAt),
            session: makeAuthenticatedSession(),
            router: AppRouter.shared
        )

        let sawSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerStartupMessagesNetworkPreloadSkippedFreshCache.rawValue
        )

        #expect(store.hasCachedMessages(for: conversationID))
        #expect(sawSkip)
    }

    @Test
    func offlineKnownStateSkipsStartupPreloadNetwork() async {
        MessengerDiagnosticsStore.shared.clear()
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }

        await store.preloadConversationMessages(
            conversation: makeConversationPreview(lastMessageAt: .now),
            session: makeAuthenticatedSession(),
            router: AppRouter.shared
        )

        let sawOfflineSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerNetworkRequestSkippedOffline.rawValue
        )

        #expect(sawOfflineSkip)
    }

    @Test
    func localCachedMessagesPopulateMemoryWithoutNetworkWhenFresh() async throws {
        MessengerDiagnosticsStore.shared.clear()
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        let localStore = MessengerLocalStore(inMemoryOnly: true)
        MessengerMessageCacheService.testingStore = localStore
        defer { MessengerMessageCacheService.testingStore = nil }

        let dto = try makeTextMessageDTO()
        await MessengerMessageCacheService.persistRESTMessages([dto], conversationID: conversationID)

        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }

        let session = makeAuthenticatedSession()

        await store.preloadConversationMessages(
            conversation: makeConversationPreview(lastMessageAt: dto.createdAt ?? .now),
            session: session,
            router: AppRouter.shared
        )

        let sawLocal = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerStartupMessagesLocalPreloadSucceeded.rawValue
        )
        let sawSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerStartupMessagesNetworkPreloadSkippedFreshCache.rawValue
        )

        #expect(store.hasCachedMessages(for: conversationID))
        #expect(sawLocal)
        #expect(sawSkip)
    }

    @Test
    func staleResponseCannotOverwriteNewerRealtimeMessage() {
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        let messageID = UUID()
        let staleFetched = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            text: "Original"
        )
        let realtimeEdited = makeMessage(
            id: messageID,
            createdAt: Date(timeIntervalSince1970: 1_000),
            text: "Edited",
            isEdited: true
        )

        store.setMessages([realtimeEdited], for: conversationID)
        store.mergeLoadedMessages([staleFetched], for: conversationID)

        let message = store.messages(for: conversationID)?.first
        #expect(message?.displayText == "Edited")
        #expect(message?.isEdited == true)
    }

    // MARK: - Conversation list

    @Test
    func refreshNetworkIfStaleSkipsRecentRefresh() async {
        MessengerDiagnosticsStore.shared.clear()
        let viewModel = ConversationListViewModel()
        viewModel.reset()
        viewModel.setLastNetworkRefreshAtForTesting(Date().addingTimeInterval(-30))

        await viewModel.refreshNetworkIfStale(session: SessionStore.shared, router: AppRouter.shared)

        let sawSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerConversationRefreshSkippedRecent.rawValue
        )

        #expect(sawSkip)
    }

    @Test
    func manualRefreshFailsFastWhenOfflineKnown() async {
        MessengerDiagnosticsStore.shared.clear()
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        store.setMessages([makeMessage(createdAt: .now)], for: conversationID)

        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }

        _ = await store.loadRecentMessagesIfNeeded(
            conversationID: conversationID,
            session: SessionStore.shared,
            router: AppRouter.shared,
            force: true,
            reason: .manualRefresh,
            conversationLastMessageAt: .now
        )

        let sawOfflineSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerNetworkRequestSkippedOffline.rawValue
        )

        #expect(sawOfflineSkip)
        #expect(store.entry(for: conversationID)?.errorMessage != nil)
        #expect(store.hasCachedMessages(for: conversationID))
    }

    @Test
    func staleLocalCacheDoesNotSkipImmediateNetworkPreloadWhenFreshnessFails() async {
        MessengerDiagnosticsStore.shared.clear()
        let store = MessageCacheStore.shared
        store.reset()
        defer { store.reset() }

        let staleMessageAt = Date(timeIntervalSince1970: 1_000)
        let newerConversationActivity = Date(timeIntervalSince1970: 5_000)
        store.setMessages([makeMessage(createdAt: staleMessageAt)], for: conversationID)

        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }

        await store.preloadConversationMessages(
            conversation: makeConversationPreview(lastMessageAt: newerConversationActivity),
            session: makeAuthenticatedSession(),
            router: AppRouter.shared
        )

        let sawFreshSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerStartupMessagesNetworkPreloadSkippedFreshCache.rawValue
        )
        let sawOfflineSkip = await waitForDiagnostics(
            event: MessengerDiagnosticEvent.messengerNetworkRequestSkippedOffline.rawValue
        )

        #expect(!sawFreshSkip)
        #expect(sawOfflineSkip)
        #expect(store.hasCachedMessages(for: conversationID))
    }

    // MARK: - Privacy

    @Test
    func diagnosticsExportHasNoSensitiveMessengerOptimizationFields() {
        MessengerDiagnosticsStore.shared.clear()
        MessengerDiagnostics.event(
            .messengerChatOpenNetworkRefreshSkippedFreshCache,
            conversationID: conversationID,
            metadata: ["count": "1", "reason": "open"]
        )

        let export = MessengerDiagnostics.exportTextForClipboard().lowercased()
        #expect(!export.contains("downloadurl"))
        #expect(!export.contains("uploadurl"))
        #expect(!export.contains("bearer"))
        #expect(!export.contains("jwt"))
        #expect(!export.contains("storagekey"))
        #expect(!export.contains("localpath"))
        #expect(!export.contains("x-amz-signature"))
    }

    // MARK: - Helpers

    private func waitForDiagnostics(
        event: String,
        conversationID: UUID? = nil,
        timeoutMs: Int = 2_000
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        while Date() < deadline {
            if MessengerDiagnosticsStore.shared.events.contains(where: { entry in
                entry.event == event
                    && (conversationID == nil || entry.conversationID == conversationID)
            }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func makeConversationPreview(lastMessageAt: Date) -> ChatConversationPreview {
        ChatConversationPreview(
            id: conversationID,
            title: "Test",
            otherParticipantProfileID: profileID,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Hi",
            lastSenderName: "A",
            lastMessageAt: lastMessageAt,
            unreadCount: 0
        )
    }

    private func makeAuthenticatedSession() -> SessionStore {
        let session = SessionStore.shared
        if let profile = try? makeProfile(id: profileID) {
            session.updateCurrentProfile(profile)
        }
        return session
    }

    private func makeMessage(
        id: UUID = UUID(),
        createdAt: Date,
        text: String = "Hello",
        isEdited: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            displayText: text,
            rawBody: text,
            createdAt: createdAt,
            isMine: true,
            isDeleted: false,
            isEdited: isEdited,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: .sent
        )
    }

    private func makeTextMessageDTO() throws -> MessageDTO {
        try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          "conversationID": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "senderProfileID": "cccccccc-cccc-cccc-cccc-cccccccccccc",
          "kind": "text",
          "body": "Hello",
          "attachments": [],
          "replyTo": null,
          "reactions": [],
          "createdAt": "2026-07-02T14:00:00Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))
    }

    private func makeProfile(id: UUID) throws -> UserProfileDTO {
        try JSONCoding.decoder.decode(UserProfileDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "displayName": "Test",
          "birthDate": "1990-01-01",
          "gender": "other",
          "bio": null,
          "city": null,
          "latitude": null,
          "longitude": null,
          "moodModeEnabled": false,
          "activityModeEnabled": false,
          "isVisibleInDiscovery": true
        }
        """.utf8))
    }
}
