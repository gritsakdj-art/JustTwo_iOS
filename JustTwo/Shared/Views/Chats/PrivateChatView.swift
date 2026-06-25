import SwiftUI

struct PrivateChatView: View {
    let conversation: ChatConversationPreview

    @State private var messages: [ChatMessage]
    @State private var draftText = ""

    init(conversation: ChatConversationPreview) {
        self.conversation = conversation
        _messages = State(initialValue: ChatUIMockData.messages(for: conversation.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesArea
            MessageInputView(text: $draftText, onSend: sendMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chatBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cardSurface.opacity(0.95), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            senderName: message.isMine ? nil : conversation.title
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private var chatBackground: some View {
        Color.discoverBackgroundGradient
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(conversation.title)
                    .font(Font.App.headline(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primaryText)

                Text("chats.personal")
                    .font(Font.App.caption())
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }

    private func sendMessage() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(
            ChatMessage(
                id: UUID(),
                text: trimmed,
                createdAt: Date(),
                isMine: true
            )
        )
        draftText = ""
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

#Preview {
    NavigationStack {
        PrivateChatView(conversation: ChatUIMockData.conversations[0])
    }
}
