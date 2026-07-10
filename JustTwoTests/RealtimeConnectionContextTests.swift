@testable import JustTwo
import Foundation
import Testing

@Suite("Realtime Connection Context Tests", .serialized)
@MainActor
struct RealtimeConnectionContextTests {

    @Test("stale socket presence event does not override newer REST offline")
    func staleSocketPresenceDoesNotOverrideRESTOffline() {
        let presenceStore = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        RealtimeTransportGuard.resetForTesting()

        let socketA = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)
        #expect(socketA.connectionEpoch == 1)

        _ = presenceStore.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .realtime,
            sessionGeneration: socketA.sessionGeneration,
            realtimeConnectionEpoch: socketA.connectionEpoch
        )

        let socketB = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)
        #expect(socketB.connectionEpoch == 2)

        _ = presenceStore.applySnapshot(
            profileID: profileID,
            isOnline: false,
            lastSeenAt: Date(timeIntervalSince1970: 3_000),
            source: .rest,
            requestConnectionEpoch: socketB.connectionEpoch
        )
        #expect(!presenceStore.isOnline(profileID: profileID))

        let queuedOnline = PresenceChangedPayload(profileID: profileID, isOnline: true, lastSeenAt: nil)
        #expect(!RealtimeTransportGuard.accepts(socketA, presenceStore: presenceStore))
        let applied = presenceStore.apply(
            queuedOnline,
            connectionEpoch: socketA.connectionEpoch,
            sessionGeneration: socketA.sessionGeneration
        )

        #expect(applied == false)
        #expect(!presenceStore.isOnline(profileID: profileID))
        #expect(presenceStore.source(for: profileID) == .rest)
    }

    @Test("current socket event is accepted")
    func currentSocketEventAccepted() {
        let presenceStore = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        RealtimeTransportGuard.resetForTesting()

        let context = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)
        let payload = PresenceChangedPayload(profileID: profileID, isOnline: true, lastSeenAt: nil)

        #expect(RealtimeTransportGuard.accepts(context, presenceStore: presenceStore))
        #expect(presenceStore.apply(payload, connectionEpoch: context.connectionEpoch, sessionGeneration: context.sessionGeneration))
        #expect(presenceStore.isOnline(profileID: profileID))
    }

    @Test("logout session generation rejects old socket event")
    func logoutSessionGenerationRejectsOldSocketEvent() {
        let presenceStore = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        RealtimeTransportGuard.resetForTesting()

        let context = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)
        presenceStore.clearAll()

        let payload = PresenceChangedPayload(profileID: profileID, isOnline: true, lastSeenAt: nil)
        #expect(!RealtimeTransportGuard.accepts(context, presenceStore: presenceStore))
        #expect(!presenceStore.apply(payload, connectionEpoch: context.connectionEpoch, sessionGeneration: context.sessionGeneration))
        #expect(!presenceStore.isOnline(profileID: profileID))
    }

    @Test("stale socket typing started is ignored at transport guard")
    func staleSocketTypingIgnored() {
        let presenceStore = PresenceStore.makeForTesting()
        RealtimeTransportGuard.resetForTesting()

        let socketA = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)
        _ = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)

        let typingEvent = RealtimeEvent.typingStarted(
            conversationID: fixedConversationID(),
            profileID: fixedProfileID()
        )
        #expect(!RealtimeTransportGuard.accepts(socketA, presenceStore: presenceStore))
        RealtimeTransportGuard.logIgnoredEvent(typingEvent, context: socketA, presenceStore: presenceStore)
    }

    @Test("stale transport context is not accepted after reconnect")
    func staleTransportContextNotAcceptedAfterReconnect() {
        let presenceStore = PresenceStore.makeForTesting()
        RealtimeTransportGuard.resetForTesting()

        let socketA = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)
        _ = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)

        #expect(!RealtimeTransportGuard.accepts(socketA, presenceStore: presenceStore))
        #expect(RealtimeTransportGuard.staleReason(for: socketA, presenceStore: presenceStore) == "staleConnectionEpoch")
    }

    private func fixedProfileID() -> UUID {
        UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    }

    private func fixedConversationID() -> UUID {
        UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    }
}
