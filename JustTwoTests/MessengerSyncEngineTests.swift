import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerSyncEngineTests {
    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    @Test
    func hydrateLoadsPersistedCursorIntoRuntimeState() async throws {
        let store = makeStore()
        let engine = makeEngine(store: store)
        let delta = MessengerDeltaSyncService(syncState: MessengerSyncStateStore.shared)

        try await store.upsertSyncMetadata(makeMetadata(revision: 42))
        MessengerSyncStateStore.shared.reset()

        await engine.hydrateFromLocalStore()

        #expect(MessengerSyncStateStore.shared.currentRevision == 42)
        #expect(engine.state == .idle)
        _ = delta
    }

    @Test
    func missingMetadataHydratesSafely() async throws {
        let store = makeStore()
        let engine = makeEngine(store: store)
        MessengerSyncStateStore.shared.reset()

        await engine.hydrateFromLocalStore()

        #expect(MessengerSyncStateStore.shared.currentRevision == nil)
        #expect(engine.state == .idle)
        #expect(try await store.fetchSyncMetadata() == nil)
    }

    @Test
    func resetClearsSyncMetadata() async throws {
        let store = makeStore()
        try await store.upsertSyncMetadata(makeMetadata(revision: 99))

        try await store.resetAllMessengerData()

        #expect(try await store.fetchSyncMetadata() == nil)
    }

    @Test
    func validateRevisionOrderDetectsGap() {
        let events = [
            makeEvent(revision: 105, conversationID: conversationID)
        ]

        #expect(throws: MessengerSyncEngineError.revisionGapDetected) {
            try validateRevisionOrderForTests(events: events, afterRevision: 100)
        }
    }

    @Test
    func validateRevisionOrderAcceptsNextRevision() throws {
        let events = [
            makeEvent(revision: 101, conversationID: conversationID)
        ]

        try validateRevisionOrderForTests(events: events, afterRevision: 100)
    }

    @Test
    func persistedMetadataRoundTripsThroughStore() async throws {
        let store = makeStore()
        try await store.upsertSyncMetadata(makeMetadata(revision: 10, state: .backoff))
        let snapshot = try #require(try await store.fetchSyncMetadata())
        #expect(snapshot.lastAppliedRevision == 10)
        #expect(snapshot.state == MessengerSyncEngineState.backoff.rawValue)
    }

    @Test
    func syncDiagnosticsDoNotLeakSensitiveMetadata() {
        let entry = MessengerDiagnostics.makeEntry(
            .syncCursorAdvanced,
            conversationID: conversationID,
            metadata: [
                "body": "secret",
                "caption": "hidden",
                "downloadUrl": "https://example.com/file?X-Amz-Signature=abc",
                "Authorization": "Bearer jwt-token",
                "localPath": "/Users/secret/file.jpg"
            ]
        )

        let export = entry.exportLine
        #expect(!export.contains("secret"))
        #expect(!export.contains("hidden"))
        #expect(!export.contains("Bearer"))
        #expect(!export.contains("/Users/"))
    }

    private func makeEngine(store: MessengerLocalStore) -> MessengerSyncEngine {
        #if DEBUG
        MessengerMessageCacheService.testingStore = store
        #endif
        let syncState = MessengerSyncStateStore.shared
        syncState.reset()
        return MessengerSyncEngine(
            deltaSync: MessengerDeltaSyncService(syncState: syncState),
            syncState: syncState
        )
    }

    private func makeStore() -> MessengerLocalStore {
        MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
    }

    private func makeMetadata(
        revision: Int64,
        state: MessengerSyncEngineState = .idle
    ) -> LocalMessengerSyncMetadataSnapshot {
        LocalMessengerSyncMetadataSnapshot(
            id: MessengerPersistence.syncMetadataGlobalID,
            lastAppliedRevision: revision,
            lastSuccessfulSyncAt: Date(),
            lastFullRefreshAt: nil,
            lastAttemptedSyncAt: nil,
            lastFailedAt: nil,
            lastErrorCode: nil,
            state: state.rawValue,
            needsFullRefresh: false,
            lastBootstrapAt: nil,
            lastKnownServerRevision: nil,
            schemaVersion: MessengerPersistence.schemaVersion,
            localUpdatedAt: Date()
        )
    }

    private func makeEvent(revision: Int64, conversationID: UUID) -> MessengerSyncEventDTO {
        let json = """
        {
          "revision": \(revision),
          "type": "conversation.updated",
          "conversationID": "\(conversationID.uuidString)",
          "messageID": null,
          "actorProfileID": null,
          "occurredAt": "2026-07-02T13:39:35Z",
          "conversation": null,
          "message": null,
          "receipt": null
        }
        """.data(using: .utf8)!

        return try! JSONDecoder.justTwoAPI.decode(MessengerSyncEventDTO.self, from: json)
    }

    private func validateRevisionOrderForTests(
        events: [MessengerSyncEventDTO],
        afterRevision: Int64
    ) throws {
        guard !events.isEmpty else { return }
        let sorted = events.sorted { $0.revision < $1.revision }
        if let first = sorted.first, first.revision > afterRevision + 1 {
            throw MessengerSyncEngineError.revisionGapDetected
        }
        for index in 1..<sorted.count {
            if sorted[index].revision <= sorted[index - 1].revision {
                throw MessengerSyncEngineError.outOfOrderRevision
            }
        }
    }
}
