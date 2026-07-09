import Foundation
import SwiftData

@Model
final class LocalMessengerPendingMedia {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var pendingMediaID: String
    var clientMessageID: String
    var conversationID: String
    var localRelativePath: String
    var contentType: String
    var byteSize: Int
    var width: Int?
    var height: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        pendingMediaID: String,
        clientMessageID: String,
        conversationID: String,
        localRelativePath: String,
        contentType: String,
        byteSize: Int,
        width: Int?,
        height: Int?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.pendingMediaID = pendingMediaID
        self.clientMessageID = clientMessageID
        self.conversationID = conversationID
        self.localRelativePath = localRelativePath
        self.contentType = contentType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
