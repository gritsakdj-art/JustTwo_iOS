import Foundation
import SwiftData

@Model
final class LocalMessengerReactionAggregate {
    @Attribute(.unique) var id: String
    var messageID: String
    var conversationID: String
    var emoji: String
    var count: Int
    var reactedByMe: Bool
    var localUpdatedAt: Date

    init(
        id: String,
        messageID: String,
        conversationID: String,
        emoji: String,
        count: Int,
        reactedByMe: Bool,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.messageID = messageID
        self.conversationID = conversationID
        self.emoji = emoji
        self.count = count
        self.reactedByMe = reactedByMe
        self.localUpdatedAt = localUpdatedAt
    }
}
