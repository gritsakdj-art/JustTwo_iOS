import SwiftUI

struct ChatBubbleView: View {
    let text: String
    let senderName: String?
    let createdAt: Date
    let isMine: Bool

    private enum UI {
        static let tailWidth: CGFloat = 12
        static let textHPad: CGFloat = 14
        static let topPad: CGFloat = 10
        static let bottomForTime: CGFloat = 22
        static let textLift: CGFloat = 3
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

            Text(text)
                .font(Font.App.body())
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.leading)
                .padding(.top, UI.topPad)
                .padding(.bottom, UI.bottomForTime + UI.textLift)
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
                .overlay(alignment: .bottomTrailing) {
                    Text(createdAt, style: .time)
                        .font(Font.App.caption(size: 11))
                        .foregroundStyle(Color.secondaryText.opacity(0.75))
                        .monospacedDigit()
                        .padding(.trailing, 10 + (isMine ? UI.tailWidth : 0))
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
        }
        .frame(maxWidth: UI.maxWidth, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, UI.sideInset)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 12) {
        ChatBubbleView(
            text: "Hello, this is a longer incoming message to see how it wraps.",
            senderName: "Emma",
            createdAt: Date(),
            isMine: false
        )

        ChatBubbleView(
            text: "Hi there! Looks good. How does a longer outgoing message look?",
            senderName: nil,
            createdAt: Date().addingTimeInterval(-300),
            isMine: true
        )
    }
    .padding()
    .background(Color.discoverBackgroundGradient)
}
