import SwiftUI

private struct IsDiscoverShellKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDiscoverShell: Bool {
        get { self[IsDiscoverShellKey.self] }
        set { self[IsDiscoverShellKey.self] = newValue }
    }
}

extension View {
    /// Uses a clear background inside `DiscoverView` so the shell gradient shows through;
    /// keeps `discoverBackgroundGradient` when presented standalone (onboarding, previews).
    func discoverShellBackground() -> some View {
        modifier(DiscoverShellBackgroundModifier())
    }
}

private struct DiscoverShellBackgroundModifier: ViewModifier {
    @Environment(\.isDiscoverShell) private var isDiscoverShell

    func body(content: Content) -> some View {
        content.background {
            if isDiscoverShell {
                Color.clear
            } else {
                Color.discoverBackgroundGradient.ignoresSafeArea()
            }
        }
    }
}
