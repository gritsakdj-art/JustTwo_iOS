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

struct ResendVerificationRequest: EncodableAPIRequest {
    typealias Response = MessageResponse

    let email: String

    var path: String { "auth/resend-verification" }
    var method: HTTPMethod { .post }
    var bodyValue: ResendVerificationRequestBody? {
        ResendVerificationRequestBody(email: email)
    }
}

struct VerifyEmailRequest: APIRequest {
    typealias Response = MessageResponse

    let token: String

    var path: String { "auth/verify-email" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "token", value: token)]
    }
}

struct VerifyEmailSessionRequest: EncodableAPIRequest {
    typealias Response = AuthResponse

    let token: String

    var path: String { "auth/verify-email-session" }
    var method: HTTPMethod { .post }
    var bodyValue: VerifyEmailSessionRequestBody? {
        VerifyEmailSessionRequestBody(token: token)
    }
}
