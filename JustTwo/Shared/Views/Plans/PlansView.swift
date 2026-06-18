import SwiftUI

struct PlansView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "calendar.badge.clock",
            title: "tab.plans",
            subtitle: "placeholder.plans.subtitle"
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        PlansView()
    }
}
