@testable import JustTwo
import Foundation
import Testing

@Suite("Presence PR8B Tests", .serialized)
struct PresenceTests {

    @Test("presence.changed online decodes")
    func presenceChangedOnlineDecodes() throws {
        guard case .presenceChanged(let payload) = try decodeEvent(presenceChangedJSON(
            status: "online",
            lastSeenAt: "null"
        )) else {
            Issue.record("Expected presence.changed")
            return
        }

        #expect(payload.profileID.uuidString == "44444444-4444-4444-8444-444444444444".uppercased())
        #expect(payload.status == .online)
        #expect(payload.lastSeenAt == nil)
    }

    @Test("presence.changed offline decodes")
    func presenceChangedOfflineDecodes() throws {
        guard case .presenceChanged(let payload) = try decodeEvent(presenceChangedJSON(
            status: "offline",
            lastSeenAt: #""2026-06-26T13:24:05Z""#
        )) else {
            Issue.record("Expected presence.changed")
            return
        }

        #expect(payload.status == .offline)
        #expect(payload.lastSeenAt != nil)
    }

    @Test("unknown presence status does not crash")
    func unknownPresenceStatusDoesNotCrash() throws {
        guard case .presenceChanged(let payload) = try decodeEvent(presenceChangedJSON(
            status: "away",
            lastSeenAt: "null"
        )) else {
            Issue.record("Expected presence.changed")
            return
        }

        #expect(payload.status == .unknown)
    }

    @MainActor
    @Test("presence store applies online")
    func presenceStoreAppliesOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedOtherProfileID()

        store.apply(profileID: profileID, status: .online, lastSeenAt: nil)

        #expect(store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == nil)
    }

    @MainActor
    @Test("presence store applies offline")
    func presenceStoreAppliesOffline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedOtherProfileID()
        let lastSeen = Date(timeIntervalSince1970: 1_000)

        store.apply(profileID: profileID, status: .offline, lastSeenAt: lastSeen)

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.lastSeenAt(profileID: profileID) == lastSeen)
    }

    @MainActor
    @Test("presence store clears on session clear")
    func presenceStoreClearsOnSessionClear() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedOtherProfileID()

        store.apply(profileID: profileID, status: .online, lastSeenAt: nil)
        store.clearAll()

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.statuses.isEmpty)
    }

    @MainActor
    @Test("presence store ignores unknown status updates")
    func presenceStoreIgnoresUnknownStatus() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedOtherProfileID()

        store.apply(profileID: profileID, status: .unknown, lastSeenAt: nil)

        #expect(!store.isOnline(profileID: profileID))
        #expect(store.statuses[profileID] == nil)
    }

    @MainActor
    @Test("conversation row online state reflects presence store")
    func conversationRowOnlineState() {
        let store = PresenceStore.makeForTesting()
        let otherProfileID = fixedOtherProfileID()
        let conversation = makeConversation(otherParticipantProfileID: otherProfileID)

        #expect(!store.isOnline(profileID: conversation.otherParticipantProfileID))

        store.apply(profileID: otherProfileID, status: .online, lastSeenAt: nil)

        #expect(store.isOnline(profileID: conversation.otherParticipantProfileID))
    }

    @MainActor
    @Test("coordinator ignores current user presence")
    func coordinatorIgnoresSelfPresence() async throws {
        let presenceStore = PresenceStore.makeForTesting()
        let eventRouter = RealtimeEventRouter.makeForTesting()
        let coordinator = MessengerRealtimeCoordinator(
            realtimeClient: makeTestRealtimeClient(),
            eventRouter: eventRouter,
            presenceStore: presenceStore
        )

        let currentProfileID = fixedCurrentProfileID()
        let session = SessionStore.shared
        let previousProfile = session.currentProfile
        defer {
            session.updateCurrentProfile(previousProfile)
            coordinator.stop()
        }

        session.updateCurrentProfile(try makeProfile(id: currentProfileID))

        coordinator.activateConversationList(
            ConversationListViewModel.preview(conversations: []),
            session: session,
            router: AppRouter.shared
        )

        try await Task.sleep(for: .milliseconds(50))

        eventRouter.route(.presenceChanged(payload: PresenceChangedPayload(
            profileID: currentProfileID,
            status: .online,
            lastSeenAt: nil
        )))

        try await Task.sleep(for: .milliseconds(100))

        #expect(!presenceStore.isOnline(profileID: currentProfileID))
    }

    @MainActor
    @Test("coordinator applies other participant presence")
    func coordinatorAppliesOtherPresence() async throws {
        let presenceStore = PresenceStore.makeForTesting()
        let eventRouter = RealtimeEventRouter.makeForTesting()
        let coordinator = MessengerRealtimeCoordinator(
            realtimeClient: makeTestRealtimeClient(),
            eventRouter: eventRouter,
            presenceStore: presenceStore
        )

        let currentProfileID = fixedCurrentProfileID()
        let otherProfileID = fixedOtherProfileID()
        let session = SessionStore.shared
        let previousProfile = session.currentProfile
        defer {
            session.updateCurrentProfile(previousProfile)
            coordinator.stop()
        }

        session.updateCurrentProfile(try makeProfile(id: currentProfileID))

        coordinator.activateConversationList(
            ConversationListViewModel.preview(conversations: []),
            session: session,
            router: AppRouter.shared
        )

        try await Task.sleep(for: .milliseconds(50))

        await Task.yield()

        eventRouter.route(.presenceChanged(payload: PresenceChangedPayload(
            profileID: otherProfileID,
            status: .online,
            lastSeenAt: nil
        )))

        let applied = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            presenceStore.isOnline(profileID: otherProfileID)
        }

        #expect(applied)
    }

    @MainActor
    @Test("logout style disconnect clears shared presence store")
    func logoutDisconnectClearsPresence() {
        let profileID = fixedOtherProfileID()
        PresenceStore.shared.apply(profileID: profileID, status: .online, lastSeenAt: nil)

        let client = makeTestRealtimeClient()
        client.simulateActiveConnectionForTesting()
        client.disconnect()

        #expect(!PresenceStore.shared.isOnline(profileID: profileID))
    }

    @MainActor
    @Test("coordinator stop clears injected presence store")
    func coordinatorStopClearsPresence() async throws {
        let presenceStore = PresenceStore.makeForTesting()
        let eventRouter = RealtimeEventRouter.makeForTesting()
        let coordinator = MessengerRealtimeCoordinator(
            realtimeClient: makeTestRealtimeClient(),
            eventRouter: eventRouter,
            presenceStore: presenceStore
        )

        let otherProfileID = fixedOtherProfileID()
        presenceStore.apply(profileID: otherProfileID, status: .online, lastSeenAt: nil)

        coordinator.stop()

        #expect(!presenceStore.isOnline(profileID: otherProfileID))
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await MainActor.run(body: condition) {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        return await MainActor.run(body: condition)
    }

    private func decodeEvent(_ json: String) throws -> RealtimeEvent {
        try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(json.utf8)).event
    }

    private func presenceChangedJSON(status: String, lastSeenAt: String) -> String {
        """
        {
          "type": "presence.changed",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {
            "profileID": "44444444-4444-4444-8444-444444444444",
            "status": "\(status)",
            "lastSeenAt": \(lastSeenAt)
          }
        }
        """
    }

    private func makeConversation(otherParticipantProfileID: UUID?) -> ChatConversationPreview {
        ChatConversationPreview(
            id: fixedConversationID(),
            title: "Taylor",
            otherParticipantProfileID: otherParticipantProfileID,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: nil,
            lastSenderName: nil,
            lastMessageAt: nil,
            unreadCount: 0
        )
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

    @MainActor
    private func makeTestRealtimeClient() -> RealtimeClient {
        RealtimeClient(
            router: .shared,
            reconnectPolicy: RealtimeReconnectPolicy(
                initialDelay: 60,
                multiplier: 2,
                maxDelay: 60
            ),
            tokenProvider: { "test-token" }
        )
    }

    private func fixedConversationID() -> UUID {
        UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    }

    private func fixedCurrentProfileID() -> UUID {
        UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    }

    private func fixedOtherProfileID() -> UUID {
        UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    }
}
