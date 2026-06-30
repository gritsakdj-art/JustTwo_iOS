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
}
