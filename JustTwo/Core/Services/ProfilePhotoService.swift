import Foundation

enum ProfilePhotoService {

    static let maxPhotoCount = 6

    static func listPhotos() async throws -> [ProfilePhotoDTO] {
        let response = try await NetworkExecutor.shared.send(ListProfilePhotosRequest())
        return response.photos
    }

    static func uploadPhoto(
        prepared: PreparedProfilePhoto,
        position: Int? = nil,
        isPrimary: Bool
    ) async throws -> ProfilePhotoDTO {
        let uploadResponse = try await NetworkExecutor.shared.send(
            CreateProfilePhotoUploadURLRequest(
                body: CreateProfilePhotoUploadURLRequestBody(
                    contentType: prepared.contentType,
                    byteSize: prepared.byteSize,
                    width: prepared.width,
                    height: prepared.height,
                    position: position,
                    isPrimary: isPrimary
                )
            )
        )

        let upload = uploadResponse.upload

        try await ObjectStorageUploader.upload(
            data: prepared.data,
            uploadURL: upload.uploadUrl,
            method: upload.method,
            headers: upload.headers
        )

        let completed = try await NetworkExecutor.shared.send(
            CompleteProfilePhotoUploadRequest(uploadID: upload.id)
        )
        return completed.photo
    }

    static func setPrimary(photoID: UUID) async throws -> ProfilePhotoDTO {
        let response = try await NetworkExecutor.shared.send(
            SetPrimaryProfilePhotoRequest(photoID: photoID)
        )
        return response.photo
    }

    static func reorderPhotos(photoIDs: [UUID]) async throws -> [ProfilePhotoDTO] {
        let response = try await NetworkExecutor.shared.send(
            ReorderProfilePhotosRequest(photoIDs: photoIDs)
        )
        return response.photos
    }

    static func updateAvatarPresentation(
        photoID: UUID,
        presentation: AvatarPresentationDTO
    ) async throws -> ProfilePhotoDTO {
        let response = try await NetworkExecutor.shared.send(
            UpdateAvatarPresentationRequest(photoID: photoID, presentation: presentation)
        )
        return response.photo
    }

    static func deletePhoto(photoID: UUID) async throws {
        _ = try await NetworkExecutor.shared.send(DeleteProfilePhotoRequest(photoID: photoID))
    }

    static func refreshDownloadURL(photoID: UUID) async throws -> ProfilePhotoDownloadURLDTO {
        let response = try await NetworkExecutor.shared.send(
            GetProfilePhotoDownloadURLRequest(photoID: photoID)
        )
        return response.photo
    }
}
