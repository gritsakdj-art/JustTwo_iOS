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
    let otherParticipantLastSeenAt: Date?
    let lastMessageID: String?
    let lastMessageKind: String?
    let lastMessageBody: String?
    let lastMessageSenderProfileID: String?
    let lastMessageCreatedAt: Date?
    let lastMessageDeletedAt: Date?
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
    let hasLocalThumbnail: Bool
    let hasLocalFullImage: Bool
    let localThumbnailByteSize: Int?
    let localFullByteSize: Int?
    let mediaCachedAt: Date?
    let mediaLastAccessedAt: Date?
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
    let lastAttemptedSyncAt: Date?
    let lastFailedAt: Date?
    let lastErrorCode: String?
    let state: String?
    let needsFullRefresh: Bool
    let lastBootstrapAt: Date?
    let lastKnownServerRevision: Int64?
    let schemaVersion: Int
    let localUpdatedAt: Date
}

enum MessengerOutboxItemKind: String, Sendable, Equatable {
    case text
    case image
}

enum MessengerOutboxItemStatus: String, Sendable, Equatable {
    case pending
    case sending
    case failed
    case sent
    case cancelled
}

struct MessengerOutboxItemSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let conversationID: String
    let clientMessageID: String
    let kind: MessengerOutboxItemKind
    let body: String
    let replyToMessageID: String?
    let status: MessengerOutboxItemStatus
    let attemptCount: Int
    let lastErrorCode: String?
    let nextRetryAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let lastAttemptAt: Date?
    let serverMessageID: String?
    let pendingMediaID: String?
}

enum MessengerOutboxRetryPolicy {
    /// Stale `sending` jobs older than this are reset to `pending` on relaunch.
    static let staleSendingThreshold: TimeInterval = 120

    static func nextRetryDate(afterAttemptCount attemptCount: Int, from now: Date = .now) -> Date {
        switch attemptCount {
        case 0, 1:
            return now
        case 2:
            return now.addingTimeInterval(5)
        case 3:
            return now.addingTimeInterval(15)
        default:
            return now.addingTimeInterval(60)
        }
    }
}
