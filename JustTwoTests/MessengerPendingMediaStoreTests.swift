import Foundation
import Testing
@testable import JustTwo
#if canImport(UIKit)
import UIKit
#endif

@Suite(.serialized)
struct MessengerPendingMediaStoreTests {
    private let clientMessageID = "client-media-1"
    private let pendingMediaID = "pending-media-1"

    @Test
    func storesFileUnderRelativeKey() throws {
        #if canImport(UIKit)
        let data = makeTestJPEGData()
        let relativePath = try MessengerPendingMediaStore.storeJPEG(
            data: data,
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID
        )

        #expect(!relativePath.isEmpty)
        #expect(!relativePath.hasPrefix("/"))
        #expect(relativePath.contains(pendingMediaID))

        let prepared = try MessengerPendingMediaStore.preparedImage(
            relativePath: relativePath,
            contentType: "image/jpeg",
            byteSize: data.count,
            width: 10,
            height: 10
        )
        #expect(prepared.byteSize == data.count)

        MessengerPendingMediaStore.delete(relativePath: relativePath)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    @Test
    func deleteRemovesStoredFile() throws {
        #if canImport(UIKit)
        let data = makeTestJPEGData()
        let relativePath = try MessengerPendingMediaStore.storeJPEG(
            data: data,
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID
        )

        MessengerPendingMediaStore.delete(relativePath: relativePath)

        do {
            _ = try MessengerPendingMediaStore.preparedImage(
                relativePath: relativePath,
                contentType: "image/jpeg",
                byteSize: data.count,
                width: 10,
                height: 10
            )
            Issue.record("Expected missing file after delete")
        } catch MessengerPendingMediaStoreError.fileMissing {
            #expect(true)
        }
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    @Test
    func diagnosticsSanitizePendingMediaID() {
        let sanitized = MessengerPendingMediaStore.sanitizedPendingMediaIDForDiagnostics(
            "1234567890abcdef"
        )
        #expect(sanitized.hasSuffix("..."))
        #expect(!sanitized.contains("abcdef"))
    }

    #if canImport(UIKit)
    private func makeTestJPEGData() -> Data {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
    #endif
}
