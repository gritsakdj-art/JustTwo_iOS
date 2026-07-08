import SwiftUI
import SwiftData

@main
struct JustTwoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        AppModelContainerFactory.makeSharedContainer()
    }()

    init() {
        AppFontRegistrar.registerFonts()
        AppTabBarAppearance.configure()
        PushRegistrationService.shared.configure()
        AppBuildEnvironment.beginTestFlightResolutionIfNeeded()
        MessengerLocalStore.configureShared(modelContainer: sharedModelContainer)
        #if DEBUG
        MainThreadHangDiagnostics.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
