import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatBubbleView: View {
    let text: String
    let senderName: String?
    let createdAt: Date
    let isMine: Bool
    var replyPreview: String?
    var replyImageAttachment: ChatMessageAttachment?
    var onReplyTap: (() -> Void)?
    var imageAttachment: ChatMessageAttachment?
    var isEdited: Bool = false
    var isDeleted: Bool = false
    var reactions: [ChatMessageReaction] = []
    var deliveryStatus: MessageDeliveryStatus?
    var localSendState: MessageLocalSendState?
    var onRetry: (() -> Void)?
    var onReactionTap: ((ChatMessageReaction) -> Void)?
    var onImageTap: ((ChatMessageAttachment) -> Void)?

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
                    .font(Font.App.caption(size: 14, weight: .semibold))
                    .foregroundStyle(Color.chatSenderNameGradient)
                    .padding(.horizontal, 4)
            }

            bubbleBody

            if localSendState == .failed, let onRetry {
                failedSendFooter(onRetry: onRetry)
            }
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
                HStack(spacing: 8) {
                    if let replyImageAttachment {
                        ChatImageBubbleView(
                            attachment: replyImageAttachment,
                            size: ChatImageBubbleLayout.thumbnailSize(for: replyImageAttachment),
                            cornerRadius: 8,
                            onTap: onReplyTap
                        )
                    }

                    Text(replyPreview)
                        .font(Font.App.caption())
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                }
                .padding(.vertical, 6)
                .padding(.leading, 17)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.discoverViolet.opacity(0.08))
                )
                .overlay(alignment: .leading) {
                    // Telegram-style accent bar, stretched to the preview height.
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.chatSenderNameGradient)
                        .frame(width: 3)
                        .padding(.vertical, 5)
                        .padding(.leading, 6)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture {
                    onReplyTap?()
                }
            }

            if let imageAttachment, !isDeleted {
                ChatImageBubbleView(
                    attachment: imageAttachment,
                    size: imageBubbleSize(for: imageAttachment),
                    showsSendProgress: localSendState == .sending,
                    isMine: isMine,
                    onTap: { onImageTap?(imageAttachment) }
                )
            }

            if shouldShowText {
                Text(text)
                    .font(Font.App.body())
                    .foregroundStyle(isDeleted ? Color.secondaryText : Color.primaryText)
                    .italic(isDeleted)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var shouldShowText: Bool {
        isDeleted || imageAttachment == nil || !text.isEmpty && text != ChatUIMapping.imageMessagePreviewText
    }

    private func imageBubbleSize(for attachment: ChatMessageAttachment) -> CGSize {
        #if canImport(UIKit)
        let screenWidth = UIScreen.main.bounds.width
        #else
        let screenWidth: CGFloat = 390
        #endif
        // The photo lives inside the bubble's content paddings, next to the side inset and
        // the message row's horizontal padding. Subtract all of that chrome so a landscape
        // photo at max width still fits inside the bubble instead of poking past its edge.
        let bubbleChrome = bottomLeadingInset + bottomTrailingInset + UI.sideInset + 24
        let availableWidth = max(ChatImageBubbleLayout.minWidth, screenWidth - bubbleChrome)
        return ChatImageBubbleLayout.displaySize(
            for: attachment,
            maxBubbleWidth: min(
                ChatImageBubbleLayout.maxBubbleWidth(screenWidth: screenWidth),
                availableWidth
            )
        )
    }

    private var bubbleBackground: some View {
        ChatBubbleShape(isMine: isMine)
            .fill(isMine ? Color.chatBubbleMineGradient : Color.chatBubbleOtherGradient)
            .overlay(
                ChatBubbleShape(isMine: isMine)
                    .stroke(
                        Color.glassBorderHighlight.opacity(isMine ? 0.18 : 0.12),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.chatBubbleShadow.opacity(0.10), radius: 3, x: 0, y: 1)
            .shadow(color: Color.chatBubbleShadow.opacity(0.14), radius: 10, x: 0, y: 6)
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
            } else if localSendState == .sending, imageAttachment == nil {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.secondaryText.opacity(0.75))
                    .frame(width: 12, height: 12)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .allowsHitTesting(false)
    }

    private func failedSendFooter(onRetry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("chats.message.sendFailed")
                .font(Font.App.caption())
                .foregroundStyle(Color.secondaryText)

            Button(action: onRetry) {
                Text("chats.message.retry")
                    .font(Font.App.caption(weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
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
