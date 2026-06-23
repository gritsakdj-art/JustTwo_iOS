import SwiftUI

struct ResetPasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var resetToken: String?
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var didComplete = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    init(token: String) {
        _resetToken = State(initialValue: token)
    }

    init(initialErrorMessage: String) {
        _resetToken = State(initialValue: nil)
        _errorMessage = State(initialValue: initialErrorMessage)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    header

                    contentCard
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.xxl)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.authBackgroundGradient.ignoresSafeArea())
            .hideKeyboardOnTap()
        }
        .navigationBarBackButtonHidden()
    }

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(didComplete ? Color.discoverSelectedGradient : Color.brandPrimaryGradient)

                Image(systemName: didComplete ? "checkmark" : "key.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }
            .frame(width: 78, height: 78)
            .shadow(color: Color.brandPrimaryGlow.opacity(0.22), radius: 18, x: 0, y: 10)

            Text("reset_password.title")
                .font(Font.App.screenTitle)
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.center)

            Text("reset_password.subtitle")
                .font(Font.App.subtitle)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if resetToken != nil, !didComplete {
                passwordFields

                PrimaryButton(
                    "reset_password.change_password",
                    systemImage: "arrow.right",
                    isLoading: isSubmitting,
                    isDisabled: !canSubmit
                ) {
                    submit()
                }

                Button {
                    goToLogin()
                } label: {
                    Text("reset_password.back_to_login")
                        .font(Font.App.footnote(weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.spring(pressedScale: 0.96))
            } else {
                messageBlock

                PrimaryButton("reset_password.back_to_login", systemImage: "person.crop.circle") {
                    goToLogin()
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.cardSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .stroke(Color.glassBorderHighlight.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.16), radius: 24, x: 0, y: 14)
        .animation(.easeInOut(duration: 0.18), value: errorMessage)
        .animation(.easeInOut(duration: 0.18), value: statusMessage)
        .animation(.easeInOut(duration: 0.18), value: didComplete)
    }

    private var passwordFields: some View {
        VStack(spacing: 22) {
            BaseTextField(
                title: "reset_password.new_password",
                text: $newPassword,
                isSecure: true,
                textContentType: .newPassword,
                errorMessage: newPasswordValidationMessage
            )

            BaseTextField(
                title: "reset_password.confirm_password",
                text: $confirmPassword,
                isSecure: true,
                textContentType: .newPassword,
                errorMessage: confirmPasswordValidationMessage
            )

            messageBlock
        }
    }

    private var messageBlock: some View {
        VStack(spacing: AppSpacing.sm) {
            if let statusMessage {
                Text(statusMessage)
                    .font(Font.App.footnote(weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 28)
    }

    private var canSubmit: Bool {
        resetToken != nil
            && !isSubmitting
            && PasswordPolicy.isValid(newPassword)
            && confirmPassword == newPassword
    }

    private var newPasswordValidationMessage: String? {
        guard !newPassword.isEmpty else { return nil }
        return PasswordPolicy.isValid(newPassword) ? nil : String(localized: "auth.error.weak_password")
    }

    private var confirmPasswordValidationMessage: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return confirmPassword == newPassword ? nil : String(localized: "reset_password.error.passwords_do_not_match")
    }

    private func submit() {
        guard let token = resetToken, canSubmit else { return }

        isSubmitting = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                _ = try await AuthService.resetPassword(token: token, newPassword: newPassword)
                resetToken = nil
                newPassword = ""
                confirmPassword = ""
                session.clearSession()
                didComplete = true
                statusMessage = String(localized: "reset_password.success")

                try? await Task.sleep(nanoseconds: 1_100_000_000)
                router.resetTo(.auth)
            } catch let error as NetworkError {
                if error.isInvalidOrExpiredPasswordResetToken || error.isValidationFailed {
                    resetToken = nil
                    errorMessage = String(localized: "reset_password.error.invalid_or_expired")
                } else {
                    errorMessage = error.userMessage
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }

    private func goToLogin() {
        resetToken = nil
        newPassword = ""
        confirmPassword = ""
        session.clearSession()
        router.resetTo(.auth)
    }
}

#Preview {
    ResetPasswordView(token: "preview-token")
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}
