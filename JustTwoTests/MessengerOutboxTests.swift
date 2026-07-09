import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerOutboxTests {
    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let clientMessageID = "client-outbox-text-1"

    @Test
    func createTextOutboxItemPersistsStableClientMessageIDAndBody() async throws {
        let store = makeStore()
        let snapshot = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Offline hello",
            replyToMessageID: nil
        )

        #expect(snapshot.conversationID == conversationID.uuidString)
        #expect(snapshot.clientMessageID == clientMessageID)
        #expect(snapshot.body == "Offline hello")
        #expect(snapshot.status == .pending)
        #expect(snapshot.attemptCount == 0)

        let fetched = try await store.fetchOutboxItem(clientMessageID: clientMessageID)
        #expect(fetched == snapshot)
    }

    @Test
    func retryUsesSameClientMessageID() async throws {
        let store = makeStore()
        let snapshot = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Retry me",
            replyToMessageID: nil
        )

        try await store.markOutboxPending(clientMessageID: clientMessageID)
        let pending = try #require(try await store.fetchOutboxItem(clientMessageID: clientMessageID))

        #expect(pending.clientMessageID == snapshot.clientMessageID)
        #expect(pending.body == snapshot.body)
    }

    @Test
    func failedSendIncrementsAttemptCountAndSchedulesRetry() async throws {
        let store = makeStore()
        _ = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Retry me",
            replyToMessageID: nil
        )

        try await store.markOutboxSending(clientMessageID: clientMessageID)
        try await store.markOutboxFailed(
            clientMessageID: clientMessageID,
            errorCode: "networkOffline",
            nextRetryAt: nil
        )

        let failed = try #require(try await store.fetchOutboxItem(clientMessageID: clientMessageID))
        #expect(failed.status == .failed)
        #expect(failed.attemptCount == 1)
        #expect(failed.nextRetryAt != nil)
        #expect(failed.lastErrorCode == "networkOffline")
    }

    @Test
    func successfulSendDeletesOutboxItem() async throws {
        let store = makeStore()
        _ = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Done",
            replyToMessageID: nil
        )

        let serverMessageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        try await store.markOutboxSent(clientMessageID: clientMessageID, serverMessageID: serverMessageID)
        try await store.deleteOutboxItem(clientMessageID: clientMessageID)

        let fetched = try await store.fetchOutboxItem(clientMessageID: clientMessageID)
        #expect(fetched == nil)
    }

    @Test
    func resetClearsOutbox() async throws {
        let store = makeStore()
        _ = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Logout",
            replyToMessageID: nil
        )

        try await store.resetAllMessengerData()
        let items = try await store.fetchOutboxItems(conversationID: conversationID)
        #expect(items.isEmpty)
    }

    @Test
    func pendingOutboxItemSurvivesForRehydrate() async throws {
        let store = makeStore()
        _ = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Survives relaunch",
            replyToMessageID: nil
        )

        let items = try await store.fetchOutboxItems(conversationID: conversationID)
        #expect(items.count == 1)
        #expect(items[0].status == .pending)
        #expect(items[0].clientMessageID == clientMessageID)
    }

    @Test
    func confirmedClientMessageIDAllowsOutboxCleanup() async throws {
        let store = makeStore()
        _ = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Already sent",
            replyToMessageID: nil
        )

        try await store.deleteOutboxItem(clientMessageID: clientMessageID)
        let items = try await store.fetchOutboxItems(conversationID: conversationID)
        #expect(items.isEmpty)
    }

    @Test
    func registerPersistedTextEntryDoesNotDuplicateOutboxRow() async throws {
        let store = makeStore()
        MessengerOutbox.shared.clear()

        let snapshot = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Ordered send",
            replyToMessageID: nil
        )

        MessengerOutbox.shared.registerPersistedTextEntry(
            snapshot: snapshot,
            localMessageID: OptimisticMessageIdentity.localMessageID(for: clientMessageID),
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        let items = try await store.fetchOutboxItems(conversationID: conversationID)
        #expect(items.count == 1)
        #expect(items[0].clientMessageID == clientMessageID)
        #expect(MessengerOutbox.shared.entry(for: clientMessageID) != nil)
    }

    @Test
    func createTextOutboxItemPrecedesInMemoryRegistration() async throws {
        let store = makeStore()
        MessengerOutbox.shared.clear()

        let snapshot = try await store.createTextOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: "Persist first",
            replyToMessageID: nil
        )

        let persisted = try #require(try await store.fetchOutboxItem(clientMessageID: clientMessageID))
        #expect(persisted.status == .pending)
        #expect(MessengerOutbox.shared.entry(for: clientMessageID) == nil)

        MessengerOutbox.shared.registerPersistedTextEntry(
            snapshot: snapshot,
            localMessageID: OptimisticMessageIdentity.localMessageID(for: clientMessageID),
            session: SessionStore.shared,
            router: AppRouter.shared
        )

        #expect(MessengerOutbox.shared.entry(for: clientMessageID)?.state == .queued)
    }

    @Test
    func outboxDiagnosticsDoNotIncludeMessageBody() {
        let entry = MessengerDiagnostics.makeEntry(
            .outboxItemCreated,
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "kind": "text",
                "status": "pending",
                "body": "secret body"
            ]
        )

        #expect(entry.metadata["body"] == nil)
        #expect(!entry.exportLine.contains("secret body"))
        #expect(entry.exportLine.contains("outboxItemCreated"))
    }

    private func makeStore() -> MessengerLocalStore {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        #if DEBUG
        MessengerMessageCacheService.testingStore = store
        #endif
        return store
    }
}
