import SwiftUI

struct ChatsView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "bubble.left.and.bubble.right.fill",
            title: "tab.chats",
            subtitle: "placeholder.chats.subtitle"
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        ChatsView()
    }
}
