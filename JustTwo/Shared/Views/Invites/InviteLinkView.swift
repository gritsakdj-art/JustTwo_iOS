import SwiftUI

struct InviteLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var viewModel = InviteLinkViewModel()
    @State private var shareLinkItem: ShareURLItem?
    @State private var shareQRImage: UIImage?
    @State private var pastedInvitePreview: PastedInvitePreview?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.discoverBackgroundGradient
                    .ignoresSafeArea()

                content
                    .padding(.horizontal, AppSpacing.lg)
            }
            .navigationTitle("invite.link.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.primaryText)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .sheet(item: $shareLinkItem) { item in
                ActivityShareSheet(items: [item.url])
            }
            .sheet(item: Binding(
                get: { shareQRImage.map(ShareImageItem.init) },
                set: { shareQRImage = $0?.image }
            )) { item in
                ActivityShareSheet(items: [item.image])
            }
            .fullScreenCover(item: $pastedInvitePreview) { item in
                InvitePreviewView(token: item.token)
                    .environment(session)
                    .environment(router)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .loaded(let content):
            loadedView(content)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var loadingView: some View {
        VStack(spacing: AppSpacing.sm) {
            ProgressView()
                .tint(Color.brandPrimary)
            Text("invite.link.loading")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedView(_ content: InviteLinkViewModel.LoadedContent) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                qrSection(content.qrImage)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("invite.link.subtitle")
                        .font(Font.App.subheadline())
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)

                    Text(content.inviteURL.absoluteString)
                        .font(Font.App.manrope(size: 13, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    if viewModel.didCopyLink {
                        Text("invite.link.copied")
                            .font(Font.App.caption())
                            .foregroundStyle(Color.brandPrimary)
                            .frame(maxWidth: .infinity)
                    }

                    if let expiresAt = content.invite.expiresAt {
                        Text(expiresLabel(expiresAt))
                            .font(Font.App.caption())
                            .foregroundStyle(Color.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                }

                actionButtonsRow(content)

                pasteInviteSection
            }
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private func actionButtonsRow(_ content: InviteLinkViewModel.LoadedContent) -> some View {
        HStack(spacing: 18) {
            ActionButton(
                icon: "doc.on.doc",
                accessibilityLabel: "invite.link.copy",
                size: 52,
                iconSize: 18,
                style: .outlined(
                    iconColor: Color.discoverViolet,
                    borderColor: Color.discoverViolet.opacity(0.22)
                )
            ) {
                viewModel.copyLink()
            }

            ActionButton(
                icon: "square.and.arrow.up",
                accessibilityLabel: "invite.link.share",
                size: 52,
                iconSize: 18,
                style: .outlined(
                    iconColor: Color.discoverViolet,
                    borderColor: Color.discoverViolet.opacity(0.22)
                )
            ) {
                shareLinkItem = ShareURLItem(url: content.inviteURL)
            }

            ActionButton(
                icon: "qrcode",
                accessibilityLabel: "invite.link.share_qr",
                size: 52,
                iconSize: 18,
                style: .outlined(
                    iconColor: Color.discoverViolet,
                    borderColor: Color.discoverViolet.opacity(0.22)
                )
            ) {
                shareQRImage = content.qrImage
            }

            ActionButton(
                icon: "arrow.clockwise",
                accessibilityLabel: "invite.link.refresh",
                size: 52,
                iconSize: 18,
                style: .outlined(
                    iconColor: Color.discoverPink,
                    borderColor: Color.discoverPink.opacity(0.22)
                )
            ) {
                Task { await viewModel.refresh() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pasteInviteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("invite.link.paste.section")
                .font(Font.App.manrope(size: 15, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            Text("invite.link.paste.hint")
                .font(Font.App.caption())
                .foregroundStyle(Color.secondaryText)

            HStack(spacing: AppSpacing.sm) {
                TextField("invite.link.paste.placeholder", text: $viewModel.pastedLinkText, axis: .vertical)
                    .font(Font.App.manrope(size: 14, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)
                    .onChange(of: viewModel.pastedLinkText) { _, _ in
                        viewModel.pastedLinkError = nil
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                ActionButton(
                    icon: "doc.on.clipboard",
                    accessibilityLabel: "invite.link.paste.clipboard",
                    size: 44,
                    iconSize: 16,
                    style: .outlined(
                        iconColor: Color.discoverViolet,
                        borderColor: Color.discoverViolet.opacity(0.22)
                    )
                ) {
                    viewModel.pasteFromClipboard()
                }

                ActionButton(
                    icon: "arrow.right.circle.fill",
                    accessibilityLabel: "invite.link.paste.open",
                    size: 44,
                    iconSize: 18,
                    style: .gradient(
                        gradient: Color.brandPrimaryGradient,
                        shadowColor: Color.brandPrimaryGlow.opacity(0.22)
                    )
                ) {
                    openPastedInvite()
                }
            }

            if let error = viewModel.pastedLinkError {
                Text(error)
                    .font(Font.App.caption())
                    .foregroundStyle(Color.discoverPink)
            }
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func qrSection(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 200, maxHeight: 200)
            .padding(AppSpacing.sm)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .frame(maxWidth: .infinity)
    }

    private func openPastedInvite() {
        guard let token = viewModel.parsedPastedInviteToken() else { return }
        pastedInvitePreview = PastedInvitePreview(token: token)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)

            Text("invite.error.title")
                .font(Font.App.manrope(size: 20, weight: .bold))
                .foregroundStyle(Color.primaryText)

            Text(message)
                .font(Font.App.subtitle)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)

            PrimaryButton("common.retry") {
                Task { await viewModel.refresh() }
            }

            pasteInviteSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, AppSpacing.lg)
    }

    private func expiresLabel(_ date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return String(format: String(localized: "invite.link.valid_until_format"), formatted)
    }
}

private struct PastedInvitePreview: Identifiable {
    let id = UUID()
    let token: String
}

private struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview {
    InviteLinkView()
}
