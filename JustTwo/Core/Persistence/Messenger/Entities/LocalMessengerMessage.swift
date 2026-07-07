import Foundation
import SwiftData

@Model
final class LocalMessengerMessage {
    @Attribute(.unique) var id: String
    var conversationID: String
    var clientMessageID: String?
    var senderProfileID: String
    var kind: String
    var body: String?
    var createdAt: Date
    var editedAt: Date?
    var deletedAt: Date?
    var deliveryStatus: String?
    var replyToMessageID: String?
    var replyToBody: String?
    var replyToSenderProfileID: String?
    var localState: String
    var localCreatedAt: Date
    var localUpdatedAt: Date

    init(
        id: String,
        conversationID: String,
        clientMessageID: String?,
        senderProfileID: String,
        kind: String,
        body: String?,
        createdAt: Date,
        editedAt: Date?,
        deletedAt: Date?,
        deliveryStatus: String?,
        replyToMessageID: String?,
        replyToBody: String?,
        replyToSenderProfileID: String?,
        localState: String,
        localCreatedAt: Date,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.clientMessageID = clientMessageID
        self.senderProfileID = senderProfileID
        self.kind = kind
        self.body = body
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.deliveryStatus = deliveryStatus
        self.replyToMessageID = replyToMessageID
        self.replyToBody = replyToBody
        self.replyToSenderProfileID = replyToSenderProfileID
        self.localState = localState
        self.localCreatedAt = localCreatedAt
        self.localUpdatedAt = localUpdatedAt
    }
}
