import SwiftUI

struct ChatsView: View {
    @State private var route: ChatRoute?

    private struct ChatRoute: Identifiable, Hashable {
        let conversation: ChatConversationPreview
        var id: UUID { conversation.id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                conversationsList
            }
            .discoverShellBackground()
            .navigationDestination(item: $route) { route in
                PrivateChatView(conversation: route.conversation)
                    .discoverShellBackground()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("chats.header")
                .font(Font.App.headline(size: 17, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.clear
                .overlay(alignment: .bottom) {
                    Divider().overlay(Color.hairline)
                }
        )
    }

    private var conversationsList: some View {
        List {
            ForEach(ChatUIMockData.conversations) { conversation in
                ChatConversationRow(conversation: conversation) {
                    route = ChatRoute(conversation: conversation)
                }
                .listRowInsets(.init())
                .listRowSeparatorTint(Color.hairline)
                .listRowBackground(Color.clear)
            }

            if ChatUIMockData.conversations.isEmpty {
                Text("chats.empty")
                    .font(Font.App.subheadline())
                    .foregroundStyle(Color.secondaryText)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ChatsView()
        .environment(\.isDiscoverShell, true)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
}
