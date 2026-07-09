import Foundation

enum MessengerOutboxErrorCode: String, Sendable, Equatable {
    case networkUnavailable
    case timeout
    case unauthorized
    case serverError
    case uploadFailed
    case createMessageFailed
    case missingPendingMedia
    case cancelled
    case unknown

    var blocksAutomaticRetry: Bool {
        switch self {
        case .unauthorized, .missingPendingMedia, .cancelled:
            return true
        case .networkUnavailable, .timeout, .serverError, .uploadFailed, .createMessageFailed, .unknown:
            return false
        }
    }

  nonisolated static func classify(_ error: Error) -> MessengerOutboxErrorCode {
        if error is CancellationError {
            return .cancelled
        }

        let sanitized = MessengerDiagnostics.sanitizeError(error)
        switch sanitized {
        case "network", "noInternet":
            return .networkUnavailable
        case "timeout":
            return .timeout
        case "unauthorized":
            return .unauthorized
        case "server", "http500", "http502", "http503":
            return .serverError
        case "cancelled":
            return .cancelled
        default:
            if sanitized.hasPrefix("http") {
                return .serverError
            }
            return .unknown
        }
    }

    nonisolated static func classifyUploadFailure(_ error: Error) -> MessengerOutboxErrorCode {
        let base = classify(error)
        if base == .unknown || base == .networkUnavailable || base == .timeout {
            return .uploadFailed
        }
        return base
    }

    nonisolated static func classifyCreateMessageFailure(_ error: Error) -> MessengerOutboxErrorCode {
        let base = classify(error)
        if base == .unknown || base == .networkUnavailable || base == .timeout {
            return .createMessageFailed
        }
        return base
    }
}
