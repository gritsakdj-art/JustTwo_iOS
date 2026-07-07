import Foundation

struct LoginRequestBody: Encodable {
    let email: String
    let password: String
}

struct RegisterRequestBody: Encodable {
    let email: String
    let password: String
}

struct ForgotPasswordRequestBody: Encodable {
    let email: String
}

struct ResetPasswordRequestBody: Encodable {
    let token: String
    let newPassword: String
}

struct DeleteAccountRequestBody: Encodable {
    let password: String
}

struct AuthResponse: Decodable {
    let success: Bool
    let message: String
    let token: String?
    let user: UserResponse?
    let verificationRequired: Bool?

    var requiresEmailVerification: Bool {
        verificationRequired == true && token == nil
    }
}

nonisolated struct UserResponse: Decodable, Sendable {
    let id: UUID
    let email: String
    let emailVerified: Bool
    let emailVerifiedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailVerified
        case emailVerifiedAt
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        email: String,
        emailVerified: Bool = false,
        emailVerifiedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.emailVerified = emailVerified
        self.emailVerifiedAt = emailVerifiedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        emailVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .emailVerifiedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct ResendVerificationRequestBody: Encodable {
    let email: String
}

struct VerifyEmailSessionRequestBody: Encodable {
    let token: String
}

struct MessageResponse: Decodable {
    let success: Bool
    let message: String
}
