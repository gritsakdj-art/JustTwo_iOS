import Foundation

enum AuthMode {
    case login
    case register
}

@MainActor
@Observable
final class AuthViewModel {
    var mode: AuthMode = .login
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?
    var showForgotPasswordOption = false
    var isForgotPasswordSheetPresented = false
    var forgotPasswordEmail = ""
    var isSendingForgotPassword = false
    var forgotPasswordMessage: String?
    var forgotPasswordErrorMessage: String?

    var emailValidationMessage: String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return nil }
        return isValidEmail(trimmedEmail) ? nil : String(localized: "auth.error.invalid_email")
    }

    var passwordValidationMessage: String? {
        guard !password.isEmpty else { return nil }

        switch mode {
        case .login:
            return nil
        case .register:
            return PasswordPolicy.isValid(password) ? nil : String(localized: "auth.error.weak_password")
        }
    }

    var isValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty,
              !password.isEmpty,
              isValidEmail(trimmedEmail)
        else { return false }

        switch mode {
        case .login:
            return true
        case .register:
            return isValidEmail(trimmedEmail) && PasswordPolicy.isValid(password)
        }
    }

    func submit(using session: SessionStore, router: AppRouter) {
        guard isValid, !isLoading else { return }

        isLoading = true
        errorMessage = nil
        showForgotPasswordOption = false

        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedPassword = password

        Task {
            do {
                let response: AuthResponse

                switch mode {
                case .login:
                    response = try await AuthService.login(
                        email: normalizedEmail,
                        password: normalizedPassword
                    )
                case .register:
                    response = try await AuthService.register(
                        email: normalizedEmail,
                        password: normalizedPassword
                    )
                }

                if response.requiresEmailVerification {
                    session.setPendingVerificationEmail(normalizedEmail)
                    router.showCheckEmail(email: normalizedEmail)
                    isLoading = false
                    showForgotPasswordOption = false
                    return
                }

                try session.signIn(response)
                showForgotPasswordOption = false

                if session.isEmailVerified {
                    switch mode {
                    case .register:
                        session.updateCurrentProfile(nil)
                        router.resetTo(.profileSetup)
                    case .login:
                        router.retrySplash()
                    }
                } else {
                    router.showCheckEmail(email: session.pendingVerificationEmail ?? normalizedEmail)
                }
            } catch let error as NetworkError {
                if error.isEmailNotVerified {
                    session.setPendingVerificationEmail(normalizedEmail)
                    showForgotPasswordOption = false
                    router.showCheckEmail(
                        email: normalizedEmail,
                        message: String(localized: "email_verification.login_required_message")
                    )
                } else if mode == .login, error.isInvalidCredentials {
                    errorMessage = error.userMessage
                    showForgotPasswordOption = true
                } else {
                    errorMessage = error.userMessage
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    func toggleMode() {
        mode = mode == .login ? .register : .login
        errorMessage = nil
        showForgotPasswordOption = false
        resetForgotPasswordState()
    }

    func presentForgotPassword() {
        forgotPasswordEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        forgotPasswordMessage = nil
        forgotPasswordErrorMessage = nil
        isForgotPasswordSheetPresented = true
    }

    func sendForgotPassword() {
        let normalizedEmail = forgotPasswordEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !isSendingForgotPassword else { return }
        guard isValidEmail(normalizedEmail) else {
            forgotPasswordErrorMessage = String(localized: "auth.error.invalid_email")
            forgotPasswordMessage = nil
            return
        }

        isSendingForgotPassword = true
        forgotPasswordEmail = normalizedEmail
        forgotPasswordMessage = nil
        forgotPasswordErrorMessage = nil

        Task {
            do {
                _ = try await AuthService.forgotPassword(email: normalizedEmail)
                forgotPasswordMessage = String(localized: "auth.forgot_password.generic_success")
            } catch let error as NetworkError {
                forgotPasswordErrorMessage = error.userMessage
            } catch {
                forgotPasswordErrorMessage = error.localizedDescription
            }

            isSendingForgotPassword = false
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func resetForgotPasswordState() {
        isForgotPasswordSheetPresented = false
        forgotPasswordEmail = ""
        isSendingForgotPassword = false
        forgotPasswordMessage = nil
        forgotPasswordErrorMessage = nil
    }
}
