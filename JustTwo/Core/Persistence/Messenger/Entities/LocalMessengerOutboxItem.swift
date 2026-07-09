import Foundation
import SwiftData

@Model
final class LocalMessengerOutboxItem {
    @Attribute(.unique) var id: String
    var conversationID: String
    @Attribute(.unique) var clientMessageID: String
    var kind: String
    var body: String
    var replyToMessageID: String?
    var status: String
    var attemptCount: Int
    var lastErrorCode: String?
    var nextRetryAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?
    var serverMessageID: String?

    init(
        id: String,
        conversationID: String,
        clientMessageID: String,
        kind: String,
        body: String,
        replyToMessageID: String?,
        status: String,
        attemptCount: Int,
        lastErrorCode: String?,
        nextRetryAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        lastAttemptAt: Date?,
        serverMessageID: String?
    ) {
        self.id = id
        self.conversationID = conversationID
        self.clientMessageID = clientMessageID
        self.kind = kind
        self.body = body
        self.replyToMessageID = replyToMessageID
        self.status = status
        self.attemptCount = attemptCount
        self.lastErrorCode = lastErrorCode
        self.nextRetryAt = nextRetryAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttemptAt = lastAttemptAt
        self.serverMessageID = serverMessageID
    }
}
