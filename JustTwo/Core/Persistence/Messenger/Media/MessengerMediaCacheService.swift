import Foundation
import UIKit

@MainActor
enum MessengerMediaCacheService {

    #if DEBUG
    nonisolated(unsafe) static var testingDiskCache: (any MessengerMediaDiskCacheProtocol)?
    nonisolated(unsafe) static var testingLocalStore: MessengerLocalStore?
    #endif

    private static var diskCache: any MessengerMediaDiskCacheProtocol {
        #if DEBUG
        if let testingDiskCache {
            return testingDiskCache
        }
        #endif
        return MessengerMediaDiskCache.shared
    }

    static func loadBubbleImage(attachmentID: String) async -> UIImage? {
        let metadataStore = metadataStoreForUpdates()
        if let thumbnail = await loadImage(attachmentID: attachmentID, variant: .thumbnail) {
            await recordAccess(attachmentID: attachmentID, variant: .thumbnail, store: metadataStore)
            return thumbnail
        }
        if let full = await loadImage(attachmentID: attachmentID, variant: .full) {
            await recordAccess(attachmentID: attachmentID, variant: .full, store: metadataStore)
            return full
        }
        return nil
    }

    static func loadViewerImage(attachmentID: String) async -> UIImage? {
        let metadataStore = metadataStoreForUpdates()
        if let full = await loadImage(attachmentID: attachmentID, variant: .full) {
            await recordAccess(attachmentID: attachmentID, variant: .full, store: metadataStore)
            return full
        }
        if let thumbnail = await loadImage(attachmentID: attachmentID, variant: .thumbnail) {
            await recordAccess(attachmentID: attachmentID, variant: .thumbnail, store: metadataStore)
            return thumbnail
        }
        return nil
    }

    static func storeBubbleImage(_ image: UIImage, attachmentID: String) async {
        guard let data = await jpegData(from: image, quality: 0.86) else { return }
        await storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)
    }

    static func storeViewerImage(_ image: UIImage, attachmentID: String) async {
        guard let data = await jpegData(from: image, quality: 0.92) else { return }
        await storeImageData(data, attachmentID: attachmentID, variant: .full)
    }

    static func storeImageData(
        _ data: Data,
        attachmentID: String,
        variant: MessengerMediaVariant,
        store overrideStore: MessengerLocalStore? = nil
    ) async {
        let metadataStore = overrideStore ?? metadataStoreForUpdates()
        do {
            try await diskCache.storeImageData(data, attachmentID: attachmentID, variant: variant)
            await updateMetadata(
                attachmentID: attachmentID,
                variant: variant,
                byteSize: data.count,
                store: metadataStore
            )
            await enforceQuotaIfNeeded(store: metadataStore)
        } catch {
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheStoreFailed,
                metadata: [
                    "attachmentID": sanitizedAttachmentIDForDiagnostics(attachmentID),
                    "variant": variant.rawValue,
                    "reason": MessengerDiagnostics.sanitizeError(error)
                ]
            )
        }
    }

    static func removeMedia(attachmentID: String) async {
        let metadataStore = metadataStoreForUpdates()
        await diskCache.removeMedia(for: attachmentID)
        await clearMetadata(attachmentID: attachmentID, store: metadataStore)
        ChatMessageImageCache.shared.remove(for: attachmentID)
    }

    static func runCleanupIfNeeded() async {
        let metadataStore = metadataStoreForUpdates()
        let policy = MessengerMediaCacheCleanupPolicy.default
        let referencedKeys = await fetchReferencedAttachmentIDs(store: metadataStore)
        await diskCache.cleanup(policy: policy, referencedAttachmentIDs: referencedKeys)
    }

    static func clearAll() async {
        await diskCache.clearAll()
    }

    // MARK: - Private

    private static func loadImage(
        attachmentID: String,
        variant: MessengerMediaVariant
    ) async -> UIImage? {
        guard let data = try? await diskCache.cachedImageData(for: attachmentID, variant: variant),
              let image = await image(data: data) else {
            return nil
        }
        return image
    }

    private static func image(data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data).map { SendableMessengerMediaImage(image: $0) }
        }.value?.image
    }

    private static func jpegData(from image: UIImage, quality: CGFloat) async -> Data? {
        let sendableImage = SendableMessengerMediaImage(image: image)
        return await Task.detached(priority: .utility) {
            sendableImage.image.jpegData(compressionQuality: quality)
        }.value
    }

    private static func metadataStoreForUpdates() -> MessengerLocalStore {
        #if DEBUG
        if let testingLocalStore {
            return testingLocalStore
        }
        #endif
        return .shared
    }

    private static func recordAccess(
        attachmentID: String,
        variant: MessengerMediaVariant,
        store: MessengerLocalStore
    ) async {
        do {
            try await store.recordAttachmentMediaAccess(
                attachmentID: attachmentID,
                variant: variant,
                accessedAt: Date()
            )
        } catch {
            // Metadata update failure must not block rendering.
        }
    }

    private static func updateMetadata(
        attachmentID: String,
        variant: MessengerMediaVariant,
        byteSize: Int,
        store: MessengerLocalStore
    ) async {
        do {
            try await store.updateAttachmentMediaCacheMetadata(
                attachmentID: attachmentID,
                variant: variant,
                byteSize: byteSize,
                cachedAt: Date()
            )
        } catch {
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheStoreFailed,
                metadata: [
                    "attachmentID": sanitizedAttachmentIDForDiagnostics(attachmentID),
                    "variant": variant.rawValue,
                    "reason": "metadataUpdateFailed"
                ]
            )
        }
    }

    private static func clearMetadata(attachmentID: String, store: MessengerLocalStore) async {
        do {
            try await store.clearAttachmentMediaCacheMetadata(attachmentID: attachmentID)
        } catch {
            // Best effort.
        }
    }

    private static func fetchReferencedAttachmentIDs(store: MessengerLocalStore) async -> Set<String> {
        (try? await store.fetchAttachmentLocalCacheKeys()) ?? []
    }

    private static func enforceQuotaIfNeeded(store: MessengerLocalStore) async {
        let totalBytes = await diskCache.totalCachedBytes()
        let policy = MessengerMediaCacheCleanupPolicy.default
        guard totalBytes > policy.maxBytes else { return }
        let referencedKeys = await fetchReferencedAttachmentIDs(store: store)
        await diskCache.cleanup(policy: policy, referencedAttachmentIDs: referencedKeys)
    }

    private static func sanitizedAttachmentIDForDiagnostics(_ attachmentID: String) -> String {
        if let uuid = UUID(uuidString: attachmentID) {
            return MessengerDiagnostics.sanitizeID(uuid)
        }
        let trimmed = attachmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return String(trimmed.prefix(8)) + "..."
    }
}

private struct SendableMessengerMediaImage: @unchecked Sendable {
    let image: UIImage
}
