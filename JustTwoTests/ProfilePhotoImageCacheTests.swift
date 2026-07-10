import Foundation
import Testing
@testable import JustTwo
#if canImport(UIKit)
import UIKit
#endif

@Suite(.serialized)
struct ProfilePhotoImageCacheTests {
    private let cache = ProfilePhotoImageCache.shared

    @Test
    func syncImageLookupDoesNotHitDiskForMissingMemoryEntry() {
        #if canImport(UIKit)
        #expect(cache.image(for: UUID()) == nil)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    @Test
    func saveJPEGDataPersistsAndLoadsAsynchronously() async throws {
        #if canImport(UIKit)
        let photoID = UUID()
        defer { cache.remove(photoID: photoID) }

        let data = makeTestJPEGData()
        await cache.saveJPEGData(data, for: photoID)

        let loaded = await cache.loadImage(for: photoID)
        #expect(loaded != nil)
        #expect(cache.image(for: photoID) != nil)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    @Test
    func avatarFallbackIsAvailableInMemoryAfterSave() async throws {
        #if canImport(UIKit)
        cache.clearAvatarFallback()
        defer { cache.clearAvatarFallback() }

        let image = makeTestImage()
        cache.saveAvatarFallback(image)

        #expect(cache.avatarFallback() != nil)
        #expect(await cache.loadAvatarFallback() != nil)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    #if canImport(UIKit)
    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }

    private func makeTestJPEGData() -> Data {
        makeTestImage().jpegData(compressionQuality: 0.9)!
    }
    #endif
}

@Suite
struct ProfilePhotoImagePipelineTests {
    @Test
    func asyncPrepareJPEGProducesUploadReadyPayload() async throws {
        #if canImport(UIKit)
        let data = makeTestJPEGData(width: 1800, height: 1200)
        let prepared = try #require(await ProfilePhotoImagePipeline.prepareJPEG(from: data))

        #expect(prepared.contentType == "image/jpeg")
        #expect(prepared.byteSize == Int64(prepared.data.count))
        #expect(prepared.width <= 1024)
        #expect(prepared.height <= 1024)
        #expect(prepared.data.count > 0)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    @Test
    func asyncJPEGDataMatchesSyncQuality() async throws {
        #if canImport(UIKit)
        let image = makeTestImage(size: CGSize(width: 320, height: 320))
        let asyncData = try #require(
            await ProfilePhotoImagePipeline.jpegData(from: image, compressionQuality: 0.9)
        )
        let syncData = try #require(image.jpegData(compressionQuality: 0.9))

        #expect(asyncData.count == syncData.count)
        #expect(asyncData == syncData)
        #else
        Issue.record("UIKit unavailable")
        #endif
    }

    #if canImport(UIKit)
    private func makeTestImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeTestJPEGData(width: CGFloat, height: CGFloat) -> Data {
        makeTestImage(size: CGSize(width: width, height: height))
            .jpegData(compressionQuality: 0.9)!
    }
    #endif
}
