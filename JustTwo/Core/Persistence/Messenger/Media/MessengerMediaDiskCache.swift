import Foundation

private enum MessengerMediaDiskCacheSupport {
    nonisolated static func sanitizeAttachmentID(_ attachmentID: String) throws -> String {
        let trimmed = attachmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MessengerMediaDiskCacheError.invalidAttachmentID }
        guard !trimmed.hasPrefix("local-") else { throw MessengerMediaDiskCacheError.unsupportedPendingAttachment }
        guard !trimmed.contains("..") else { throw MessengerMediaDiskCacheError.invalidAttachmentID }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw MessengerMediaDiskCacheError.invalidAttachmentID
        }

        return trimmed.lowercased()
    }

    nonisolated static func lookupMetadata(
        attachmentID: String,
        variant: MessengerMediaVariant? = nil,
        byteSize: Int? = nil,
        reason: String? = nil,
        durationMs: Date? = nil,
        cacheHit: Bool? = nil
    ) -> [String: String] {
        var metadata: [String: String] = [
            "attachmentID": sanitizedAttachmentIDForDiagnostics(attachmentID)
        ]
        if let variant {
            metadata["variant"] = variant.rawValue
        }
        if let byteSize {
            metadata["byteSize"] = "\(byteSize)"
        }
        if let reason {
            metadata["reason"] = reason
        }
        if let durationMs {
            metadata["durationMs"] = "\(durationMilliseconds(since: durationMs))"
        }
        if let cacheHit {
            metadata["cacheHit"] = cacheHit ? "true" : "false"
        }
        return metadata
    }

    nonisolated static func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }

    nonisolated static func sanitizedAttachmentIDForDiagnostics(_ attachmentID: String) -> String {
        if let uuid = UUID(uuidString: attachmentID) {
            return MessengerDiagnostics.sanitizeID(uuid)
        }
        let trimmed = attachmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return String(trimmed.prefix(8)) + "..."
    }

    nonisolated static func sanitizedErrorCategory(_ error: Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }
        if let cacheError = error as? MessengerMediaDiskCacheError {
            switch cacheError {
            case .invalidAttachmentID, .unsupportedPendingAttachment:
                return "invalidAttachmentID"
            case .directoryCreationFailed, .writeFailed, .readFailed:
                return "io"
            }
        }
        return "unknown"
    }
}

final class MessengerMediaDiskCache: MessengerMediaDiskCacheProtocol, @unchecked Sendable {

    static let shared = MessengerMediaDiskCache()

    #if DEBUG
    nonisolated(unsafe) static var testingRootURL: URL?
    #endif

    private let fileManager: FileManager
    private let cacheFolderName = "MediaCache"
    private let attachmentsFolderName = "attachments"
    private let queue = DispatchQueue(label: "io.justtwo.media-disk-cache", qos: .utility)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func cachedImageData(for attachmentID: String, variant: MessengerMediaVariant) async throws -> Data? {
        try await runOnQueue {
            try self.cachedImageDataSync(for: attachmentID, variant: variant)
        }
    }

    func storeImageData(
        _ data: Data,
        attachmentID: String,
        variant: MessengerMediaVariant
    ) async throws {
        try await runOnQueue {
            try self.storeImageDataSync(data, attachmentID: attachmentID, variant: variant)
        }
    }

    func removeMedia(for attachmentID: String) async {
        await runOnQueue {
            self.removeMediaSync(for: attachmentID)
        }
    }

    func cleanup(
        policy: MessengerMediaCacheCleanupPolicy,
        referencedAttachmentIDs: Set<String>
    ) async {
        await runOnQueue {
            self.cleanupSync(policy: policy, referencedAttachmentIDs: referencedAttachmentIDs)
        }
    }

    func clearAll() async {
        await runOnQueue {
            self.clearAllSync()
        }
    }

    func totalCachedBytes() async -> Int64 {
        await runOnQueue {
            self.totalCachedBytesSync()
        }
    }

    // MARK: - Sync implementations

    private func cachedImageDataSync(
        for attachmentID: String,
        variant: MessengerMediaVariant
    ) throws -> Data? {
        let startedAt = Date()
        let sanitized = try MessengerMediaDiskCacheSupport.sanitizeAttachmentID(attachmentID)

        MessengerDiagnostics.event(
            .messengerMediaDiskCacheLookupStarted,
            metadata: MessengerMediaDiskCacheSupport.lookupMetadata(attachmentID: sanitized, variant: variant)
        )

        let fileURL = fileURL(for: sanitized, variant: variant)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheMiss,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                    attachmentID: sanitized,
                    variant: variant,
                    durationMs: startedAt
                )
            )
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheHit,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                    attachmentID: sanitized,
                    variant: variant,
                    byteSize: data.count,
                    durationMs: startedAt,
                    cacheHit: true
                )
            )
            return data
        } catch {
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheReadFailed,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                    attachmentID: sanitized,
                    variant: variant,
                    reason: MessengerMediaDiskCacheSupport.sanitizedErrorCategory(error),
                    durationMs: startedAt
                )
            )
            return nil
        }
    }

    private func storeImageDataSync(
        _ data: Data,
        attachmentID: String,
        variant: MessengerMediaVariant
    ) throws {
        let startedAt = Date()
        let sanitized = try MessengerMediaDiskCacheSupport.sanitizeAttachmentID(attachmentID)

        MessengerDiagnostics.event(
            .messengerMediaDiskCacheStoreStarted,
            metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                attachmentID: sanitized,
                variant: variant,
                byteSize: data.count
            )
        )

        let directory = attachmentDirectory(for: sanitized)
        do {
            try ensureDirectoryExists(at: directory)
            let fileURL = fileURL(for: sanitized, variant: variant)
            try data.write(to: fileURL, options: [.atomic])
            try applyFileProtectionAndBackupExclusion(to: fileURL)
            try applyFileProtectionAndBackupExclusion(to: directory)

            MessengerDiagnostics.event(
                .messengerMediaDiskCacheStoreSucceeded,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                    attachmentID: sanitized,
                    variant: variant,
                    byteSize: data.count,
                    durationMs: startedAt
                )
            )
        } catch {
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheStoreFailed,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                    attachmentID: sanitized,
                    variant: variant,
                    reason: MessengerMediaDiskCacheSupport.sanitizedErrorCategory(error),
                    durationMs: startedAt
                )
            )
            throw MessengerMediaDiskCacheError.writeFailed
        }
    }

    private func removeMediaSync(for attachmentID: String) {
        guard let sanitized = try? MessengerMediaDiskCacheSupport.sanitizeAttachmentID(attachmentID) else { return }
        let directory = attachmentDirectory(for: sanitized)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        do {
            try fileManager.removeItem(at: directory)
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheRemoved,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(attachmentID: sanitized, reason: "delete")
            )
        } catch {
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheStoreFailed,
                metadata: MessengerMediaDiskCacheSupport.lookupMetadata(
                    attachmentID: sanitized,
                    reason: MessengerMediaDiskCacheSupport.sanitizedErrorCategory(error)
                )
            )
        }
    }

    private func cleanupSync(
        policy: MessengerMediaCacheCleanupPolicy,
        referencedAttachmentIDs: Set<String>
    ) {
        let startedAt = Date()
        MessengerDiagnostics.event(
            .messengerMediaDiskCacheCleanupStarted,
            metadata: ["maxBytes": "\(policy.maxBytes)"]
        )

        let referenced = Set(
            referencedAttachmentIDs.compactMap { try? MessengerMediaDiskCacheSupport.sanitizeAttachmentID($0) }
        )
        let cutoff = Calendar.current.date(byAdding: .day, value: -policy.maxAgeDays, to: Date())

        var entries = (try? allCacheEntriesSync()) ?? []
        var removedCount = 0

        for entry in entries where !referenced.contains(entry.attachmentID) {
            try? fileManager.removeItem(at: entry.directoryURL)
            removedCount += 1
        }

        entries = (try? allCacheEntriesSync()) ?? []

        if let cutoff {
            for entry in entries where entry.lastModified < cutoff {
                try? fileManager.removeItem(at: entry.directoryURL)
                removedCount += 1
            }
        }

        entries = (try? allCacheEntriesSync()) ?? []
        var totalBytes = entries.reduce(Int64(0)) { $0 + $1.byteSize }

        if totalBytes > policy.maxBytes {
            let sorted = entries.sorted { $0.lastModified < $1.lastModified }
            for entry in sorted where totalBytes > policy.targetBytesAfterCleanup {
                try? fileManager.removeItem(at: entry.directoryURL)
                totalBytes -= entry.byteSize
                removedCount += 1
            }
        }

        MessengerDiagnostics.event(
            .messengerMediaDiskCacheCleanupSucceeded,
            metadata: [
                "removedCount": "\(removedCount)",
                "totalBytes": "\(max(0, totalBytes))",
                "durationMs": "\(MessengerMediaDiskCacheSupport.durationMilliseconds(since: startedAt))"
            ]
        )
    }

    private func clearAllSync() {
        let root = attachmentsRootURL
        if fileManager.fileExists(atPath: root.path) {
            try? fileManager.removeItem(at: root)
        }
    }

    private func totalCachedBytesSync() -> Int64 {
        let entries = (try? allCacheEntriesSync()) ?? []
        return entries.reduce(0) { $0 + $1.byteSize }
    }

    // MARK: - Paths

    private var applicationSupportRoot: URL {
        #if DEBUG
        if let testingRootURL = Self.testingRootURL {
            return testingRootURL
        }
        #endif

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    private var cacheRootURL: URL {
        applicationSupportRoot
            .appendingPathComponent("JustTwo", isDirectory: true)
            .appendingPathComponent(cacheFolderName, isDirectory: true)
    }

    private var attachmentsRootURL: URL {
        cacheRootURL.appendingPathComponent(attachmentsFolderName, isDirectory: true)
    }

    private func attachmentDirectory(for sanitizedAttachmentID: String) -> URL {
        attachmentsRootURL.appendingPathComponent(sanitizedAttachmentID, isDirectory: true)
    }

    private func fileURL(for sanitizedAttachmentID: String, variant: MessengerMediaVariant) -> URL {
        attachmentDirectory(for: sanitizedAttachmentID).appendingPathComponent(variant.fileName, isDirectory: false)
    }

    // MARK: - Helpers

    private struct CacheEntry {
        let attachmentID: String
        let directoryURL: URL
        let byteSize: Int64
        let lastModified: Date
    }

    private func allCacheEntriesSync() throws -> [CacheEntry] {
        let root = attachmentsRootURL
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories.compactMap { directoryURL in
            guard (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }

            let attachmentID = directoryURL.lastPathComponent
            guard (try? MessengerMediaDiskCacheSupport.sanitizeAttachmentID(attachmentID)) != nil else { return nil }

            let files = (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let imageFiles = files.filter {
                let name = $0.lastPathComponent.lowercased()
                return name == MessengerMediaVariant.thumbnail.fileName
                    || name == MessengerMediaVariant.full.fileName
            }

            guard !imageFiles.isEmpty else { return nil }

            let byteSize = imageFiles.reduce(Int64(0)) { partial, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return partial + Int64(size)
            }

            let lastModified = imageFiles.compactMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }.max() ?? .distantPast

            return CacheEntry(
                attachmentID: attachmentID,
                directoryURL: directoryURL,
                byteSize: byteSize,
                lastModified: lastModified
            )
        }
    }

    private func ensureDirectoryExists(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func applyFileProtectionAndBackupExclusion(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)

        MessengerDiagnostics.event(
            .messengerMediaDiskCacheFileProtectionApplied,
            metadata: ["cacheKey": relativeCacheKey(for: url)]
        )
        MessengerDiagnostics.event(
            .messengerMediaDiskCacheBackupExcluded,
            metadata: ["cacheKey": relativeCacheKey(for: url)]
        )
    }

    private func relativeCacheKey(for url: URL) -> String {
        let rootPath = cacheRootURL.path
        let path = url.path
        guard path.hasPrefix(rootPath) else {
            return "media-cache"
        }
        let suffix = path.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? "media-cache" : String(suffix.prefix(120))
    }

    private func runOnQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runOnQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func runOnQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
