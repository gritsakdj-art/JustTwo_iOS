import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

protocol APIRequest {
    associatedtype Response: Decodable

    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var requiresAuth: Bool { get }
}

extension APIRequest {
    var queryItems: [URLQueryItem] { [] }
    var headers: [String: String] { [:] }
    var body: Data? { nil }
    var requiresAuth: Bool { false }
}

protocol EncodableAPIRequest: APIRequest {
    associatedtype Body: Encodable

    var bodyValue: Body? { get }
}

extension EncodableAPIRequest {
    var body: Data? {
        guard let bodyValue else { return nil }
        return try? JSONCoding.encoder.encode(bodyValue)
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder = JSONDecoder.justTwoAPI
}

extension JSONDecoder {
    static var justTwoAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string) {
                return date
            }

            if let date = ISO8601DateFormatter.standard.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(string)"
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum APIErrorCode: String {
    case emailAlreadyExists = "email_already_exists"
    case invalidEmail = "invalid_email"
    case weakPassword = "weak_password"
    case invalidCredentials = "invalid_credentials"
    case emailNotVerified = "email_not_verified"
    case missingToken = "missing_token"
    case invalidToken = "invalid_token"
    case profileNotFound = "profile_not_found"
    case invalidGender = "invalid_gender"
    case ageRestricted = "age_restricted"
    case validationFailed = "validation_failed"
    case invalidProfileModes = "invalid_profile_modes"
    case invalidOrExpiredVerificationToken = "invalid_or_expired_verification_token"
    case invalidOrExpiredPasswordResetToken = "invalid_or_expired_password_reset_token"
    case emailDeliveryFailed = "email_delivery_failed"
    case invalidPassword = "invalid_password"
    case accountDeletionFailed = "account_deletion_failed"
}

struct APIErrorResponse: Decodable, Error {
    let success: Bool
    let code: String
    let message: String
    let field: String?

    var errorCode: APIErrorCode? {
        APIErrorCode(rawValue: code)
    }

    var userFriendlyMessage: String {
        switch errorCode {
        case .emailAlreadyExists:
            return String(localized: "auth.error.email_already_exists")
        case .invalidEmail:
            return String(localized: "auth.error.invalid_email")
        case .weakPassword:
            return String(localized: "auth.error.weak_password")
        case .invalidCredentials:
            return String(localized: "auth.error.invalid_credentials")
        case .emailNotVerified:
            return String(localized: "auth.error.email_not_verified")
        case .missingToken, .invalidToken:
            return String(localized: "auth.error.session_expired")
        case .profileNotFound:
            return String(localized: "profile.error.not_found")
        case .invalidGender:
            return String(localized: "profile.error.invalid_gender")
        case .ageRestricted:
            return String(localized: "profile.error.age_restricted")
        case .invalidProfileModes:
            return String(localized: "profile.error.invalid_modes")
        case .invalidOrExpiredVerificationToken:
            return String(localized: "email_verification.error.invalid_or_expired")
        case .invalidOrExpiredPasswordResetToken:
            return String(localized: "auth.error.invalid_or_expired_password_reset_token")
        case .emailDeliveryFailed:
            return String(localized: "email_verification.error.delivery_failed")
        case .invalidPassword:
            return String(localized: "profile.account.error.incorrect_password")
        case .accountDeletionFailed:
            return String(localized: "profile.account.error.deletion_failed")
        case .validationFailed, .none:
            return errorCode == .validationFailed ? String(localized: "common.error.validation_failed") : message
        }
    }
}

struct HealthResponse: Decodable {
    let status: String
    let service: String
}

struct HealthCheckRequest: APIRequest {
    typealias Response = HealthResponse

    var path: String { "health" }
    var method: HTTPMethod { .get }
}
