import SwiftUI

struct ChatMessageReactionsView: View {
    let reactions: [ChatMessageReaction]
    var onTap: ((ChatMessageReaction) -> Void)?

    @ScaledMetric(relativeTo: .caption) private var emojiSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var countFontSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 9
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 5
    @ScaledMetric(relativeTo: .caption) private var chipSpacing: CGFloat = 5
    @ScaledMetric(relativeTo: .caption) private var contentSpacing: CGFloat = 3

    var body: some View {
        HStack(spacing: chipSpacing) {
            ForEach(reactions) { reaction in
                Button {
                    onTap?(reaction)
                } label: {
                    HStack(spacing: contentSpacing) {
                        Text(reaction.displayEmoji)
                            .font(.system(size: emojiSize))

                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(
                                    Font.App.manrope(
                                        size: countFontSize,
                                        weight: .semibold,
                                        relativeTo: .caption
                                    )
                                )
                                .foregroundStyle(
                                    reaction.reactedByMe ? Color.onAccentText : Color.secondaryText
                                )
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                reaction.reactedByMe
                                    ? Color.chatReactionSelected.opacity(0.92)
                                    : Color.elevatedSurface.opacity(0.92)
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                reaction.reactedByMe ? Color.chatReactionSelected : Color.hairline.opacity(0.7),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.spring(pressedScale: 0.94))
                .disabled(onTap == nil)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

#Preview {
    VStack(spacing: 16) {
        ChatMessageReactionsView(
            reactions: [
                ChatMessageReaction(emoji: "👍", count: 2, reactedByMe: true),
                ChatMessageReaction(emoji: "❤️", count: 1, reactedByMe: false)
            ],
            onTap: { _ in }
        )

        ChatMessageReactionsView(
            reactions: [
                ChatMessageReaction(emoji: "😂", count: 1, reactedByMe: true)
            ],
            onTap: { _ in }
        )
    }
    .padding()
    .background(Color.chatBubbleMine)
}
