import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AuthViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                header

                VStack(spacing: 16) {
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
                        .font(.footnote)
                        .foregroundStyle(Color.discoverPink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(
                    viewModel.mode == .login ? "auth.login" : "auth.register",
                    systemImage: "arrow.right",
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.isValid
                ) {
                    viewModel.submit(using: session)
                }

                HStack(spacing: 6) {
                    Text(viewModel.mode == .login ? "auth.no_account" : "auth.have_account")
                        .font(.footnote)
                        .foregroundStyle(Color.discoverSecondaryText)

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            viewModel.toggleMode()
                        }
                    } label: {
                        Text(viewModel.mode == .login ? "auth.register" : "auth.login")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xxl)
            .padding(.bottom, AppSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
        .hideKeyboardOnTap()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("app.name")
                .font(Font.App.screenTitle)
                .foregroundStyle(Color.discoverPrimaryText)

            Text(viewModel.mode == .login ? "auth.subtitle" : "auth.register_subtitle")
                .font(Font.App.subtitle)
                .foregroundStyle(Color.discoverSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AuthView()
        .environment(SessionStore.shared)
}
