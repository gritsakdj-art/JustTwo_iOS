import Foundation

struct LoginRequestBody: Encodable {
    let email: String
    let password: String
}

struct RegisterRequestBody: Encodable {
    let email: String
    let password: String
}

struct AuthResponse: Decodable {
    let success: Bool
    let message: String
    let token: String
    let user: UserResponse
}

struct UserResponse: Decodable {
    let id: UUID
    let email: String
    let createdAt: Date?
    let updatedAt: Date?
}
