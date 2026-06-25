import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("chats.messagePlaceholder", text: $text, axis: .vertical)
                .font(Font.App.body())
                .foregroundStyle(Color.primaryText)
                .lineLimit(1...4)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.fieldBackground.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(canSend ? Color.brandPrimary : Color.disabled)
                    )
            }
            .disabled(!canSend)
            .buttonStyle(.spring(pressedScale: 0.92))
        }
        .padding()
        .background(
            Color.cardSurface.opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Divider()
                .overlay(Color.hairline)
        }
    }
}

#Preview {
    ChatMessageInputPreviewHost()
}

private struct ChatMessageInputPreviewHost: View {
    @State private var text = "Hi"

    var body: some View {
        MessageInputView(text: $text, onSend: {})
            .padding()
            .background(Color.discoverBackgroundGradient)
    }
}
