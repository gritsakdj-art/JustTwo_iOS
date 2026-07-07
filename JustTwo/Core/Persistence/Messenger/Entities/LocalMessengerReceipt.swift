import Foundation
import SwiftData

@Model
final class LocalMessengerReceipt {
    @Attribute(.unique) var id: String
    var conversationID: String
    var profileID: String
    var lastDeliveredAt: Date?
    var lastReadAt: Date?
    var lastDeliveredMessageID: String?
    var lastReadMessageID: String?
    var localUpdatedAt: Date

    init(
        id: String,
        conversationID: String,
        profileID: String,
        lastDeliveredAt: Date?,
        lastReadAt: Date?,
        lastDeliveredMessageID: String?,
        lastReadMessageID: String?,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.profileID = profileID
        self.lastDeliveredAt = lastDeliveredAt
        self.lastReadAt = lastReadAt
        self.lastDeliveredMessageID = lastDeliveredMessageID
        self.lastReadMessageID = lastReadMessageID
        self.localUpdatedAt = localUpdatedAt
    }
}
