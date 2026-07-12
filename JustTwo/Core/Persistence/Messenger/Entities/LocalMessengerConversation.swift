import Foundation
import SwiftData

@Model
final class LocalMessengerConversation {
    @Attribute(.unique) var id: String
    var type: String
    var status: String
    var connectionID: String?
    var createdAt: Date
    var updatedAt: Date?
    var lastMessageAt: Date?
    var lastReadAt: Date?
    var unreadCount: Int
    var otherParticipantProfileID: String?
    var otherParticipantDisplayName: String?
    var otherParticipantPrimaryPhotoID: String?
    var otherParticipantPrimaryPhotoDownloadURLExpiresAt: Date?
    var otherParticipantLastSeenAt: Date?
    var lastMessageID: String?
    var lastMessageKind: String?
    var lastMessageBody: String?
    var lastMessageSenderProfileID: String?
    var lastMessageCreatedAt: Date?
    var lastMessageDeletedAt: Date?
    var lastMessageDeliveryStatus: String?
    var lastSyncedAt: Date?
    var localUpdatedAt: Date

    init(
        id: String,
        type: String,
        status: String,
        connectionID: String?,
        createdAt: Date,
        updatedAt: Date?,
        lastMessageAt: Date?,
        lastReadAt: Date?,
        unreadCount: Int,
        otherParticipantProfileID: String?,
        otherParticipantDisplayName: String?,
        otherParticipantPrimaryPhotoID: String?,
        otherParticipantPrimaryPhotoDownloadURLExpiresAt: Date?,
        otherParticipantLastSeenAt: Date? = nil,
        lastMessageID: String?,
        lastMessageKind: String?,
        lastMessageBody: String?,
        lastMessageSenderProfileID: String?,
        lastMessageCreatedAt: Date?,
        lastMessageDeletedAt: Date?,
        lastMessageDeliveryStatus: String? = nil,
        lastSyncedAt: Date?,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.connectionID = connectionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessageAt = lastMessageAt
        self.lastReadAt = lastReadAt
        self.unreadCount = unreadCount
        self.otherParticipantProfileID = otherParticipantProfileID
        self.otherParticipantDisplayName = otherParticipantDisplayName
        self.otherParticipantPrimaryPhotoID = otherParticipantPrimaryPhotoID
        self.otherParticipantPrimaryPhotoDownloadURLExpiresAt = otherParticipantPrimaryPhotoDownloadURLExpiresAt
        self.otherParticipantLastSeenAt = otherParticipantLastSeenAt
        self.lastMessageID = lastMessageID
        self.lastMessageKind = lastMessageKind
        self.lastMessageBody = lastMessageBody
        self.lastMessageSenderProfileID = lastMessageSenderProfileID
        self.lastMessageCreatedAt = lastMessageCreatedAt
        self.lastMessageDeletedAt = lastMessageDeletedAt
        self.lastMessageDeliveryStatus = lastMessageDeliveryStatus
        self.lastSyncedAt = lastSyncedAt
        self.localUpdatedAt = localUpdatedAt
    }
}
