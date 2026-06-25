import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    var onAttach: (() -> Void)? = nil
    var isSending: Bool = false

    private enum UI {
        static let controlSize: CGFloat = 44
        static let fieldCornerRadius: CGFloat = 14
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            attachButton

            TextField("chats.messagePlaceholder", text: $text, axis: .vertical)
                .font(Font.App.body())
                .foregroundStyle(Color.primaryText)
                .lineLimit(1...4)
                .disabled(isSending)
                .onChange(of: text) { _, newValue in
                    if newValue.count > MessengerLimits.maxMessageLength {
                        text = String(newValue.prefix(MessengerLimits.maxMessageLength))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: UI.fieldCornerRadius, style: .continuous)
                        .fill(Color.fieldBackground.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UI.fieldCornerRadius, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )

            sendButton
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    private var attachButton: some View {
        Button {
            onAttach?()
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.discoverViolet)
                .frame(width: UI.controlSize, height: UI.controlSize)
                .background(
                    Circle()
                        .fill(Color.fieldBackground.opacity(0.96))
                )
                .overlay(
                    Circle()
                        .stroke(Color.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.spring(pressedScale: 0.92))
        .disabled(isSending)
        .accessibilityLabel("chats.attach")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Group {
                if isSending {
                    ProgressView()
                        .tint(Color.onAccentText)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(Color.onAccentText)
            .frame(width: UI.controlSize, height: UI.controlSize)
            .background(
                Circle()
                    .fill(canSend ? Color.brandPrimary : Color.disabled)
            )
        }
        .disabled(!canSend)
        .buttonStyle(.spring(pressedScale: 0.92))
    }
}

#Preview {
    ChatMessageInputPreviewHost()
}

private struct ChatMessageInputPreviewHost: View {
    @State private var text = "Hi"

    var body: some View {
        VStack {
            Spacer()
            MessageInputView(text: $text, onSend: {}, onAttach: {})
        }
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
    }
}
