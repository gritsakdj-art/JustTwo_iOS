import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let senderName: String?
    let onLongPress: (CGRect) -> Void
    var onRetry: (() -> Void)?
    var onReactionTap: ((ChatMessageReaction) -> Void)?

    @State private var bubbleFrame: CGRect = .zero

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
                deliveryStatus: message.deliveryStatus,
                localSendState: message.localSendState,
                onRetry: onRetry,
                onReactionTap: onReactionTap
            )
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
                bubbleFrame = frame
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                guard message.canReply || message.canCopy || message.canEdit || message.canDelete || message.canReact else {
                    return
                }
                onLongPress(bubbleFrame)
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
                    ],
                    deliveryStatus: nil
                ),
                senderName: "Emma",
                onLongPress: { _ in }
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
                    reactions: [],
                    deliveryStatus: .delivered
                ),
                senderName: nil,
                onLongPress: { _ in }
            )
        }
        .padding(.vertical, 8)
    }
    .background(Color.discoverBackgroundGradient)
}
