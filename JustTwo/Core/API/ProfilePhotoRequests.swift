import Foundation

struct ListProfilePhotosRequest: APIRequest {
    typealias Response = ProfilePhotosResponse

    var path: String { "profile/me/photos" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}

struct CreateProfilePhotoUploadURLRequest: EncodableAPIRequest {
    typealias Response = CreateProfilePhotoUploadURLResponse
    typealias Body = CreateProfilePhotoUploadURLRequestBody

    let bodyValue: CreateProfilePhotoUploadURLRequestBody?

    var path: String { "profile/me/photos/upload-url" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }

    init(body: CreateProfilePhotoUploadURLRequestBody) {
        bodyValue = body
    }
}

struct CompleteProfilePhotoUploadRequest: EncodableAPIRequest {
    typealias Response = CompleteProfilePhotoUploadResponse
    typealias Body = EmptyRequestBody

    let uploadID: UUID
    let bodyValue: EmptyRequestBody?

    var path: String { "profile/me/photos/uploads/\(uploadID.uuidString)/complete" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }

    init(uploadID: UUID) {
        self.uploadID = uploadID
        bodyValue = EmptyRequestBody()
    }
}

struct SetPrimaryProfilePhotoRequest: APIRequest {
    typealias Response = CompleteProfilePhotoUploadResponse

    let photoID: UUID

    var path: String { "profile/me/photos/\(photoID.uuidString)/primary" }
    var method: HTTPMethod { .patch }
    var requiresAuth: Bool { true }
}

struct ReorderProfilePhotosRequest: EncodableAPIRequest {
    typealias Response = ProfilePhotosResponse
    typealias Body = ReorderProfilePhotosRequestBody

    let bodyValue: ReorderProfilePhotosRequestBody?

    var path: String { "profile/me/photos/reorder" }
    var method: HTTPMethod { .patch }
    var requiresAuth: Bool { true }

    init(photoIDs: [UUID]) {
        bodyValue = ReorderProfilePhotosRequestBody(photoIds: photoIDs)
    }
}

struct UpdateAvatarPresentationRequest: EncodableAPIRequest {
    typealias Response = CompleteProfilePhotoUploadResponse
    typealias Body = UpdateAvatarPresentationRequestBody

    let photoID: UUID
    let bodyValue: UpdateAvatarPresentationRequestBody?

    var path: String { "profile/me/photos/\(photoID.uuidString)/presentation" }
    var method: HTTPMethod { .patch }
    var requiresAuth: Bool { true }

    init(photoID: UUID, presentation: AvatarPresentationDTO) {
        self.photoID = photoID
        bodyValue = UpdateAvatarPresentationRequestBody(
            offsetX: presentation.offsetX,
            offsetY: presentation.offsetY,
            scale: presentation.scale
        )
    }
}

struct DeleteProfilePhotoRequest: APIRequest {
    typealias Response = DeleteProfilePhotoResponse

    let photoID: UUID

    var path: String { "profile/me/photos/\(photoID.uuidString)" }
    var method: HTTPMethod { .delete }
    var requiresAuth: Bool { true }
}

struct GetProfilePhotoDownloadURLRequest: APIRequest {
    typealias Response = ProfilePhotoDownloadURLResponse

    let photoID: UUID

    var path: String { "profile/photos/\(photoID.uuidString)/download-url" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}
