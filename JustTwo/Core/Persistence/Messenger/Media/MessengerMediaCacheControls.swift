import Foundation

@MainActor
enum MessengerMediaCacheControls {

    static func inventory(store overrideStore: MessengerLocalStore? = nil) async -> MessengerMediaCacheInventory {
        let metadataStore = overrideStore ?? metadataStoreForUpdates()
        let policy = MessengerMediaCacheCleanupPolicy.default
        let referencedKeys = await fetchReferencedAttachmentIDs(store: metadataStore)
        let disk = await diskCache.confirmedInventory(referencedAttachmentIDs: referencedKeys)
        let pending = MessengerPendingMediaStore.inventory()

        let confirmedTotalBytes = disk.thumbnailBytes + disk.fullBytes
        let confirmedFileCount = disk.thumbnailCount + disk.fullCount
        let totalMessengerMediaBytes = confirmedTotalBytes + pending.totalBytes
        let overLimitBytes = max(0, confirmedTotalBytes - policy.softLimitBytes)

        return MessengerMediaCacheInventory(
            confirmedThumbnailBytes: disk.thumbnailBytes,
            confirmedFullBytes: disk.fullBytes,
            confirmedThumbnailFileCount: disk.thumbnailCount,
            confirmedFullFileCount: disk.fullCount,
            confirmedFileCount: confirmedFileCount,
            confirmedTotalBytes: confirmedTotalBytes,
            pendingOutgoingBytes: pending.totalBytes,
            pendingOutgoingFileCount: pending.fileCount,
            totalMessengerMediaBytes: totalMessengerMediaBytes,
            oldestConfirmedAccessAt: disk.oldestAccess,
            newestConfirmedAccessAt: disk.newestAccess,
            orphanConfirmedFileCount: disk.orphanCount,
            orphanConfirmedBytes: disk.orphanBytes,
            cacheSoftLimitBytes: policy.softLimitBytes,
            cacheHardLimitBytes: policy.hardLimitBytes,
            overLimitBytes: overLimitBytes
        )
    }

    static func trimNow(store overrideStore: MessengerLocalStore? = nil) async -> MessengerMediaCacheTrimResult {
        let metadataStore = overrideStore ?? metadataStoreForUpdates()
        let policy = MessengerMediaCacheCleanupPolicy.default
        let referencedKeys = await fetchReferencedAttachmentIDs(store: metadataStore)
        let result = await diskCache.cleanup(policy: policy, referencedAttachmentIDs: referencedKeys)
        await reconcileMetadataAfterDiskChanges(store: metadataStore)
        MessengerMediaCacheLastOperationStore.recordTrim(result)
        return result
    }

    static func clearConfirmedMediaCache(store overrideStore: MessengerLocalStore? = nil) async -> MessengerMediaCacheClearResult {
        let metadataStore = overrideStore ?? metadataStoreForUpdates()
        let inventoryBefore = await inventory(store: metadataStore)
        let pending = MessengerPendingMediaStore.inventory()

        await diskCache.clearAll()
        try? await metadataStore.clearAllConfirmedMediaCacheMetadata()
        ChatMessageImageCache.shared.clear()

        return MessengerMediaCacheClearResult(
            deletedConfirmedBytes: inventoryBefore.confirmedTotalBytes,
            deletedConfirmedFileCount: inventoryBefore.confirmedFileCount,
            preservedPendingBytes: pending.totalBytes,
            preservedPendingFileCount: pending.fileCount,
            finishedAt: Date()
        )
    }

    static func runCleanupIfNeeded(store overrideStore: MessengerLocalStore? = nil) async {
        _ = await trimNow(store: overrideStore)
    }

    static func runOrphanCleanup(store overrideStore: MessengerLocalStore? = nil) async -> MessengerMediaCacheTrimResult {
        await trimNow(store: overrideStore)
    }

    // MARK: - Private

    private static var diskCache: any MessengerMediaDiskCacheProtocol {
        #if DEBUG
        if let testingDiskCache = MessengerMediaCacheService.testingDiskCache {
            return testingDiskCache
        }
        #endif
        return MessengerMediaDiskCache.shared
    }

    private static func metadataStoreForUpdates() -> MessengerLocalStore {
        #if DEBUG
        if let testingLocalStore = MessengerMediaCacheService.testingLocalStore {
            return testingLocalStore
        }
        #endif
        return .shared
    }

    private static func fetchReferencedAttachmentIDs(store: MessengerLocalStore) async -> Set<String> {
        (try? await store.fetchAttachmentLocalCacheKeys()) ?? []
    }

    private static func reconcileMetadataAfterDiskChanges(store: MessengerLocalStore) async {
        let referencedKeys = await fetchReferencedAttachmentIDs(store: store)
        for attachmentID in referencedKeys {
            let hasThumbnail = await diskCache.hasCachedVariant(for: attachmentID, variant: .thumbnail)
            let hasFull = await diskCache.hasCachedVariant(for: attachmentID, variant: .full)
            if !hasThumbnail && !hasFull {
                try? await store.clearAttachmentMediaCacheMetadata(attachmentID: attachmentID)
            } else {
                // Metadata flags are reconciled lazily on next access/store.
            }
        }
    }
}
