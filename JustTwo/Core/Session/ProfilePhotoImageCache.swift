import UIKit

/// In-memory + on-disk cache for profile photo image bytes (never signed URLs).
final class ProfilePhotoImageCache {

    static let shared = ProfilePhotoImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.justtwo.profile-photo-cache", qos: .utility)

    private let avatarFallbackFileName = "avatar-fallback.jpg"

    private init() {
        memoryCache.countLimit = 12
    }

    private var cacheDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProfilePhotoImages", isDirectory: true)
    }

    private func photoFileURL(for photoID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(photoID.uuidString).jpg")
    }

    private var avatarFallbackURL: URL {
        cacheDirectory.appendingPathComponent(avatarFallbackFileName)
    }

    private func avatarMemoryKey() -> NSString {
        "avatar-fallback" as NSString
    }

    func image(for photoID: UUID) -> UIImage? {
        let key = photoID.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let url = photoFileURL(for: photoID)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key)
        return image
    }

    func save(_ image: UIImage, for photoID: UUID) {
        memoryCache.setObject(image, forKey: photoID.uuidString as NSString)

        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = photoFileURL(for: photoID)

        ioQueue.async { [weak self] in
            self?.ensureCacheDirectory()
            try? data.write(to: url, options: .atomic)
        }
    }

    func saveJPEGData(_ data: Data, for photoID: UUID) {
        guard let image = UIImage(data: data) else { return }
        save(image, for: photoID)
    }

    func avatarFallback() -> UIImage? {
        if let cached = memoryCache.object(forKey: avatarMemoryKey()) {
            return cached
        }

        guard let data = try? Data(contentsOf: avatarFallbackURL),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: avatarMemoryKey())
        return image
    }

    func saveAvatarFallback(_ image: UIImage) {
        memoryCache.setObject(image, forKey: avatarMemoryKey())

        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = avatarFallbackURL

        ioQueue.async { [weak self] in
            self?.ensureCacheDirectory()
            try? data.write(to: url, options: .atomic)
        }
    }

    func remove(photoID: UUID) {
        memoryCache.removeObject(forKey: photoID.uuidString as NSString)

        let url = photoFileURL(for: photoID)
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: url)
        }
    }

    func clearAvatarFallback() {
        memoryCache.removeObject(forKey: avatarMemoryKey())

        let url = avatarFallbackURL
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: url)
        }
    }

    func clear() {
        memoryCache.removeAllObjects()

        let directory = cacheDirectory
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: directory)
        }
    }

    private func ensureCacheDirectory() {
        let directory = cacheDirectory
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
