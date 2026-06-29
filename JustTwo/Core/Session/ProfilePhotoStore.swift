import Foundation
import UIKit

@MainActor
@Observable
final class ProfilePhotoStore {

    static let shared = ProfilePhotoStore()

    private(set) var photos: [ProfilePhotoDTO] = []
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var isMutating = false
    private(set) var lastErrorMessage: String?
    private(set) var primaryPhotoRevision = 0

    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?
    private let imageCache = ProfilePhotoImageCache.shared

    var primaryPhoto: ProfilePhotoDTO? {
        photos.first(where: \.isPrimary) ?? photos.first
    }

    /// Gallery order is owned by the backend and is independent from primary status.
    var galleryPhotos: [ProfilePhotoDTO] {
        photos.sorted(by: Self.photoOrder)
    }

    func ensureCachedImage(for photoID: UUID) async {
        if imageCache.image(for: photoID) != nil {
            return
        }
        await downloadAndCachePhoto(photoID: photoID, asAvatarFallback: false)
    }

    var canAddPhoto: Bool {
        photos.count < ProfilePhotoService.maxPhotoCount
    }

    private init() {}

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        photos = []
        hasLoaded = false
        isLoading = false
        isUploading = false
        isMutating = false
        lastErrorMessage = nil
        primaryPhotoRevision = 0
        imageCache.clear()
    }

    func cachedImage(for photoID: UUID) -> UIImage? {
        imageCache.image(for: photoID)
    }

    func avatarFallbackImage() -> UIImage? {
        if let primaryPhoto,
           let cached = imageCache.image(for: primaryPhoto.id) {
            return cached
        }
        return imageCache.avatarFallback()
    }

    func loadPhotos(force: Bool = false) async {
        if !force, hasLoaded {
            return
        }

        if let loadTask, !force {
            await loadTask.value
            return
        }

        if force {
            loadTask?.cancel()
            loadTask = nil
            hasLoaded = false
        }

        let task = Task { @MainActor in
            isLoading = true
            lastErrorMessage = nil

            do {
                photos = try await fetchPhotosFromServer()
                hasLoaded = true
                await cachePrimaryPhotoIfNeeded()
            } catch let error as NetworkError {
                lastErrorMessage = error.userMessage
            } catch {
                lastErrorMessage = error.localizedDescription
            }

            isLoading = false
        }

        loadTask = task
        await task.value

        if loadTask == task {
            loadTask = nil
        }
    }

    @discardableResult
    func uploadPhoto(data: Data, isPrimary: Bool) async throws -> ProfilePhotoDTO {
        guard let prepared = ProfilePhotoImagePipeline.prepareJPEG(from: data) else {
            throw ProfilePhotoStoreError.invalidImage
        }
        return try await uploadPreparedPhoto(prepared, isPrimary: isPrimary)
    }

    @discardableResult
    func uploadPreparedPhoto(_ prepared: PreparedProfilePhoto, isPrimary: Bool) async throws -> ProfilePhotoDTO {
        try ensureCanAddPhoto(isPrimary: isPrimary)

        isUploading = true
        lastErrorMessage = nil
        defer { isUploading = false }

        guard let position = Self.nextAvailablePosition(in: photos) else {
            throw isPrimary ? ProfilePhotoStoreError.avatarUploadLimitReached : ProfilePhotoStoreError.photoLimitReached
        }

        let shouldBePrimary = isPrimary || photos.isEmpty

        let photo = try await ProfilePhotoService.uploadPhoto(
            prepared: prepared,
            position: position,
            isPrimary: shouldBePrimary
        )

        cacheUploadedImage(prepared, for: photo.id, isPrimary: photo.isPrimary || shouldBePrimary)
        await reloadPhotos()
        return photo
    }

    func setPrimary(photoID: UUID) async throws {
        isMutating = true
        lastErrorMessage = nil
        defer { isMutating = false }

        promoteToAvatarFallback(photoID: photoID)

        _ = try await ProfilePhotoService.setPrimary(photoID: photoID)
        await reloadPhotos()
        primaryPhotoRevision += 1

        if imageCache.avatarFallback() == nil {
            await downloadAndCachePhoto(photoID: photoID, asAvatarFallback: true)
        }
    }

    func reorderPhotos(photoIDs: [UUID]) async throws {
        isMutating = true
        lastErrorMessage = nil
        defer { isMutating = false }

        let reordered = try await ProfilePhotoService.reorderPhotos(photoIDs: photoIDs)
        photos = reordered.sorted(by: Self.photoOrder)
    }

    @discardableResult
    func updateAvatarPresentation(
        photoID: UUID,
        transform: AvatarCropTransform
    ) async throws -> ProfilePhotoDTO {
        isMutating = true
        lastErrorMessage = nil
        defer { isMutating = false }

        let updated = try await ProfilePhotoService.updateAvatarPresentation(
            photoID: photoID,
            presentation: AvatarPresentationDTO(transform)
        )
        if let index = photos.firstIndex(where: { $0.id == updated.id }) {
            photos[index] = updated
        }
        if updated.isPrimary {
            primaryPhotoRevision += 1
        }
        return updated
    }

    func deletePhoto(photoID: UUID) async throws {
        isMutating = true
        lastErrorMessage = nil
        defer { isMutating = false }

        let wasPrimary = photos.first(where: { $0.id == photoID })?.isPrimary == true
        imageCache.remove(photoID: photoID)

        try await ProfilePhotoService.deletePhoto(photoID: photoID)
        await reloadPhotos()

        if wasPrimary {
            if let newPrimary = primaryPhoto {
                promoteToAvatarFallback(photoID: newPrimary.id)
                if imageCache.image(for: newPrimary.id) == nil {
                    await downloadAndCachePhoto(photoID: newPrimary.id, asAvatarFallback: true)
                }
            } else {
                imageCache.clearAvatarFallback()
            }
            primaryPhotoRevision += 1
        }
    }

    func reloadPhotos() async {
        do {
            photos = try await fetchPhotosFromServer()
            hasLoaded = true
            await cachePrimaryPhotoIfNeeded()
        } catch let error as NetworkError {
            lastErrorMessage = error.userMessage
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshDownloadURL(for photoID: UUID) async {
        _ = try? await ProfilePhotoService.refreshDownloadURL(photoID: photoID)
        await reloadPhotos()
    }

    private func fetchPhotosFromServer() async throws -> [ProfilePhotoDTO] {
        (try await ProfilePhotoService.listPhotos()).sorted(by: Self.photoOrder)
    }

    private static func photoOrder(_ lhs: ProfilePhotoDTO, _ rhs: ProfilePhotoDTO) -> Bool {
        if lhs.position != rhs.position {
            return lhs.position < rhs.position
        }
        return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
    }

    private func ensureCanAddPhoto(isPrimary: Bool) throws {
        guard canAddPhoto else {
            throw isPrimary
                ? ProfilePhotoStoreError.avatarUploadLimitReached
                : ProfilePhotoStoreError.photoLimitReached
        }
    }

    private static func nextAvailablePosition(in photos: [ProfilePhotoDTO]) -> Int? {
        let usedPositions = Set(photos.map(\.position))
        return (0..<ProfilePhotoService.maxPhotoCount).first { !usedPositions.contains($0) }
    }

    private func cacheUploadedImage(_ prepared: PreparedProfilePhoto, for photoID: UUID, isPrimary: Bool) {
        imageCache.saveJPEGData(prepared.data, for: photoID)
        if isPrimary, let image = UIImage(data: prepared.data) {
            imageCache.saveAvatarFallback(image)
            primaryPhotoRevision += 1
        }
    }

    private func promoteToAvatarFallback(photoID: UUID) {
        if let image = imageCache.image(for: photoID) {
            imageCache.saveAvatarFallback(image)
        }
    }

    private func cachePrimaryPhotoIfNeeded() async {
        guard let primaryPhoto else { return }

        if imageCache.image(for: primaryPhoto.id) != nil {
            promoteToAvatarFallback(photoID: primaryPhoto.id)
            return
        }

        await downloadAndCachePhoto(photoID: primaryPhoto.id, asAvatarFallback: true)
    }

    private func downloadAndCachePhoto(photoID: UUID, asAvatarFallback: Bool) async {
        guard let photo = photos.first(where: { $0.id == photoID }) ?? primaryPhoto,
              let url = URL(string: photo.downloadUrl) else {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return
            }

            imageCache.save(image, for: photo.id)
            if asAvatarFallback {
                imageCache.saveAvatarFallback(image)
            }
        } catch {
            return
        }
    }
}

enum ProfilePhotoStoreError: LocalizedError {
    case invalidImage
    case photoLimitReached
    case avatarUploadLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "profile.photos.error.invalid_image")
        case .photoLimitReached:
            return String(localized: "profile.photos.error.limit_reached")
        case .avatarUploadLimitReached:
            return String(localized: "profile.photos.error.avatar_limit_reached")
        }
    }
}
