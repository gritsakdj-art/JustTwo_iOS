import SwiftUI

struct ChatConversationRow: View {
    let conversation: ChatConversationPreview
    let isOnline: Bool
    let onTap: () -> Void

    private enum UI {
        static let avatarSize: CGFloat = 56 // Сделали чуть крупнее, люди любят лица
        static let rowSpacing: CGFloat = 14
        static let textStackSpacing: CGFloat = 6 // Чуть плотнее, чтобы не разваливалось
        static let metaStackSpacing: CGFloat = 6
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 14
    }
    
    // Вычисляем, есть ли непрочитанные
    private var isUnread: Bool {
        conversation.unreadCount > 0
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: UI.rowSpacing) {
                ChatAvatarView(
                    title: conversation.title,
                    photoURL: conversation.avatarURL,
                    photoID: conversation.avatarPhotoID,
                    size: UI.avatarSize
                )
                .onlinePresenceIndicator(isVisible: isOnline, size: 14, borderWidth: 2)

                VStack(alignment: .leading, spacing: UI.textStackSpacing) {
                    Text(conversation.title)
                        .font(Font.App.manrope(size: 17, weight: isUnread ? .bold : .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) { // Уменьшил пробел между именем и сообщением
                        if let sender = conversation.lastSenderName, !sender.isEmpty {
                            Text(sender + ":")
                                .font(Font.App.manrope(size: 14, weight: isUnread ? .bold : .semibold))
                                // Если непрочитано — цвет праймери, иначе — фиолетовый
                                .foregroundStyle(isUnread ? Color.primaryText : Color.discoverViolet)
                                .lineLimit(1)
                        }

                        if let text = conversation.lastMessageText, !text.isEmpty {
                            Text(text)
                                .font(Font.App.manrope(size: 14, weight: isUnread ? .semibold : .regular))
                                // Если непрочитано — выделяем, чтобы бросалось в глаза
                                .foregroundStyle(isUnread ? Color.primaryText : Color.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text("chats.noMessagesYet")
                                .font(Font.App.manrope(size: 14, weight: .regular))
                                .foregroundStyle(Color.secondaryText.opacity(0.85))
                                .italic() // Легкий акцент для системного текста
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: UI.metaStackSpacing) {
                    if let date = conversation.lastMessageAt {
                        Text(date, style: .time)
                            // Время тоже делаем жирнее, если сообщение не прочитано
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
                        // Сохраняем место, чтобы верстка не прыгала
                        Text(" ")
                            .font(Font.App.manrope(size: 12, weight: .heavy))
                            .padding(.vertical, 4)
                            .opacity(0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, UI.horizontalPadding)
            .padding(.vertical, UI.verticalPadding)
            .background(
                Color.cardSurface,
                in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 16, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        }
        .buttonStyle(ChatPressableRowStyle())
    }
}

// ✨ Дофаминовая кнопка: теперь она немного «прожимается» внутрь
struct ChatPressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                    .fill(Color.discoverViolet.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0) // Та самая магия
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(ChatUIMockData.conversations) { conversation in
                ChatConversationRow(conversation: conversation, isOnline: false, onTap: {})
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
    .background(Color.discoverBackgroundGradient)
}
