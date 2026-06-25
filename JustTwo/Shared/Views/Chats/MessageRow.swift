import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let senderName: String?
    let onLongPress: () -> Void
    var onReactionTap: ((ChatMessageReaction) -> Void)?

    var body: some View {
        HStack {
            if message.isMine { Spacer() }

            ChatBubbleView(
                text: message.displayText,
                senderName: senderName,
                createdAt: message.createdAt,
                isMine: message.isMine,
                replyPreview: message.replyPreview?.body,
                isEdited: message.isEdited,
                isDeleted: message.isDeleted,
                reactions: message.reactions,
                onReactionTap: onReactionTap
            )
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35) {
                guard message.canReply || message.canCopy || message.canEdit || message.canDelete || message.canReact else {
                    return
                }
                onLongPress()
            }

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
                    displayText: "Hey! Want to grab coffee this weekend?",
                    rawBody: "Hey! Want to grab coffee this weekend?",
                    createdAt: Date().addingTimeInterval(-3_600),
                    isMine: false,
                    isDeleted: false,
                    isEdited: false,
                    replyPreview: nil,
                    reactions: [
                        ChatMessageReaction(emoji: "👍", count: 1, reactedByMe: false)
                    ]
                ),
                senderName: "Emma",
                onLongPress: {}
            )

            MessageRow(
                message: ChatMessage(
                    id: UUID(),
                    displayText: "Sounds great — Saturday works for me.",
                    rawBody: "Sounds great — Saturday works for me.",
                    createdAt: Date(),
                    isMine: true,
                    isDeleted: false,
                    isEdited: true,
                    replyPreview: ChatReplyPreview(
                        id: UUID(),
                        body: "Want to grab coffee?",
                        isDeleted: false
                    ),
                    reactions: []
                ),
                senderName: nil,
                onLongPress: {}
            )
        }
        .padding(.vertical, 8)
    }
    .background(Color.discoverBackgroundGradient)
}
