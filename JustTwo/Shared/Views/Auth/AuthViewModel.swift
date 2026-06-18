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
            return isValidPassword(password) ? nil : String(localized: "auth.error.weak_password")
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
            return isValidEmail(trimmedEmail) && isValidPassword(password)
        }
    }

    func submit(using session: SessionStore, router: AppRouter) {
        guard isValid, !isLoading else { return }

        isLoading = true
        errorMessage = nil

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
                    return
                }

                try session.signIn(response)

                switch mode {
                case .register:
                    session.updateCurrentProfile(nil)
                    router.resetTo(.profileSetup)
                case .login:
                    router.retrySplash()
                }
            } catch let error as NetworkError {
                if error.isEmailNotVerified {
                    session.setPendingVerificationEmail(normalizedEmail)
                    router.showCheckEmail(
                        email: normalizedEmail,
                        message: String(localized: "email_verification.login_required_message")
                    )
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
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func isValidPassword(_ value: String) -> Bool {
        let hasLetter = value.rangeOfCharacter(from: .letters) != nil
        let hasDigit = value.rangeOfCharacter(from: .decimalDigits) != nil
        return value.count >= 8 && hasLetter && hasDigit
    }
}
