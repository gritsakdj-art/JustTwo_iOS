import SwiftUI

struct InvitePreviewView: View {
    let token: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var viewModel: InvitePreviewViewModel
    @State private var isBlockConfirmationPresented = false

    init(token: String) {
        self.token = token
        _viewModel = State(initialValue: InvitePreviewViewModel(token: token))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.discoverBackgroundGradient
                    .ignoresSafeArea()

                content
                    .padding(.horizontal, AppSpacing.lg)
            }
            .navigationTitle("invite.preview.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.done") {
                        router.dismissInvitePreview()
                        dismiss()
                    }
                    .foregroundStyle(Color.primaryText)
                }
            }
            .task {
                await viewModel.load(session: session, router: router)
            }
            .alert("invite.preview.block.title", isPresented: $isBlockConfirmationPresented) {
                Button("common.cancel", role: .cancel) {}
                Button("invite.preview.block.confirm", role: .destructive) {
                    Task {
                        await viewModel.block(session: session, router: router)
                    }
                }
            } message: {
                Text("invite.preview.block.message")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingView(isAccepting: false)
        case .accepting:
            loadingView(isAccepting: true)
        case .loaded(let content):
            loadedView(content)
        case .unavailable(let message):
            messageView(
                title: "invite.preview.unavailable.title",
                message: message
            )
        case .failed(let message):
            messageView(
                title: "invite.error.title",
                message: message
            )
        case .blocked:
            messageView(
                title: "invite.preview.blocked.title",
                message: String(localized: "invite.preview.blocked.message")
            )
        }
    }

    private func loadingView(isAccepting: Bool) -> some View {
        VStack(spacing: AppSpacing.sm) {
            ProgressView()
                .tint(Color.brandPrimary)
            Text(isAccepting ? "invite.preview.accepting" : "invite.preview.loading")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedView(_ content: InvitePreviewContent) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer(minLength: AppSpacing.lg)

            ChatAvatarView(
                title: content.displayName,
                photoURL: content.avatarURL,
                photoID: content.avatarPhotoID,
                size: 96
            )

            VStack(spacing: AppSpacing.sm) {
                Text(content.displayName)
                    .font(Font.App.manrope(size: 24, weight: .bold))
                    .foregroundStyle(Color.primaryText)

                if let city = content.city, !city.isEmpty {
                    Text(city)
                        .font(Font.App.subheadline())
                        .foregroundStyle(Color.secondaryText)
                }

                if let bio = content.bio, !bio.isEmpty {
                    Text(bio)
                        .font(Font.App.body())
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.sm)
                }

                Text("invite.preview.invited_you")
                    .font(Font.App.subheadline())
                    .foregroundStyle(Color.primaryText)
                    .padding(.top, AppSpacing.sm)
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                        .font(Font.App.caption())
                    .foregroundStyle(Color.brandPrimary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: AppSpacing.lg) {
                HStack(spacing: 28) {
                    ActionButton(
                        icon: "xmark",
                        accessibilityLabel: "invite.preview.decline",
                        size: 60,
                        iconSize: 22,
                        style: .outlined(
                            iconColor: Color.discoverPink,
                            borderColor: Color.discoverPink.opacity(0.25)
                        )
                    ) {
                        router.dismissInvitePreview()
                        dismiss()
                    }

                    ActionButton(
                        icon: "checkmark",
                        accessibilityLabel: "invite.preview.accept",
                        size: 72,
                        iconSize: 26,
                        style: .gradient(
                            gradient: Color.discoverSelectedGradient,
                            shadowColor: Color.discoverViolet.opacity(0.38)
                        )
                    ) {
                        Task {
                            await viewModel.accept(session: session, router: router)
                            if router.pendingChatConversation != nil {
                                dismiss()
                            }
                        }
                    }
                }

                Button("invite.preview.block") {
                    isBlockConfirmationPresented = true
                }
                .font(Font.App.button)
                .foregroundStyle(Color.discoverPink)
            }
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private func messageView(title: LocalizedStringResource, message: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)

            Text(title)
                .font(Font.App.manrope(size: 20, weight: .bold))
                .foregroundStyle(Color.primaryText)

            Text(message)
                .font(Font.App.subtitle)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)

            PrimaryButton("common.done") {
                router.dismissInvitePreview()
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    InvitePreviewView(token: "preview-token")
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}
