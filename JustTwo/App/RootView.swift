import SwiftUI

struct RootView: View {
    @State private var router = AppRouter.shared
    @State private var session = SessionStore.shared
    @State private var photoStore = ProfilePhotoStore.shared
    @State private var avatarCropStore = ProfileAvatarCropStore.shared
    @Environment(\.layoutDirection) private var systemLayoutDirection
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app.language") private var selectedLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage("app.theme") private var selectedThemeRawValue = AppTheme.system.rawValue

    var body: some View {
        RootRouterView()
            .id(router.reloadID)
            .environment(router)
            .environment(session)
            .environment(photoStore)
            .environment(avatarCropStore)
            .environment(\.locale, selectedLanguage.locale)
            .environment(\.layoutDirection, selectedLanguage.layoutDirection(system: systemLayoutDirection))
            .preferredColorScheme(selectedTheme.colorScheme)
            .onOpenURL { url in
                AppDeepLinkHandler.handle(url, router: router, session: session)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    session.applicationDidBecomeActive()
                case .background:
                    session.applicationDidEnterBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageRawValue) ?? .system
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }
}

#Preview {
    RootView()
}
