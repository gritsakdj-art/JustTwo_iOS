import SwiftUI

struct PrivateChatView: View {
    private static let bottomAnchorID = "private-chat-bottom-anchor"

    @State private var viewModel: ChatViewModel
    @State private var presenceStore = PresenceStore.shared

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private let usesPreviewData: Bool
    private let targetMessageID: UUID?

    @State private var bottomChromeHeight: CGFloat = 72
    @State private var didScrollToTargetMessage = false
    @State private var initialScrollTask: Task<Void, Never>?

    init(
        conversation: ChatConversationPreview,
        targetMessageID: UUID? = nil,
        previewViewModel: ChatViewModel? = nil
    ) {
        self.targetMessageID = targetMessageID
        if let previewViewModel {
            _viewModel = State(initialValue: previewViewModel)
            usesPreviewData = true
        } else {
            _viewModel = State(initialValue: ChatViewModel(conversation: conversation))
            usesPreviewData = false
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .bottom) {
            messagesArea(bottomInset: bottomChromeHeight)

            bottomChrome
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: BottomChromeHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .onPreferenceChange(BottomChromeHeightKey.self) { height in
            if height > 0 {
                bottomChromeHeight = height
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chatBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationStackHostingBackgroundClear()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarContent }
        .task {
            guard !usesPreviewData else { return }
            await viewModel.open(session: session, router: router)
            viewModel.activateRealtime(session: session, router: router)
        }
        .onAppear {
            guard !usesPreviewData else { return }
            viewModel.activateRealtime(session: session, router: router)
        }
        .onDisappear {
            guard !usesPreviewData else { return }
            viewModel.deactivateRealtime()
        }
        .sheet(isPresented: actionMenuPresented) {
            if let message = viewModel.actionMenuMessage {
                ChatMessageActionSheet(
                    message: message,
                    onReply: { viewModel.startReply(to: message) },
                    onCopy: { viewModel.copyMessage(message) },
                    onEdit: { viewModel.startEdit(message: message) },
                    onDelete: { viewModel.requestDelete(message) },
                    onReact: { emoji in
                        Task {
                            await viewModel.applyReaction(
                                emoji,
                                to: message,
                                session: session,
                                router: router
                            )
                        }
                    },
                    onDismiss: { viewModel.dismissActionMenu() }
                )
            }
        }
        .alert(
            "chats.action.delete_confirm_title",
            isPresented: deleteAlertPresented
        ) {
            Button("chats.action.delete", role: .destructive) {
                let message = viewModel.pendingDeleteMessage
                viewModel.pendingDeleteMessage = nil

                Task {
                    await viewModel.deleteConfirmedMessage(message, session: session, router: router)
                }
            }
            Button("common.cancel", role: .cancel) {
                viewModel.pendingDeleteMessage = nil
            }
        } message: {
            Text("chats.action.delete_confirm_message")
        }
        .alert(
            "chats.error.title",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("common.cancel", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var actionMenuPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionMenuMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissActionMenu()
                }
            }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeleteMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.pendingDeleteMessage = nil
                }
            }
        )
    }

    private var bottomChrome: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 0) {
            if let mode = viewModel.composeBannerMode {
                ChatComposeBanner(mode: mode) {
                    viewModel.cancelCompose()
                    if viewModel.editingMessage != nil {
                        viewModel.draftText = ""
                    }
                }
            }

            MessageInputView(
                text: $viewModel.draftText,
                onSend: {
                    Task {
                        await viewModel.send(session: session, router: router)
                    }
                },
                isSending: viewModel.isSending
            )
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private func messagesArea(bottomInset: CGFloat) -> some View {
        Group {
            if viewModel.isLoading, viewModel.messages.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .tint(Color.brandPrimary)
                    Text("chats.loadingMessages")
                        .font(Font.App.subheadline())
                        .foregroundStyle(Color.secondaryText)
                }
            } else if let errorMessage = viewModel.errorMessage, viewModel.messages.isEmpty {
                StatePlaceholderView(
                    title: String(localized: "chats.error.title"),
                    subtitle: errorMessage,
                    systemImage: "exclamationmark.triangle",
                    actionTitle: "common.retry",
                    action: {
                        Task {
                            await viewModel.reload(session: session, router: router)
                        }
                    }
                )
            } else {
                messageList(bottomInset: bottomInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hideKeyboardOnTap()
    }

    private func messageList(bottomInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(
                            message: message,
                            senderName: message.isMine ? nil : viewModel.conversation.title,
                            onLongPress: {
                                viewModel.openActionMenu(for: message)
                            },
                            onReactionTap: { reaction in
                                Task {
                                    await viewModel.toggleReaction(
                                        reaction,
                                        on: message,
                                        session: session,
                                        router: router
                                    )
                                }
                            }
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: max(24, bottomInset + 16))
                        .id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
                guard wasLoading, !isLoading else { return }
                scheduleScrollToVisiblePosition(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.last?.id) { oldValue, newValue in
                guard oldValue != nil, newValue != nil else { return }
                scheduleScrollToVisiblePosition(proxy, animated: true)
            }
            .onChange(of: bottomInset) { _, _ in
                scheduleScrollToVisiblePosition(proxy, animated: false)
            }
            .onAppear {
                scheduleScrollToVisiblePosition(proxy, animated: false)
            }
            .onDisappear {
                initialScrollTask?.cancel()
                initialScrollTask = nil
            }
        }
    }

    private var chatBackground: some View {
        ChatPatternBackground()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(viewModel.conversation.title)
                    .font(Font.App.headline(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)

                if viewModel.isOtherParticipantTyping {
                    Text("chats.typing")
                        .font(Font.App.caption())
                        .foregroundStyle(Color.secondaryText)
                        .italic()
                } else if presenceStore.isOnline(profileID: viewModel.conversation.otherParticipantProfileID) {
                    Text("chats.online")
                        .font(Font.App.caption())
                        .foregroundStyle(Color.secondaryText)
                } else {
                    Text("chats.personal")
                        .font(Font.App.caption())
                        .foregroundStyle(Color.secondaryText)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            ChatAvatarView(
                title: viewModel.conversation.title,
                photoURL: viewModel.conversation.avatarURL,
                photoID: viewModel.conversation.avatarPhotoID,
                size: 38
            )
            .onlinePresenceRing(
                isOnline: presenceStore.isOnline(profileID: viewModel.conversation.otherParticipantProfileID)
            )
            .accessibilityLabel(Text(viewModel.conversation.title))
        }
    }

    private func scheduleScrollToVisiblePosition(_ proxy: ScrollViewProxy, animated: Bool) {
        initialScrollTask?.cancel()
        initialScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(64))
            guard !Task.isCancelled else { return }
            scrollToTargetMessage(proxy, animated: animated)
            scrollToBottom(proxy, animated: animated)
        }
    }

    private func scrollToTargetMessage(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !didScrollToTargetMessage,
              let targetMessageID,
              viewModel.messages.contains(where: { $0.id == targetMessageID }) else {
            return
        }

        didScrollToTargetMessage = true
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(targetMessageID, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetMessageID, anchor: .center)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard targetMessageID == nil || didScrollToTargetMessage else { return }
        guard let lastMessageID = viewModel.messages.last?.id else { return }

        let scroll = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25), scroll)
        } else {
            scroll()
        }
    }
}

private struct BottomChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Chat - With reactions") {
    NavigationStack {
        PrivateChatView(
            conversation: ChatUIMockData.conversations[0],
            previewViewModel: .preview(
                conversation: ChatUIMockData.conversations[0],
                messages: ChatUIMockData.richThread
            )
        )
    }
    .environment(SessionStore.shared)
    .environment(AppRouter.shared)
}

#Preview("Chat - Dark") {
    NavigationStack {
        PrivateChatView(
            conversation: ChatUIMockData.conversations[0],
            previewViewModel: .preview(
                conversation: ChatUIMockData.conversations[0],
                messages: ChatUIMockData.richThread
            )
        )
    }
    .environment(SessionStore.shared)
    .environment(AppRouter.shared)
    .preferredColorScheme(.dark)
}
