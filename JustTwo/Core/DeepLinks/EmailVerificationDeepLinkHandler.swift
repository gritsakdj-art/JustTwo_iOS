import Foundation

enum EmailVerificationDeepLinkResult: Equatable {
    case verifyEmail(token: String)
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
            return .invalid(message: String(localized: "email_verification.error.missing_token"))
        }

        return .verifyEmail(token: token)
    }

    @MainActor
    static func handle(_ url: URL, router: AppRouter) {
        switch parse(url) {
        case .verifyEmail(let token):
            router.showEmailVerificationResult(token: token)
        case .invalid(let message):
            router.showEmailVerificationError(message)
        case .ignored:
            break
        }
    }

    private static func isSupportedURL(_ url: URL) -> Bool {
        if url.scheme == "https",
           url.host == "api.jtwo.online",
           url.path == "/auth/verify-email" {
            return true
        }

        return false
    }
}
