import Foundation

nonisolated struct AvatarPresentationDTO: Codable, Equatable, Sendable {
    let offsetX: Double
    let offsetY: Double
    let scale: Double

    static let identity = AvatarPresentationDTO(offsetX: 0, offsetY: 0, scale: 1)
}

nonisolated struct ProfilePhotoDTO: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let position: Int
    let isPrimary: Bool
    let contentType: String?
    let byteSize: Int64?
    let width: Int?
    let height: Int?
    let downloadUrl: String
    let avatarPresentation: AvatarPresentationDTO
    let createdAt: Date?
    let updatedAt: Date?
}

nonisolated struct ProfilePhotosResponse: Decodable, Sendable {
    let photos: [ProfilePhotoDTO]
}

nonisolated struct ReorderProfilePhotosRequestBody: Encodable {
    let photoIds: [UUID]
}

nonisolated struct UpdateAvatarPresentationRequestBody: Encodable {
    let offsetX: Double
    let offsetY: Double
    let scale: Double
}

nonisolated struct CreateProfilePhotoUploadURLRequestBody: Encodable {
    let contentType: String
    let byteSize: Int64
    let width: Int?
    let height: Int?
    let position: Int?
    let isPrimary: Bool?
}

nonisolated struct ProfilePhotoUploadDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let storageKey: String
    let uploadUrl: String
    let method: String
    let headers: [String: String]
    let expiresAt: Date
}

nonisolated struct CreateProfilePhotoUploadURLResponse: Decodable, Sendable {
    let upload: ProfilePhotoUploadDTO
}

nonisolated struct CompleteProfilePhotoUploadResponse: Decodable, Sendable {
    let photo: ProfilePhotoDTO
}

nonisolated struct ProfilePhotoDownloadURLDTO: Decodable, Sendable {
    let id: UUID
    let downloadUrl: String
    let expiresAt: Date
}

nonisolated struct ProfilePhotoDownloadURLResponse: Decodable, Sendable {
    let photo: ProfilePhotoDownloadURLDTO
}

nonisolated struct DeleteProfilePhotoResponse: Decodable, Sendable {
    let success: Bool
}

nonisolated struct EmptyRequestBody: Encodable {}

nonisolated struct PreparedProfilePhoto {
    let data: Data
    let contentType: String
    let byteSize: Int64
    let width: Int
    let height: Int
}
