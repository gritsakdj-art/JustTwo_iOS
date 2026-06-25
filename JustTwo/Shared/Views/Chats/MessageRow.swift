import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let senderName: String?

    var body: some View {
        HStack {
            if message.isMine { Spacer() }

            ChatBubbleView(
                text: message.text,
                senderName: senderName,
                createdAt: message.createdAt,
                isMine: message.isMine
            )

            if !message.isMine { Spacer() }
        }
        .padding(.horizontal, 12)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 8) {
            MessageRow(
                message: ChatMessage(
                    id: UUID(),
                    text: "Hey! Want to grab coffee this weekend?",
                    createdAt: Date().addingTimeInterval(-3_600),
                    isMine: false
                ),
                senderName: "Emma"
            )

            MessageRow(
                message: ChatMessage(
                    id: UUID(),
                    text: "Sounds great — Saturday works for me.",
                    createdAt: Date(),
                    isMine: true
                ),
                senderName: nil
            )
        }
        .padding(.vertical, 8)
    }
    .background(Color.discoverBackgroundGradient)
}
