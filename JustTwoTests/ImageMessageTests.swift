import Foundation
import Testing
@testable import JustTwo

@MainActor
struct ImageMessageTests {

    @Test
    func textMessageWithoutAttachmentsDecodesWithEmptyArray() throws {
        let dto = try JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "conversationID": "22222222-2222-2222-2222-222222222222",
          "senderProfileID": "33333333-3333-3333-3333-333333333333",
          "kind": "text",
          "body": "Hello",
          "replyTo": null,
          "reactions": [],
          "createdAt": "2026-07-02T09:00:00Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))

        #expect(dto.kind == .text)
        #expect(dto.attachments.isEmpty)
    }

    @Test
    func imageMessageWithAttachmentDecodes() throws {
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
          "deliveryStatus": "sent",
          "clientMessageID": "client-image-1",
          "createdAt": "2026-07-02T09:00:00Z",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))

        #expect(dto.kind == .image)
        #expect(dto.body == nil)
        #expect(dto.attachments.count == 1)
        #expect(dto.attachments[0].contentType == "image/jpeg")
        #expect(dto.attachments[0].downloadUrl?.host == "storage.example")
    }

    @Test
    func deletedImageMessageDecodesWithoutAttachments() throws {
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

        let mapped = ChatUIMapping.message(from: dto, currentProfileID: dto.senderProfileID)
        #expect(mapped.kind == .image)
        #expect(mapped.isDeleted)
        #expect(mapped.imageAttachment == nil)
        #expect(mapped.rawBody == nil)
    }

    @Test
    func uploadURLRequestEncodesImageMetadata() throws {
        let body = CreateMessageAttachmentUploadRequestBody(
            contentType: "image/jpeg",
            byteSize: 482391,
            width: 1280,
            height: 960
        )
        let json = try object(from: JSONCoding.encoder.encode(body))

        #expect(json["contentType"] as? String == "image/jpeg")
        #expect(json["byteSize"] as? Int == 482391)
        #expect(json["width"] as? Int == 1280)
        #expect(json["height"] as? Int == 960)
    }

    @Test
    func imageCreateMessageRequestEncodesBodyNullAndUploadID() throws {
        let uploadID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let body = SendMessageRequestBody(
            kind: .image,
            body: nil,
            replyToID: nil,
            clientMessageID: "client-image-1",
            attachmentUploadID: uploadID
        )
        let json = try object(from: JSONCoding.encoder.encode(body))

        #expect(json["kind"] as? String == "image")
        #expect(json["body"] is NSNull)
        #expect(json["clientMessageID"] as? String == "client-image-1")
        #expect(json["attachmentUploadID"] as? String == uploadID.uuidString)
    }

    @Test
    func optimisticImageMessageUsesLocalAttachmentAndNoDeliveryStatus() {
        let clientMessageID = "client-image-optimistic"
        let prepared = PreparedChatImage(
            localFileURL: URL(fileURLWithPath: "/tmp/justtwo-chat-images/client-image-optimistic.jpg"),
            contentType: "image/jpeg",
            byteSize: 1234,
            width: 800,
            height: 600
        )

        let message = ChatMessage.optimisticOutgoingImage(
            clientMessageID: clientMessageID,
            prepared: prepared,
            replyPreview: nil
        )

        #expect(message.kind == .image)
        #expect(message.clientMessageID == clientMessageID)
        #expect(message.localSendState == .sending)
        #expect(message.deliveryStatus == nil)
        #expect(message.imageAttachment?.localFileURL == prepared.localFileURL)
        #expect(message.imageAttachment?.downloadURL == nil)
    }

    @Test
    func diagnosticsDoNotKeepSignedURLs() {
        let entry = MessengerDiagnostics.makeEntry(
            .imageUploadStarted,
            metadata: [
                "uploadUrl": "https://storage.example/object?X-Amz-Signature=secret",
                "downloadUrl": "https://storage.example/object?X-Amz-Signature=secret",
                "contentType": "image/jpeg",
                "byteSize": "1234"
            ]
        )

        #expect(entry.metadata["uploadUrl"] == nil)
        #expect(entry.metadata["downloadUrl"] == nil)
        #expect(entry.metadata["contentType"] == "image/jpeg")
        #expect(entry.metadata["byteSize"] == "1234")
        #expect(!entry.exportLine.contains("X-Amz-Signature"))
    }

    private func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ImageMessageTests", code: 1)
        }
        return object
    }
}
