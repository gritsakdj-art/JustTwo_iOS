import Foundation

enum AppDeepLinkHandler {
    @MainActor
    static func handle(_ url: URL, router: AppRouter, session: SessionStore) {
        guard let deepLink = DeepLinkParser.parse(url) else { return }

        switch deepLink {
        case .emailVerification(let token):
            router.showEmailVerificationResult(token: token)

        case .passwordReset(let token):
            router.showResetPassword(token: token)

        case .invite(let token):
            router.handleIncomingInvite(token: token, session: session)

        case .invalidAuthLink(let message, let isPasswordReset):
            if isPasswordReset {
                router.showResetPasswordError(message)
            } else {
                router.showEmailVerificationError(message)
            }
        }
    }
}
