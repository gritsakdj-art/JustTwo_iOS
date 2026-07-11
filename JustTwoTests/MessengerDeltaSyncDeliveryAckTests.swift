@testable import JustTwo
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct MessengerDeltaSyncDeliveryAckTests {

    // MARK: - Repair persistence failure

    @Test("repair does not schedule ack when boundary persistence fails, then succeeds on retry")
    func repairPersistenceFailureBlocksAckUntilRetrySucceeds() async throws {
        let store = makeStore()
        let syncState = MessengerSyncStateStore.shared
        syncState.reset()
        syncState.setRevision(10)

        #if DEBUG
        MessengerMessageCacheService.testingStore = store
        MessengerSyncService.testingFetchSyncEventsHandler = { _, conversationID in
            #expect(conversationID == self.conversationID)
            return self.makeSyncEventsResponse(
                events: [try self.makeMessageCreatedEvent(
                    revision: 11,
                    messageID: self.messageC,
                    createdAtISO: "2026-06-26T13:18:31Z"
                )],
                nextRevision: 11,
                hasMore: false
            )
        }
        defer {
            MessengerMessageCacheService.testingStore = nil
            MessengerSyncService.testingFetchSyncEventsHandler = nil
        }
        #endif

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store
        var acks: [UUID] = []
        coordinator.markDeliveredHandler = { _, messageID in
            acks.append(messageID)
        }

        let session = makeAuthenticatedSession(ownerProfileID: ownerB)
        let service = makeDeltaSyncService(
            store: store,
            syncState: syncState,
            coordinator: coordinator
        )
        service.autoFullRefreshFallback = false

        store.testingCommitAuthoritativeSyncPageFailuresRemaining = 1
        let first = await service.syncConversationRepair(
            conversationID: conversationID,
            session: session,
            router: AppRouter.shared
        )
        #expect(first == false)
        #expect(acks.isEmpty)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB).isEmpty)

        store.testingCommitAuthoritativeSyncPageFailuresRemaining = 0
        let second = await service.syncConversationRepair(
            conversationID: conversationID,
            session: session,
            router: AppRouter.shared
        )
        #expect(second == true)
        #expect(acks == [messageC])
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB).isEmpty)
    }

    // MARK: - Partial page apply failure

    @Test("partial message apply failure blocks cursor, boundary, and ack scheduling")
    func partialApplyFailureBlocksCursorBoundaryAndAck() async throws {
        let store = makeStore()
        let syncState = MessengerSyncStateStore.shared
        syncState.reset()
        syncState.setRevision(100)

        #if DEBUG
        MessengerMessageCacheService.testingStore = store
        MessengerMessageCacheService.testingFailPersistForMessageIDs = [messageB]
        MessengerSyncService.testingFetchSyncEventsHandler = { _, _ in
            self.makeSyncEventsResponse(
                events: [
                    try self.makeMessageCreatedEvent(
                        revision: 101,
                        messageID: self.messageA,
                        createdAtISO: "2026-06-26T13:18:01Z"
                    ),
                    try self.makeMessageCreatedEvent(
                        revision: 102,
                        messageID: self.messageB,
                        createdAtISO: "2026-06-26T13:18:02Z"
                    ),
                    try self.makeMessageCreatedEvent(
                        revision: 103,
                        messageID: self.messageC,
                        createdAtISO: "2026-06-26T13:18:03Z"
                    )
                ],
                nextRevision: 103,
                hasMore: false
            )
        }
        defer {
            MessengerMessageCacheService.testingStore = nil
            MessengerMessageCacheService.testingFailPersistForMessageIDs = []
            MessengerSyncService.testingFetchSyncEventsHandler = nil
        }
        #endif

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store
        var acks: [UUID] = []
        coordinator.markDeliveredHandler = { _, messageID in acks.append(messageID) }

        let session = makeAuthenticatedSession(ownerProfileID: ownerB)
        let service = makeDeltaSyncService(
            store: store,
            syncState: syncState,
            coordinator: coordinator
        )
        service.autoFullRefreshFallback = false

        let succeeded = await service.syncDeltas(
            reason: .bootstrap,
            session: session,
            router: AppRouter.shared
        )
        #expect(succeeded == false)
        #expect(acks.isEmpty)
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == nil)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB).isEmpty)
        #expect(syncState.currentRevision == 100)
    }

    // MARK: - Safe-boundary calculation

    @Test("failed message persistence excludes boundary from apply result and ack")
    func failedPersistenceExcludesMessageFromSafeBoundary() async throws {
        let store = makeStore()
        let syncState = MessengerSyncStateStore.shared
        syncState.reset()

        #if DEBUG
        MessengerMessageCacheService.testingStore = store
        MessengerMessageCacheService.testingFailPersistForMessageIDs = [messageB]
        defer {
            MessengerMessageCacheService.testingStore = nil
            MessengerMessageCacheService.testingFailPersistForMessageIDs = []
        }
        #endif

        let service = makeDeltaSyncService(store: store, syncState: syncState)
        let session = makeAuthenticatedSession(ownerProfileID: ownerB)

        let events = [
            try makeMessageCreatedEvent(
                revision: 201,
                messageID: messageA,
                createdAtISO: "2026-06-26T13:18:01Z"
            ),
            try makeMessageCreatedEvent(
                revision: 202,
                messageID: messageB,
                createdAtISO: "2026-06-26T13:18:02Z"
            )
        ]

        await #expect(throws: MessengerSyncEngineError.applyFailed) {
            try await service.applyEventsForTesting(
                events,
                profileID: ownerB,
                session: session,
                router: AppRouter.shared
            )
        }
    }

    // MARK: - Single-save proof

    @Test("commit failure leaves no durable cursor or boundary; success is visible from reload")
    func commitFailureLeavesNoDurableStateSuccessReloads() async throws {
        let store = makeStore()

        store.testingCommitAuthoritativeSyncPageFailuresRemaining = 1
        await #expect(throws: MessengerLocalStoreError.storeUnavailable) {
            try await store.commitAuthoritativeSyncPage(
                ownerProfileID: ownerB,
                advancedRevision: 55,
                safeBoundaries: [conversationID: boundaryC]
            )
        }
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == nil)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB).isEmpty)

        store.testingCommitAuthoritativeSyncPageFailuresRemaining = 0
        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerB,
            advancedRevision: 55,
            safeBoundaries: [conversationID: boundaryC]
        )

        // SwiftDataMessengerLocalStore uses a fresh ModelContext per call; re-read proves durability.
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == 55)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB)[conversationID] == boundaryC)
    }

    // MARK: - Bootstrap offline

    @Test("offline bootstrap loads pending boundary without request storm; ack follows network restore")
    func offlineBootstrapLoadsPendingAndAcksAfterNetworkRestore() async throws {
        let store = makeStore()
        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerB,
            advancedRevision: nil,
            safeBoundaries: [conversationID: boundaryC]
        )

        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store
        var acks: [UUID] = []
        coordinator.markDeliveredHandler = { _, messageID in acks.append(messageID) }

        let session = makeAuthenticatedSession(ownerProfileID: ownerB)
        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: ownerB,
            session: session,
            router: AppRouter.shared
        )
        #expect(acks.isEmpty)

        NetworkPathMonitor.testingForceOffline = false
        coordinator.retryPendingAcks(reason: "testNetworkRestore")
        try await Task.sleep(for: .milliseconds(50))
        #expect(acks == [boundaryC.messageID])
    }

    // MARK: - Stale commit after account switch

    @Test("stale commit after logout does not apply to new session")
    func staleCommitAfterLogoutDoesNotMutateNewSession() async throws {
        let store = makeStore()
        store.testingSuspendCommitBeforeWrite = true

        var commitTask: Task<[UUID: MessageReceiptBoundary], Error>!
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            store.testingOnCommitSuspended = { ready.resume() }
            commitTask = Task {
                try await store.commitAuthoritativeSyncPage(
                    ownerProfileID: ownerA,
                    advancedRevision: 77,
                    safeBoundaries: [conversationID: boundaryC]
                )
            }
        }

        try await store.resetAllMessengerData()
        store.testingResumeSuspendedCommitForTests()
        do {
            _ = try await commitTask.value
            Issue.record("Expected stale commit to throw")
        } catch MessengerLocalStoreError.staleSession {
            // Expected.
        }

        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == nil)

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store
        var acks = 0
        coordinator.markDeliveredHandler = { _, _ in acks += 1 }
        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: ownerB,
            session: makeAuthenticatedSession(ownerProfileID: ownerB),
            router: AppRouter.shared
        )
        #expect(acks == 0)
    }

    // MARK: - Fixtures

    private let ownerA = UUID(uuidString: "a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1")!
    private let ownerB = UUID(uuidString: "b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2")!
    private let conversationID = UUID(uuidString: "c0c0c0c0-c0c0-4c0c-8c0c-c0c0c0c0c0c0")!
    private let messageA = UUID(uuidString: "d0d0d0d0-0000-4000-8000-00000000000a")!
    private let messageB = UUID(uuidString: "d0d0d0d0-0000-4000-8000-00000000000b")!
    private let messageC = UUID(uuidString: "d0d0d0d0-0000-4000-8000-00000000000c")!

    private var boundaryC: MessageReceiptBoundary {
        MessageReceiptBoundary(
            createdAt: Date(timeIntervalSince1970: 20),
            messageID: messageC
        )
    }

    private func makeStore() -> MessengerLocalStore {
        MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
    }

    private func makeDeltaSyncService(
        store: MessengerLocalStore,
        syncState: MessengerSyncStateStore,
        coordinator: ConversationDeliveryAckCoordinator? = nil
    ) -> MessengerDeltaSyncService {
        #if DEBUG
        MessengerMessageCacheService.testingStore = store
        #endif
        let service = MessengerDeltaSyncService(syncState: syncState)
        #if DEBUG
        if let coordinator {
            service.testingDeliveryAckCoordinator = coordinator
        }
        #endif
        return service
    }

    private func makeAuthenticatedSession(ownerProfileID: UUID) -> SessionStore {
        let session = SessionStore.shared
        if APIAuth.accessToken == nil {
            try? APIAuth.save(token: "test-delivery-ack-token")
        }
        if let profile = try? makeProfile(id: ownerProfileID) {
            session.updateCurrentProfile(profile)
        }
        if let user = try? makeVerifiedUser() {
            session.setCurrentUser(user)
        }
        return session
    }

    private func makeProfile(id: UUID) throws -> UserProfileDTO {
        try JSONCoding.decoder.decode(UserProfileDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "displayName": "Me",
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

    private func makeVerifiedUser() throws -> UserResponse {
        try JSONCoding.decoder.decode(UserResponse.self, from: Data("""
        {
          "id": "\(ownerB.uuidString)",
          "email": "test@example.com",
          "emailVerified": true,
          "createdAt": "2026-01-01T00:00:00Z"
        }
        """.utf8))
    }

    private func makeMessageCreatedEvent(
        revision: Int64,
        messageID: UUID,
        createdAtISO: String
    ) throws -> MessengerSyncEventDTO {
        let senderID = ownerA
        let json = """
        {
          "revision": \(revision),
          "type": "message.created",
          "conversationID": "\(conversationID.uuidString)",
          "messageID": "\(messageID.uuidString)",
          "actorProfileID": "\(senderID.uuidString)",
          "occurredAt": "\(createdAtISO)",
          "conversation": null,
          "message": {
            "id": "\(messageID.uuidString)",
            "conversationID": "\(conversationID.uuidString)",
            "senderProfileID": "\(senderID.uuidString)",
            "kind": "text",
            "body": "hello",
            "attachments": [],
            "replyTo": null,
            "reactions": [],
            "deliveryStatus": "sent",
            "clientMessageID": null,
            "createdAt": "\(createdAtISO)",
            "editedAt": null,
            "deletedAt": null
          },
          "receipt": null
        }
        """.data(using: .utf8)!
        return try JSONDecoder.justTwoAPI.decode(MessengerSyncEventDTO.self, from: json)
    }

    private func makeSyncEventsResponse(
        events: [MessengerSyncEventDTO],
        nextRevision: Int64,
        hasMore: Bool
    ) -> MessengerSyncEventsResponse {
        MessengerSyncEventsResponse(
            events: events,
            nextRevision: nextRevision,
            hasMore: hasMore
        )
    }
}
