import SwiftUI

struct ChatsView: View {
    var body: some View {
        PlaceholderTabScreen(
            iconName: "bubble.left.and.bubble.right.fill",
            title: "Chats",
            subtitle: "New conversations and active chats will live here."
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        ChatsView()
    }
}
