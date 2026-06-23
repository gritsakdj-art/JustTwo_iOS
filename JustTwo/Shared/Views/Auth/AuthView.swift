import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var viewModel = AuthViewModel()

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    header

                    form
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.xxl)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
                .offset(y: -min(proxy.size.height * 0.04, 36))
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(authBackground)
            .hideKeyboardOnTap()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimaryGradient)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.onAccentText)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Color.brandPrimaryGlow.opacity(0.18), radius: 10, x: 0, y: 5)

                Text("app.name")
                    .font(Font.App.screenTitle)
                    .foregroundStyle(Color.primaryText)
            }

            Text(viewModel.mode == .login ? "auth.subtitle" : "auth.register_subtitle")
                .font(Font.App.subtitle)
                .foregroundStyle(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(spacing: 26) {
                BaseTextField(
                    title: "auth.email",
                    text: $viewModel.email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    errorMessage: viewModel.emailValidationMessage
                )

                BaseTextField(
                    title: "auth.password",
                    text: $viewModel.password,
                    isSecure: true,
                    textContentType: viewModel.mode == .register ? .newPassword : .password,
                    errorMessage: viewModel.passwordValidationMessage
                )
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if viewModel.mode == .login, viewModel.showForgotPasswordOption {
                Button {
                    viewModel.presentForgotPassword()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 13, weight: .bold))

                        Text("auth.forgot_password.link")
                            .font(Font.App.footnote(weight: .semibold))
                    }
                    .foregroundStyle(Color.brandPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.spring(pressedScale: 0.96))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            PrimaryButton(
                viewModel.mode == .login ? "auth.login" : "auth.register",
                systemImage: "arrow.right",
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.isValid
            ) {
                viewModel.submit(using: session, router: router)
            }

            HStack(spacing: 6) {
                Text(viewModel.mode == .login ? "auth.no_account" : "auth.have_account")
                    .font(Font.App.footnote())
                    .foregroundStyle(Color.secondaryText)

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                        viewModel.toggleMode()
                    }
                } label: {
                    Text(viewModel.mode == .login ? "auth.register" : "auth.login")
                        .font(Font.App.footnote(weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
                .buttonStyle(.spring(pressedScale: 0.94))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(AppSpacing.lg)
        .background(Color.cardSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .stroke(Color.glassBorderHighlight.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.16), radius: 24, x: 0, y: 14)
        .animation(.easeInOut(duration: 0.18), value: viewModel.errorMessage)
        .animation(.easeInOut(duration: 0.18), value: viewModel.showForgotPasswordOption)
        .sheet(isPresented: $viewModel.isForgotPasswordSheetPresented) {
            forgotPasswordSheet
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
        }
    }

    private var forgotPasswordSheet: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("auth.forgot_password.title")
                    .font(Font.App.manrope(size: 20, weight: .bold))
                    .foregroundStyle(Color.primaryText)

                Text("auth.forgot_password.subtitle")
                    .font(Font.App.subheadline())
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BaseTextField(
                title: "auth.email",
                text: $viewModel.forgotPasswordEmail,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                errorMessage: viewModel.forgotPasswordErrorMessage
            )

            if let message = viewModel.forgotPasswordMessage {
                Text(message)
                    .font(Font.App.footnote(weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(
                "auth.forgot_password.send",
                systemImage: "paperplane.fill",
                isLoading: viewModel.isSendingForgotPassword,
                isDisabled: viewModel.forgotPasswordEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                viewModel.sendForgotPassword()
            }

            Button {
                viewModel.isForgotPasswordSheetPresented = false
            } label: {
                Text("common.cancel")
                    .font(Font.App.footnote(weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.spring(pressedScale: 0.96))
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .background(Color.authBackgroundGradient.ignoresSafeArea())
    }

    private var authBackground: some View {
        ZStack {
            Color.authBackgroundGradient.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.surface.opacity(0.0),
                    Color.surface.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    AuthView()
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}
