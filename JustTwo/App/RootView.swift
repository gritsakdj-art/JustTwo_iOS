import SwiftUI

struct RootView: View {
    @State private var router = AppRouter.shared
    @State private var session = SessionStore.shared
    @AppStorage("app.theme") private var selectedThemeRawValue = AppTheme.system.rawValue

    var body: some View {
        RootRouterView()
            .id(router.reloadID)
            .environment(router)
            .environment(session)
            .preferredColorScheme(selectedTheme.colorScheme)
            .onOpenURL { url in
                EmailVerificationDeepLinkHandler.handle(url, router: router)
            }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }
}

#Preview {
    RootView()
}
