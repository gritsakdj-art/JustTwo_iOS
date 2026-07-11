@testable import JustTwo
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct DeliveryAckPersistenceTests {

    // MARK: - Store-level atomicity & monotonic merge

    @Test("commit persists cursor and proven-safe boundary together")
    func commitPersistsCursorAndBoundaryAtomically() async throws {
        let store = makeStore()

        let committed = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 5,
            safeBoundaries: [conversationID: boundaryC]
        )

        #expect(committed[conversationID] == boundaryC)
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == 5)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA)[conversationID] == boundaryC)
    }

    @Test("commit monotonically keeps the highest boundary and highest cursor")
    func commitMonotonicMergeKeepsHighest() async throws {
        let store = makeStore()

        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 5,
            safeBoundaries: [conversationID: boundaryC]
        )

        let lower = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 4,
            safeBoundaries: [conversationID: boundaryB]
        )
        #expect(lower[conversationID] == boundaryC)
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == 5)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA)[conversationID] == boundaryC)

        let higher = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 7,
            safeBoundaries: [conversationID: boundaryD]
        )
        #expect(higher[conversationID] == boundaryD)
        #expect(try await store.fetchSyncMetadata()?.lastAppliedRevision == 7)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA)[conversationID] == boundaryD)
    }

    @Test("clearing through a lower boundary retains a strictly higher persisted boundary")
    func higherBoundaryRetainedWhenClearingLower() async throws {
        let store = makeStore()

        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: nil,
            safeBoundaries: [conversationID: boundaryD]
        )

        try await store.clearPendingDeliveryBoundary(
            ownerProfileID: ownerA,
            conversationID: conversationID,
            through: boundaryC
        )
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA)[conversationID] == boundaryD)

        try await store.clearPendingDeliveryBoundary(
            ownerProfileID: ownerA,
            conversationID: conversationID,
            through: boundaryD
        )
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
    }

    @Test("pending boundaries are isolated per owner and wiped on reset")
    func boundariesAreOwnerScopedAndResetClearsThem() async throws {
        let store = makeStore()

        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 3,
            safeBoundaries: [conversationID: boundaryC]
        )
        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerB,
            advancedRevision: nil,
            safeBoundaries: [otherConversationID: boundaryD]
        )

        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA)[conversationID] == boundaryC)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB)[otherConversationID] == boundaryD)

        try await store.clearPendingDeliveryBoundaries(ownerProfileID: ownerA)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB)[otherConversationID] == boundaryD)

        try await store.resetAllMessengerData()
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerB).isEmpty)
    }

    // MARK: - Test 1: network failure survives process recreation

    @Test("network failure keeps durable boundary that a recreated coordinator replays")
    func networkFailureSurvivesCoordinatorRecreation() async throws {
        let store = makeStore()
        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 12,
            safeBoundaries: [conversationID: boundaryC]
        )

        let coordinator1 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator1.boundaryStore = store
        var failCalls = 0
        coordinator1.markDeliveredHandler = { _, _ in
            failCalls += 1
            throw FakeStoreError.network
        }
        await coordinator1.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: boundaryC,
            currentProfileID: ownerA,
            session: session,
            router: router,
            source: "deltaSync",
            evidence: .authoritativeSync(fromRevision: 11, throughRevision: 12)
        )
        #expect(failCalls >= 1)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA)[conversationID] == boundaryC)
        coordinator1.reset()

        let coordinator2 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator2.boundaryStore = store
        var okCalls: [(UUID, UUID)] = []
        coordinator2.markDeliveredHandler = { conversationID, messageID in
            okCalls.append((conversationID, messageID))
        }
        await coordinator2.bootstrapPersistedBoundaries(
            ownerProfileID: ownerA,
            session: session,
            router: router
        )

        #expect(okCalls.count == 1)
        #expect(okCalls.first?.1 == boundaryC.messageID)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
    }

    // MARK: - Test 2: no unnecessary retry after successful cleanup

    @Test("recreated coordinator issues zero acks after successful cleanup")
    func noRetryAfterSuccessfulCleanup() async throws {
        let store = makeStore()
        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 12,
            safeBoundaries: [conversationID: boundaryC]
        )

        let coordinator1 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator1.boundaryStore = store
        coordinator1.markDeliveredHandler = { _, _ in }
        await coordinator1.bootstrapPersistedBoundaries(
            ownerProfileID: ownerA,
            session: session,
            router: router
        )
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
        coordinator1.reset()

        let coordinator2 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator2.boundaryStore = store
        var acks = 0
        coordinator2.markDeliveredHandler = { _, _ in acks += 1 }
        await coordinator2.bootstrapPersistedBoundaries(
            ownerProfileID: ownerA,
            session: session,
            router: router
        )

        #expect(acks == 0)
    }

    // MARK: - Test 3: higher boundary survives a lower success

    @Test("higher persisted boundary survives lower ack success and is acked next")
    func higherBoundarySurvivesLowerSuccess() async throws {
        let store = makeStore()
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store

        var delivered: [MessageReceiptBoundary] = []
        // While ACK C is in flight, persist and schedule D so it becomes pending.
        coordinator.markDeliveredHandler = { conversationID, messageID in
            if messageID == self.boundaryC.messageID {
                _ = try? await store.commitAuthoritativeSyncPage(
                    ownerProfileID: self.ownerA,
                    advancedRevision: nil,
                    safeBoundaries: [conversationID: self.boundaryD]
                )
                await coordinator.scheduleAuthoritativeBoundary(
                    conversationID: conversationID,
                    boundary: self.boundaryD,
                    currentProfileID: self.ownerA,
                    session: self.session,
                    router: self.router,
                    source: "deltaSync",
                    evidence: .authoritativeSync(fromRevision: 13, throughRevision: 14)
                )
            }
            delivered.append(MessageReceiptBoundary(
                createdAt: messageID == self.boundaryC.messageID ? self.boundaryC.createdAt : self.boundaryD.createdAt,
                messageID: messageID
            ))
        }

        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 12,
            safeBoundaries: [conversationID: boundaryC]
        )
        await coordinator.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: boundaryC,
            currentProfileID: ownerA,
            session: session,
            router: router,
            source: "deltaSync",
            evidence: .authoritativeSync(fromRevision: 11, throughRevision: 12)
        )

        #expect(delivered.map(\.messageID) == [boundaryC.messageID, boundaryD.messageID])
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
    }

    // MARK: - Test 4: stale lower failure does not resurrect after higher success

    @Test("a lower boundary is not re-acked after a higher boundary is confirmed")
    func lowerBoundaryNotResurrectedAfterHigherConfirmed() async throws {
        let store = makeStore()
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store

        var acks: [UUID] = []
        coordinator.markDeliveredHandler = { _, messageID in acks.append(messageID) }

        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 20,
            safeBoundaries: [conversationID: boundaryC]
        )
        await coordinator.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: boundaryC,
            currentProfileID: ownerA,
            session: session,
            router: router,
            source: "deltaSync",
            evidence: .authoritativeSync(fromRevision: 19, throughRevision: 20)
        )
        #expect(acks == [boundaryC.messageID])

        // A stale, lower boundary arriving late must be suppressed (covered by confirmed C).
        await coordinator.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: boundaryB,
            currentProfileID: ownerA,
            session: session,
            router: router,
            source: "staleRetry",
            evidence: .authoritativeSync(fromRevision: 5, throughRevision: 6)
        )

        #expect(acks == [boundaryC.messageID])
    }

    // MARK: - Account isolation

    @Test("account switch does not replay the previous owner's pending ack")
    func accountSwitchDoesNotReplayPreviousOwner() async throws {
        let store = makeStore()
        _ = try await store.commitAuthoritativeSyncPage(
            ownerProfileID: ownerA,
            advancedRevision: 12,
            safeBoundaries: [conversationID: boundaryC]
        )

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = store

        // Logout: coordinator generation bump + durable cache reset.
        coordinator.reset()
        try await store.resetAllMessengerData()

        var acks = 0
        coordinator.markDeliveredHandler = { _, _ in acks += 1 }
        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: ownerB,
            session: session,
            router: router
        )

        #expect(acks == 0)
        #expect(try await store.loadPendingDeliveryBoundaries(ownerProfileID: ownerA).isEmpty)
    }

    @Test("stale bootstrap result is ignored after logout resets the generation")
    func staleBootstrapIgnoredAfterReset() async throws {
        let fake = FakeBoundaryStore()
        fake.byOwner[ownerA] = [conversationID: boundaryC]

        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator.boundaryStore = fake
        var acks = 0
        coordinator.markDeliveredHandler = { _, _ in acks += 1 }

        var didReset = false
        fake.onLoad = {
            if !didReset {
                didReset = true
                coordinator.reset()
            }
        }

        await coordinator.bootstrapPersistedBoundaries(
            ownerProfileID: ownerA,
            session: session,
            router: router
        )

        #expect(acks == 0)
    }

    // MARK: - Test cleanup failure (deliberate duplicate retry allowance)

    @Test("cleanup failure keeps confirmed state and allows a safe duplicate ack after restart")
    func cleanupFailureKeepsConfirmedAndAllowsDuplicateAfterRestart() async throws {
        let fake = FakeBoundaryStore()
        fake.byOwner[ownerA] = [conversationID: boundaryC]
        fake.failClear = true

        let coordinator1 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator1.boundaryStore = fake
        var acks1: [UUID] = []
        coordinator1.markDeliveredHandler = { _, messageID in acks1.append(messageID) }

        await coordinator1.bootstrapPersistedBoundaries(
            ownerProfileID: ownerA,
            session: session,
            router: router
        )
        #expect(acks1 == [boundaryC.messageID])
        #expect(fake.clearThroughCalls == 1)
        // Cleanup failed, so the record survives.
        #expect(fake.byOwner[ownerA]?[conversationID] == boundaryC)

        // Same session: confirmed C suppresses an immediate duplicate.
        await coordinator1.scheduleAuthoritativeBoundary(
            conversationID: conversationID,
            boundary: boundaryC,
            currentProfileID: ownerA,
            session: session,
            router: router,
            source: "retry",
            evidence: .persistedSafeBoundary
        )
        #expect(acks1 == [boundaryC.messageID])
        coordinator1.reset()

        // Restart: a fresh coordinator replays the surviving record; backend no-op is safe.
        fake.failClear = false
        let coordinator2 = ConversationDeliveryAckCoordinator.makeForTesting()
        coordinator2.boundaryStore = fake
        var acks2: [UUID] = []
        coordinator2.markDeliveredHandler = { _, messageID in acks2.append(messageID) }
        await coordinator2.bootstrapPersistedBoundaries(
            ownerProfileID: ownerA,
            session: session,
            router: router
        )
        #expect(acks2 == [boundaryC.messageID])
        #expect(fake.byOwner[ownerA]?[conversationID] == nil)
    }

    // MARK: - Fixtures

    private func makeStore() -> MessengerLocalStore {
        MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
    }

    private var session: SessionStore { SessionStore.shared }
    private var router: AppRouter { AppRouter.shared }

    private let ownerA = UUID(uuidString: "a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1")!
    private let ownerB = UUID(uuidString: "b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2")!
    private let conversationID = UUID(uuidString: "c0c0c0c0-c0c0-4c0c-8c0c-c0c0c0c0c0c0")!
    private let otherConversationID = UUID(uuidString: "c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2")!

    private var boundaryB: MessageReceiptBoundary {
        MessageReceiptBoundary(
            createdAt: Date(timeIntervalSince1970: 10),
            messageID: UUID(uuidString: "d0d0d0d0-0000-4000-8000-00000000000b")!
        )
    }
    private var boundaryC: MessageReceiptBoundary {
        MessageReceiptBoundary(
            createdAt: Date(timeIntervalSince1970: 20),
            messageID: UUID(uuidString: "d0d0d0d0-0000-4000-8000-00000000000c")!
        )
    }
    private var boundaryD: MessageReceiptBoundary {
        MessageReceiptBoundary(
            createdAt: Date(timeIntervalSince1970: 30),
            messageID: UUID(uuidString: "d0d0d0d0-0000-4000-8000-00000000000d")!
        )
    }
}

private enum FakeStoreError: Error {
    case network
    case clearFailed
}

@MainActor
private final class FakeBoundaryStore: ConversationDeliveryAckBoundaryStore {
    var byOwner: [UUID: [UUID: MessageReceiptBoundary]] = [:]
    var failClear = false
    var onLoad: (() -> Void)?
    private(set) var clearThroughCalls = 0

    func loadPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws -> [UUID: MessageReceiptBoundary] {
        onLoad?()
        return byOwner[ownerProfileID] ?? [:]
    }

    func clearPendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        through boundary: MessageReceiptBoundary
    ) async throws {
        clearThroughCalls += 1
        if failClear {
            throw FakeStoreError.clearFailed
        }
        if let existing = byOwner[ownerProfileID]?[conversationID], existing > boundary {
            return
        }
        byOwner[ownerProfileID]?[conversationID] = nil
    }

    func clearPendingDeliveryBoundaries(ownerProfileID: UUID) async throws {
        byOwner[ownerProfileID] = nil
    }
}
