import SwiftUI

enum MessageInputComposeMode: Equatable {
    case reply(authorName: String, preview: String)
    case edit
}

struct MessageInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    var composeMode: MessageInputComposeMode? = nil
    var onCancelCompose: (() -> Void)? = nil
    var onAttach: (() -> Void)? = nil
    var isSending: Bool = false

    @FocusState private var isInputFocused: Bool
    @State private var textSelection: TextSelection?

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

            inputField

            sendButton
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
        .background(Color.clear)
        .task(id: composeMode) {
            guard case .edit = composeMode else { return }
            await focusInputAtEnd()
        }
    }

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let composeMode {
                composeHeader(composeMode)

                Rectangle()
                    .fill(Color.hairline.opacity(0.85))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }

            TextField("chats.messagePlaceholder", text: $text, selection: $textSelection, axis: .vertical)
                .font(Font.App.body())
                .foregroundStyle(Color.primaryText)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .disabled(isSending)
                .onChange(of: text) { _, newValue in
                    if newValue.count > MessengerLimits.maxMessageLength {
                        text = String(newValue.prefix(MessengerLimits.maxMessageLength))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, composeMode == nil ? 12 : 4)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: UI.fieldCornerRadius, style: .continuous)
                .fill(Color.fieldBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UI.fieldCornerRadius, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    @MainActor
    private func focusInputAtEnd() async {
        try? await Task.sleep(for: .milliseconds(32))
        isInputFocused = true
        moveCaretToEnd()
    }

    private func moveCaretToEnd() {
        let end = text.endIndex
        textSelection = TextSelection(range: end..<end)
    }

    @ViewBuilder
    private func composeHeader(_ mode: MessageInputComposeMode) -> some View {
        HStack(alignment: .top, spacing: 8) {
            composeQuoteBlock(mode)

            Spacer(minLength: 0)

            if let onCancelCompose {
                Button(action: onCancelCompose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.elevatedSurface))
                }
                .buttonStyle(.spring(pressedScale: 0.92))
                .accessibilityLabel(String(localized: "common.cancel"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    @ViewBuilder
    private func composeQuoteBlock(_ mode: MessageInputComposeMode) -> some View {
        switch mode {
        case .reply(let authorName, let preview):
            VStack(alignment: .leading, spacing: 2) {
                Text(authorName)
                    .font(Font.App.manrope(size: 13, weight: .bold))
                    .foregroundStyle(Color.discoverViolet)
                    .lineLimit(1)

                Text(preview)
                    .font(Font.App.manrope(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(2)
            }
            .padding(.leading, 11)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.discoverViolet)
                    .frame(width: 3)
            }
        case .edit:
            Text(String(localized: "chats.compose.editing"))
                .font(Font.App.manrope(size: 13, weight: .bold))
                .foregroundStyle(Color.discoverViolet)
        }
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
                sendButtonBackground
            )
        }
        .disabled(!canSend)
        .buttonStyle(.spring(pressedScale: 0.92))
    }

    @ViewBuilder
    private var sendButtonBackground: some View {
        if canSend {
            Circle()
                .fill(Color.chatSendButtonGradient)
        } else {
            Circle()
                .fill(Color.disabled)
        }
    }
}

#Preview {
    ChatMessageInputPreviewHost()
}

private struct ChatMessageInputPreviewHost: View {
    @State private var text = ""

    var body: some View {
        VStack {
            Spacer()
            MessageInputView(
                text: $text,
                onSend: {},
                composeMode: .reply(
                    authorName: "Emma",
                    preview: "Want to grab coffee this weekend? I know a great place nearby."
                ),
                onCancelCompose: {},
                onAttach: {}
            )
        }
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
    }
}
