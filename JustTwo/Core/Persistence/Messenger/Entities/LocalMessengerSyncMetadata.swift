import Foundation
import SwiftData

@Model
final class LocalMessengerSyncMetadata {
    @Attribute(.unique) var id: String
    var lastAppliedRevision: Int64?
    var lastSuccessfulSyncAt: Date?
    var lastFullRefreshAt: Date?
    var lastAttemptedSyncAt: Date?
    var lastFailedAt: Date?
    var lastErrorCode: String?
    var state: String?
    var needsFullRefresh: Bool
    var lastBootstrapAt: Date?
    var lastKnownServerRevision: Int64?
    var schemaVersion: Int
    var localUpdatedAt: Date

    init(
        id: String,
        lastAppliedRevision: Int64?,
        lastSuccessfulSyncAt: Date?,
        lastFullRefreshAt: Date?,
        lastAttemptedSyncAt: Date? = nil,
        lastFailedAt: Date? = nil,
        lastErrorCode: String? = nil,
        state: String? = nil,
        needsFullRefresh: Bool = false,
        lastBootstrapAt: Date? = nil,
        lastKnownServerRevision: Int64? = nil,
        schemaVersion: Int,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.lastAppliedRevision = lastAppliedRevision
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastFullRefreshAt = lastFullRefreshAt
        self.lastAttemptedSyncAt = lastAttemptedSyncAt
        self.lastFailedAt = lastFailedAt
        self.lastErrorCode = lastErrorCode
        self.state = state
        self.needsFullRefresh = needsFullRefresh
        self.lastBootstrapAt = lastBootstrapAt
        self.lastKnownServerRevision = lastKnownServerRevision
        self.schemaVersion = schemaVersion
        self.localUpdatedAt = localUpdatedAt
    }
}
