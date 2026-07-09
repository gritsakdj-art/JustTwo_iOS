import Foundation
import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct PreparedChatImage: Equatable, Sendable {
    let localFileURL: URL
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
}

enum ChatImagePreparationError: LocalizedError, Equatable {
    case loadFailed
    case invalidImage
    case encodingFailed
    case fileTooLarge(Int)
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed, .invalidImage, .encodingFailed, .fileWriteFailed:
            return String(localized: "chats.image.error.prepare_failed")
        case .fileTooLarge:
            return String(localized: "chats.image.error.too_large")
        }
    }
}

enum ChatImagePreparer {
    private nonisolated static let maxDimension: CGFloat = 1_600
    private nonisolated static let jpegQuality: CGFloat = 0.80

    static func prepare(_ item: PhotosPickerItem, clientMessageID: String) async throws -> PreparedChatImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ChatImagePreparationError.loadFailed
        }
        return try await Task.detached(priority: .userInitiated) {
            try prepare(data: data, clientMessageID: clientMessageID)
        }.value
    }

    nonisolated static func prepare(data: Data, clientMessageID: String) throws -> PreparedChatImage {
        let jpegData = try encodedJPEGData(from: data)
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent(safeFileName(for: clientMessageID)).appendingPathExtension("jpg")
        try writeJPEG(jpegData, to: fileURL)
        return try preparedImage(from: jpegData, fileURL: fileURL)
    }

    static func preparePersistent(
        _ item: PhotosPickerItem,
        clientMessageID: String,
        pendingMediaID: String
    ) async throws -> PreparedChatImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ChatImagePreparationError.loadFailed
        }
        return try await Task.detached(priority: .userInitiated) {
            try preparePersistent(data: data, clientMessageID: clientMessageID, pendingMediaID: pendingMediaID)
        }.value
    }

    nonisolated static func preparePersistent(
        data: Data,
        clientMessageID: String,
        pendingMediaID: String
    ) throws -> PreparedChatImage {
        let jpegData = try encodedJPEGData(from: data)
        let relativePath = try MessengerPendingMediaStore.storeJPEG(
            data: jpegData,
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID
        )
        return try MessengerPendingMediaStore.preparedImage(
            relativePath: relativePath,
            contentType: "image/jpeg",
            byteSize: jpegData.count,
            width: imageDimensions(from: jpegData).width,
            height: imageDimensions(from: jpegData).height
        )
    }

    nonisolated static func preparedFromPendingMedia(_ snapshot: MessengerPendingMediaSnapshot) throws -> PreparedChatImage {
        try MessengerPendingMediaStore.preparedImage(
            relativePath: snapshot.localRelativePath,
            contentType: snapshot.contentType,
            byteSize: snapshot.byteSize,
            width: snapshot.width ?? 0,
            height: snapshot.height ?? 0
        )
    }

    #if canImport(UIKit)
    static func loadPreviewImage(from item: PhotosPickerItem) async throws -> UIImage {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            throw ChatImagePreparationError.loadFailed
        }
        return image
    }
    #endif

    nonisolated static func removeTemporaryFile(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    nonisolated static func cleanupTemporaryDirectory() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL())
    }

    private nonisolated static func temporaryDirectory() throws -> URL {
        let directory = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private nonisolated static func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("justtwo-chat-images", isDirectory: true)
    }

    private nonisolated static func safeFileName(for clientMessageID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let characters = clientMessageID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let result = String(characters)
        return result.isEmpty ? UUID().uuidString : result
    }

    #if canImport(UIKit)
    private nonisolated static func encodedJPEGData(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ChatImagePreparationError.invalidImage
        }

        let rendered = normalizedAndResized(image)
        guard let jpegData = rendered.jpegData(compressionQuality: jpegQuality) else {
            throw ChatImagePreparationError.encodingFailed
        }
        guard jpegData.count <= MessengerLimits.maxImageBytes else {
            throw ChatImagePreparationError.fileTooLarge(jpegData.count)
        }
        return jpegData
    }

    private nonisolated static func writeJPEG(_ jpegData: Data, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        do {
            try jpegData.write(to: fileURL, options: [.atomic])
        } catch {
            throw ChatImagePreparationError.fileWriteFailed
        }
    }

    private nonisolated static func preparedImage(from jpegData: Data, fileURL: URL) throws -> PreparedChatImage {
        let dimensions = imageDimensions(from: jpegData)
        return PreparedChatImage(
            localFileURL: fileURL,
            contentType: "image/jpeg",
            byteSize: jpegData.count,
            width: dimensions.width,
            height: dimensions.height
        )
    }

    private nonisolated static func imageDimensions(from jpegData: Data) -> (width: Int, height: Int) {
        guard let image = UIImage(data: jpegData) else {
            return (0, 0)
        }
        let rendered = normalizedAndResized(image)
        return (
            width: Int(rendered.size.width.rounded()),
            height: Int(rendered.size.height.rounded())
        )
    }

    private nonisolated static func normalizedAndResized(_ image: UIImage) -> UIImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif
}
