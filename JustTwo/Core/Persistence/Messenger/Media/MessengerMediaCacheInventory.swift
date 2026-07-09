import Foundation

struct MessengerMediaCacheInventory: Sendable, Equatable {
    let confirmedThumbnailBytes: Int64
    let confirmedFullBytes: Int64
    let confirmedThumbnailFileCount: Int
    let confirmedFullFileCount: Int
    let confirmedFileCount: Int
    let confirmedTotalBytes: Int64
    let pendingOutgoingBytes: Int64
    let pendingOutgoingFileCount: Int
    let totalMessengerMediaBytes: Int64
    let oldestConfirmedAccessAt: Date?
    let newestConfirmedAccessAt: Date?
    let orphanConfirmedFileCount: Int
    let orphanConfirmedBytes: Int64
    let cacheSoftLimitBytes: Int64
    let cacheHardLimitBytes: Int64
    let overLimitBytes: Int64

    var confirmedAttachmentCount: Int {
        confirmedFileCount > 0 ? max(confirmedThumbnailFileCount, confirmedFullFileCount) : 0
    }
}

struct MessengerMediaCacheTrimResult: Sendable, Equatable {
    let removedFullCount: Int
    let removedThumbnailCount: Int
    let orphanDirectoryCount: Int
    let deletedBytes: Int64
    let finishedAt: Date

    var deletedCount: Int {
        removedFullCount + removedThumbnailCount + orphanDirectoryCount
    }
}

struct MessengerMediaCacheClearResult: Sendable, Equatable {
    let deletedConfirmedBytes: Int64
    let deletedConfirmedFileCount: Int
    let preservedPendingBytes: Int64
    let preservedPendingFileCount: Int
    let finishedAt: Date
}

enum MessengerMediaCacheLastOperationStore {
    private static let trimResultKey = "messenger.mediaCache.lastTrim"
    private static let trimFinishedAtKey = "messenger.mediaCache.lastTrimAt"
    private static let orphanRemovedKey = "messenger.mediaCache.lastOrphanRemoved"

    static func recordTrim(_ result: MessengerMediaCacheTrimResult) {
        UserDefaults.standard.set(result.deletedCount, forKey: trimResultKey)
        UserDefaults.standard.set(result.deletedBytes, forKey: "messenger.mediaCache.lastTrimBytes")
        UserDefaults.standard.set(result.finishedAt.timeIntervalSince1970, forKey: trimFinishedAtKey)
    }

    static func recordOrphanCleanup(removedCount: Int) {
        UserDefaults.standard.set(removedCount, forKey: orphanRemovedKey)
    }

    static func lastTrimDeletedCount() -> Int {
        UserDefaults.standard.integer(forKey: trimResultKey)
    }

    static func lastTrimDeletedBytes() -> Int64 {
        Int64(UserDefaults.standard.integer(forKey: "messenger.mediaCache.lastTrimBytes"))
    }

    static func lastTrimFinishedAt() -> Date? {
        let value = UserDefaults.standard.double(forKey: trimFinishedAtKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    static func lastOrphanRemovedCount() -> Int {
        UserDefaults.standard.integer(forKey: orphanRemovedKey)
    }

    #if DEBUG
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: trimResultKey)
        UserDefaults.standard.removeObject(forKey: "messenger.mediaCache.lastTrimBytes")
        UserDefaults.standard.removeObject(forKey: trimFinishedAtKey)
        UserDefaults.standard.removeObject(forKey: orphanRemovedKey)
    }
    #endif
}
