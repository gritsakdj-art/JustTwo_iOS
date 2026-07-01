import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PrivateChatView: View {
    private static let unreadSeparatorID = "private-chat-unread-separator"
    private static let loadOlderHeaderID = "private-chat-load-older-header"
    private static let bottomClearance: CGFloat = 28
    private static let bottomVisibilityThreshold: CGFloat = 0.92

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
    @State private var isNearBottom = false
    @State private var shouldStickToBottom = true
    @State private var isScrollingToBottom = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var didTriggerOlderLoadForCurrentTopReach = false
    @State private var initialScrollTask: Task<Void, Never>?
    @State private var scrollTask: Task<Void, Never>?
    @State private var olderMessagesScrollAnchorID: UUID?
    @State private var isRestoringOlderMessagesScroll = false

    init(
        conversation: ChatConversationPreview,
        targetMessageID: UUID? = nil,
        previewViewModel: ChatViewModel? = nil,
        previewPresenceStore: PresenceStore? = nil
    ) {
        self.targetMessageID = targetMessageID
        _presenceStore = State(initialValue: previewPresenceStore ?? .shared)
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
                chatBackground.ignoresSafeArea(.container, edges: .all)
            }
    }

    private var chatScreen: some View {
        @Bindable var viewModel = viewModel

        return messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .navigationStackHostingBackgroundClear()
            .toolbar(.hidden, for: .tabBar)
            .tabBarInstantRevealOnPop()
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .task {
                guard !usesPreviewData else { return }
                await viewModel.open(session: session, router: router)
                viewModel.activateRealtime(session: session, router: router)
            }
            .onAppear {
                guard !usesPreviewData else { return }
                MessengerDiagnostics.event(
                    .chatAppeared,
                    conversationID: viewModel.conversation.id,
                    metadata: [
                        "messageCount": "\(viewModel.messages.count)",
                        "isNearBottom": "\(isNearBottom)"
                    ]
                )
                viewModel.activateRealtime(session: session, router: router)
            }
            .onDisappear {
                guard !usesPreviewData else { return }
                MessengerDiagnostics.event(
                    .chatDisappeared,
                    conversationID: viewModel.conversation.id,
                    metadata: [
                        "messageCount": "\(viewModel.messages.count)",
                        "didPerformInitialScroll": "\(didPerformInitialScroll)"
                    ]
                )
                viewModel.close()
            }
            .overlay {
                if let message = viewModel.actionMenuMessage, viewModel.actionMenuAnchor != .zero {
                    ChatMessageContextMenuOverlay(
                        message: message,
                        anchor: viewModel.actionMenuAnchor,
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
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: viewModel.actionMenuMessage?.id)
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

        return MessageInputView(
            text: $viewModel.draftText,
            onSend: {
                viewModel.send(session: session, router: router)
            },
            composeMode: viewModel.composeMode,
            onCancelCompose: {
                viewModel.cancelCompose()
            },
            isSending: viewModel.isSending
        )
        .padding(.bottom, keyboardHeight)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
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
                        if viewModel.hasMoreOlderMessages {
                            loadOlderMessagesHeader(proxy: proxy)
                                .id(Self.loadOlderHeaderID)
                        }

                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            if shouldShowDaySeparator(at: index) {
                                daySeparator(
                                    title: ChatMessageDateFormatting.daySeparatorTitle(for: message.createdAt)
                                )
                                .id(Self.daySeparatorID(for: message.createdAt))
                            }

                            if message.id == viewModel.firstUnreadMessageID {
                                unreadSeparator
                                    .id(Self.unreadSeparatorID)
                            }

                            messageRow(for: message)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    guard !usesPreviewData, viewModel.hasMoreOlderMessages else { return }
                    await loadOlderMessagesPreservingScroll(proxy: proxy)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            guard viewModel.actionMenuMessage != nil else { return }
                            viewModel.dismissActionMenu()
                        }
                )

                if shouldShowScrollDownButton {
                    scrollToBottomButton {
                        requestScrollToLatestFromButton(proxy)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .animation(.easeOut(duration: 0.2), value: shouldShowScrollDownButton)
                }
            }
            .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
                guard wasLoading, !isLoading else { return }
                requestInitialScrollIfNeeded(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                if isRestoringOlderMessagesScroll,
                   let anchor = olderMessagesScrollAnchorID,
                   newCount > oldCount {
                    isRestoringOlderMessagesScroll = false
                    olderMessagesScrollAnchorID = nil
                    scrollTo(anchor, proxy: proxy, anchor: .top, animated: false)
                    return
                }

                guard oldCount == 0, newCount > 0, !viewModel.isLoading else { return }
                requestInitialScrollIfNeeded(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.last?.id) { oldValue, newValue in
                guard oldValue != nil, newValue != nil else { return }
                if shouldAutoScrollToNewLatestMessage {
                    MessengerDiagnostics.event(
                        .scrollToBottomRequested,
                        conversationID: viewModel.conversation.id,
                        metadata: [
                            "reason": "newLatestMessage",
                            "messageCount": "\(viewModel.messages.count)",
                            "isNearBottom": "\(isNearBottom)",
                            "force": "true"
                        ]
                    )
                    scheduleScrollToLatest(proxy, animated: true, force: true)
                }
            }
            .onChange(of: keyboardHeight) { oldValue, newValue in
                guard abs(newValue - oldValue) > 1, shouldStickToBottom else { return }
                scheduleScrollToLatest(proxy, animated: true, delays: [0, 120, 280], force: true)
            }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardHeight(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            #endif
            .onAppear {
                isLastReadMessageVisible = true
                isLatestMessageVisible = true
                isNearBottom = false
                shouldStickToBottom = true
                requestInitialScrollIfNeeded(proxy, animated: false)
            }
            .onDisappear {
                initialScrollTask?.cancel()
                initialScrollTask = nil
                scrollTask?.cancel()
                scrollTask = nil
            }
        }
    }

    private var shouldShowScrollDownButton: Bool {
        didPerformInitialScroll && !viewModel.messages.isEmpty && !isNearBottom
    }

    private var shouldAutoScrollToNewLatestMessage: Bool {
        guard didPerformInitialScroll, let latestMessage = viewModel.messages.last else { return false }
        return latestMessage.isMine || isNearBottom
    }

    private func updateBottomProximity(_ isVisible: Bool) {
        guard didPerformInitialScroll else { return }

        let isAtBottom = isVisible
        guard isNearBottom != isAtBottom else { return }
        isNearBottom = isAtBottom

        if isAtBottom {
            isScrollingToBottom = false
            markStuckToBottom()
        } else if !isScrollingToBottom {
            shouldStickToBottom = false
        }
    }

    private func markStuckToBottom() {
        isNearBottom = true
        isLatestMessageVisible = true
        shouldStickToBottom = true
    }

    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        let isLastMessage = message.id == viewModel.messages.last?.id

        let row = MessageRow(
            message: message,
            senderName: message.isMine ? nil : viewModel.conversation.title,
            onLongPress: { frame in
                viewModel.openActionMenu(for: message, anchor: frame)
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

        Group {
            if isLastMessage {
                row
                    .padding(.bottom, Self.bottomClearance)
                    .onScrollVisibilityChange(threshold: Self.bottomVisibilityThreshold) { isVisible in
                        updateBottomProximity(isVisible)
                    }
            } else if message.id == viewModel.lastReadVisibilityMessageID {
                row.onScrollVisibilityChange(threshold: 0.08) { isVisible in
                    guard didPerformInitialScroll else { return }
                    guard isLastReadMessageVisible != isVisible else { return }
                    isLastReadMessageVisible = isVisible
                }
            } else {
                row
            }
        }
        .id(message.id)
        .scaleEffect(viewModel.actionMenuMessage?.id == message.id ? 1.02 : 1)
        .zIndex(viewModel.actionMenuMessage?.id == message.id ? 2 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: viewModel.actionMenuMessage?.id)
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
        .padding(.horizontal, 22)
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

    private func loadOlderMessagesHeader(proxy: ScrollViewProxy) -> some View {
        Group {
            if viewModel.isLoadingOlderMessages {
                ProgressView()
                    .tint(Color.brandPrimary)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondaryText.opacity(0.8))

                    Text("chats.loadOlderMessagesHint")
                        .font(Font.App.caption())
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !usesPreviewData, !viewModel.isLoadingOlderMessages else { return }
            Task { await loadOlderMessagesPreservingScroll(proxy: proxy) }
        }
        .onScrollVisibilityChange(threshold: 0.4) { isVisible in
            guard !usesPreviewData else { return }
            guard isVisible else {
                didTriggerOlderLoadForCurrentTopReach = false
                return
            }
            guard viewModel.hasMoreOlderMessages,
                  !viewModel.isLoadingOlderMessages,
                  !isRestoringOlderMessagesScroll,
                  !didTriggerOlderLoadForCurrentTopReach else { return }
            didTriggerOlderLoadForCurrentTopReach = true
            Task { await loadOlderMessagesPreservingScroll(proxy: proxy) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            Text(
                viewModel.isLoadingOlderMessages
                    ? "chats.loadingOlderMessages"
                    : "chats.loadOlderMessagesHint"
            )
        )
    }

    private func loadOlderMessagesPreservingScroll(proxy: ScrollViewProxy) async {
        olderMessagesScrollAnchorID = viewModel.messages.first?.id
        isRestoringOlderMessagesScroll = olderMessagesScrollAnchorID != nil
        await viewModel.loadOlderMessages(session: session, router: router)

        if isRestoringOlderMessagesScroll,
           let anchor = olderMessagesScrollAnchorID,
           viewModel.messages.contains(where: { $0.id == anchor }) {
            isRestoringOlderMessagesScroll = false
            olderMessagesScrollAnchorID = nil
            scrollTo(anchor, proxy: proxy, anchor: .top, animated: false)
        }
    }

    private func daySeparator(title: String) -> some View {
        Text(title)
            .font(Font.App.caption(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.chatBubbleOther.opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.glassBorderHighlight.opacity(0.22), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func shouldShowDaySeparator(at index: Int) -> Bool {
        guard index >= 0, index < viewModel.messages.count else { return false }
        if index == 0 { return true }

        let message = viewModel.messages[index]
        let previous = viewModel.messages[index - 1]
        return ChatMessageDateFormatting.isDifferentDay(message.createdAt, from: previous.createdAt)
    }

    private static func daySeparatorID(for date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return "private-chat-day-\(day.timeIntervalSince1970)"
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
            headerTitle
        }

        ToolbarItem(placement: .topBarTrailing) {
            headerAvatar
        }
    }

    private var headerTitle: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: 210)
        .background(
            Capsule(style: .continuous)
                .fill(Color.surface.opacity(0.82))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.glassBorderHighlight.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.10), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var headerAvatar: some View {
        let headerAvatarSize: CGFloat = 32

        return ChatAvatarView(
            title: viewModel.conversation.title,
            photoURL: viewModel.conversation.avatarURL,
            photoID: viewModel.conversation.avatarPhotoID,
            size: headerAvatarSize
        )
        .onlinePresenceRing(
            isOnline: presenceStore.isOnline(profileID: viewModel.conversation.otherParticipantProfileID),
            avatarSize: headerAvatarSize
        )
        .accessibilityLabel(Text(viewModel.conversation.title))
    }

    private func requestInitialScrollIfNeeded(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !didPerformInitialScroll, !viewModel.isLoading, !viewModel.messages.isEmpty else { return }
        scheduleInitialScroll(proxy, animated: animated)
    }

    private func scheduleInitialScroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !didPerformInitialScroll, !viewModel.messages.isEmpty else { return }
        guard initialScrollTask == nil else { return }

        let target = viewModel.initialScrollTarget(pushTargetMessageID: targetMessageID)
        logInitialScrollTarget(target)

        initialScrollTask = Task { @MainActor in
            defer {
                didPerformInitialScroll = true
                initialScrollTask = nil
                if !isNearBottom {
                    shouldStickToBottom = false
                }
            }

            let delays: [UInt64] = [0, 100, 250]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled, !viewModel.messages.isEmpty else { return }
                applyInitialScroll(
                    proxy,
                    target: target,
                    animated: animated && delay == 0
                )
            }
        }
    }

    private func scheduleScrollToLatest(
        _ proxy: ScrollViewProxy,
        animated: Bool,
        delays: [UInt64] = [50],
        force: Bool = false
    ) {
        scrollTask?.cancel()
        isScrollingToBottom = true
        scrollTask = Task { @MainActor in
            defer {
                scrollTask = nil
                if isScrollingToBottom, !isNearBottom {
                    isScrollingToBottom = false
                }
            }

            let lastIndex = delays.count - 1

            for (index, delay) in delays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled else { return }
                if isNearBottom && !force {
                    MessengerDiagnostics.event(
                        .scrollSkipped,
                        conversationID: viewModel.conversation.id,
                        metadata: [
                            "reason": "alreadyNearBottom",
                            "messageCount": "\(viewModel.messages.count)",
                            "force": "false"
                        ]
                    )
                    return
                }

                scrollToLatestMessage(proxy, animated: animated && index == lastIndex)
            }

            if !Task.isCancelled, shouldStickToBottom {
                markStuckToBottom()
                MessengerDiagnostics.event(
                    .scrollToBottomCompleted,
                    conversationID: viewModel.conversation.id,
                    metadata: [
                        "messageCount": "\(viewModel.messages.count)",
                        "isNearBottom": "\(isNearBottom)"
                    ]
                )
            }
        }
    }

    private func requestScrollToLatestFromButton(_ proxy: ScrollViewProxy) {
        MessengerDiagnostics.event(
            .scrollToBottomRequested,
            conversationID: viewModel.conversation.id,
            metadata: [
                "reason": "button",
                "messageCount": "\(viewModel.messages.count)",
                "isNearBottom": "\(isNearBottom)",
                "isLatestMessageVisible": "\(isLatestMessageVisible)"
            ]
        )
        shouldStickToBottom = true
        scheduleScrollToLatest(proxy, animated: true, delays: [0, 60, 180, 360], force: true)
    }

    #if canImport(UIKit)
    private func updateKeyboardHeight(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        let nextKeyboardHeight = max(0, screenHeight - frame.minY)
        guard abs(keyboardHeight - nextKeyboardHeight) > 1 else { return }
        let previousHeight = keyboardHeight
        keyboardHeight = nextKeyboardHeight
        MessengerDiagnostics.event(
            .keyboardHeightChanged,
            conversationID: viewModel.conversation.id,
            metadata: [
                "previousHeight": "\(previousHeight)",
                "nextHeight": "\(nextKeyboardHeight)",
                "shouldStickToBottom": "\(shouldStickToBottom)"
            ]
        )
    }
    #endif

    private func logInitialScrollTarget(_ target: ChatViewModel.InitialScrollTarget) {
        let targetName: String
        switch target {
        case .targetMessage:
            targetName = "pushMessage"
            NetworkDebug.log("Chat initial scroll target: push message")
        case .unreadSeparator:
            targetName = "unreadSeparator"
            NetworkDebug.log("Chat initial scroll target: unread separator centered")
        case .lastReadMessage:
            targetName = "lastReadMessage"
            NetworkDebug.log("Chat initial scroll target: last read message")
        case .bottom:
            targetName = "bottom"
            NetworkDebug.log("Chat initial scroll target: bottom")
        }
        MessengerDiagnostics.event(
            .scrollInitialTargetSelected,
            conversationID: viewModel.conversation.id,
            metadata: [
                "target": targetName,
                "messageCount": "\(viewModel.messages.count)",
                "isNearBottom": "\(isNearBottom)",
                "isLatestMessageVisible": "\(isLatestMessageVisible)"
            ]
        )
    }

    private func applyInitialScroll(
        _ proxy: ScrollViewProxy,
        target: ChatViewModel.InitialScrollTarget,
        animated: Bool
    ) {
        switch target {
        case .targetMessage(let messageID):
            didScrollToTargetMessage = true
            scrollTo(messageID, proxy: proxy, anchor: .center, animated: animated)
        case .unreadSeparator:
            scrollTo(Self.unreadSeparatorID, proxy: proxy, anchor: .center, animated: animated)
        case .lastReadMessage(let messageID):
            scrollTo(messageID, proxy: proxy, anchor: .bottom, animated: animated)
        case .bottom:
            scrollToLatestMessage(proxy, animated: animated)
        }
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastMessageID = viewModel.messages.last?.id else { return }

        let scroll = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
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
}

@MainActor
private enum PrivateChatPreviewState {
    static let conversation = ChatUIMockData.conversations[0]

    static func onlinePresenceStore() -> PresenceStore {
        let store = PresenceStore.makeForTesting()
        if let profileID = conversation.otherParticipantProfileID {
            store.apply(profileID: profileID, status: .online, lastSeenAt: nil)
        }
        return store
    }

    static func typingViewModel() -> ChatViewModel {
        var typingProfileIDs: Set<UUID> = []
        if let profileID = conversation.otherParticipantProfileID {
            typingProfileIDs.insert(profileID)
        }

        return .preview(
            conversation: conversation,
            messages: ChatUIMockData.richThread,
            typingProfileIDs: typingProfileIDs
        )
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

#Preview("Chat - Online typing") {
    NavigationStack {
        PrivateChatView(
            conversation: PrivateChatPreviewState.conversation,
            previewViewModel: PrivateChatPreviewState.typingViewModel(),
            previewPresenceStore: PrivateChatPreviewState.onlinePresenceStore()
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
