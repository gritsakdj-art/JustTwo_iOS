import UIKit

/// In-memory cache for chat message images. Keys use attachment/message identity,
/// never signed download URLs.
@MainActor
final class ChatMessageImageCache {
    static let shared = ChatMessageImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        memoryCache.countLimit = 64
    }

    static func cacheKey(for attachment: ChatMessageAttachment) -> String {
        attachment.id.lowercased()
    }

    func image(for cacheKey: String) -> UIImage? {
        memoryCache.object(forKey: cacheKey as NSString)
    }

    func save(_ image: UIImage, for cacheKey: String) {
        memoryCache.setObject(image, forKey: cacheKey as NSString)
    }

    func remove(for cacheKey: String) {
        memoryCache.removeObject(forKey: cacheKey as NSString)
    }

    func clear() {
        memoryCache.removeAllObjects()
    }
}
