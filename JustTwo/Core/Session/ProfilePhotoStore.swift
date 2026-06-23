import Foundation

@MainActor
@Observable
final class ProfilePhotoStore {

    static let shared = ProfilePhotoStore()

    private(set) var photos: [ProfilePhotoDTO] = []
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var isMutating = false
    private(set) var lastErrorMessage: String?

    private var hasLoaded = false

    var primaryPhoto: ProfilePhotoDTO? {
        photos.first(where: \.isPrimary) ?? photos.first
    }

    var canAddPhoto: Bool {
        photos.count < ProfilePhotoService.maxPhotoCount
    }

    private init() {}

    func reset() {
        photos = []
        hasLoaded = false
        isLoading = false
        isUploading = false
        isMutating = false
        lastErrorMessage = nil
    }

    func loadPhotos(force: Bool = false) async {
        guard force || !hasLoaded else { return }

        isLoading = true
        lastErrorMessage = nil

        do {
            photos = try await fetchPhotosFromServer()
            hasLoaded = true
        } catch let error as NetworkError {
            lastErrorMessage = error.userMessage
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isLoading = false
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

        await reloadPhotos()
        return photo
    }

    func setPrimary(photoID: UUID) async throws {
        isMutating = true
        lastErrorMessage = nil
        defer { isMutating = false }

        _ = try await ProfilePhotoService.setPrimary(photoID: photoID)
        await reloadPhotos()
    }

    func deletePhoto(photoID: UUID) async throws {
        isMutating = true
        lastErrorMessage = nil
        defer { isMutating = false }

        try await ProfilePhotoService.deletePhoto(photoID: photoID)
        await reloadPhotos()
    }

    func reloadPhotos() async {
        do {
            photos = try await fetchPhotosFromServer()
            hasLoaded = true
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
        try await ProfilePhotoService.listPhotos()
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
