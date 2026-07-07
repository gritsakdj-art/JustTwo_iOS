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
    var hasLocalThumbnail: Bool?
    var hasLocalFullImage: Bool?
    var localThumbnailByteSize: Int?
    var localFullByteSize: Int?
    var mediaCachedAt: Date?
    var mediaLastAccessedAt: Date?
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
        hasLocalThumbnail: Bool? = false,
        hasLocalFullImage: Bool? = false,
        localThumbnailByteSize: Int? = nil,
        localFullByteSize: Int? = nil,
        mediaCachedAt: Date? = nil,
        mediaLastAccessedAt: Date? = nil,
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
        self.hasLocalThumbnail = hasLocalThumbnail
        self.hasLocalFullImage = hasLocalFullImage
        self.localThumbnailByteSize = localThumbnailByteSize
        self.localFullByteSize = localFullByteSize
        self.mediaCachedAt = mediaCachedAt
        self.mediaLastAccessedAt = mediaLastAccessedAt
        self.localUpdatedAt = localUpdatedAt
    }
}
