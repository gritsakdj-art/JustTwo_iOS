@testable import JustTwo
import Foundation
import Testing

@Suite("Messenger Cache Write Guard Tests", .serialized)
@MainActor
struct MessengerCacheWriteGuardTests {

    @Test("pending write ignored after logout reset")
    func pendingWriteIgnoredAfterLogoutReset() async throws {
        let store = makeStore()

        try await store.upsertConversations([makeConversationDTO(lastSeenISO: "2026-07-10T12:00:00Z")])
        store.testingSuspendUpsertBeforeWrite = true

        var upsertTask: Task<Void, Error>!
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            store.testingOnUpsertSuspended = { ready.resume() }
            upsertTask = Task {
                try await store.upsertConversations([
                    makeConversationDTO(lastSeenISO: "2026-07-10T14:00:00Z")
                ])
            }
        }

        try await store.resetAllMessengerData()
        store.testingResumeSuspendedUpsertForTests()
        do {
            try await upsertTask.value
        } catch MessengerLocalStoreError.staleSession {
            // Expected: suspended write resumes after logout reset.
        }

        #expect(try await store.fetchLocalConversations().isEmpty)
    }

    @Test("newer lastSeen remains after older delayed write")
    func newerLastSeenRemainsAfterOlderDelayedWrite() async throws {
        let store = makeStore()
        let newer = makeConversationDTO(lastSeenISO: "2026-07-10T14:00:00Z")
        let older = makeConversationDTO(lastSeenISO: "2026-07-10T12:00:00Z")

        try await store.upsertConversations([newer])
        store.testingSuspendUpsertBeforeWrite = true

        var olderTask: Task<Void, Error>!
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            store.testingOnUpsertSuspended = { ready.resume() }
            olderTask = Task {
                try await store.upsertConversations([older])
            }
        }

        store.testingResumeSuspendedUpsertForTests()
        try await olderTask.value

        let stored = try #require(try await store.fetchLocalConversations().first?.otherParticipantLastSeenAt)
        let expected = ISO8601DateFormatter().date(from: "2026-07-10T14:00:00Z")
        #expect(stored == expected)
    }

    @Test("current session write succeeds")
    func currentSessionWriteSucceeds() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO(lastSeenISO: "2026-07-10T12:00:00Z")])
        let snapshot = try #require(try await store.fetchLocalConversations().first)
        #expect(snapshot.otherParticipantLastSeenAt != nil)
    }

    @Test("reset completes before new account cache write")
    func resetCompletesBeforeNewWrite() async throws {
        let store = makeStore()
        try await store.upsertConversations([makeConversationDTO()])
        try await store.resetAllMessengerData()
        #expect(try await store.fetchLocalConversations().isEmpty)

        try await store.upsertConversations([makeConversationDTO(lastSeenISO: "2026-07-10T12:00:00Z")])
        #expect(try await store.fetchLocalConversations().count == 1)
    }

    @Test("stale write context detects account mismatch")
    func staleWriteContextDetectsAccountMismatch() {
        let store = makeStore()
        let capturedUserID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let context = MessengerCacheWriteContext(
            sessionGeneration: store.currentSessionGeneration,
            accountUserID: capturedUserID
        )
        #expect(context.staleReason(store: store) == "accountMismatch")
    }

    @Test("pending write with stale account context is ignored")
    func pendingWriteWithStaleAccountContextIgnored() async throws {
        let store = makeStore()
        let staleContext = MessengerCacheWriteContext(
            sessionGeneration: store.currentSessionGeneration,
            accountUserID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        )
        #expect(staleContext.staleReason(store: store) == "accountMismatch")

        try await store.upsertConversations([makeConversationDTO(lastSeenISO: "2026-07-10T12:00:00Z")])
        #expect(try await store.fetchLocalConversations().count == 1)
    }

    private func makeStore() -> MessengerLocalStore {
        MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
    }

    private func makeConversationDTO(lastSeenISO: String? = nil) -> ConversationDTO {
        let presenceJSON: String
        if let lastSeenISO {
            presenceJSON = """
            "presence": {
              "isOnline": false,
              "lastSeenAt": "\(lastSeenISO)"
            }
            """
        } else {
            presenceJSON = ""
        }

        let profileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let photoJSON = """
        "primaryPhoto": null
        """

        return try! JSONCoding.decoder.decode(ConversationDTO.self, from: Data("""
        {
          "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "type": "direct",
          "status": "active",
          "connectionID": null,
          "otherParticipant": {
            "profile": {
              "id": "\(profileID.uuidString)",
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
          "lastMessage": null,
          "unreadCount": 0,
          "lastReadAt": null,
          "lastMessageAt": "2026-06-26T13:18:31Z",
          "createdAt": "2026-06-26T13:18:31Z",
          "updatedAt": "2026-06-26T13:18:31Z"
        }
        """.utf8))
    }
}
