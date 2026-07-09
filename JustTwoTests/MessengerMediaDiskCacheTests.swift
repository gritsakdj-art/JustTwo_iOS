import Foundation
import Testing
import UIKit
@testable import JustTwo

@Suite(.serialized)
struct MessengerMediaDiskCacheTests {

    private let attachmentID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
    private let otherAttachmentID = "ffffffff-ffff-ffff-ffff-ffffffffffff"

    @Test
    func storesAndReadsImageDataByAttachmentIDAndVariant() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())

        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)
        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)

        #expect(loaded == data)
    }

    @Test
    func missingAttachmentReturnsNil() async throws {
        let cache = makeCache()
        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .full)
        #expect(loaded == nil)
    }

    @Test
    func sanitizedAttachmentIDCannotEscapeCacheDirectory() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())

        await #expect(throws: MessengerMediaDiskCacheError.self) {
            try await cache.storeImageData(data, attachmentID: "../escape", variant: .thumbnail)
        }

        await #expect(throws: MessengerMediaDiskCacheError.self) {
            try await cache.storeImageData(data, attachmentID: "local-pending", variant: .thumbnail)
        }

        let root = try #require(MessengerMediaDiskCache.testingRootURL)
        let escaped = root.appendingPathComponent("escape", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
    }

    @Test
    func removeMediaDeletesFiles() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .full)

        await cache.removeMedia(for: attachmentID)

        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .full)
        #expect(loaded == nil)
    }

    @Test
    func corruptedFileHandledGracefully() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)

        let fileURL = expectedFileURL(for: attachmentID, variant: .thumbnail)
        try Data([0x00, 0x01, 0x02]).write(to: fileURL)

        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        #expect(loaded?.count == 3)
    }

    @Test
    func cacheDirectoryExcludedFromBackupAndProtected() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)

        let fileURL = expectedFileURL(for: attachmentID, variant: .thumbnail)
        let directoryURL = fileURL.deletingLastPathComponent()

        let fileValues = try fileURL.resourceValues(forKeys: [
            .isExcludedFromBackupKey,
            .fileProtectionKey
        ])
        let directoryValues = try directoryURL.resourceValues(forKeys: [
            .isExcludedFromBackupKey,
            .fileProtectionKey
        ])

        #expect(fileValues.isExcludedFromBackup == true)
        #expect(fileValues.fileProtection == .completeUntilFirstUserAuthentication)
        #expect(directoryValues.isExcludedFromBackup == true)
    }

    @Test
    @MainActor
    func metadataUpdatesOnStoreAndAccess() async throws {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        let cache = makeCache()
        MessengerMediaCacheService.testingDiskCache = cache
        MessengerMediaCacheService.testingLocalStore = store
        MessengerMessageCacheService.testingStore = store
        defer {
            MessengerMediaCacheService.testingDiskCache = nil
            MessengerMediaCacheService.testingLocalStore = nil
            MessengerMessageCacheService.testingStore = nil
        }

        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let attachmentUUID = UUID(uuidString: attachmentID)!

        let dto = makeImageMessageDTO(
            conversationID: conversationID,
            messageID: messageID,
            attachmentID: attachmentUUID
        )
        try await store.upsertMessages([dto], conversationID: conversationID)

        let data = try #require(makeJPEGData())
        await MessengerMediaCacheService.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail, store: store)
        await MessengerMediaCacheService.storeImageData(data, attachmentID: attachmentID, variant: .full, store: store)

        let snapshot = try #require(
            try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first
        )
        let attachment = try #require(snapshot.attachments.first)
        #expect(attachment.hasLocalThumbnail)
        #expect(attachment.hasLocalFullImage)
        #expect(attachment.localThumbnailByteSize == data.count)
        #expect(attachment.localFullByteSize == data.count)
        #expect(attachment.mediaCachedAt != nil)
        #expect(attachment.mediaLastAccessedAt != nil)

        let encoded = String(describing: attachment)
        #expect(!encoded.contains("downloadUrl"))
        #expect(!encoded.contains("uploadUrl"))
        #expect(!encoded.contains("/Users/"))
    }

    @Test
    @MainActor
    func deletedMessageClearsMetadataAndDiskCache() async throws {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        let cache = makeCache()
        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let attachmentUUID = UUID(uuidString: attachmentID)!

        MessengerMediaCacheService.testingDiskCache = cache
        MessengerMediaCacheService.testingLocalStore = store
        MessengerMessageCacheService.testingStore = store
        defer {
            MessengerMediaCacheService.testingDiskCache = nil
            MessengerMediaCacheService.testingLocalStore = nil
            MessengerMessageCacheService.testingStore = nil
        }

        try await store.upsertMessages(
            [makeImageMessageDTO(conversationID: conversationID, messageID: messageID, attachmentID: attachmentUUID)],
            conversationID: conversationID
        )
        await MessengerMediaCacheService.storeImageData(
            try #require(makeJPEGData()),
            attachmentID: attachmentID,
            variant: .thumbnail,
            store: store
        )

        try await store.markMessageDeleted(messageID: messageID, deletedAt: Date())

        let snapshot = try #require(
            try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first
        )
        #expect(snapshot.attachments.isEmpty)

        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        #expect(loaded == nil)
    }

    @Test
    func cachedImageSnapshotMapsToDiskCacheRenderSource() {
        let profileID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        let attachmentSnapshot = LocalAttachmentSnapshot(
            id: attachmentID,
            messageID: messageID.uuidString,
            conversationID: conversationID.uuidString,
            kind: MessageKind.image.rawValue,
            contentType: "image/jpeg",
            byteSize: 1_200,
            width: 800,
            height: 600,
            createdAt: Date(),
            localCacheKey: attachmentID,
            downloadURLExpiresAt: nil,
            hasLocalThumbnail: true,
            hasLocalFullImage: false,
            localThumbnailByteSize: 841,
            localFullByteSize: nil,
            mediaCachedAt: Date(),
            mediaLastAccessedAt: Date(),
            localUpdatedAt: Date()
        )

        let messageSnapshot = LocalMessageSnapshot(
            id: messageID.uuidString,
            conversationID: conversationID.uuidString,
            clientMessageID: nil,
            senderProfileID: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            kind: MessageKind.image.rawValue,
            body: nil,
            createdAt: Date(),
            editedAt: nil,
            deletedAt: nil,
            deliveryStatus: MessageDeliveryStatus.sent.rawValue,
            replyToMessageID: nil,
            replyToBody: nil,
            replyToSenderProfileID: nil,
            localState: .serverConfirmed,
            localCreatedAt: Date(),
            localUpdatedAt: Date(),
            attachments: [attachmentSnapshot],
            reactions: []
        )

        let mapped = ChatUIMapping.message(from: messageSnapshot, currentProfileID: profileID)

        #expect(mapped.imageAttachment?.downloadURL == nil)
        #expect(mapped.imageAttachment?.hasLocalDiskThumbnail == true)
        #expect(mapped.imageRenderSource == .diskCache(attachmentID: attachmentID))
    }

    @Test
    func storeWithMixedCaseAttachmentIDReadsWithLowercase() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        let mixedCaseID = "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"

        try await cache.storeImageData(data, attachmentID: mixedCaseID, variant: .thumbnail)

        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        #expect(loaded == data)
        #expect(FileManager.default.fileExists(atPath: expectedFileURL(for: attachmentID, variant: .thumbnail).path))
    }

    @Test
    func removeMediaWithUppercaseRemovesLowercaseCache() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)

        await cache.removeMedia(for: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")

        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        #expect(loaded == nil)
    }

    @Test
    func cleanupKeepsReferencedFileWhenReferenceUsesUppercase() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)
        try await cache.storeImageData(data, attachmentID: otherAttachmentID, variant: .thumbnail)

        let policy = MessengerMediaCacheCleanupPolicy(
            maxBytes: 50_000,
            targetBytesAfterCleanup: 40_000,
            maxAgeDays: 90
        )

        await cache.cleanup(
            policy: policy,
            referencedAttachmentIDs: ["EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"]
        )

        let kept = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        let removed = try await cache.cachedImageData(for: otherAttachmentID, variant: .thumbnail)
        #expect(kept != nil)
        #expect(removed == nil)
    }

    @Test
    func viewerFallsBackToThumbnailWhenFullMissing() async throws {
        let cache = makeCache()
        MessengerMediaCacheService.testingDiskCache = cache
        defer { MessengerMediaCacheService.testingDiskCache = nil }

        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)

        let image = await MessengerMediaCacheService.loadViewerImage(attachmentID: attachmentID)
        #expect(image != nil)
    }

    @Test
    @MainActor
    func restReupsertPreservesMediaCacheMetadata() async throws {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        let cache = makeCache()
        MessengerMediaCacheService.testingDiskCache = cache
        MessengerMediaCacheService.testingLocalStore = store
        defer {
            MessengerMediaCacheService.testingDiskCache = nil
            MessengerMediaCacheService.testingLocalStore = nil
        }

        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let attachmentUUID = UUID(uuidString: attachmentID)!
        let dto = makeImageMessageDTO(
            conversationID: conversationID,
            messageID: messageID,
            attachmentID: attachmentUUID
        )

        try await store.upsertMessages([dto], conversationID: conversationID)
        let data = try #require(makeJPEGData())
        await MessengerMediaCacheService.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail, store: store)
        await MessengerMediaCacheService.storeImageData(data, attachmentID: attachmentID, variant: .full, store: store)

        try await store.upsertMessages([dto], conversationID: conversationID)

        let attachment = try #require(
            try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).first?
                .attachments.first
        )
        #expect(attachment.hasLocalThumbnail)
        #expect(attachment.hasLocalFullImage)
        #expect(attachment.mediaCachedAt != nil)
    }

    @Test
    @MainActor
    func deleteWithUppercaseAttachmentIDRemovesLowercaseDiskCache() async throws {
        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        let cache = makeCache()
        MessengerMediaCacheService.testingDiskCache = cache
        MessengerMediaCacheService.testingLocalStore = store
        defer {
            MessengerMediaCacheService.testingDiskCache = nil
            MessengerMediaCacheService.testingLocalStore = nil
        }

        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let attachmentUUID = UUID(uuidString: attachmentID)!

        try await store.upsertMessages(
            [makeImageMessageDTO(conversationID: conversationID, messageID: messageID, attachmentID: attachmentUUID)],
            conversationID: conversationID
        )
        await MessengerMediaCacheService.storeImageData(
            try #require(makeJPEGData()),
            attachmentID: attachmentID,
            variant: .thumbnail,
            store: store
        )

        await MessengerMediaCacheService.removeMedia(attachmentID: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")

        let loaded = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        #expect(loaded == nil)
    }

    @Test
    func deletedImageSnapshotDoesNotExposeDiskRenderSource() {
        let profileID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        let snapshot = LocalMessageSnapshot(
            id: messageID.uuidString,
            conversationID: conversationID.uuidString,
            clientMessageID: nil,
            senderProfileID: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            kind: MessageKind.image.rawValue,
            body: nil,
            createdAt: Date(),
            editedAt: nil,
            deletedAt: Date(),
            deliveryStatus: nil,
            replyToMessageID: nil,
            replyToBody: nil,
            replyToSenderProfileID: nil,
            localState: .deleted,
            localCreatedAt: Date(),
            localUpdatedAt: Date(),
            attachments: [],
            reactions: []
        )

        let mapped = ChatUIMapping.message(from: snapshot, currentProfileID: profileID)
        #expect(mapped.isDeleted)
        #expect(mapped.imageAttachment == nil)
        #expect(mapped.imageRenderSource == nil)
    }

    @Test
    func cachedAttachmentWithoutDiskFlagsHasNoDiskRenderSource() {
        let snapshot = LocalAttachmentSnapshot(
            id: attachmentID,
            messageID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            conversationID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            kind: MessageKind.image.rawValue,
            contentType: "image/jpeg",
            byteSize: 1_200,
            width: 800,
            height: 600,
            createdAt: Date(),
            localCacheKey: attachmentID,
            downloadURLExpiresAt: nil,
            hasLocalThumbnail: false,
            hasLocalFullImage: false,
            localThumbnailByteSize: nil,
            localFullByteSize: nil,
            mediaCachedAt: nil,
            mediaLastAccessedAt: nil,
            localUpdatedAt: Date()
        )

        let attachment = ChatMessageAttachment.cached(snapshot)
        #expect(attachment.downloadURL == nil)
        #expect(attachment.hasLocalDiskCache == false)

        let message = ChatMessage(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            kind: .image,
            displayText: "Photo",
            rawBody: nil,
            imageAttachment: attachment,
            createdAt: Date(),
            isMine: false,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )
        #expect(message.imageRenderSource == nil)
    }

    @Test
    func diskCacheHitAllowsBubbleRenderWithoutDownloadURL() async throws {
        let cache = makeCache()
        MessengerMediaCacheService.testingDiskCache = cache
        defer { MessengerMediaCacheService.testingDiskCache = nil }

        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)

        let image = await MessengerMediaCacheService.loadBubbleImage(attachmentID: attachmentID)
        #expect(image != nil)
    }

    @Test
    func cleanupRemovesOrphansAndHonorsQuota() async throws {
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)
        try await cache.storeImageData(data, attachmentID: otherAttachmentID, variant: .thumbnail)

        let policy = MessengerMediaCacheCleanupPolicy(
            maxBytes: 50_000,
            targetBytesAfterCleanup: 40_000,
            maxAgeDays: 90
        )

        await cache.cleanup(policy: policy, referencedAttachmentIDs: [attachmentID])

        let kept = try await cache.cachedImageData(for: attachmentID, variant: .thumbnail)
        let removed = try await cache.cachedImageData(for: otherAttachmentID, variant: .thumbnail)
        #expect(kept != nil)
        #expect(removed == nil)
    }

    @Test
    @MainActor
    func diagnosticsExportDoesNotLeakSensitiveMediaMetadata() async throws {
        MessengerDiagnosticsStore.shared.clear()
        let cache = makeCache()
        let data = try #require(makeJPEGData())
        try await cache.storeImageData(
            data,
            attachmentID: attachmentID,
            variant: .thumbnail
        )

        let export = (await MessengerDiagnostics.exportTextForClipboard()).lowercased()
        #expect(!export.contains("x-amz-signature"))
        #expect(!export.contains("downloadurl"))
        #expect(!export.contains("uploadurl"))
        #expect(!export.contains("bearer"))
        #expect(!export.contains("authorization"))
        #expect(!export.contains("jwt"))
        #expect(!export.contains("storagekey"))
        #expect(!export.contains("/users/"))
    }
}

// MARK: - Fixtures

private extension MessengerMediaDiskCacheTests {
    func makeCache() -> MessengerMediaDiskCache {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("justtwo-media-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        MessengerMediaDiskCache.testingRootURL = root
        return MessengerMediaDiskCache()
    }

    func expectedFileURL(for attachmentID: String, variant: MessengerMediaVariant) -> URL {
        let root = MessengerMediaDiskCache.testingRootURL!
        return root
            .appendingPathComponent("JustTwo", isDirectory: true)
            .appendingPathComponent("MediaCache", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(attachmentID, isDirectory: true)
            .appendingPathComponent(variant.fileName, isDirectory: false)
    }

    func makeJPEGData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    func makeImageMessageDTO(
        conversationID: UUID,
        messageID: UUID,
        attachmentID: UUID,
        deleted: Bool = false
    ) -> MessageDTO {
        let deletedAt = deleted ? "2026-07-02T13:45:00Z" : "null"
        let body = deleted ? "null" : "null"
        return try! JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(messageID.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "cccccccc-cccc-cccc-cccc-cccccccccccc",
          "kind": "image",
          "body": \(body),
          "createdAt": "2026-07-02T13:00:00Z",
          "editedAt": null,
          "deletedAt": \(deletedAt),
          "deliveryStatus": "sent",
          "clientMessageID": null,
          "replyTo": null,
          "reactions": [],
          "attachments": [
            {
              "id": "\(attachmentID.uuidString)",
              "contentType": "image/jpeg",
              "byteSize": 1200,
              "width": 800,
              "height": 600,
              "downloadUrl": "https://storage.test/photo.jpg?X-Amz-Signature=secret",
              "downloadUrlExpiresAt": "2026-07-02T14:00:00Z"
            }
          ]
        }
        """.utf8))
    }
}
