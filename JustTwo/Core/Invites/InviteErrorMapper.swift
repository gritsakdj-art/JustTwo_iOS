import Foundation

enum InviteErrorMapper {
    static func previewMessage(for error: NetworkError) -> String {
        switch error.apiErrorCode {
        case "invalid_invite_token":
            return String(localized: "invite.error.invalid")
        case "invite_expired":
            return String(localized: "invite.error.expired")
        case "invite_revoked", "invite_already_used":
            return String(localized: "invite.error.unavailable")
        case "cannot_accept_own_invite":
            return String(localized: "invite.error.own_invite")
        case "message_privacy_restricted":
            return String(localized: "invite.error.privacy_restricted")
        case "user_blocked":
            return String(localized: "chats.error.user_blocked")
        default:
            if error.isUnauthorized {
                return String(localized: "invite.error.login_required")
            }
            return error.userMessage
        }
    }

    static func isUnavailable(_ error: NetworkError) -> Bool {
        switch error.apiErrorCode {
        case "invalid_invite_token", "invite_expired", "invite_revoked", "invite_already_used",
             "cannot_accept_own_invite", "message_privacy_restricted":
            return true
        default:
            return false
        }
    }

    static func acceptMessage(for error: NetworkError) -> String {
        previewMessage(for: error)
    }
}
