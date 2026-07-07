import Foundation

protocol MessengerMediaDiskCacheProtocol: Sendable {
    func cachedImageData(for attachmentID: String, variant: MessengerMediaVariant) async throws -> Data?
    func storeImageData(_ data: Data, attachmentID: String, variant: MessengerMediaVariant) async throws
    func removeMedia(for attachmentID: String) async
    func cleanup(
        policy: MessengerMediaCacheCleanupPolicy,
        referencedAttachmentIDs: Set<String>
    ) async
    func clearAll() async
    func totalCachedBytes() async -> Int64
}

enum MessengerMediaDiskCacheError: Error, Equatable {
    case invalidAttachmentID
    case unsupportedPendingAttachment
    case directoryCreationFailed
    case writeFailed
    case readFailed
}
