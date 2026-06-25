import SwiftUI

struct ChatMessageReactionsView: View {
    let reactions: [ChatMessageReaction]
    var onTap: ((ChatMessageReaction) -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(reactions) { reaction in
                Button {
                    onTap?(reaction)
                } label: {
                    HStack(spacing: 3) {
                        Text(reaction.displayEmoji)
                            .font(.system(size: 13))

                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(Font.App.manrope(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    reaction.reactedByMe ? Color.onAccentText : Color.secondaryText
                                )
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                reaction.reactedByMe
                                    ? Color.brandPrimary.opacity(0.92)
                                    : Color.elevatedSurface.opacity(0.92)
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                reaction.reactedByMe ? Color.brandPrimary : Color.hairline.opacity(0.7),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.spring(pressedScale: 0.94))
                .disabled(onTap == nil)
            }
        }
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
