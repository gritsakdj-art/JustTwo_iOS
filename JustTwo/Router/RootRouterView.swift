import SwiftUI

struct RootRouterView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if router.screen == .main, session.isFullyAuthenticated {
                DiscoverView()
            } else {
                NavigationStack {
                    screenContent
                }
            }
        }
        .animation(nil, value: router.screen)
        .animation(nil, value: router.reloadID)
    }

    @ViewBuilder
    private var screenContent: some View {
        switch router.screen {
        case .splash:
            SplashView()

        case .auth:
            AuthView()

        case .checkEmail(let email, let message):
            CheckEmailView(email: email, initialMessage: message)

        case .emailVerificationResult(let token):
            EmailVerificationResultView(token: token)

        case .emailVerificationError(let message):
            EmailVerificationResultView(initialState: .genericError(message))

        case .profileSetup:
            if session.isFullyAuthenticated {
                ProfileSettingsView(context: .onboarding)
            } else {
                verificationGateOrAuth
            }

        case .main:
            verificationGateOrAuth
        }
    }

    @ViewBuilder
    private var verificationGateOrAuth: some View {
        if let email = session.pendingVerificationEmail ?? session.currentUser?.email {
            CheckEmailView(email: email)
        } else {
            AuthView()
        }
    }
}

#Preview {
    RootRouterView()
        .environment(AppRouter.shared)
        .environment(SessionStore.shared)
}
