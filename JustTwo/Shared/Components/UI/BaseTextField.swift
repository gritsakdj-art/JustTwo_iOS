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

    @FocusState private var isFocused: Bool
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isFocused ? Color.discoverViolet : Color.discoverSecondaryText)

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
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.discoverPrimaryText)

                if isSecure {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            showPassword.toggle()
                        }
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.discoverViolet : Color.discoverSecondaryText)
                            .scaleEffect(showPassword ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.surface.opacity(0.96))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            .shadow(
                color: isFocused ? Color.discoverViolet.opacity(0.22) : Color.clear,
                radius: 14,
                x: 0,
                y: 6
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.discoverViolet.opacity(0.5), lineWidth: 4)
                        .blur(radius: 4)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var borderColor: Color {
        isFocused ? Color.discoverViolet : Color.discoverSecondaryText.opacity(0.22)
    }
}

#Preview("BaseTextField") {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()

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
