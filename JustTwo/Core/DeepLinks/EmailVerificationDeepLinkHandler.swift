import Foundation

enum EmailVerificationDeepLinkResult: Equatable {
    case verifyEmail(token: String)
    case resetPassword(token: String)
    case invalid(message: String)
    case ignored
}

enum EmailVerificationDeepLinkHandler {
    static func parse(_ url: URL) -> EmailVerificationDeepLinkResult {
        guard let deepLink = DeepLinkParser.parse(url) else { return .ignored }

        switch deepLink {
        case .emailVerification(let token):
            return .verifyEmail(token: token)
        case .passwordReset(let token):
            return .resetPassword(token: token)
        case .invalidAuthLink(let message, _):
            return .invalid(message: message)
        case .invite:
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
}
