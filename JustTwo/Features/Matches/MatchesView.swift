import SwiftUI

struct MatchesView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "heart.fill",
            title: "Matches",
            subtitle: "People you liked and mutual matches will appear here."
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        MatchesView()
    }
}
