@testable import JustTwo
import Foundation
import Testing

@Suite("Realtime Client Foundation Tests")
struct RealtimeTests {

    @Test("client messages encode backend field names")
    func clientMessagesEncodeBackendFieldNames() throws {
        let conversationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let ping = try jsonObject(for: RealtimeClientMessageDTO.ping())
        #expect(ping["type"] as? String == "ping")
        #expect(ping["conversationID"] == nil)

        let subscribe = try jsonObject(for: RealtimeClientMessageDTO.subscribe(conversationID: conversationID))
        #expect(subscribe["type"] as? String == "subscribe.conversation")
        #expect(subscribe["conversationID"] as? String == conversationID.uuidString)

        let unsubscribe = try jsonObject(for: RealtimeClientMessageDTO.unsubscribe(conversationID: conversationID))
        #expect(unsubscribe["type"] as? String == "unsubscribe.conversation")
        #expect(unsubscribe["conversationID"] as? String == conversationID.uuidString)
    }

    @Test("server events decode PR2 PR3 and PR4 event types")
    func serverEventsDecodeKnownTypes() throws {
        let conversationID = "22222222-2222-2222-2222-222222222222"
        let messageID = "33333333-3333-3333-3333-333333333333"
        let profileID = "44444444-4444-4444-4444-444444444444"

        #expect(try decodeEvent(connectionReadyJSON()).type == "connection.ready")
        #expect(try decodeEvent(pongJSON()).type == "pong")
        #expect(try decodeEvent(errorJSON()).type == "error")

        if case .subscriptionReady(let id) = try decodeEvent(subscriptionReadyJSON(conversationID)) {
            #expect(id.uuidString == conversationID.uppercased())
        } else {
            Issue.record("Expected subscription.ready")
        }

        if case .subscriptionRemoved(let id) = try decodeEvent(subscriptionRemovedJSON(conversationID)) {
            #expect(id.uuidString == conversationID.uppercased())
        } else {
            Issue.record("Expected subscription.removed")
        }

        if case .messageCreated(let id, let message) = try decodeEvent(messageEventJSON("message.created")) {
            #expect(id.uuidString == conversationID.uppercased())
            #expect(message.id.uuidString == messageID.uppercased())
            #expect(message.body == "Hello")
        } else {
            Issue.record("Expected message.created")
        }

        if case .messageEdited(let id, let message) = try decodeEvent(messageEventJSON("message.edited")) {
            #expect(id.uuidString == conversationID.uppercased())
            #expect(message.id.uuidString == messageID.uppercased())
        } else {
            Issue.record("Expected message.edited")
        }

        if case .reactionAdded(_, let payload) = try decodeEvent(reactionAddedJSON()) {
            #expect(payload.messageID.uuidString == messageID.uppercased())
            #expect(payload.reaction.emoji == "❤️")
            #expect(payload.reaction.count == .bool(true))
            #expect(payload.reaction.reactedByMe)
        } else {
            Issue.record("Expected reaction.added")
        }

        if case .reactionRemoved(_, let payload) = try decodeEvent(reactionRemovedJSON()) {
            #expect(payload.messageID.uuidString == messageID.uppercased())
            #expect(payload.profileID?.uuidString == profileID.uppercased())
            #expect(payload.emoji == "❤️")
        } else {
            Issue.record("Expected reaction.removed")
        }

        if case .conversationRead(_, let payload) = try decodeEvent(conversationReadJSON()) {
            #expect(payload.profileID.uuidString == profileID.uppercased())
            #expect(payload.lastReadAt != nil)
        } else {
            Issue.record("Expected conversation.read")
        }

        if case .conversationUpdated(let id, let payload) = try decodeEvent(conversationUpdatedJSON()) {
            #expect(id.uuidString == conversationID.uppercased())
            #expect(payload.conversationID.uuidString == conversationID.uppercased())
            #expect(payload.updatedAt != nil)
        } else {
            Issue.record("Expected conversation.updated")
        }
    }

    @Test("message deleted decodes without body")
    func messageDeletedDecodesWithoutBody() throws {
        guard case .messageDeleted(_, let payload) = try decodeEvent(messageDeletedJSON()) else {
            Issue.record("Expected message.deleted")
            return
        }

        #expect(payload.messageID.uuidString == "33333333-3333-3333-3333-333333333333".uppercased())
        #expect(payload.deletedAt != nil)
        #expect(payload.isDeleted)
    }

    @Test("unknown event does not crash")
    func unknownEventDoesNotCrash() throws {
        guard case .unknown(let type) = try decodeEvent("""
        {
          "type": "future.event",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {"unexpected": true}
        }
        """) else {
            Issue.record("Expected unknown event")
            return
        }

        #expect(type == "future.event")
    }

    @Test("reconnect policy increases and caps")
    func reconnectPolicyIncreasesAndCaps() {
        let policy = RealtimeReconnectPolicy(initialDelay: 1, multiplier: 2, maxDelay: 15)

        #expect(policy.delay(forAttempt: 1) == 1)
        #expect(policy.delay(forAttempt: 2) == 2)
        #expect(policy.delay(forAttempt: 3) == 4)
        #expect(policy.delay(forAttempt: 8) == 15)
    }

    @MainActor
    @Test("intentional disconnect suppresses receive error reconnect")
    func intentionalDisconnectSuppressesReceiveErrorReconnect() {
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.disconnect()
        client.simulateReceiveErrorForTesting(URLError(.networkConnectionLost))

        #expect(client.state == .disconnected)
        #expect(!client.hasPendingReconnectForTesting)
    }

    @MainActor
    @Test("logout style disconnect cancels pending reconnect")
    func logoutStyleDisconnectCancelsPendingReconnect() {
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.simulateReceiveErrorForTesting(URLError(.networkConnectionLost))

        guard case .reconnecting(let attempt) = client.state else {
            Issue.record("Expected reconnecting state")
            return
        }

        #expect(attempt == 1)
        #expect(client.hasPendingReconnectForTesting)

        client.disconnect()

        #expect(client.state == .disconnected)
        #expect(!client.hasPendingReconnectForTesting)
    }

    @MainActor
    @Test("network failure while authenticated schedules reconnect")
    func networkFailureWhileAuthenticatedSchedulesReconnect() {
        let client = makeRealtimeClientForLifecycleTests()

        client.simulateActiveConnectionForTesting()
        client.simulateReceiveErrorForTesting(URLError(.networkConnectionLost))

        guard case .reconnecting(let attempt) = client.state else {
            Issue.record("Expected reconnecting state")
            return
        }

        #expect(attempt == 1)
        #expect(client.hasPendingReconnectForTesting)

        client.disconnect()
    }

    @MainActor
    @Test("router routes known and unknown events")
    func routerRoutesEvents() async {
        let router = RealtimeEventRouter.shared
        var iterator = router.stream().makeAsyncIterator()

        router.route(.pong)
        let event = await iterator.next()

        #expect(event?.type == "pong")

        router.route(.unknown(type: "future.event"))
        let unknown = await iterator.next()

        #expect(unknown?.type == "future.event")
    }

    private func jsonObject(for message: RealtimeClientMessageDTO) throws -> [String: Any] {
        let data = try JSONCoding.encoder.encode(message)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func decodeEvent(_ json: String) throws -> RealtimeEvent {
        try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(json.utf8)).event
    }

    @MainActor
    private func makeRealtimeClientForLifecycleTests() -> RealtimeClient {
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

    private func connectionReadyJSON() -> String {
        """
        {
          "type": "connection.ready",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {
            "userID": "44444444-4444-4444-4444-444444444444",
            "connectionID": "55555555-5555-5555-5555-555555555555"
          }
        }
        """
    }

    private func pongJSON() -> String {
        """
        {
          "type": "pong",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "payload": {}
        }
        """
    }

    private func errorJSON() -> String {
        """
        {
          "type": "error",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "code": "invalid_message",
          "message": "Invalid message",
          "payload": {}
        }
        """
    }

    private func subscriptionReadyJSON(_ conversationID: String) -> String {
        """
        {
          "type": "subscription.ready",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "\(conversationID)",
          "payload": {}
        }
        """
    }

    private func subscriptionRemovedJSON(_ conversationID: String) -> String {
        """
        {
          "type": "subscription.removed",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "\(conversationID)",
          "payload": {}
        }
        """
    }

    private func messageEventJSON(_ type: String) -> String {
        """
        {
          "type": "\(type)",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "message": {
              "id": "33333333-3333-3333-3333-333333333333",
              "conversationID": "22222222-2222-2222-2222-222222222222",
              "senderProfileID": "44444444-4444-4444-4444-444444444444",
              "kind": "text",
              "body": "Hello",
              "replyTo": null,
              "reactions": [],
              "createdAt": "2026-06-26T13:18:31Z",
              "editedAt": null,
              "deletedAt": null
            }
          }
        }
        """
    }

    private func messageDeletedJSON() -> String {
        """
        {
          "type": "message.deleted",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "messageID": "33333333-3333-3333-3333-333333333333",
            "deletedAt": "2026-06-26T13:18:31Z",
            "isDeleted": true
          }
        }
        """
    }

    private func reactionAddedJSON() -> String {
        """
        {
          "type": "reaction.added",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "messageID": "33333333-3333-3333-3333-333333333333",
            "reaction": {
              "emoji": "❤️",
              "count": true,
              "reactedByMe": true
            }
          }
        }
        """
    }

    private func reactionRemovedJSON() -> String {
        """
        {
          "type": "reaction.removed",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "messageID": "33333333-3333-3333-3333-333333333333",
            "profileID": "44444444-4444-4444-4444-444444444444",
            "emoji": "❤️"
          }
        }
        """
    }

    private func conversationReadJSON() -> String {
        """
        {
          "type": "conversation.read",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "profileID": "44444444-4444-4444-4444-444444444444",
            "lastReadAt": "2026-06-26T13:18:31Z"
          }
        }
        """
    }

    private func conversationUpdatedJSON() -> String {
        """
        {
          "type": "conversation.updated",
          "eventID": "00000000-0000-0000-0000-000000000001",
          "occurredAt": "2026-06-26T13:18:31Z",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "payload": {
            "conversationID": "22222222-2222-2222-2222-222222222222",
            "updatedAt": "2026-06-26T13:18:31Z",
            "lastMessageAt": "2026-06-26T13:18:31Z"
          }
        }
        """
    }
}
