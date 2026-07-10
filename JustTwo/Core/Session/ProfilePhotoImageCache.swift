import UIKit

/// In-memory + on-disk cache for profile photo image bytes (never signed URLs).
final class ProfilePhotoImageCache {

    static let shared = ProfilePhotoImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.justtwo.profile-photo-cache", qos: .utility)

    private let avatarFallbackFileName = "avatar-fallback.jpg"
    private let jpegCompressionQuality: CGFloat = 0.85

    private init() {
        memoryCache.countLimit = 48
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

    /// Returns an in-memory cached image when available. Does not read from disk.
    func image(for photoID: UUID) -> UIImage? {
        memoryCache.object(forKey: photoID.uuidString as NSString)
    }

    func loadImage(for photoID: UUID) async -> UIImage? {
        let key = photoID.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        return await performOnIOQueue { [weak self] in
            guard let self else { return nil as UIImage? }

            let url = self.photoFileURL(for: photoID)
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                return nil
            }

            self.memoryCache.setObject(image, forKey: key)
            return image
        }
    }

    func save(_ image: UIImage, for photoID: UUID) {
        memoryCache.setObject(image, forKey: photoID.uuidString as NSString)

        ioQueue.async { [weak self] in
            guard let self,
                  let data = image.jpegData(compressionQuality: self.jpegCompressionQuality) else {
                return
            }
            self.writeJPEGData(data, to: self.photoFileURL(for: photoID))
        }
    }

    func saveJPEGData(_ data: Data, for photoID: UUID) async {
        guard let image = await ProfilePhotoImagePipeline.decodeImage(from: data) else { return }

        let key = photoID.uuidString as NSString
        memoryCache.setObject(image, forKey: key)

        await performOnIOQueue { [weak self] in
            self?.writeJPEGData(data, to: self?.photoFileURL(for: photoID))
        }
    }

    /// Returns an in-memory avatar fallback when available. Does not read from disk.
    func avatarFallback() -> UIImage? {
        memoryCache.object(forKey: avatarMemoryKey())
    }

    func loadAvatarFallback() async -> UIImage? {
        let key = avatarMemoryKey()
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        return await performOnIOQueue { [weak self] in
            guard let self else { return nil as UIImage? }

            guard let data = try? Data(contentsOf: self.avatarFallbackURL),
                  let image = UIImage(data: data) else {
                return nil
            }

            self.memoryCache.setObject(image, forKey: key)
            return image
        }
    }

    func saveAvatarFallback(_ image: UIImage) {
        memoryCache.setObject(image, forKey: avatarMemoryKey())

        ioQueue.async { [weak self] in
            guard let self,
                  let data = image.jpegData(compressionQuality: self.jpegCompressionQuality) else {
                return
            }
            self.writeJPEGData(data, to: self.avatarFallbackURL)
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

    private func writeJPEGData(_ data: Data, to url: URL?) {
        guard let url else { return }
        ensureCacheDirectory()
        try? data.write(to: url, options: .atomic)
    }

    private func ensureCacheDirectory() {
        let directory = cacheDirectory
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func performOnIOQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
