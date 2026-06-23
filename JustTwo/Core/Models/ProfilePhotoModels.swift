import Foundation

struct AvatarPresentationDTO: Codable, Equatable, Sendable {
    let offsetX: Double
    let offsetY: Double
    let scale: Double

    static let identity = AvatarPresentationDTO(offsetX: 0, offsetY: 0, scale: 1)
}

struct ProfilePhotoDTO: Decodable, Identifiable, Equatable, Sendable {
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

struct ProfilePhotosResponse: Decodable {
    let photos: [ProfilePhotoDTO]
}

struct ReorderProfilePhotosRequestBody: Encodable {
    let photoIds: [UUID]
}

struct UpdateAvatarPresentationRequestBody: Encodable {
    let offsetX: Double
    let offsetY: Double
    let scale: Double
}

struct CreateProfilePhotoUploadURLRequestBody: Encodable {
    let contentType: String
    let byteSize: Int64
    let width: Int?
    let height: Int?
    let position: Int?
    let isPrimary: Bool?
}

struct ProfilePhotoUploadDTO: Decodable {
    let id: UUID
    let photoId: UUID
    let storageKey: String
    let uploadUrl: String
    let method: String
    let headers: [String: String]
    let expiresAt: Date
}

struct CreateProfilePhotoUploadURLResponse: Decodable {
    let upload: ProfilePhotoUploadDTO
}

struct CompleteProfilePhotoUploadResponse: Decodable {
    let photo: ProfilePhotoDTO
}

struct ProfilePhotoDownloadURLDTO: Decodable {
    let id: UUID
    let downloadUrl: String
    let expiresAt: Date
}

struct ProfilePhotoDownloadURLResponse: Decodable {
    let photo: ProfilePhotoDownloadURLDTO
}

struct DeleteProfilePhotoResponse: Decodable {
    let success: Bool
}

struct EmptyRequestBody: Encodable {}

struct PreparedProfilePhoto {
    let data: Data
    let contentType: String
    let byteSize: Int64
    let width: Int
    let height: Int
}
