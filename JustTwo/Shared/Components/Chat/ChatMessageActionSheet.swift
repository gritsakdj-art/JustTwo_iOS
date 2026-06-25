import SwiftUI

struct ChatMessageActionSheet: View {
    let message: ChatMessage
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReact: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.hairline)
                .frame(width: 40, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                if message.canReply {
                    actionRow(
                        title: "chats.action.reply",
                        icon: "arrowshape.turn.up.left.fill",
                        action: onReply
                    )
                    rowDivider
                }

                if message.canCopy {
                    actionRow(
                        title: "chats.action.copy",
                        icon: "doc.on.doc",
                        action: onCopy
                    )
                    rowDivider
                }

                if message.canEdit {
                    actionRow(
                        title: "chats.action.edit",
                        icon: "pencil",
                        action: onEdit
                    )
                    rowDivider
                }

                if message.canDelete {
                    actionRow(
                        title: "chats.action.delete",
                        icon: "trash",
                        tint: Color.error,
                        action: onDelete
                    )
                }
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
            .padding(.horizontal, AppSpacing.lg)

            if message.canReact {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("chats.action.react")
                        .font(Font.App.manrope(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        ForEach(ChatQuickReactions.emojis, id: \.self) { emoji in
                            Button {
                                onReact(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(Color.elevatedSurface)
                                    )
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Color.hairline, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.spring(pressedScale: 0.92))
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
            }

            Button("common.cancel") {
                onDismiss()
            }
            .font(Font.App.manrope(size: 16, weight: .semibold))
            .foregroundStyle(Color.discoverViolet)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .background(sheetBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var sheetBackground: some View {
        ZStack {
            Color.discoverBackgroundGradient
            Color.cardSurface.opacity(colorScheme == .dark ? 0.22 : 0.35)
        }
    }

    private var cardBackground: some View {
        Color.cardSurface.opacity(colorScheme == .dark ? 0.96 : 0.98)
    }

    private var rowDivider: some View {
        Divider().overlay(Color.hairline)
    }

    private func actionRow(
        title: LocalizedStringResource,
        icon: String,
        tint: Color = Color.discoverViolet,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)

                Text(title)
                    .font(Font.App.manrope(size: 16, weight: .semibold))
                    .foregroundStyle(tint == Color.error ? Color.error : Color.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChatPressableRowStyle())
    }
}

#Preview {
    ChatMessageActionSheet(
        message: ChatMessage(
            id: UUID(),
            displayText: "Sounds great — Saturday works for me.",
            rawBody: "Sounds great — Saturday works for me.",
            createdAt: Date(),
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [ChatMessageReaction(emoji: "👍", count: 1, reactedByMe: true)]
        ),
        onReply: {},
        onCopy: {},
        onEdit: {},
        onDelete: {},
        onReact: { _ in },
        onDismiss: {}
    )
}
