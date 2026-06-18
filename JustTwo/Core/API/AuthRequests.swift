import Foundation

struct LoginRequest: EncodableAPIRequest {
    typealias Response = AuthResponse

    let email: String
    let password: String

    var path: String { "auth/login" }
    var method: HTTPMethod { .post }
    var bodyValue: LoginRequestBody? {
        LoginRequestBody(email: email, password: password)
    }
}

struct RegisterRequest: EncodableAPIRequest {
    typealias Response = AuthResponse

    let email: String
    let password: String

    var path: String { "auth/register" }
    var method: HTTPMethod { .post }
    var bodyValue: RegisterRequestBody? {
        RegisterRequestBody(email: email, password: password)
    }
}

struct CurrentUserRequest: APIRequest {
    typealias Response = UserResponse

    var path: String { "me" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}
