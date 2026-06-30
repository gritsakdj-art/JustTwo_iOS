import Foundation

enum PushNotificationRoute: Equatable, Sendable {
    case conversation(conversationId: UUID, messageId: UUID?, senderId: UUID?)
}

struct PushNotificationPayloadParser: Sendable {
    func parse(userInfo: [AnyHashable: Any]) -> PushNotificationRoute? {
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

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func uuidValue(from userInfo: [AnyHashable: Any], keys: [String]) -> UUID? {
        for key in keys {
            guard let raw = stringValue(userInfo[AnyHashable(key)]) else { continue }
            if let uuid = UUID(uuidString: raw) {
                return uuid
            }
        }
        return nil
    }
}
