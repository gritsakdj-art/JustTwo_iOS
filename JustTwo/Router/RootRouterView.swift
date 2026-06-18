import SwiftUI

struct RootRouterView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if router.screen == .main {
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
            ProfileSettingsView(context: .onboarding)

        case .main:
            EmptyView()
        }
    }
}

#Preview {
    RootRouterView()
        .environment(AppRouter.shared)
        .environment(SessionStore.shared)
}
