import SwiftUI

struct ChatComposeBanner: View {
    enum Mode {
        case reply(authorName: String, preview: String)
        case edit
    }

    let mode: Mode
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.discoverViolet)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(Font.App.manrope(size: 13, weight: .bold))
                    .foregroundStyle(Color.discoverViolet)

                if case .reply(_, let preview) = mode {
                    Text(preview)
                        .font(Font.App.manrope(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.elevatedSurface))
            }
            .buttonStyle(.spring(pressedScale: 0.92))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    private var titleText: String {
        switch mode {
        case .reply(let authorName, _):
            String(format: String(localized: "chats.compose.replying_to_format"), authorName)
        case .edit:
            String(localized: "chats.compose.editing")
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ChatComposeBanner(
            mode: .reply(authorName: "Emma", preview: "Want to grab coffee this weekend?"),
            onCancel: {}
        )
        ChatComposeBanner(mode: .edit, onCancel: {})
    }
}
