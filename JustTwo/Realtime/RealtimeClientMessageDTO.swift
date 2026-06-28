import Foundation

struct RealtimeClientMessageDTO: Encodable, Equatable, Sendable {
    let type: String
    let conversationID: UUID?

    private init(type: String, conversationID: UUID? = nil) {
        self.type = type
        self.conversationID = conversationID
    }

    static func ping() -> RealtimeClientMessageDTO {
        RealtimeClientMessageDTO(type: "ping")
    }

    static func subscribe(conversationID: UUID) -> RealtimeClientMessageDTO {
        RealtimeClientMessageDTO(
            type: "subscribe.conversation",
            conversationID: conversationID
        )
    }

    static func unsubscribe(conversationID: UUID) -> RealtimeClientMessageDTO {
        RealtimeClientMessageDTO(
            type: "unsubscribe.conversation",
            conversationID: conversationID
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case conversationID
    }
}
