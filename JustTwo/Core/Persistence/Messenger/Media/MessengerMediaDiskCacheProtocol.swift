import Foundation

protocol MessengerMediaDiskCacheProtocol: Sendable {
    func cachedImageData(for attachmentID: String, variant: MessengerMediaVariant) async throws -> Data?
    func storeImageData(_ data: Data, attachmentID: String, variant: MessengerMediaVariant) async throws
    func removeMedia(for attachmentID: String) async
    func cleanup(
        policy: MessengerMediaCacheCleanupPolicy,
        referencedAttachmentIDs: Set<String>
    ) async -> MessengerMediaCacheTrimResult
    func clearAll() async
    func totalCachedBytes() async -> Int64
    func hasCachedVariant(for attachmentID: String, variant: MessengerMediaVariant) async -> Bool
    func confirmedInventory(referencedAttachmentIDs: Set<String>) async -> (
        thumbnailBytes: Int64,
        fullBytes: Int64,
        thumbnailCount: Int,
        fullCount: Int,
        orphanBytes: Int64,
        orphanCount: Int,
        oldestAccess: Date?,
        newestAccess: Date?
    )
}

enum MessengerMediaDiskCacheError: Error, Equatable {
    case invalidAttachmentID
    case unsupportedPendingAttachment
    case directoryCreationFailed
    case writeFailed
    case readFailed
}
