import Foundation

@MainActor
@Observable
final class AppRouter {

    static let shared = AppRouter()

    var screen: AppScreen = .splash
    var splashError: NetworkError?
    var reloadID = UUID()

    var pendingInviteToken: String?
    var presentedInvitePreviewToken: String?
    var selectedMainTab: AppTab = .discover
    var pendingChatConversation: ChatConversationPreview?
    var pendingChatMessageID: UUID?

    private init() {}

    func goTo(_ screen: AppScreen) {
        self.screen = screen
    }

    func resetTo(_ screen: AppScreen) {
        self.screen = screen
        splashError = nil
        if screen == .main {
            PushNotificationRoutingCoordinator.shared.applyPendingRouteIfPossible()
        }
    }

    func handleSplash(_ state: SplashState) {
        switch state {
        case .loading:
            break

        case .networkError(let error):
            splashError = error
            screen = .splash

        case .offlineRecoverable:
            splashError = nil
            screen = .splash

        case .result(let result):
            splashError = nil

            switch result {
            case .needAuth:
                resetTo(.auth)
            case .needEmailVerification(let email):
                showCheckEmail(email: email)
            case .needProfileSetup:
                resetTo(.profileSetup)
            case .ready:
                resetTo(.main)
                presentPendingInviteIfNeeded()
            }
        }
    }

    func retrySplash() {
        splashError = nil
        reloadID = UUID()
        screen = .splash
    }

    func showCheckEmail(email: String, message: String? = nil) {
        resetTo(.checkEmail(email: email, message: message))
    }

    func showEmailVerificationResult(token: String) {
        resetTo(.emailVerificationResult(token: token))
    }

    func showEmailVerificationError(_ message: String) {
        resetTo(.emailVerificationError(message: message))
    }

    func showResetPassword(token: String) {
        resetTo(.resetPassword(token: token))
    }

    func showResetPasswordError(_ message: String) {
        resetTo(.resetPasswordError(message: message))
    }

    func handleIncomingInvite(token: String, session: SessionStore) {
        pendingInviteToken = token

        guard session.hasActiveSession else {
            resetTo(.auth)
            return
        }

        guard session.isEmailVerified else {
            if let email = session.pendingVerificationEmail ?? session.currentUser?.email {
                showCheckEmail(
                    email: email,
                    message: String(localized: "invite.error.login_required")
                )
            } else {
                resetTo(.auth)
            }
            return
        }

        if screen == .main {
            presentedInvitePreviewToken = token
        } else if screen == .profileSetup {
            // Profile setup can finish before showing invite preview.
            presentedInvitePreviewToken = token
        } else {
            retrySplash()
        }
    }

    func presentPendingInviteIfNeeded() {
        guard let token = pendingInviteToken else { return }
        presentedInvitePreviewToken = token
    }

    func dismissInvitePreview() {
        presentedInvitePreviewToken = nil
        pendingInviteToken = nil
    }

    func openChatAfterInviteAccept(_ conversation: ChatConversationPreview) {
        openChat(conversation)
        presentedInvitePreviewToken = nil
        pendingInviteToken = nil
    }

    func openChat(_ conversation: ChatConversationPreview, messageID: UUID? = nil) {
        pendingChatConversation = conversation
        pendingChatMessageID = messageID
        selectedMainTab = .chats
    }

    func clearPendingChatNavigation() {
        pendingChatConversation = nil
        pendingChatMessageID = nil
    }

    func clearPendingChatConversation() {
        clearPendingChatNavigation()
    }
}
