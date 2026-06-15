import SwiftUI

struct PlansView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "calendar.badge.clock",
            title: "Plans",
            subtitle: "Upcoming dates, invites, and saved ideas will appear here."
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        PlansView()
    }
}
