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
