import Foundation

enum PushDeliveryEvent: Sendable {
    nonisolated static let messageCreated = "message.created"
}

enum PushNotificationRoute: Equatable, Sendable {
    case conversation(conversationId: UUID, messageId: UUID?, senderId: UUID?)
}

struct PushNotificationPayloadParser: Sendable {
    nonisolated init() {}

    /// Parses a messenger background wake hint from a push `userInfo` dictionary.
    /// Requires `event == "message.created"` (PR20D3A) or legacy `type == "message.created"`.
    /// Returns `nil` for non-messenger, malformed, or tap-only payloads without event/type.
    nonisolated func parseWakeIntent(userInfo: [AnyHashable: Any]) -> MessengerBackgroundWakeIntent? {
        if let event = stringValue(userInfo["event"]) {
            guard event == PushDeliveryEvent.messageCreated else { return nil }
        } else if let type = stringValue(userInfo["type"]) {
            guard type == PushDeliveryEvent.messageCreated else { return nil }
            if let route = stringValue(userInfo["route"]), route != "conversation" {
                return nil
            }
        } else {
            return nil
        }

        guard let conversationID = uuidValue(
            from: userInfo,
            keys: ["conversationID", "conversationId"]
        ) else {
            return nil
        }

        let messageID = uuidValue(from: userInfo, keys: ["messageID", "messageId"])
        return MessengerBackgroundWakeIntent(
            conversationID: conversationID,
            messageID: messageID
        )
    }

    nonisolated func parse(userInfo: [AnyHashable: Any]) -> PushNotificationRoute? {
        if let type = stringValue(userInfo["type"]) {
            guard type == "message.created" else { return nil }
            if let route = stringValue(userInfo["route"]), route != "conversation" {
                return nil
            }
        }

        guard let conversationID = uuidValue(
            from: userInfo,
            keys: ["conversationId", "conversationID"]
        ) else {
            return nil
        }

        let messageID = uuidValue(from: userInfo, keys: ["messageId", "messageID"])
        let senderID = uuidValue(from: userInfo, keys: ["senderId", "senderID"])

        return .conversation(
            conversationId: conversationID,
            messageId: messageID,
            senderId: senderID
        )
    }

    private nonisolated func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private nonisolated func uuidValue(from userInfo: [AnyHashable: Any], keys: [String]) -> UUID? {
        for key in keys {
            guard let raw = stringValue(userInfo[AnyHashable(key)]) else { continue }
            if let uuid = UUID(uuidString: raw) {
                return uuid
            }
        }
        return nil
    }
}
