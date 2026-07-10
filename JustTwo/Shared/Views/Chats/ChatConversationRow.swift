import SwiftUI

struct ChatConversationRow: View {
    let conversation: ChatConversationPreview
    let isOnline: Bool
    var isTyping: Bool = false
    var presenceStatusText: String? = nil
    var presenceAccessibilityLabel: String? = nil
    var onDelete: () -> Void = {}
    var onMute: () -> Void = {}
    let onTap: () -> Void

    private enum UI {
        static let avatarSize: CGFloat = 56
        static let rowSpacing: CGFloat = 14
        static let textStackSpacing: CGFloat = 6
        static let metaStackSpacing: CGFloat = 6
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 14
        static let unreadBarWidth: CGFloat = 3
        static let unreadBarHeight: CGFloat = 42
        static let unreadBarCornerRadius: CGFloat = 2
        static let unreadBarAvatarSpacing: CGFloat = 8
    }

    private var isUnread: Bool {
        conversation.unreadCount > 0
    }

    var body: some View {
        Button(action: onTap) {
            rowContent
                .padding(.horizontal, UI.horizontalPadding)
                .padding(.vertical, UI.verticalPadding)
                .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .shadow(
                color: Color.discoverCardShadow.opacity(isUnread ? 0.12 : 0.08),
                radius: isUnread ? 20 : 16,
                x: 0,
                y: 6
            )
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        }
        .buttonStyle(ChatPressableRowStyle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("chats.delete", systemImage: "trash")
            }

            Button(action: onMute) {
                Label("chats.mute", systemImage: "bell.slash")
            }
            .tint(.orange)
        }
    }

    private var rowContent: some View {
        HStack(spacing: UI.rowSpacing) {
            HStack(spacing: UI.unreadBarAvatarSpacing) {
                unreadAccentBar

                ChatAvatarView(
                    title: conversation.title,
                    photoURL: conversation.avatarURL,
                    photoID: conversation.avatarPhotoID,
                    size: UI.avatarSize
                )
                .onlinePresenceIndicator(isVisible: isOnline, size: 14, borderWidth: 2)
            }

            VStack(alignment: .leading, spacing: UI.textStackSpacing) {
                Text(conversation.title)
                    .font(Font.App.manrope(size: 17, weight: isUnread ? .bold : .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)

                if let presenceStatusText, !isTyping, !isOnline {
                    Text(presenceStatusText)
                        .font(Font.App.manrope(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }

                messagePreview
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel)

            VStack(alignment: .trailing, spacing: UI.metaStackSpacing) {
                if let date = conversation.lastMessageAt {
                    Text(relativeTimeString(for: date))
                        .font(Font.App.manrope(size: 12, weight: isUnread ? .bold : .medium))
                        .foregroundStyle(isUnread ? Color.brandPrimary : Color.secondaryText)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(Font.App.manrope(size: 12, weight: .medium))
                        .opacity(0)
                }

                if isUnread {
                    Text("\(conversation.unreadCount)")
                        .font(Font.App.manrope(size: 12, weight: .heavy))
                        .foregroundStyle(Color.onAccentText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brandPrimary))
                } else {
                    Text(" ")
                        .font(Font.App.manrope(size: 12, weight: .heavy))
                        .padding(.vertical, 4)
                        .opacity(0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unreadAccentBar: some View {
        RoundedRectangle(cornerRadius: UI.unreadBarCornerRadius, style: .continuous)
            .fill(isUnread ? Color.brandPrimary : Color.clear)
            .frame(width: UI.unreadBarWidth, height: UI.unreadBarHeight)
    }

    private var rowAccessibilityLabel: String {
        var parts = [conversation.title]
        if isTyping {
            parts.append(String(localized: "chats.typing"))
        } else if let presenceAccessibilityLabel, !presenceAccessibilityLabel.isEmpty {
            parts.append(presenceAccessibilityLabel)
        } else if isOnline {
            parts.append(String(localized: "presence.online"))
        }
        if let preview = conversation.lastMessageText, !preview.isEmpty, !isTyping {
            parts.append(preview)
        }
        return parts.joined(separator: ", ")
    }

    private var messagePreview: some View {
        HStack(spacing: 4) {
            if isTyping {
                TypingDotsView(color: .discoverViolet, dotSize: 5, spacing: 3)

                Text("chats.typing")
                    .font(Font.App.manrope(size: 14, weight: .medium))
                    .foregroundStyle(Color.discoverViolet)
                    .lineLimit(1)
            } else {
                if let sender = conversation.lastSenderName, !sender.isEmpty {
                    Text(sender + ":")
                        .font(Font.App.manrope(size: 14, weight: isUnread ? .bold : .semibold))
                        .foregroundStyle(isUnread ? Color.primaryText : Color.discoverViolet)
                        .lineLimit(1)
                }

                if let text = conversation.lastMessageText, !text.isEmpty {
                    Text(text)
                        .font(Font.App.manrope(size: 14, weight: isUnread ? .semibold : .regular))
                        .foregroundStyle(isUnread ? Color.primaryText : Color.secondaryText)
                        .lineLimit(1)
                } else {
                    Text("chats.noMessagesYet")
                        .font(Font.App.manrope(size: 14, weight: .regular))
                        .foregroundStyle(Color.secondaryText.opacity(0.85))
                        .italic()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
            .fill(
                isUnread
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color.brandPrimary.opacity(0.07),
                                Color.cardSurface
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Color.cardSurface)
            )
    }

    private func relativeTimeString(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "chats.yesterday")
        }
        if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day,
           daysAgo < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct ChatPressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .fill(Color.discoverViolet.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(ChatUIMockData.conversations) { conversation in
                let isTypingPreview = conversation.id == ChatUIMockData.conversations.first?.id
                ChatConversationRow(
                    conversation: conversation,
                    isOnline: isTypingPreview,
                    isTyping: isTypingPreview,
                    onTap: {}
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
    .background(Color.discoverBackgroundGradient)
}
