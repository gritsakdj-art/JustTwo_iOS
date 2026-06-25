import SwiftUI

struct ChatConversationRow: View {
    let conversation: ChatConversationPreview
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.discoverVioletLight.opacity(0.35))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(conversation.title.prefix(1).uppercased())
                            .font(Font.App.subheadline(weight: .bold))
                            .foregroundStyle(Color.discoverViolet)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(conversation.title)
                        .font(Font.App.subheadline(weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let sender = conversation.lastSenderName, !sender.isEmpty {
                            Text(sender + ":")
                                .font(Font.App.caption(weight: .semibold))
                                .foregroundStyle(Color.discoverViolet)
                                .lineLimit(1)
                        }

                        if let text = conversation.lastMessageText, !text.isEmpty {
                            Text(text)
                                .font(Font.App.caption())
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text("chats.noMessagesYet")
                                .font(Font.App.caption())
                                .foregroundStyle(Color.secondaryText.opacity(0.85))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    if let date = conversation.lastMessageAt {
                        Text(date, style: .time)
                            .font(Font.App.caption(size: 11))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text(" ")
                            .font(Font.App.caption(size: 11))
                            .opacity(0)
                    }

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(Font.App.caption(size: 11, weight: .bold))
                            .foregroundStyle(Color.onAccentText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.brandPrimary))
                    } else {
                        Text(" ")
                            .font(Font.App.caption(size: 11))
                            .opacity(0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
    ChatConversationRow(
        conversation: ChatUIMockData.conversations[0],
        onTap: {}
    )
    .background(Color.discoverBackgroundGradient)
}
