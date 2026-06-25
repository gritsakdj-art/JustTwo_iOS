import SwiftUI

struct ChatBubbleView: View {
    let text: String
    let senderName: String?
    let createdAt: Date
    let isMine: Bool
    var replyPreview: String?
    var isEdited: Bool = false
    var isDeleted: Bool = false
    var reactions: [ChatMessageReaction] = []
    var onReactionTap: ((ChatMessageReaction) -> Void)?

    private enum UI {
        static let tailWidth: CGFloat = 12
        static let textHPad: CGFloat = 14
        static let topPad: CGFloat = 10
        static let bottomForTime: CGFloat = 22
        static let bottomForReactionsRow: CGFloat = 30
        static let textLift: CGFloat = 3
        static let bottomInset: CGFloat = 8
        static let maxWidth: CGFloat = 320
        static let sideInset: CGFloat = 48
    }

    var body: some View {
        VStack(
            alignment: isMine ? .trailing : .leading,
            spacing: 6
        ) {
            if let senderName {
                Text(senderName)
                    .font(Font.App.caption(weight: .semibold))
                    .foregroundStyle(
                        isMine
                            ? Color.discoverViolet.opacity(0.9)
                            : Color.discoverVioletLight.opacity(0.9)
                    )
                    .padding(.horizontal, 4)
            }

            bubbleBody
        }
        .frame(maxWidth: UI.maxWidth, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, UI.sideInset)
        .padding(.vertical, 4)
    }

    private var contentBottomPadding: CGFloat {
        UI.textLift + (reactions.isEmpty ? UI.bottomForTime : UI.bottomForReactionsRow)
    }

    private var bottomLeadingInset: CGFloat {
        UI.textHPad + (isMine ? 0 : UI.tailWidth)
    }

    private var bottomTrailingInset: CGFloat {
        UI.textHPad + (isMine ? UI.tailWidth : 0)
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyPreview {
                Text(replyPreview)
                    .font(Font.App.caption())
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.discoverViolet.opacity(0.08))
                    )
            }

            Text(text)
                .font(Font.App.body())
                .foregroundStyle(isDeleted ? Color.secondaryText : Color.primaryText)
                .italic(isDeleted)
                .multilineTextAlignment(.leading)
        }
        .padding(.top, UI.topPad)
        .padding(.bottom, contentBottomPadding)
        .padding(.leading, UI.textHPad + (isMine ? 0 : UI.tailWidth))
        .padding(.trailing, UI.textHPad + (isMine ? UI.tailWidth : 0))
        .background(
            ChatBubbleShape(isMine: isMine)
                .fill(isMine ? Color.chatBubbleMine : Color.chatBubbleOther)
                .overlay(
                    ChatBubbleShape(isMine: isMine)
                        .stroke(
                            Color.glassBorderHighlight.opacity(isMine ? 0.18 : 0.12),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 3, x: 0, y: 1)
                .shadow(color: Color.discoverCardShadow.opacity(0.12), radius: 10, x: 0, y: 6)
        )
        .overlay(alignment: .bottom) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if !reactions.isEmpty {
                    ChatMessageReactionsView(
                        reactions: reactions,
                        onTap: onReactionTap
                    )
                }

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    if isEdited {
                        Text("chats.edited")
                            .font(Font.App.caption(size: 11))
                            .foregroundStyle(Color.secondaryText.opacity(0.75))
                    }

                    Text(createdAt, style: .time)
                        .font(Font.App.caption(size: 11))
                        .foregroundStyle(Color.secondaryText.opacity(0.75))
                        .monospacedDigit()
                }
                .allowsHitTesting(false)
            }
            .padding(.leading, bottomLeadingInset)
            .padding(.trailing, bottomTrailingInset)
            .padding(.bottom, UI.bottomInset)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ChatBubbleView(
            text: "Hello, this is a longer incoming message to see how it wraps.",
            senderName: "Emma",
            createdAt: Date(),
            isMine: false,
            replyPreview: "Previous message preview",
            reactions: [
                ChatMessageReaction(emoji: "👍", count: 2, reactedByMe: false),
                ChatMessageReaction(emoji: "❤️", count: 1, reactedByMe: true)
            ]
        )

        ChatBubbleView(
            text: "Sounds great!",
            senderName: nil,
            createdAt: Date().addingTimeInterval(-300),
            isMine: true,
            isEdited: true,
            reactions: [
                ChatMessageReaction(emoji: "😂", count: 1, reactedByMe: true)
            ]
        )
    }
    .padding()
    .background(Color.discoverBackgroundGradient)
}
