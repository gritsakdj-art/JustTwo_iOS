import Foundation
import SwiftData

@Model
final class LocalMessengerAttachment {
    @Attribute(.unique) var id: String
    var messageID: String
    var conversationID: String
    var kind: String
    var contentType: String?
    var byteSize: Int?
    var width: Int?
    var height: Int?
    var createdAt: Date?
    var localCacheKey: String?
    var downloadURLExpiresAt: Date?
    var localUpdatedAt: Date

    init(
        id: String,
        messageID: String,
        conversationID: String,
        kind: String,
        contentType: String?,
        byteSize: Int?,
        width: Int?,
        height: Int?,
        createdAt: Date?,
        localCacheKey: String?,
        downloadURLExpiresAt: Date?,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.messageID = messageID
        self.conversationID = conversationID
        self.kind = kind
        self.contentType = contentType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.localCacheKey = localCacheKey
        self.downloadURLExpiresAt = downloadURLExpiresAt
        self.localUpdatedAt = localUpdatedAt
    }
}
