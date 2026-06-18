import SwiftUI

struct RootView: View {
    @State private var session = SessionStore.shared
    @AppStorage("app.theme") private var selectedThemeRawValue = AppTheme.system.rawValue

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                loadingView
            case .auth:
                AuthView()
            case .profileSetup:
                NavigationStack {
                    ProfileSettingsView(context: .onboarding)
                }
            case .main:
                DiscoverView()
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
        .environment(session)
        .task {
            await session.bootstrap()
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.discoverBackgroundGradient.ignoresSafeArea()
            ProgressView()
                .tint(Color.brandPrimary)
        }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }
}

#Preview {
    RootView()
}
