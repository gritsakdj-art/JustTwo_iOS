import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import JustTwo

struct ChatImageBubbleLayoutTests {

    @Test
    func invalidDimensionsUseFallbackAspectRatio() {
        #expect(ChatImageBubbleLayout.aspectRatio(width: 0, height: 960) == ChatImageBubbleLayout.fallbackAspectRatio)
        #expect(ChatImageBubbleLayout.aspectRatio(width: 1280, height: 0) == ChatImageBubbleLayout.fallbackAspectRatio)
    }

    @Test
    func portraitImageClampsHeight() {
        let size = ChatImageBubbleLayout.displaySize(
            width: 900,
            height: 2_000,
            maxBubbleWidth: 280
        )

        #expect(size.height <= ChatImageBubbleLayout.maxHeight + 0.5)
        #expect(size.width >= ChatImageBubbleLayout.minWidth)
    }

    @Test
    func landscapeImageKeepsMinimumHeight() {
        let size = ChatImageBubbleLayout.displaySize(
            width: 2_000,
            height: 600,
            maxBubbleWidth: 280
        )

        #expect(size.height >= ChatImageBubbleLayout.minHeight)
        #expect(size.width <= ChatImageBubbleLayout.maxWidthCap + 0.5)
    }

    @Test
    func maxWidthRespectsScreenCap() {
        let size = ChatImageBubbleLayout.displaySize(
            width: 1_024,
            height: 768,
            maxBubbleWidth: ChatImageBubbleLayout.maxBubbleWidth(screenWidth: 500)
        )

        #expect(size.width <= ChatImageBubbleLayout.maxWidthCap + 0.5)
    }

    @Test
    func landscapeImageUsesTighterWidthCap() {
        let size = ChatImageBubbleLayout.displaySize(
            width: 4_032,
            height: 3_024,
            maxBubbleWidth: 280
        )

        #expect(size.width <= ChatImageBubbleLayout.landscapeMaxWidthCap + 0.5)
    }

    @Test
    func portraitImageStillUsesFullWidthCap() {
        let size = ChatImageBubbleLayout.displaySize(
            width: 3_024,
            height: 4_032,
            maxBubbleWidth: 280
        )

        #expect(size.width > ChatImageBubbleLayout.landscapeMaxWidthCap)
        #expect(size.height <= ChatImageBubbleLayout.maxHeight + 0.5)
    }

    @Test
    func landscapeImageNeverExceedsReducedAvailableWidth() {
        // Simulates a narrow bubble (small screen minus bubble chrome): the photo must
        // shrink to the available width instead of overflowing the bubble edge.
        let availableWidth: CGFloat = 208
        let size = ChatImageBubbleLayout.displaySize(
            width: 4_032,
            height: 3_024,
            maxBubbleWidth: availableWidth
        )

        #expect(size.width <= availableWidth + 0.5)
        #expect(size.height >= ChatImageBubbleLayout.minHeight)
    }

    @Test
    func thumbnailKeepsLongSideAt100() {
        let landscape = ChatImageBubbleLayout.thumbnailSize(width: 4_032, height: 3_024)
        #expect(landscape.width == 100)
        #expect(landscape.height == 75)

        let portrait = ChatImageBubbleLayout.thumbnailSize(width: 3_024, height: 4_032)
        #expect(portrait.height == 100)
        #expect(portrait.width == 75)

        let square = ChatImageBubbleLayout.thumbnailSize(width: 500, height: 500)
        #expect(square.width == 100)
        #expect(square.height == 100)
    }

    @Test
    func thumbnailInvalidMetadataUsesFallbackRatio() {
        let size = ChatImageBubbleLayout.thumbnailSize(width: 0, height: 0)
        #expect(size.width == 100)
        #expect(size.height == 75)
    }

    @Test
    func verySmallMetadataStillUsesMinimumDimensions() {
        let size = ChatImageBubbleLayout.displaySize(
            width: 40,
            height: 30,
            maxBubbleWidth: 280
        )

        #expect(size.width >= ChatImageBubbleLayout.minWidth)
        #expect(size.height >= ChatImageBubbleLayout.minHeight)
    }
}

@MainActor
struct ChatMessageImageCacheTests {

    @Test
    func cacheKeyUsesAttachmentIDNotSignedURL() {
        let attachment = ChatMessageAttachment(
            id: "44444444-4444-4444-4444-444444444444",
            contentType: "image/jpeg",
            byteSize: 100,
            width: 100,
            height: 100,
            localFileURL: nil,
            downloadURL: URL(string: "https://storage.example/object.jpg?X-Amz-Signature=secret"),
            downloadUrlExpiresAt: nil
        )

        #expect(ChatMessageImageCache.cacheKey(for: attachment) == attachment.id)
        #expect(!ChatMessageImageCache.cacheKey(for: attachment).contains("X-Amz"))
    }

    @Test
    func cacheHitAndMissWork() {
        let cache = ChatMessageImageCache.shared
        let key = "test-cache-key-\(UUID().uuidString)"
        defer { cache.remove(for: key) }

        #expect(cache.image(for: key) == nil)

        let image = UIImage(systemName: "heart.fill")!
        cache.save(image, for: key)

        #expect(cache.image(for: key) != nil)
    }
}

struct ChatImageRenderStateTests {

    @Test
    func textMessageDoesNotCreateImageRenderSource() {
        let message = ChatMessage(
            id: UUID(),
            kind: .text,
            displayText: "Hello",
            rawBody: "Hello",
            createdAt: .now,
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )

        #expect(message.imageRenderSource == nil)
    }

    @Test
    func imageMessageWithAttachmentCreatesRemoteRenderSource() throws {
        let dto = try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "senderProfileID": "33333333-3333-3333-3333-333333333333",
          "kind": "image",
          "body": null,
          "attachments": [
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "contentType": "image/jpeg",
              "byteSize": 482391,
              "width": 1280,
              "height": 960,
              "downloadUrl": "https://storage.example/object.jpg?X-Amz-Signature=secret",
              "downloadUrlExpiresAt": "2026-07-02T09:15:00Z"
            }
          ],
          "replyTo": null,
          "reactions": [],
          "createdAt": "2026-07-02T09:00:00Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))

        let message = ChatUIMapping.message(from: dto, currentProfileID: dto.senderProfileID)
        #expect(message.imageRenderSource == .remote(attachmentID: "44444444-4444-4444-4444-444444444444".lowercased()))
    }

    @Test
    func deletedImageMessageDoesNotCreateRenderableImageState() throws {
        let dto = try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "senderProfileID": "33333333-3333-3333-3333-333333333333",
          "kind": "image",
          "body": null,
          "attachments": [],
          "replyTo": null,
          "reactions": [],
          "createdAt": "2026-07-02T09:00:00Z",
          "editedAt": null,
          "deletedAt": "2026-07-02T09:05:00Z"
        }
        """.utf8))

        let message = ChatUIMapping.message(from: dto, currentProfileID: dto.senderProfileID)
        #expect(message.isDeleted)
        #expect(message.imageRenderSource == nil)
    }

    @Test
    func replyToCaptionlessImageKeepsQuoteAlive() throws {
        // Backend stores "" as the body of caption-less image messages, so replyTo.body
        // arrives as an empty string. The quote must survive (photo placeholder text),
        // not be dropped or mistaken for a deleted original.
        let dto = try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "senderProfileID": "33333333-3333-3333-3333-333333333333",
          "kind": "text",
          "body": "Nice shot!",
          "attachments": [],
          "replyTo": {
            "id": "55555555-5555-5555-5555-555555555555",
            "body": "",
            "senderProfileID": "33333333-3333-3333-3333-333333333333"
          },
          "reactions": [],
          "createdAt": "2026-07-02T09:00:00Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))

        let message = ChatUIMapping.message(from: dto, currentProfileID: dto.senderProfileID)
        let preview = try #require(message.replyPreview)
        #expect(preview.id == UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        #expect(!preview.isDeleted)
        #expect(preview.body == ChatUIMapping.imageMessagePreviewText)
    }

    @Test
    func replyToDeletedMessageStaysMarkedDeleted() throws {
        let dto = try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "senderProfileID": "33333333-3333-3333-3333-333333333333",
          "kind": "text",
          "body": "reply text",
          "attachments": [],
          "replyTo": {
            "id": "55555555-5555-5555-5555-555555555555",
            "body": null,
            "senderProfileID": "33333333-3333-3333-3333-333333333333"
          },
          "reactions": [],
          "createdAt": "2026-07-02T09:00:00Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))

        let message = ChatUIMapping.message(from: dto, currentProfileID: dto.senderProfileID)
        let preview = try #require(message.replyPreview)
        #expect(preview.isDeleted)
    }

    @Test
    func optimisticLocalImageUsesLocalFileSource() {
        let prepared = PreparedChatImage(
            localFileURL: URL(fileURLWithPath: "/tmp/justtwo-chat-images/client-image.jpg"),
            contentType: "image/jpeg",
            byteSize: 1_234,
            width: 800,
            height: 600
        )

        let message = ChatMessage.optimisticOutgoingImage(
            clientMessageID: "client-image-optimistic",
            prepared: prepared,
            replyPreview: nil
        )

        #expect(message.imageRenderSource == .localFile)
    }
}

struct ChatImageBubbleDiagnosticsTests {

    @Test
    func imageBubbleDiagnosticsDoNotKeepSignedURLs() {
        let entry = MessengerDiagnostics.makeEntry(
            .imageBubbleRenderFailed,
            metadata: [
                "downloadUrl": "https://storage.example/object.jpg?X-Amz-Signature=secret",
                "uploadUrl": "https://storage.example/upload?X-Amz-Signature=secret",
                "attachmentID": "44444444-4444-4444-4444-444444444444",
                "source": "remote"
            ]
        )

        #expect(entry.metadata["downloadUrl"] == nil)
        #expect(entry.metadata["uploadUrl"] == nil)
        #expect(entry.metadata["attachmentID"] == "44444444-4444-4444-4444-444444444444")
        #expect(!entry.exportLine.contains("X-Amz-Signature"))
    }
}
