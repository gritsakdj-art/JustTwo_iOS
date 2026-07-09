import Foundation

struct MessengerPendingMediaSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let pendingMediaID: String
    let clientMessageID: String
    let conversationID: String
    let localRelativePath: String
    let contentType: String
    let byteSize: Int
    let width: Int?
    let height: Int?
    let createdAt: Date
    let updatedAt: Date
}

enum MessengerPendingMediaStoreError: Error, Equatable {
    case invalidIdentifier
    case directoryCreationFailed
    case writeFailed
    case readFailed
    case fileMissing
}

enum MessengerPendingMediaStore {

    nonisolated static let directoryName = "MessengerPendingMedia"

    nonisolated static func storeJPEG(
        data: Data,
        pendingMediaID: String,
        clientMessageID: String
    ) throws -> String {
        let relativePath = try relativePath(for: pendingMediaID, clientMessageID: clientMessageID)
        let fileURL = try fileURL(forRelativePath: relativePath)
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try excludeFromBackup(directory)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try data.write(to: fileURL, options: [.atomic])
            try applyFileProtection(to: fileURL)
        } catch {
            throw MessengerPendingMediaStoreError.writeFailed
        }
        return relativePath
    }

    nonisolated static func preparedImage(
        relativePath: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int
    ) throws -> PreparedChatImage {
        let fileURL = try fileURL(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MessengerPendingMediaStoreError.fileMissing
        }
        return PreparedChatImage(
            localFileURL: fileURL,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height
        )
    }

    nonisolated static func delete(relativePath: String) {
        guard let fileURL = try? fileURL(forRelativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    nonisolated static func clearAll() {
        guard let directory = try? rootDirectoryURL() else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated static func pruneOrphans(validRelativePaths: Set<String>) -> Int {
        guard let directory = try? rootDirectoryURL(),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }

        var removedCount = 0
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let relative = relativePath(from: fileURL)
            guard !validRelativePaths.contains(relative) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
            removedCount += 1
        }
        return removedCount
    }

    nonisolated static func makeRelativePath(
        pendingMediaID: String,
        clientMessageID: String
    ) throws -> String {
        try relativePath(for: pendingMediaID, clientMessageID: clientMessageID)
    }

    nonisolated static func sanitizedPendingMediaIDForDiagnostics(_ pendingMediaID: String) -> String {
        let trimmed = pendingMediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return String(trimmed.prefix(8)) + "..."
    }

    private nonisolated static func relativePath(for pendingMediaID: String, clientMessageID: String) throws -> String {
        let safeMediaID = try sanitizedFileComponent(pendingMediaID)
        let safeClientID = try sanitizedFileComponent(clientMessageID)
        return "\(safeMediaID)/\(safeClientID).jpg"
    }

    private nonisolated static func fileURL(forRelativePath relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count == 2, components[1].hasSuffix(".jpg") else {
            throw MessengerPendingMediaStoreError.invalidIdentifier
        }
        let safeMediaID = try sanitizedFileComponent(components[0])
        let clientFileStem = String(components[1].dropLast(4))
        let safeClientID = try sanitizedFileComponent(clientFileStem)
        return try rootDirectoryURL()
            .appendingPathComponent(safeMediaID)
            .appendingPathComponent("\(safeClientID).jpg")
    }

    private nonisolated static func relativePath(from fileURL: URL) -> String {
        guard let root = try? rootDirectoryURL().standardizedFileURL.path,
              fileURL.standardizedFileURL.path.hasPrefix(root) else {
            return fileURL.lastPathComponent
        }
        let suffix = String(fileURL.standardizedFileURL.path.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = suffix.split(separator: "/")
        guard components.count >= 2 else { return suffix }
        return "\(components[components.count - 2])/\(components[components.count - 1])"
    }

    private nonisolated static func rootDirectoryURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("JustTwo", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private nonisolated static func sanitizedFileComponent(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(".."), !trimmed.contains("/") else {
            throw MessengerPendingMediaStoreError.invalidIdentifier
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw MessengerPendingMediaStoreError.invalidIdentifier
        }
        return trimmed
    }

    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    private nonisolated static func applyFileProtection(to url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
}
