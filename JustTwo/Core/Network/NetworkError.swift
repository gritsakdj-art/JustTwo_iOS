import Foundation

enum NetworkError: LocalizedError, Identifiable, Sendable {

    case noInternet
    case tlsFailure
    case timeout
    case connectionLost
    case serverUnavailable
    case cancelled
    case unauthorized
    case httpError(statusCode: Int, response: APIErrorResponse?)
    case decodingError(String)
    case invalidResponse
    case unknown(Error)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .noInternet:
            return String(localized: "network.error.no_internet")
        case .tlsFailure:
            return String(localized: "network.error.tls_failure")
        case .timeout:
            return String(localized: "network.error.timeout")
        case .connectionLost:
            return String(localized: "network.error.connection_lost")
        case .serverUnavailable:
            return String(localized: "network.error.server_unavailable")
        case .cancelled:
            return String(localized: "network.error.cancelled")
        case .unauthorized:
            return String(localized: "network.error.unauthorized")
        case .httpError(_, let response):
            return response?.userFriendlyMessage ?? String(localized: "network.error.request_failed")
        case .decodingError(let message):
            return String.localizedStringWithFormat(
                String(localized: "network.error.decoding_format"),
                message
            )
        case .invalidResponse:
            return String(localized: "network.error.invalid_response")
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    var systemImage: String {
        switch self {
        case .noInternet:
            return "wifi.slash"
        case .tlsFailure:
            return "lock.slash"
        case .timeout:
            return "clock.arrow.circlepath"
        case .connectionLost:
            return "wifi.exclamationmark"
        case .serverUnavailable:
            return "server.rack"
        case .cancelled:
            return "xmark.circle"
        case .unauthorized:
            return "person.crop.circle.badge.exclamationmark"
        case .httpError:
            return "exclamationmark.triangle"
        case .decodingError, .invalidResponse:
            return "doc.text.magnifyingglass"
        case .unknown:
            return "exclamationmark.triangle"
        }
    }
}

extension NetworkError {

    static func map(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }

        let ns = error as NSError

        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled:
                return .cancelled
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff:
                return .noInternet
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNetworkConnectionLost:
                return .connectionLost
            case NSURLErrorCannotLoadFromNetwork:
                return .serverUnavailable
            case NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return .serverUnavailable
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid:
                return .tlsFailure
            default:
                return .unknown(error)
            }
        }

        return .unknown(error)
    }

    var actionTitle: String? {
        switch self {
        case .noInternet, .tlsFailure, .timeout, .connectionLost, .serverUnavailable, .httpError:
            return String(localized: "common.retry")
        case .unauthorized:
            return String(localized: "auth.login")
        case .cancelled, .unknown, .decodingError, .invalidResponse:
            return nil
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .noInternet, .tlsFailure, .timeout, .connectionLost, .serverUnavailable:
            return true
        case .unauthorized, .cancelled, .unknown, .httpError, .decodingError, .invalidResponse:
            return false
        }
    }

    var isUserFacing: Bool {
        switch self {
        case .cancelled:
            return false
        default:
            return true
        }
    }

    var apiErrorCode: String? {
        guard case .httpError(_, let response) = self else { return nil }
        return response?.code
    }

    var apiErrorMessage: String? {
        guard case .httpError(_, let response) = self else { return nil }
        return response?.message
    }

    var isProfileNotFound: Bool {
        apiErrorCode == "profile_not_found"
    }

    var isEmailNotVerified: Bool {
        apiErrorCode == "email_not_verified"
    }

    var isInvalidCredentials: Bool {
        apiErrorCode == "invalid_credentials"
    }

    var isInvalidPassword: Bool {
        apiErrorCode == "invalid_password"
    }

    var isInvalidOrExpiredVerificationToken: Bool {
        apiErrorCode == "invalid_or_expired_verification_token"
    }

    var isInvalidOrExpiredPasswordResetToken: Bool {
        apiErrorCode == "invalid_or_expired_password_reset_token"
    }

    var isValidationFailed: Bool {
        apiErrorCode == "validation_failed"
    }

    var isUserBlocked: Bool {
        apiErrorCode == "user_blocked"
    }

    var isConversationNotFound: Bool {
        apiErrorCode == "conversation_not_found"
    }

    var isMessageNotFound: Bool {
        apiErrorCode == "message_not_found"
    }

    var isUnauthorized: Bool {
        switch self {
        case .unauthorized:
            return true
        case .httpError(let statusCode, let response):
            guard statusCode == 401 else { return false }
            let code = response?.errorCode
            return code == nil || code == .missingToken || code == .invalidToken
        default:
            return false
        }
    }

    var shouldClearSession: Bool {
        isUnauthorized
    }

    var userMessage: String {
        if case .httpError(_, let response) = self {
            return response?.userFriendlyMessage ?? localizedDescription
        }
        return localizedDescription
    }
}
