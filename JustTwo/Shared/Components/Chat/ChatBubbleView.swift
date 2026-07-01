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
    var deliveryStatus: MessageDeliveryStatus?
    var onReactionTap: ((ChatMessageReaction) -> Void)?

    private enum UI {
        static let tailWidth: CGFloat = 12
        static let textHPad: CGFloat = 14
        static let topPad: CGFloat = 10
        static let textLift: CGFloat = 3
        static let maxWidth: CGFloat = 320
        static let sideInset: CGFloat = 48
        static let minWidth: CGFloat = 120
        static let minWidthEdited: CGFloat = 156
        static let timeClusterWidth: CGFloat = 54
        static let dateTimeClusterWidth: CGFloat = 108
        static let editedLabelWidth: CGFloat = 52
        static let receiptWidth: CGFloat = 22
        static let reactionMetadataSpacing: CGFloat = 4
        static let textToReactionsSpacing: CGFloat = 6
    }

    @ScaledMetric(relativeTo: .caption) private var bottomForTime: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var scaledTextToReactionsSpacing: CGFloat = UI.textToReactionsSpacing
    @ScaledMetric(relativeTo: .caption) private var scaledReactionMetadataSpacing: CGFloat = UI.reactionMetadataSpacing
    @ScaledMetric(relativeTo: .caption) private var bottomInset: CGFloat = 8

    private var bubbleMinWidth: CGFloat {
        let horizontalInsets = bottomLeadingInset + bottomTrailingInset
        let metadataWidth = metadataClusterWidth
            + (isEdited ? UI.editedLabelWidth + 4 : 0)
            + (deliveryStatus == nil ? 0 : UI.receiptWidth)
        return max(isEdited ? UI.minWidthEdited : UI.minWidth, horizontalInsets + metadataWidth + 12)
    }

    private var metadataClusterWidth: CGFloat {
        ChatMessageDateFormatting.isToday(createdAt) ? UI.timeClusterWidth : UI.dateTimeClusterWidth
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
        UI.textLift + bottomForTime
    }

    private var bottomLeadingInset: CGFloat {
        UI.textHPad + (isMine ? 0 : UI.tailWidth)
    }

    private var bottomTrailingInset: CGFloat {
        UI.textHPad + (isMine ? UI.tailWidth : 0)
    }

    private var bubbleBody: some View {
        Group {
            if reactions.isEmpty {
                messageContent
                    .padding(.top, UI.topPad)
                    .padding(.bottom, contentBottomPadding)
                    .padding(.leading, UI.textHPad + (isMine ? 0 : UI.tailWidth))
                    .padding(.trailing, UI.textHPad + (isMine ? UI.tailWidth : 0))
                    .frame(minWidth: bubbleMinWidth, alignment: .leading)
                    .background(bubbleBackground)
                    .overlay(alignment: .bottom) {
                        HStack {
                            Spacer(minLength: 0)
                            metadataCluster
                        }
                        .padding(.leading, bottomLeadingInset)
                        .padding(.trailing, bottomTrailingInset)
                        .padding(.bottom, bottomInset)
                    }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    messageContent
                        .padding(.top, UI.topPad)
                        .padding(.leading, UI.textHPad + (isMine ? 0 : UI.tailWidth))
                        .padding(.trailing, UI.textHPad + (isMine ? UI.tailWidth : 0))

                    ChatMessageReactionsView(
                        reactions: reactions,
                        onTap: onReactionTap
                    )
                    .padding(.top, scaledTextToReactionsSpacing)
                    .padding(.leading, bottomLeadingInset)
                    .padding(.trailing, bottomTrailingInset)

                    HStack {
                        Spacer(minLength: 0)
                        metadataCluster
                    }
                    .padding(.top, scaledReactionMetadataSpacing)
                    .padding(.leading, bottomLeadingInset)
                    .padding(.trailing, bottomTrailingInset)
                    .padding(.bottom, bottomInset)
                }
                .frame(minWidth: bubbleMinWidth, alignment: .leading)
                .background(bubbleBackground)
            }
        }
    }

    private var messageContent: some View {
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
    }

    private var bubbleBackground: some View {
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
    }

    private var metadataCluster: some View {
        HStack(spacing: 4) {
            if isEdited {
                Text("chats.edited")
                    .font(Font.App.caption(size: 11))
                    .foregroundStyle(Color.secondaryText.opacity(0.75))
                    .lineLimit(1)
            }

            Text(ChatMessageDateFormatting.metadataText(for: createdAt))
                .font(Font.App.caption(size: 11))
                .foregroundStyle(Color.secondaryText.opacity(0.75))
                .monospacedDigit()
                .lineLimit(1)

            if let deliveryStatus {
                MessageDeliveryReceiptView(status: deliveryStatus)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .allowsHitTesting(false)
    }
}

private struct MessageDeliveryReceiptView: View {
    let status: MessageDeliveryStatus

    var body: some View {
        HStack(spacing: -5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
            if status != .sent {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(status == .read ? Color.discoverVioletLight : Color.secondaryText.opacity(0.75))
        .frame(width: status == .sent ? 10 : 16, height: 12, alignment: .trailing)
        .accessibilityHidden(true)
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
            ],
            deliveryStatus: .read
        )

        ChatBubbleView(
            text: "Message from yesterday",
            senderName: "Emma",
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            isMine: false
        )

        ChatBubbleView(
            text: "Hi",
            senderName: nil,
            createdAt: Date(),
            isMine: true,
            deliveryStatus: .sent
        )

        ChatBubbleView(
            text: "Hi",
            senderName: "Emma",
            createdAt: Date(),
            isMine: false
        )

        ChatBubbleView(
            text: "!",
            senderName: nil,
            createdAt: Date(),
            isMine: true
        )
    }
    .padding()
    .background(Color.discoverBackgroundGradient)
}
