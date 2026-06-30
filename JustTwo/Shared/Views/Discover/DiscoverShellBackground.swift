import SwiftUI

extension View {
    /// Applies the app shell gradient behind tab and profile screens.
    func discoverShellBackground() -> some View {
        modifier(DiscoverShellBackgroundModifier())
    }
}

private struct DiscoverShellBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            Color.discoverBackgroundGradient
                .ignoresSafeArea()
        }
    }
}
