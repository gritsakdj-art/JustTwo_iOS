import Foundation

struct GetProfileRequest: APIRequest {
    typealias Response = ProfileEnvelopeResponse

    var path: String { "profile/me" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}

struct UpsertProfileRequest: EncodableAPIRequest {
    typealias Response = ProfileEnvelopeResponse

    let bodyValue: UpsertProfileRequestBody?

    var path: String { "profile/me" }
    var method: HTTPMethod { .put }
    var requiresAuth: Bool { true }

    init(body: UpsertProfileRequestBody) {
        bodyValue = body
    }
}
