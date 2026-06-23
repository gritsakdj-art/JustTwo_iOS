import Combine
import SwiftUI

struct CheckEmailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    let email: String
    let initialMessage: String?

    @State private var isChecking = false
    @State private var isResending = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var resendAvailableAt: Date = .now
    @State private var now = Date()

    private let resendCooldown: TimeInterval = 45
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(email: String, initialMessage: String? = nil) {
        self.email = email
        self.initialMessage = initialMessage
        _statusMessage = State(initialValue: initialMessage)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    icon

                    VStack(spacing: AppSpacing.sm) {
                        Text("email_verification.check.title")
                            .font(Font.App.screenTitle)
                            .foregroundStyle(Color.primaryText)
                            .multilineTextAlignment(.center)

                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "email_verification.check.subtitle_format"),
                                email
                            )
                        )
                        .font(Font.App.subtitle)
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    messageBlock

                    VStack(spacing: AppSpacing.lg) {
                        PrimaryButton(
                            "email_verification.check.i_verified",
                            systemImage: "checkmark",
                            isLoading: isChecking
                        ) {
                            checkVerification()
                        }

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
                            .foregroundStyle(resendDisabled ? Color.disabled : Color.brandPrimary)
                            .background(Color.cardSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
                        }
                        .buttonStyle(.spring(pressedScale: 0.97, isEnabled: !resendDisabled))
                        .disabled(resendDisabled)

                        Button {
                            session.clearSession()
                            router.resetTo(.auth)
                        } label: {
                            Text("email_verification.check.back_to_login")
                                .font(Font.App.footnote(weight: .semibold))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .buttonStyle(.spring(pressedScale: 0.96))
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.xxl)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.authBackgroundGradient.ignoresSafeArea())
        }
        .navigationBarBackButtonHidden()
        .onReceive(timer) { value in
            now = value
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
                    .foregroundStyle(Color.error)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.18), value: statusMessage)
        .animation(.easeInOut(duration: 0.18), value: errorMessage)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.brandPrimaryGradient)

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.onAccentText)
        }
        .frame(width: 86, height: 86)
        .shadow(color: Color.brandPrimaryGlow.opacity(0.22), radius: 18, x: 0, y: 10)
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

    private func checkVerification() {
        guard !isChecking else { return }

        isChecking = true
        errorMessage = nil
        statusMessage = nil

        Task {
            defer { isChecking = false }

            guard session.hasActiveSession else {
                statusMessage = String(localized: "email_verification.check.verified_login")
                return
            }

            do {
                let user = try await AuthService.refreshCurrentUser()
                session.setCurrentUser(user)

                if user.emailVerified {
                    router.retrySplash()
                } else {
                    errorMessage = String(localized: "email_verification.check.not_verified_yet")
                }
            } catch let error as NetworkError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resend() {
        guard !resendDisabled else { return }

        isResending = true
        errorMessage = nil
        statusMessage = nil

        Task {
            defer { isResending = false }

            do {
                _ = try await AuthService.resendVerification(email: email)
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
    CheckEmailView(email: "test@example.com")
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}
