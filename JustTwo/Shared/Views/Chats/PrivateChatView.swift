import SwiftUI

struct PrivateChatView: View {
    private static let bottomPaddingID = "private-chat-bottom-padding"
    private static let unreadSeparatorID = "private-chat-unread-separator"
    private static let scrollCoordinateSpace = "private-chat-scroll-space"
    private static let inputClearance: CGFloat = 16

    @State private var viewModel: ChatViewModel
    @State private var presenceStore = PresenceStore.shared

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private let usesPreviewData: Bool
    private let targetMessageID: UUID?

    @State private var didScrollToTargetMessage = false
    @State private var didPerformInitialScroll = false
    @State private var isLastReadMessageVisible = true
    @State private var isLatestMessageVisible = true
    @State private var scrollViewportHeight: CGFloat = 0
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
        chatScreen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                chatBackground.ignoresSafeArea()
            }
    }

    private var chatScreen: some View {
        @Bindable var viewModel = viewModel

        return messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
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
    private var messageList: some View {
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
                messageScrollView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hideKeyboardOnTap()
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            if message.id == viewModel.firstUnreadMessageID {
                                unreadSeparator
                                    .id(Self.unreadSeparatorID)
                            }

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
                            .background {
                                messageVisibilityTracker(for: message)
                            }
                        }

                        Color.clear
                            .frame(height: Self.inputClearance)
                            .id(Self.bottomPaddingID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .coordinateSpace(name: Self.scrollCoordinateSpace)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollViewportHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
                .scrollIndicators(.hidden)
                .onPreferenceChange(ScrollViewportHeightKey.self) { height in
                    scrollViewportHeight = max(0, height)
                }
                .onPreferenceChange(LastReadMessageFrameKey.self) { frame in
                    updateLastReadVisibility(frame: frame)
                }
                .onPreferenceChange(LatestMessageFrameKey.self) { frame in
                    updateLatestMessageVisibility(frame: frame)
                }

                if shouldShowScrollDownButton {
                    scrollToBottomButton {
                        scrollToLatestMessage(proxy, animated: true)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .animation(.easeOut(duration: 0.2), value: shouldShowScrollDownButton)
                }
            }
            .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
                guard wasLoading, !isLoading else { return }
                scheduleInitialScroll(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                guard newCount > 0, oldCount != newCount, !didPerformInitialScroll else { return }
                scheduleInitialScroll(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.last?.id) { oldValue, newValue in
                guard oldValue != nil, newValue != nil else { return }
                if isLatestMessageVisible {
                    scheduleScrollToLatest(proxy, animated: true)
                }
            }
            .onAppear {
                didPerformInitialScroll = false
                didScrollToTargetMessage = false
                isLastReadMessageVisible = true
                isLatestMessageVisible = true
                scheduleInitialScroll(proxy, animated: false)
            }
            .onDisappear {
                initialScrollTask?.cancel()
                initialScrollTask = nil
            }
        }
    }

    private var shouldShowScrollDownButton: Bool {
        didPerformInitialScroll && !viewModel.messages.isEmpty && !isLastReadMessageVisible
    }

    @ViewBuilder
    private func messageVisibilityTracker(for message: ChatMessage) -> some View {
        let isLastRead = message.id == viewModel.lastReadVisibilityMessageID
        let isLatest = message.id == viewModel.messages.last?.id

        if isLastRead || isLatest {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(Self.scrollCoordinateSpace))
                Color.clear
                    .preference(
                        key: LastReadMessageFrameKey.self,
                        value: isLastRead ? frame : .zero
                    )
                    .preference(
                        key: LatestMessageFrameKey.self,
                        value: isLatest ? frame : .zero
                    )
            }
        }
    }

    private var unreadSeparator: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)

            Text("chats.unreadMessages")
                .font(Font.App.caption(size: 12, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(Color.brandPrimary.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.28), lineWidth: 1)
        )
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("chats.unreadMessages"))
    }

    private func scrollToBottomButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.chatBubbleOther.opacity(0.96))
                        .shadow(color: Color.discoverCardShadow.opacity(0.16), radius: 12, x: 0, y: 6)
                )
                .overlay(
                    Circle()
                        .stroke(Color.glassBorderHighlight.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("chats.scrollToLatest"))
        .transition(.scale.combined(with: .opacity))
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

    private func scheduleInitialScroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !didPerformInitialScroll, !viewModel.messages.isEmpty else { return }
        initialScrollTask?.cancel()
        initialScrollTask = Task { @MainActor in
            let delays: [UInt64] = [0, 50, 100, 200, 350, 500, 700]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled, !didPerformInitialScroll else { return }
                guard !viewModel.messages.isEmpty else { continue }
                performInitialScroll(proxy, animated: animated)
            }
            didPerformInitialScroll = true
        }
    }

    private func scheduleScrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        initialScrollTask?.cancel()
        initialScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollToLatestMessage(proxy, animated: animated)
        }
    }

    private func performInitialScroll(_ proxy: ScrollViewProxy, animated: Bool) {
        let target = viewModel.initialScrollTarget(pushTargetMessageID: targetMessageID)
        switch target {
        case .targetMessage(let messageID):
            didScrollToTargetMessage = true
            NetworkDebug.log("Chat initial scroll target: push message")
            scrollTo(messageID, proxy: proxy, anchor: .center, animated: animated)
        case .lastReadMessage(let messageID):
            NetworkDebug.log("Chat initial scroll target: last read message")
            scrollTo(messageID, proxy: proxy, anchor: .bottom, animated: animated)
        case .bottom:
            NetworkDebug.log("Chat initial scroll target: bottom")
            scrollToLatestMessage(proxy, animated: animated)
        }
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastMessageID = viewModel.messages.last?.id else { return }

        let scroll = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
            proxy.scrollTo(Self.bottomPaddingID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25), scroll)
        } else {
            scroll()
        }
    }

    private func scrollTo<ID: Hashable>(
        _ id: ID,
        proxy: ScrollViewProxy,
        anchor: UnitPoint,
        animated: Bool
    ) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }

    private func updateLastReadVisibility(frame: CGRect) {
        guard frame != .zero else { return }
        let nextValue = ChatViewModel.isMessageVisibleInViewport(
            frame: frame,
            viewportHeight: scrollViewportHeight
        )
        guard nextValue != isLastReadMessageVisible else { return }
        isLastReadMessageVisible = nextValue
        NetworkDebug.log(nextValue ? "Chat down button hidden" : "Chat down button visible")
    }

    private func updateLatestMessageVisibility(frame: CGRect) {
        guard frame != .zero else { return }
        isLatestMessageVisible = ChatViewModel.isMessageVisibleInViewport(
            frame: frame,
            viewportHeight: scrollViewportHeight
        )
    }
}

private struct ScrollViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LastReadMessageFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct LatestMessageFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
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
