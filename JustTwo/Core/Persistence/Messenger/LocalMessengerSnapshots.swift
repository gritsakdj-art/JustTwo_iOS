import Foundation

enum LocalMessengerMessageState: String, Sendable, Equatable {
    case serverConfirmed
    case sending
    case failed
    case deleted
    case pendingUpload
}

struct LocalConversationSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let type: String
    let status: String
    let connectionID: String?
    let createdAt: Date
    let updatedAt: Date?
    let lastMessageAt: Date?
    let lastReadAt: Date?
    let unreadCount: Int
    let otherParticipantProfileID: String?
    let otherParticipantDisplayName: String?
    let otherParticipantPrimaryPhotoID: String?
    let otherParticipantPrimaryPhotoDownloadURLExpiresAt: Date?
    let lastMessageID: String?
    let lastSyncedAt: Date?
    let localUpdatedAt: Date
}

struct LocalMessageSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let conversationID: String
    let clientMessageID: String?
    let senderProfileID: String
    let kind: String
    let body: String?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?
    let deliveryStatus: String?
    let replyToMessageID: String?
    let replyToBody: String?
    let replyToSenderProfileID: String?
    let localState: LocalMessengerMessageState
    let localCreatedAt: Date
    let localUpdatedAt: Date
    let attachments: [LocalAttachmentSnapshot]
    let reactions: [LocalReactionAggregateSnapshot]
}

struct LocalAttachmentSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let messageID: String
    let conversationID: String
    let kind: String
    let contentType: String?
    let byteSize: Int?
    let width: Int?
    let height: Int?
    let createdAt: Date?
    let localCacheKey: String?
    let downloadURLExpiresAt: Date?
    let localUpdatedAt: Date
}

struct LocalReactionAggregateSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let messageID: String
    let conversationID: String
    let emoji: String
    let count: Int
    let reactedByMe: Bool
    let localUpdatedAt: Date
}

struct LocalReceiptSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let conversationID: String
    let profileID: String
    let lastDeliveredAt: Date?
    let lastReadAt: Date?
    let lastDeliveredMessageID: String?
    let lastReadMessageID: String?
    let localUpdatedAt: Date
}

struct LocalMessengerSyncMetadataSnapshot: Sendable, Equatable {
    let id: String
    let lastAppliedRevision: Int64?
    let lastSuccessfulSyncAt: Date?
    let lastFullRefreshAt: Date?
    let schemaVersion: Int
    let localUpdatedAt: Date
}
