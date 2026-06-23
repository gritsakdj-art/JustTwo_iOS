import SwiftUI

struct PrimaryButton: View {
    let title: LocalizedStringResource
    let systemImage: String?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            action()
        }) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(Color.onAccentText)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }

                Text(title)
                    .font(Font.App.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isDisabled ? Color.disabled : Color.onAccentText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous))
            .opacity(isDisabled ? 0.65 : 1)
            .shadow(color: Color.brandPrimaryGlow.opacity(isDisabled ? 0.10 : 0.22), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(PrimaryButtonStyle(isDisabled: isDisabled || isLoading))
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(Text(title))
    }

    private var backgroundStyle: LinearGradient {
        isDisabled ? Color.brandPrimaryPressedGradient : Color.brandPrimaryGradient
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.brandPrimaryPressedGradient.opacity(configuration.isPressed && !isDisabled ? 1 : 0),
                in: RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous)
            )
            .springButtonEffect(
                isPressed: configuration.isPressed && !isDisabled,
                pressedScale: 0.98,
                response: 0.2,
                dampingFraction: 0.75
            )
    }
}

#Preview {
    ZStack {
        Color.authBackgroundGradient.ignoresSafeArea()
        VStack(spacing: 16) {
            PrimaryButton("auth.login", systemImage: "arrow.right") { }
            PrimaryButton("auth.register", isLoading: true) { }
            PrimaryButton("common.done", isDisabled: true) { }
        }
        .padding(24)
    }
}
