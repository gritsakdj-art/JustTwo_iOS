import SwiftUI

struct ProfileView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "person.crop.circle.fill",
            title: "Profile",
            subtitle: "Your photos, preferences, and account settings will be managed here."
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        ProfileView()
    }
}
