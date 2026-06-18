import SwiftUI

struct MatchesView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "heart.fill",
            title: "tab.matches",
            subtitle: "placeholder.matches.subtitle"
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        MatchesView()
    }
}
