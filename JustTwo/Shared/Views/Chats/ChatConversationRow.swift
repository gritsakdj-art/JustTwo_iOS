import SwiftUI

struct ChatConversationRow: View {
    let conversation: ChatConversationPreview
    let onTap: () -> Void

    private enum UI {
        static let avatarSize: CGFloat = 52
        static let rowSpacing: CGFloat = 14
        static let textStackSpacing: CGFloat = 8
        static let metaStackSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 13
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

                VStack(alignment: .leading, spacing: UI.textStackSpacing) {
                    Text(conversation.title)
                        .font(Font.App.manrope(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let sender = conversation.lastSenderName, !sender.isEmpty {
                            Text(sender + ":")
                                .font(Font.App.manrope(size: 14, weight: .semibold))
                                .foregroundStyle(Color.discoverViolet)
                                .lineLimit(1)
                        }

                        if let text = conversation.lastMessageText, !text.isEmpty {
                            Text(text)
                                .font(Font.App.manrope(size: 14, weight: .regular))
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text("chats.noMessagesYet")
                                .font(Font.App.manrope(size: 14, weight: .regular))
                                .foregroundStyle(Color.secondaryText.opacity(0.85))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: UI.metaStackSpacing) {
                    if let date = conversation.lastMessageAt {
                        Text(date, style: .time)
                            .font(Font.App.manrope(size: 13, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text(" ")
                            .font(Font.App.manrope(size: 13, weight: .medium))
                            .opacity(0)
                    }

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(Font.App.manrope(size: 13, weight: .bold))
                            .foregroundStyle(Color.onAccentText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.brandPrimary))
                    } else {
                        Text(" ")
                            .font(Font.App.manrope(size: 13, weight: .bold))
                            .opacity(0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, UI.horizontalPadding)
            .padding(.vertical, UI.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChatPressableRowStyle())
    }
}

struct ChatPressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.discoverViolet.opacity(configuration.isPressed ? 0.08 : 0)
                    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(ChatUIMockData.conversations) { conversation in
                ChatConversationRow(conversation: conversation, onTap: {})
                Divider().overlay(Color.hairline)
            }
        }
    }
    .background(Color.discoverBackgroundGradient)
}
