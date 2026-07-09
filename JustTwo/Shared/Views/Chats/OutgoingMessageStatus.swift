import Foundation

@MainActor
enum OutgoingMessageStatus {
    static func label(for state: MessageLocalSendState, isImage: Bool) -> String {
        label(
            for: state,
            isImage: isImage,
            isNetworkOffline: NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline
        )
    }

    static func label(
        for state: MessageLocalSendState,
        isImage: Bool,
        isNetworkOffline: Bool
    ) -> String {
        switch state {
        case .waitingForNetwork:
            if isNetworkOffline {
                return String(localized: "chats.message.willSendWhenOnline")
            }
            return String(localized: "chats.message.waitingForNetwork")
        case .sending:
            if isImage {
                return String(localized: "chats.message.sendingImage")
            }
            return String(localized: "chats.message.sending")
        case .uploading:
            if isImage {
                return String(localized: "chats.message.uploadingPhoto")
            }
            return String(localized: "chats.message.uploading")
        case .retrying:
            return String(localized: "chats.message.retrying")
        case .failed:
            return String(localized: "chats.message.sendFailed")
        }
    }

    static func diagnosticName(for state: MessageLocalSendState) -> String {
        switch state {
        case .waitingForNetwork: return "waitingForNetwork"
        case .sending: return "sending"
        case .uploading: return "uploading"
        case .retrying: return "retrying"
        case .failed: return "failed"
        }
    }
}

extension MessageLocalSendState {
    var isInFlight: Bool {
        switch self {
        case .sending, .uploading, .retrying:
            return true
        case .waitingForNetwork, .failed:
            return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .failed, .waitingForNetwork:
            return true
        case .sending, .uploading, .retrying:
            return false
        }
    }

    var showsProgressIndicator: Bool {
        switch self {
        case .sending, .uploading, .retrying:
            return true
        case .waitingForNetwork, .failed:
            return false
        }
    }
}
