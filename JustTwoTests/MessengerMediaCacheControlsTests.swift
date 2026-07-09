import Foundation
import Testing
@testable import JustTwo
#if canImport(UIKit)
import UIKit
#endif

@Suite(.serialized)
struct MessengerMediaCacheControlsTests {

    private let attachmentID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
    private let otherAttachmentID = "ffffffff-ffff-ffff-ffff-ffffffffffff"
    private let pendingMediaID = "pending-media-pr19"
    private let clientMessageID = "client-pr19-image"

    @Test
    @MainActor
    func inventoryCountsThumbnailAndFullBytesSeparately() async throws {
        let (cache, store) = try await makeHarness()
        defer { resetHarness() }

        let thumbData = try #require(makeJPEGData())
        let fullData = try #require(makeJPEGData(width: 120, height: 120))
        try await cache.storeImageData(thumbData, attachmentID: attachmentID, variant: .thumbnail)
        try await cache.storeImageData(fullData, attachmentID: attachmentID, variant: .full)
        try await seedAttachmentMetadata(store: store, attachmentID: attachmentID)

        let inventory = await MessengerMediaCacheControls.inventory(store: store)

        #expect(inventory.confirmedThumbnailBytes > 0)
        #expect(inventory.confirmedFullBytes > 0)
        #expect(inventory.confirmedThumbnailFileCount == 1)
        #expect(inventory.confirmedFullFileCount == 1)
        #expect(inventory.confirmedTotalBytes == inventory.confirmedThumbnailBytes + inventory.confirmedFullBytes)
    }

    @Test
    @MainActor
    func inventoryCountsPendingOutgoingBytesSeparately() async throws {
        let (cache, store) = try await makeHarness()
        defer { resetHarness() }

        let pendingData = try #require(makeJPEGData())
        let relativePath = try MessengerPendingMediaStore.storeJPEG(
            data: pendingData,
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID
        )
        _ = try await store.createImageOutboxItem(
            conversationID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            clientMessageID: clientMessageID,
            caption: nil,
            replyToMessageID: nil,
            pendingMediaID: pendingMediaID,
            localRelativePath: relativePath,
            contentType: "image/jpeg",
            byteSize: pendingData.count,
            width: 80,
            height: 80
        )

        let inventory = await MessengerMediaCacheControls.inventory(store: store)

        #expect(inventory.pendingOutgoingFileCount == 1)
        #expect(inventory.pendingOutgoingBytes > 0)
        #expect(inventory.totalMessengerMediaBytes >= inventory.pendingOutgoingBytes)
        _ = cache
    }

    @Test
    @MainActor
    func clearConfirmedCachePreservesPendingOutgoingMedia() async throws {
        let (cache, store) = try await makeHarness()
        defer { resetHarness() }

        let confirmedData = try #require(makeJPEGData())
        try await cache.storeImageData(confirmedData, attachmentID: attachmentID, variant: .thumbnail)
        try await seedAttachmentMetadata(store: store, attachmentID: attachmentID)

        let pendingData = try #require(makeJPEGData(width: 90, height: 90))
        let relativePath = try MessengerPendingMediaStore.storeJPEG(
            data: pendingData,
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID
        )
        _ = try await store.createImageOutboxItem(
            conversationID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            clientMessageID: clientMessageID,
            caption: nil,
            replyToMessageID: nil,
            pendingMediaID: pendingMediaID,
            localRelativePath: relativePath,
            contentType: "image/jpeg",
            byteSize: pendingData.count,
            width: 90,
            height: 90
        )

        let clearResult = await MessengerMediaCacheControls.clearConfirmedMediaCache(store: store)
        let inventory = await MessengerMediaCacheControls.inventory(store: store)

        #expect(clearResult.deletedConfirmedFileCount >= 1)
        #expect(clearResult.preservedPendingFileCount == 1)
        #expect(clearResult.preservedPendingBytes > 0)
        #expect(inventory.confirmedTotalBytes == 0)
        #expect(inventory.pendingOutgoingFileCount == 1)
        #expect(try await cache.cachedImageData(for: attachmentID, variant: .thumbnail) == nil)
        let pendingMedia = try await store.fetchPendingMedia(clientMessageID: clientMessageID)
        #expect(pendingMedia != nil)
    }

    @Test
    @MainActor
    func trimDeletesOldestFullImagesFirst() async throws {
        let (cache, store) = try await makeHarness()
        defer { resetHarness() }

        let oldData = try #require(makeJPEGData(width: 200, height: 200))
        let newData = try #require(makeJPEGData(width: 180, height: 180))
        try await cache.storeImageData(oldData, attachmentID: attachmentID, variant: .full)
        try await cache.storeImageData(newData, attachmentID: otherAttachmentID, variant: .full)
        try await seedAttachmentMetadata(store: store, attachmentID: attachmentID)
        try await seedAttachmentMetadata(store: store, attachmentID: otherAttachmentID)

        touchFile(attachmentID: attachmentID, variant: .full, date: Date(timeIntervalSince1970: 1))
        touchFile(attachmentID: otherAttachmentID, variant: .full, date: Date())

        let policy = MessengerMediaCacheCleanupPolicy(
            maxBytes: 10_000,
            targetBytesAfterCleanup: 5_000,
            maxAgeDays: 90
        )
        let result = await cache.cleanup(
            policy: policy,
            referencedAttachmentIDs: [attachmentID, otherAttachmentID]
        )

        #expect(result.removedFullCount >= 1)
        #expect(try await cache.cachedImageData(for: attachmentID, variant: .full) == nil)
    }

    @Test
    @MainActor
    func trimDoesNothingUnderSoftLimit() async throws {
        let (cache, store) = try await makeHarness()
        defer { resetHarness() }

        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)
        try await seedAttachmentMetadata(store: store, attachmentID: attachmentID)

        let policy = MessengerMediaCacheCleanupPolicy(
            maxBytes: 10_000_000,
            targetBytesAfterCleanup: 9_000_000,
            maxAgeDays: 90
        )
        let result = await cache.cleanup(policy: policy, referencedAttachmentIDs: [attachmentID])

        #expect(result.deletedBytes == 0)
        #expect(try await cache.cachedImageData(for: attachmentID, variant: .thumbnail) != nil)
    }

    @Test
    @MainActor
    func diagnosticsMediaSummaryIsPrivacySafe() async throws {
        let (cache, store) = try await makeHarness()
        defer { resetHarness() }

        let data = try #require(makeJPEGData())
        try await cache.storeImageData(data, attachmentID: attachmentID, variant: .thumbnail)
        try await seedAttachmentMetadata(store: store, attachmentID: attachmentID)

        let inventory = await MessengerMediaCacheControls.inventory(store: store)
        let section = MessengerDiagnostics.exportMediaSummarySection(inventory: inventory)
        let lowercased = section.lowercased()

        #expect(section.contains("confirmedTotalBytes="))
        #expect(section.contains("pendingOutgoingBytes="))
        #expect(!lowercased.contains("/users/"))
        #expect(!lowercased.contains("x-amz"))
        #expect(!lowercased.contains("storagekey"))
        #expect(!lowercased.contains("bearer"))
    }

    // MARK: - Helpers

    @MainActor
    private func makeHarness() async throws -> (MessengerMediaDiskCache, MessengerLocalStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-cache-controls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        MessengerMediaDiskCache.testingRootURL = root

        let store = MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
        MessengerMediaCacheService.testingDiskCache = MessengerMediaDiskCache.shared
        MessengerMediaCacheService.testingLocalStore = store
        return (MessengerMediaDiskCache.shared, store)
    }

    @MainActor
    private func resetHarness() {
        MessengerMediaCacheService.testingDiskCache = nil
        MessengerMediaCacheService.testingLocalStore = nil
        if let root = MessengerMediaDiskCache.testingRootURL {
            try? FileManager.default.removeItem(at: root)
        }
        MessengerMediaDiskCache.testingRootURL = nil
        MessengerMediaCacheLastOperationStore.resetForTesting()
    }

    @MainActor
    private func seedAttachmentMetadata(store: MessengerLocalStore, attachmentID: String) async throws {
        let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let messageID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let attachmentUUID = UUID(uuidString: attachmentID)!
        let dto = try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(messageID.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "cccccccc-cccc-cccc-cccc-cccccccccccc",
          "kind": "image",
          "body": null,
          "createdAt": "2026-07-02T13:00:00Z",
          "editedAt": null,
          "deletedAt": null,
          "deliveryStatus": "sent",
          "clientMessageID": null,
          "replyTo": null,
          "reactions": [],
          "attachments": [
            {
              "id": "\(attachmentUUID.uuidString)",
              "contentType": "image/jpeg",
              "byteSize": 1200,
              "width": 800,
              "height": 600,
              "downloadUrl": null,
              "downloadUrlExpiresAt": null
            }
          ]
        }
        """.utf8))
        try await store.upsertMessages([dto], conversationID: conversationID)
    }

    private func makeJPEGData(width: CGFloat = 80, height: CGFloat = 80) -> Data? {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }

    private func touchFile(attachmentID: String, variant: MessengerMediaVariant, date: Date) {
        guard let root = MessengerMediaDiskCache.testingRootURL else { return }
        let fileURL = root
            .appendingPathComponent("JustTwo/MediaCache/attachments/\(attachmentID)/\(variant.fileName)")
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
    }
}
