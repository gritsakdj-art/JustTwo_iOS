import Combine
import SwiftUI

enum EmailVerificationResultState: Equatable {
    case loading
    case success
    case invalidOrExpired
    case networkError(String)
    case genericError(String)
}

struct EmailVerificationResultView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private let token: String?
    @State private var state: EmailVerificationResultState
    @State private var didStart = false
    @State private var isResending = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var resendAvailableAt: Date = .now
    @State private var now = Date()

    private let resendCooldown: TimeInterval = 45
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(token: String) {
        self.token = token
        _state = State(initialValue: .loading)
    }

    init(initialState: EmailVerificationResultState) {
        token = nil
        _state = State(initialValue: initialState)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: AppSpacing.xl) {
                icon

                VStack(spacing: AppSpacing.sm) {
                    Text(title)
                        .font(Font.App.screenTitle)
                        .foregroundStyle(Color.discoverPrimaryText)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(Font.App.subtitle)
                        .foregroundStyle(Color.discoverSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .loading = state {
                    ProgressView()
                        .tint(Color.brandPrimary)
                }

                messageBlock

                VStack(spacing: AppSpacing.lg) {
                    if showRetry {
                        PrimaryButton("common.retry", systemImage: "arrow.clockwise") {
                            verify()
                        }
                    }

                    if showResend {
                        Button {
                            resend()
                        } label: {
                            HStack(spacing: 8) {
                                if isResending {
                                    ProgressView()
                                } else {
                                    Image(systemName: "paperplane")
                                }

                                Text(resendTitle)
                                    .font(Font.App.manrope(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(resendDisabled ? Color.discoverSecondaryText : Color.brandPrimary)
                            .background(Color.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.spring(pressedScale: 0.97, isEnabled: !resendDisabled))
                        .disabled(resendDisabled)
                    }

                    PrimaryButton(primaryTitle, systemImage: primaryIcon, isDisabled: isLoading) {
                        primaryAction()
                    }

                    if showBackToLogin {
                        Button {
                            router.resetTo(.auth)
                        } label: {
                            Text("email_verification.result.back_to_login")
                                .font(Font.App.footnote(weight: .semibold))
                                .foregroundStyle(Color.discoverSecondaryText)
                        }
                        .buttonStyle(.spring(pressedScale: 0.96))
                    }
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.xxl)
            .frame(maxWidth: .infinity)
            .frame(minHeight: proxy.size.height, alignment: .center)
            .background(Color.authBackgroundGradient.ignoresSafeArea())
        }
        .navigationBarBackButtonHidden()
        .task {
            guard !didStart else { return }
            didStart = true

            if token != nil {
                verify()
            }
        }
        .onReceive(timer) { value in
            now = value
        }
    }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(iconGradient)

            if isLoading {
                ProgressView()
                    .tint(Color.onAccentText)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }
        }
        .frame(width: 86, height: 86)
        .shadow(color: Color.brandPrimary.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private var iconGradient: LinearGradient {
        switch state {
        case .success:
            return Color.discoverSelectedGradient
        case .invalidOrExpired, .networkError, .genericError:
            return Color.discoverMoodGradient
        case .loading:
            return Color.brandPrimaryGradient
        }
    }

    private var iconName: String {
        switch state {
        case .success:
            return "checkmark"
        case .invalidOrExpired:
            return "link.badge.plus"
        case .networkError:
            return "wifi.exclamationmark"
        case .genericError:
            return "exclamationmark"
        case .loading:
            return "hourglass"
        }
    }

    @ViewBuilder
    private var messageBlock: some View {
        VStack(spacing: AppSpacing.sm) {
            if let statusMessage {
                Text(statusMessage)
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.brandPrimary)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.discoverPink)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 28)
        .animation(.easeInOut(duration: 0.18), value: statusMessage)
        .animation(.easeInOut(duration: 0.18), value: errorMessage)
    }

    private var title: LocalizedStringResource {
        switch state {
        case .loading:
            return "email_verification.result.loading_title"
        case .success:
            return "email_verification.result.success_title"
        case .invalidOrExpired:
            return "email_verification.result.expired_title"
        case .networkError:
            return "email_verification.result.network_title"
        case .genericError:
            return "email_verification.result.error_title"
        }
    }

    private var subtitle: String {
        switch state {
        case .loading:
            return String(localized: "email_verification.result.loading_subtitle")
        case .success:
            return String(localized: "email_verification.result.success_subtitle")
        case .invalidOrExpired:
            return String(localized: "email_verification.result.expired_subtitle")
        case .networkError(let message), .genericError(let message):
            return message
        }
    }

    private var primaryTitle: LocalizedStringResource {
        switch state {
        case .success:
            return session.isFullyAuthenticated ? "email_verification.result.continue" : "email_verification.result.go_to_login"
        case .loading:
            return "email_verification.result.verifying"
        case .invalidOrExpired, .networkError, .genericError:
            return "email_verification.result.back_to_login"
        }
    }

    private var primaryIcon: String {
        switch state {
        case .success:
            return session.isFullyAuthenticated ? "arrow.right" : "person.crop.circle"
        case .loading:
            return "hourglass"
        case .invalidOrExpired, .networkError, .genericError:
            return "arrow.left"
        }
    }

    private var showRetry: Bool {
        if case .networkError = state {
            return token != nil
        }
        return false
    }

    private var showBackToLogin: Bool {
        showRetry
    }

    private var pendingEmail: String? {
        let email = session.pendingVerificationEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? nil : email
    }

    private var showResend: Bool {
        if case .invalidOrExpired = state {
            return pendingEmail != nil
        }

        return false
    }

    private var resendDisabled: Bool {
        isResending || resendRemaining > 0
    }

    private var resendRemaining: Int {
        max(Int(ceil(resendAvailableAt.timeIntervalSince(now))), 0)
    }

    private var resendTitle: String {
        guard resendRemaining > 0 else {
            return String(localized: "email_verification.check.resend")
        }

        return String.localizedStringWithFormat(
            String(localized: "email_verification.check.resend_countdown_format"),
            resendRemaining
        )
    }

    private func primaryAction() {
        switch state {
        case .success:
            if session.isFullyAuthenticated {
                router.retrySplash()
            } else {
                router.resetTo(.auth)
            }
        case .loading:
            break
        case .invalidOrExpired, .networkError, .genericError:
            router.resetTo(.auth)
        }
    }

    private func verify() {
        guard let token else { return }

        state = .loading
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                let response = try await AuthService.verifyEmailSession(token: token)

                do {
                    try session.signIn(response)
                } catch {
                    session.clearSession()
                }

                state = .success
            } catch let error as NetworkError {
                if error.isInvalidOrExpiredVerificationToken || error.isValidationFailed {
                    state = .invalidOrExpired
                } else {
                    state = .networkError(error.userMessage)
                }
            } catch {
                state = .genericError(error.localizedDescription)
            }
        }
    }

    private func resend() {
        guard let pendingEmail, !resendDisabled else { return }

        isResending = true
        statusMessage = nil
        errorMessage = nil

        Task {
            defer { isResending = false }

            do {
                _ = try await AuthService.resendVerification(email: pendingEmail)
                resendAvailableAt = Date().addingTimeInterval(resendCooldown)
                now = Date()
                statusMessage = String(localized: "email_verification.check.resend_success")
            } catch let error as NetworkError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    EmailVerificationResultView(initialState: .success)
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}
