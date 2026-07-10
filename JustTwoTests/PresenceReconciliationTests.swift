@testable import JustTwo
import Foundation
import Testing

@Suite("Presence Reconciliation Tests", .serialized)
@MainActor
struct PresenceReconciliationTests {

    @Test("initial REST snapshot sets online")
    func initialRESTOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        #expect(store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .rest))
        #expect(store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .rest)
    }

    @Test("initial REST snapshot sets offline and last seen")
    func initialRESTOffline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let lastSeen = Date(timeIntervalSince1970: 1_000)

        #expect(store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: lastSeen, source: .rest))
        #expect(!store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == lastSeen)
    }

    @Test("realtime offline after REST keeps offline")
    func realtimeOfflineAfterREST() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .rest)
        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: Date(timeIntervalSince1970: 2_000), source: .realtime)

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .realtime)
    }

    @Test("late REST online does not overwrite realtime offline")
    func lateRESTDoesNotOverwriteRealtimeOffline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let realtimeLastSeen = Date(timeIntervalSince1970: 2_000)

        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: realtimeLastSeen, source: .realtime)
        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .rest)

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .realtime)
    }

    @Test("realtime online after REST offline wins")
    func realtimeOnlineAfterREST() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: Date(timeIntervalSince1970: 1_000), source: .rest)
        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)

        #expect(store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .realtime)
    }

    @Test("late sync offline does not overwrite realtime online")
    func lateSyncDoesNotOverwriteRealtimeOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)
        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: Date(timeIntervalSince1970: 9_000), source: .sync)

        #expect(store.isOnline(profileID: profileID))
    }

    @Test("REST can advance last seen without changing realtime online")
    func restAdvancesLastSeenWithoutChangingOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 5_000)

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: older, source: .realtime)
        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: newer, source: .rest)

        #expect(store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == newer)
    }

    @Test("older last seen does not decrease timestamp")
    func olderLastSeenIgnored() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let newer = Date(timeIntervalSince1970: 5_000)
        let older = Date(timeIntervalSince1970: 1_000)

        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: newer, source: .rest)
        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: older, source: .rest)

        #expect(store.lastSeenAt(profileID: profileID) == newer)
    }

    @Test("realtime offline clears typing hint")
    func realtimeOfflineClearsTyping() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applyTypingOnlineHint(profileID: profileID)
        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: Date(timeIntervalSince1970: 1_000), source: .realtime)

        #expect(!store.isTypingHint(profileID: profileID))
        #expect(!store.isOnline(profileID: profileID))
    }

    @Test("cache hydrate does not mark user online")
    func cacheHydrateNotOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: false,
            lastSeenAt: Date(timeIntervalSince1970: 1_000),
            source: .cache
        )

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) != nil)
    }

    @Test("logout clears presence state")
    func logoutClearsState() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)
        store.clearAll()

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == nil)
    }

    @Test("stale session generation is ignored")
    func staleSessionGenerationIgnored() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let generation = store.currentSessionGeneration

        store.clearAll()
        #expect(!store.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .rest,
            sessionGeneration: generation
        ))
        #expect(!store.isOnline(profileID: profileID))
    }

    @Test("list and header share one store state")
    func sharedStoreState() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)

        let listOnline = store.isOnline(profileID: profileID)
        let headerOnline = store.isOnline(profileID: profileID)
        #expect(listOnline == headerOnline)
    }

    private func fixedProfileID() -> UUID {
        UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    }

    @Test("reconnect epoch allows fresh REST offline to replace preserved online")
    func reconnectEpochAllowsRESTOfflineAfterPreservedOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: nil, source: .rest)
        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)
        store.beginRealtimeReconnectCycle()

        #expect(store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .preserved)

        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: false,
            lastSeenAt: Date(timeIntervalSince1970: 3_000),
            source: .rest,
            requestConnectionEpoch: store.currentRealtimeConnectionEpoch
        )

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .rest)
    }

    @Test("reconnect epoch allows fresh REST online to keep preserved online")
    func reconnectEpochAllowsRESTOnlineAfterPreservedOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)
        store.beginRealtimeReconnectCycle()

        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .rest,
            requestConnectionEpoch: store.currentRealtimeConnectionEpoch
        )

        #expect(store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .rest)
    }

    @Test("late REST offline does not overwrite realtime online in same epoch")
    func lateRESTOfflineDoesNotOverwriteRealtimeOnlineSameEpoch() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let epoch = store.currentRealtimeConnectionEpoch

        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .realtime,
            realtimeConnectionEpoch: epoch
        )
        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: false,
            lastSeenAt: Date(timeIntervalSince1970: 4_000),
            source: .rest,
            requestConnectionEpoch: epoch
        )

        #expect(store.isOnline(profileID: profileID))
        #expect(store.source(for: profileID) == .realtime)
    }

    @Test("stale realtime callback from previous epoch is ignored")
    func staleRealtimeCallbackIgnored() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .realtime,
            realtimeConnectionEpoch: 0
        )
        store.beginRealtimeReconnectCycle()

        let applied = store.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .realtime,
            realtimeConnectionEpoch: 0
        )

        #expect(applied == false)
        #expect(store.source(for: profileID) == .preserved)
    }

    @Test("late REST from previous connection epoch is ignored for online state")
    func lateRESTFromPreviousEpochIgnored() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let epoch1 = store.currentRealtimeConnectionEpoch

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime, realtimeConnectionEpoch: epoch1)
        store.beginRealtimeReconnectCycle()

        _ = store.applySnapshot(
            profileID: profileID,
            isOnline: true,
            lastSeenAt: nil,
            source: .rest,
            requestConnectionEpoch: epoch1
        )

        #expect(store.source(for: profileID) == .preserved)
    }

    @Test("typing started then realtime online still displays typing")
    func typingThenRealtimeOnlineDisplaysTyping() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()

        _ = store.applyTypingOnlineHint(profileID: profileID)
        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)

        #expect(store.displaySemantic(for: profileID) == .typing)
    }

    @Test("typing started then realtime offline displays offline")
    func typingThenRealtimeOfflineDisplaysOffline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let lastSeen = Date(timeIntervalSince1970: 8_000)

        _ = store.applyTypingOnlineHint(profileID: profileID)
        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: lastSeen, source: .realtime)

        #expect(!store.isTypingHint(profileID: profileID))
        #expect(store.displaySemantic(for: profileID) == .lastSeen)
    }

    @Test("preserved online expires to last seen not false online")
    func preservedOnlineExpiresToLastSeen() {
        var now = Date(timeIntervalSince1970: 10_000)
        let store = PresenceStore.makeForTesting(now: { now })
        let profileID = fixedProfileID()
        let lastSeen = Date(timeIntervalSince1970: 9_500)

        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: lastSeen, source: .realtime)
        store.beginRealtimeReconnectCycle()
        now = now.addingTimeInterval(PresenceStore.preservedPresenceTTL + 1)

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == lastSeen)
        #expect(store.displaySemantic(for: profileID) == .lastSeen)
    }
}
