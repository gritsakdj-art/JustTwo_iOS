import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BaseTextField: View {
    let title: LocalizedStringResource
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var errorMessage: String? = nil

    @FocusState private var isFocused: Bool
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Font.App.manrope(size: 13, weight: .semibold))
                .foregroundStyle(isFocused ? Color.brandPrimary : Color.secondaryText)

            HStack(spacing: 12) {
                Group {
                    if isSecure && !showPassword {
                        SecureField(String(localized: title), text: $text)
                            .textContentType(textContentType)
                    } else {
                        TextField(String(localized: title), text: $text)
                            .textContentType(textContentType)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(autocapitalization)
                            .autocorrectionDisabled(true)
                    }
                }
                .focused($isFocused)
                .font(Font.App.manrope(size: 16, weight: .medium))
                .foregroundStyle(Color.primaryText)

                if isSecure {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            showPassword.toggle()
                        }
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.brandPrimary : Color.secondaryText)
                            .scaleEffect(showPassword ? 1.08 : 1)
                    }
                    .buttonStyle(.spring(pressedScale: 0.88))
                }
            }
            .frame(minHeight: 54)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .fill(Color.fieldBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            .shadow(
                color: isFocused ? Color.brandPrimary.opacity(0.12) : Color.clear,
                radius: 8,
                x: 0,
                y: 3
            )
            .animation(.easeInOut(duration: 0.16), value: isFocused)
            .animation(.easeInOut(duration: 0.16), value: errorMessage)

            if let errorMessage {
                Text(errorMessage)
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var borderColor: Color {
        if errorMessage != nil {
            return Color.error
        }
        return isFocused ? Color.brandPrimary.opacity(0.72) : Color.hairline
    }
}

#Preview("BaseTextField") {
    ZStack {
        Color.authBackgroundGradient.ignoresSafeArea()

        VStack(spacing: 20) {
            BaseTextField(
                title: "auth.email",
                text: .constant("hello@justtwo.app"),
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )

            BaseTextField(
                title: "auth.password",
                text: .constant("secret123"),
                isSecure: true,
                textContentType: .password
            )
        }
        .padding(24)
    }
}
