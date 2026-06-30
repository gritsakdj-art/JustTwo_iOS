import SwiftUI

private enum InviteLinkMode: CaseIterable, Hashable {
    case invite
    case join

    var title: LocalizedStringResource {
        switch self {
        case .invite:
            return "invite.link.mode.invite"
        case .join:
            return "invite.link.mode.join"
        }
    }
}

struct InviteLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var viewModel = InviteLinkViewModel()
    @State private var selectedMode: InviteLinkMode = .invite
    @State private var shareLinkItem: ShareURLItem?
    @State private var shareQRImage: UIImage?
    @State private var pastedInvitePreview: PastedInvitePreview?
    @State private var isScannerPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.discoverBackgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: AppSpacing.lg) {
                    modePicker

                    Group {
                        switch selectedMode {
                        case .invite:
                            inviteContent
                        case .join:
                            joinContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
            .sheet(isPresented: $isScannerPresented) {
                InviteQRCodeScannerSheet { code in
                    handleScannedInviteCode(code)
                }
            }
        }
    }

    private var modePicker: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 4
            let segmentCount = CGFloat(InviteLinkMode.allCases.count)
            let segmentWidth = max((geometry.size.width - inset * 2) / segmentCount, 0)
            let selectedIndex = CGFloat(InviteLinkMode.allCases.firstIndex(of: selectedMode) ?? 0)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.discoverSelectedGradient)
                    .frame(width: segmentWidth, height: 40)
                    .offset(x: inset + selectedIndex * segmentWidth, y: inset)
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selectedMode)

                HStack(spacing: 0) {
                    ForEach(InviteLinkMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                selectedMode = mode
                            }
                        } label: {
                            Text(mode.title)
                                .font(Font.App.manrope(size: 14, weight: selectedMode == mode ? .bold : .medium))
                                .foregroundStyle(selectedMode == mode ? Color.onAccentText : Color.discoverSecondaryText)
                                .frame(width: segmentWidth, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.spring(pressedScale: 0.98))
                    }
                }
                .padding(inset)
            }
        }
        .frame(height: 48)
        .background(Color.cardSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.hairline.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, AppSpacing.sm)
    }

    @ViewBuilder
    private var inviteContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .loaded(let content):
            inviteLoadedView(content)
        case .failed(let message):
            inviteFailedView(message: message)
        }
    }

    private var joinContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                joinHeader

                joinLinkCard
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var joinHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.discoverSelectedGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.discoverViolet.opacity(0.24), radius: 16, x: 0, y: 8)

                Image(systemName: "link.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }
            .padding(.top, AppSpacing.sm)

            Text("invite.join.headline")
                .font(Font.App.manrope(size: 20, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.center)

            Text("invite.join.subtitle")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, AppSpacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    private var joinLinkCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("invite.link.paste.section")
                .font(Font.App.manrope(size: 15, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            Text("invite.link.paste.hint")
                .font(Font.App.caption())
                .foregroundStyle(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField("invite.link.paste.placeholder", text: $viewModel.pastedLinkText, axis: .vertical)
                .font(Font.App.manrope(size: 14, weight: .medium))
                .foregroundStyle(Color.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .onChange(of: viewModel.pastedLinkText) { _, _ in
                    viewModel.pastedLinkError = nil
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                        .fill(Color.fieldBackground.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                        .stroke(Color.hairline.opacity(0.9), lineWidth: 1)
                )

            if let error = viewModel.pastedLinkError {
                Text(error)
                    .font(Font.App.caption())
                    .foregroundStyle(Color.error)
            }

            Button {
                viewModel.pasteFromClipboard()
            } label: {
                Label("invite.join.paste_clipboard", systemImage: "doc.on.clipboard")
                    .font(Font.App.manrope(size: 14, weight: .semibold))
                    .foregroundStyle(Color.discoverViolet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous)
                            .fill(Color.discoverViolet.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous)
                            .stroke(Color.discoverViolet.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.spring(pressedScale: 0.98))

            Button {
                isScannerPresented = true
            } label: {
                Label("invite.join.scan_button", systemImage: "qrcode.viewfinder")
                    .font(Font.App.manrope(size: 14, weight: .semibold))
                    .foregroundStyle(Color.discoverViolet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous)
                            .fill(Color.discoverViolet.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.button, style: .continuous)
                            .stroke(Color.discoverViolet.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.spring(pressedScale: 0.98))

            PrimaryButton(
                "invite.join.open_button",
                systemImage: "arrow.right.circle.fill",
                isDisabled: viewModel.pastedLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                openPastedInvite()
            }
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .fill(Color.cardSurface.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 20, x: 0, y: 8)
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

    private func inviteLoadedView(_ content: InviteLinkViewModel.LoadedContent) -> some View {
        ScrollView(showsIndicators: false) {
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
                                .fill(Color.fieldBackground.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                                .stroke(Color.hairline.opacity(0.9), lineWidth: 1)
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

                inviteActionButtonsRow(content)
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private func inviteActionButtonsRow(_ content: InviteLinkViewModel.LoadedContent) -> some View {
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

    private func qrSection(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 200, maxHeight: 200)
            .padding(AppSpacing.sm)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
            .shadow(color: Color.discoverCardShadow.opacity(0.12), radius: 18, x: 0, y: 8)
            .frame(maxWidth: .infinity)
    }

    private func openPastedInvite() {
        guard let token = viewModel.parsedPastedInviteToken() else { return }
        pastedInvitePreview = PastedInvitePreview(token: token)
    }

    private func handleScannedInviteCode(_ code: String) {
        viewModel.pastedLinkText = code
        guard let token = viewModel.parsedPastedInviteToken() else { return }
        pastedInvitePreview = PastedInvitePreview(token: token)
    }

    private func inviteFailedView(message: String) -> some View {
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
