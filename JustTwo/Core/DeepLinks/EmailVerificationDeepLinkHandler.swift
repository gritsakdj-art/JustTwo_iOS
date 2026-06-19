import Foundation

enum EmailVerificationDeepLinkResult: Equatable {
    case verifyEmail(token: String)
    case resetPassword(token: String)
    case invalid(message: String)
    case ignored
}

enum EmailVerificationDeepLinkHandler {
    static func parse(_ url: URL) -> EmailVerificationDeepLinkResult {
        guard isSupportedURL(url) else { return .ignored }

        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            return .invalid(message: missingTokenMessage(for: url.path))
        }

        switch url.path {
        case "/auth/verify-email":
            return .verifyEmail(token: token)
        case "/auth/reset-password":
            return .resetPassword(token: token)
        default:
            return .ignored
        }
    }

    @MainActor
    static func handle(_ url: URL, router: AppRouter) {
        switch parse(url) {
        case .verifyEmail(let token):
            router.showEmailVerificationResult(token: token)
        case .resetPassword(let token):
            router.showResetPassword(token: token)
        case .invalid(let message):
            if url.path == "/auth/reset-password" {
                router.showResetPasswordError(message)
            } else {
                router.showEmailVerificationError(message)
            }
        case .ignored:
            break
        }
    }

    private static func isSupportedURL(_ url: URL) -> Bool {
        if url.scheme == "https",
           url.host == "api.jtwo.online",
           ["/auth/verify-email", "/auth/reset-password"].contains(url.path) {
            return true
        }

        return false
    }

    private static func missingTokenMessage(for path: String) -> String {
        switch path {
        case "/auth/reset-password":
            return String(localized: "reset_password.error.missing_token")
        default:
            return String(localized: "email_verification.error.missing_token")
        }
    }
}
