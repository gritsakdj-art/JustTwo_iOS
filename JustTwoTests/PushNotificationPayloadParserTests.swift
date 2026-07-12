import Foundation
import Testing
@testable import JustTwo

struct PushNotificationPayloadParserTests {

    private let parser = PushNotificationPayloadParser()

    @Test
    func validMessageCreatedPayloadParsesConversationRoute() {
        let conversationID = UUID()
        let messageID = UUID()
        let senderID = UUID()

        let route = parser.parse(userInfo: [
            "type": "message.created",
            "route": "conversation",
            "conversationId": conversationID.uuidString,
            "messageId": messageID.uuidString,
            "senderId": senderID.uuidString
        ])

        #expect(route == .conversation(
            conversationId: conversationID,
            messageId: messageID,
            senderId: senderID
        ))
    }

    @Test
    func legacyLocalNotificationKeysStillParse() {
        let conversationID = UUID()
        let messageID = UUID()

        let route = parser.parse(userInfo: [
            "conversationID": conversationID.uuidString,
            "messageID": messageID.uuidString
        ])

        #expect(route == .conversation(
            conversationId: conversationID,
            messageId: messageID,
            senderId: nil
        ))
    }

    @Test
    func unknownTypeReturnsNil() {
        let route = parser.parse(userInfo: [
            "type": "debug.test",
            "route": "conversation",
            "conversationId": UUID().uuidString
        ])

        #expect(route == nil)
    }

    @Test
    func missingConversationIdReturnsNil() {
        let route = parser.parse(userInfo: [
            "type": "message.created",
            "route": "conversation",
            "messageId": UUID().uuidString
        ])

        #expect(route == nil)
    }

    @Test
    func invalidConversationUUIDReturnsNil() {
        let route = parser.parse(userInfo: [
            "type": "message.created",
            "route": "conversation",
            "conversationId": "not-a-uuid"
        ])

        #expect(route == nil)
    }

    @Test
    func optionalIDsAreParsedWhenValid() {
        let conversationID = UUID()
        let messageID = UUID()
        let senderID = UUID()

        let route = parser.parse(userInfo: [
            "type": "message.created",
            "conversationId": conversationID.uuidString,
            "messageId": messageID.uuidString,
            "senderId": senderID.uuidString
        ])

        #expect(route == .conversation(
            conversationId: conversationID,
            messageId: messageID,
            senderId: senderID
        ))
    }

    @Test
    func malformedOptionalUUIDDoesNotCrash() {
        let conversationID = UUID()

        let route = parser.parse(userInfo: [
            "type": "message.created",
            "route": "conversation",
            "conversationId": conversationID.uuidString,
            "messageId": "bad-message-id",
            "senderId": "bad-sender-id"
        ])

        #expect(route == .conversation(
            conversationId: conversationID,
            messageId: nil,
            senderId: nil
        ))
    }

    @Test
    func nonConversationRouteReturnsNil() {
        let route = parser.parse(userInfo: [
            "type": "message.created",
            "route": "profile",
            "conversationId": UUID().uuidString
        ])

        #expect(route == nil)
    }

    @Test
    func wakeIntentParsesCanonicalEventPayload() {
        let conversationID = UUID()
        let messageID = UUID()

        let intent = parser.parseWakeIntent(userInfo: [
            "event": "message.created",
            "conversationID": conversationID.uuidString,
            "messageID": messageID.uuidString
        ])

        #expect(intent == MessengerBackgroundWakeIntent(
            conversationID: conversationID,
            messageID: messageID
        ))
    }

    @Test
    func wakeIntentSupportsLegacyLowercaseKeys() {
        let conversationID = UUID()
        let messageID = UUID()

        let intent = parser.parseWakeIntent(userInfo: [
            "event": "message.created",
            "conversationId": conversationID.uuidString,
            "messageId": messageID.uuidString
        ])

        #expect(intent?.conversationID == conversationID)
        #expect(intent?.messageID == messageID)
    }

    @Test
    func wakeIntentRejectsNonMessengerEvent() {
        let intent = parser.parseWakeIntent(userInfo: [
            "event": "debug.test",
            "conversationID": UUID().uuidString
        ])

        #expect(intent == nil)
    }

    @Test
    func wakeIntentRejectsLegacyKeysWithoutEventOrType() {
        let intent = parser.parseWakeIntent(userInfo: [
            "conversationID": UUID().uuidString,
            "messageID": UUID().uuidString
        ])

        #expect(intent == nil)
    }

    @Test
    func wakeIntentMalformedEventStillRequiresConversationID() {
        let intent = parser.parseWakeIntent(userInfo: [
            "event": "message.created",
            "messageID": UUID().uuidString
        ])

        #expect(intent == nil)
    }
}
