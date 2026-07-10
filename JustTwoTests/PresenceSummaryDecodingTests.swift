@testable import JustTwo
import Foundation
import Testing

@Suite("PresenceSummary Decoding Tests")
struct PresenceSummaryDecodingTests {

    @Test("presence with date decodes on profile summary")
    func presenceWithDateDecodes() throws {
        let dto = try decodeConversation(includePresence: true, isOnline: false, lastSeenAt: "\"2026-07-10T12:00:00Z\"")

        let presence = try #require(dto.otherParticipant?.profile.presence)
        #expect(presence.isOnline == false)
        #expect(presence.lastSeenAt != nil)
    }

    @Test("explicit null lastSeenAt decodes")
    func explicitNullDecodes() throws {
        let dto = try decodeConversation(includePresence: true, isOnline: true, lastSeenAt: "null")

        let presence = try #require(dto.otherParticipant?.profile.presence)
        #expect(presence.isOnline == true)
        #expect(presence.lastSeenAt == nil)
    }

    @Test("payload without presence decodes")
    func missingPresenceDecodes() throws {
        let dto = try decodeConversation(includePresence: false, isOnline: false, lastSeenAt: "null")
        #expect(dto.otherParticipant?.profile.presence == nil)
    }

    @Test("realtime presence.changed supports isOnline")
    func realtimeIsOnlineDecodes() throws {
        let event = try decodeEvent("""
        {
          "type": "presence.changed",
          "payload": {
            "profileID": "44444444-4444-4444-8444-444444444444",
            "isOnline": true,
            "lastSeenAt": null
          }
        }
        """)

        guard case .presenceChanged(let payload) = event else {
            Issue.record("Expected presence.changed")
            return
        }
        #expect(payload.isOnline)
        #expect(payload.lastSeenAt == nil)
    }

    @Test("invalid lastSeenAt fails decoding")
    func invalidDateFails() {
        #expect(throws: (any Error).self) {
            _ = try decodeConversation(includePresence: true, isOnline: false, lastSeenAt: "\"not-a-date\"")
        }
    }

    @Test("realtime isOnline wins over conflicting status")
    func realtimeIsOnlineConflict() throws {
        let event = try decodeEvent("""
        {
          "type": "presence.changed",
          "payload": {
            "profileID": "44444444-4444-4444-8444-444444444444",
            "isOnline": true,
            "status": "offline",
            "lastSeenAt": null
          }
        }
        """)

        guard case .presenceChanged(let payload) = event else {
            Issue.record("Expected presence.changed")
            return
        }
        #expect(payload.isOnline)
    }

    @Test("realtime missing lastSeenAt key decodes as nil")
    func missingLastSeenAtKey() throws {
        let event = try decodeEvent("""
        {
          "type": "presence.changed",
          "payload": {
            "profileID": "44444444-4444-4444-8444-444444444444",
            "isOnline": false
          }
        }
        """)

        guard case .presenceChanged(let payload) = event else {
            Issue.record("Expected presence.changed")
            return
        }
        #expect(payload.lastSeenAt == nil)
    }

    private func decodeConversation(
        includePresence: Bool,
        isOnline: Bool,
        lastSeenAt: String
    ) throws -> ConversationDTO {
        let presenceJSON: String
        if includePresence {
            presenceJSON = """
            ,
              "presence": {
                "isOnline": \(isOnline),
                "lastSeenAt": \(lastSeenAt)
              }
            """
        } else {
            presenceJSON = ""
        }

        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "type": "direct",
          "status": "active",
          "connectionID": null,
          "otherParticipant": {
            "profile": {
              "id": "55555555-5555-4555-8555-555555555555",
              "displayName": "Taylor",
              "bio": null,
              "city": null,
              "primaryPhoto": null\(presenceJSON)
            },
            "role": "member",
            "joinedAt": "2026-06-26T13:18:31Z",
            "lastReadAt": null,
            "lastDeliveredAt": null
          },
          "lastMessage": null,
          "unreadCount": 0,
          "lastReadAt": null,
          "lastMessageAt": null,
          "createdAt": "2026-06-26T13:18:31Z",
          "updatedAt": "2026-06-26T13:18:31Z"
        }
        """

        return try JSONCoding.decoder.decode(ConversationDTO.self, from: Data(json.utf8))
    }

    private func decodeEvent(_ json: String) throws -> RealtimeEvent {
        try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(json.utf8)).event
    }
}
