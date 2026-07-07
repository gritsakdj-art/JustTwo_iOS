import Foundation
import SwiftData

@Model
final class LocalMessengerSyncMetadata {
    @Attribute(.unique) var id: String
    var lastAppliedRevision: Int64?
    var lastSuccessfulSyncAt: Date?
    var lastFullRefreshAt: Date?
    var schemaVersion: Int
    var localUpdatedAt: Date

    init(
        id: String,
        lastAppliedRevision: Int64?,
        lastSuccessfulSyncAt: Date?,
        lastFullRefreshAt: Date?,
        schemaVersion: Int,
        localUpdatedAt: Date
    ) {
        self.id = id
        self.lastAppliedRevision = lastAppliedRevision
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastFullRefreshAt = lastFullRefreshAt
        self.schemaVersion = schemaVersion
        self.localUpdatedAt = localUpdatedAt
    }
}
