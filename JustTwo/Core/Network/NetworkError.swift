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
            return "No internet connection"
        case .tlsFailure:
            return "Secure connection failed"
        case .timeout:
            return "Request timed out"
        case .connectionLost:
            return "Network connection was lost"
        case .serverUnavailable:
            return "Server is temporarily unavailable"
        case .cancelled:
            return "Request cancelled"
        case .unauthorized:
            return "Authorization required"
        case .httpError(_, let response):
            return response?.message ?? "Request failed"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .invalidResponse:
            return "Invalid server response"
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
            return "Retry"
        case .unauthorized:
            return "Sign in"
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

    var userMessage: String {
        apiErrorMessage ?? localizedDescription
    }
}
