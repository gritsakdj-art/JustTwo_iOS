import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

struct PrivateChatView: View {
    private static let unreadSeparatorID = "private-chat-unread-separator"
    private static let loadOlderHeaderID = "private-chat-load-older-header"
    private static let bottomAnchorID = "private-chat-bottom-anchor"
    private static let bottomClearance: CGFloat = 28
    private static let bottomVisibilityThreshold: CGFloat = 0.92

    @State private var viewModel: ChatViewModel
    @State private var presenceStore = PresenceStore.shared

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private let usesPreviewData: Bool
    private let targetMessageID: UUID?

    @State private var didCompleteInitialPositioning = false
    @State private var isInitialPositioningInProgress = false
    @State private var isNearBottom = false
    @State private var shouldStickToBottom = true
    @State private var isScrollingToBottom = false
    @State private var didTriggerOlderLoadForCurrentTopReach = false
    @State private var initialPositioningTask: Task<Void, Never>?
    @State private var initialPositioningGeneration = 0
    @State private var scrollTask: Task<Void, Never>?
    @State private var scrollRequestGeneration = 0
    @State private var bottomProximityUpdateTask: Task<Void, Never>?
    @State private var olderHeaderVisibilityTask: Task<Void, Never>?
    @State private var autoScrollCoalesceTask: Task<Void, Never>?
    @State private var keyboardVisibilityScrollTask: Task<Void, Never>?
    @State private var layoutStabilizationTask: Task<Void, Never>?
    @State private var imageLayoutScrollTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var olderMessagesScrollAnchorID: String?
    @State private var isRestoringOlderMessagesScroll = false
    #if canImport(PhotosUI)
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    @State private var photoViewerAttachment: ChatMessageAttachment?
    @State private var highlightedReplyTargetID: String?
    @State private var replyHighlightTask: Task<Void, Never>?

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

        return VStack(spacing: 0) {
            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomChrome
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .navigationStackHostingBackgroundClear()
        .toolbar(.hidden, for: .tabBar)
        .tabBarInstantRevealOnPop()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarContent }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            handleKeyboardVisibilityChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            handleKeyboardVisibilityChange()
        }
        #endif
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
                    "didCompleteInitialPositioning": "\(didCompleteInitialPositioning)"
                ]
            )
            viewModel.close()
            keyboardVisibilityScrollTask?.cancel()
            keyboardVisibilityScrollTask = nil
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
        .fullScreenCover(item: $photoViewerAttachment) { attachment in
            ChatPhotoViewerView(attachment: attachment)
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
            onAttach: {
                #if canImport(PhotosUI)
                isPhotoPickerPresented = true
                #endif
            },
            isSending: viewModel.blocksComposeSend,
            isAttachmentDisabled: viewModel.isPreparingImage || viewModel.editingMessage != nil
        )
        #if canImport(PhotosUI)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            selectedPhotoItem = nil
            Task {
                await viewModel.sendImage(from: item, session: session, router: router)
            }
        }
        #endif
        .background(Color.clear)
    }

    @ViewBuilder
    private var messageList: some View {
        ZStack {
            if !viewModel.messages.isEmpty {
                messageScrollView
                    .opacity(shouldShowMessageList ? 1 : 0)
            }

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowMessageList: Bool {
        usesPreviewData
            || didCompleteInitialPositioning
    }

    private var messageScrollView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.hasMoreOlderMessages {
                            loadOlderMessagesHeader()
                                .id(Self.loadOlderHeaderID)
                        }

                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.listIdentity) { index, message in
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

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .refreshable {
                    guard !usesPreviewData, viewModel.hasMoreOlderMessages else { return }
                    await loadOlderMessagesPreservingScroll()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            guard viewModel.actionMenuMessage != nil else { return }
                            viewModel.dismissActionMenu()
                        }
                )
                .onAppear {
                    scrollProxy = proxy
                    if !usesPreviewData {
                        performInitialPositioningIfNeeded()
                    }
                }
                .onDisappear {
                    if scrollProxy != nil {
                        scrollProxy = nil
                    }
                }
            }

            if shouldShowScrollDownButton {
                scrollToBottomButton {
                    requestScrollToLatestFromButton()
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.2), value: shouldShowScrollDownButton)
            }
        }
        .onChange(of: viewModel.isLoading) { _, _ in
            guard !viewModel.isAwaitingInitialMessagePage else { return }
            performInitialPositioningIfNeeded()
        }
        .onChange(of: viewModel.messages.count) { oldCount, newCount in
            if isRestoringOlderMessagesScroll,
               let anchor = olderMessagesScrollAnchorID,
               newCount > oldCount {
                isRestoringOlderMessagesScroll = false
                olderMessagesScrollAnchorID = nil
                scrollTo(anchor, anchor: .top, animated: false)
                return
            }

            if !didCompleteInitialPositioning, !viewModel.isAwaitingInitialMessagePage {
                if isInitialPositioningInProgress, newCount > oldCount {
                    initialPositioningTask?.cancel()
                    isInitialPositioningInProgress = false
                    initialPositioningTask = nil
                }
                performInitialPositioningIfNeeded()
            }
        }
        .onChange(of: viewModel.messages.last?.listIdentity) { oldValue, newValue in
            guard didCompleteInitialPositioning else { return }
            guard oldValue != nil, newValue != nil else { return }

            autoScrollCoalesceTask?.cancel()
            autoScrollCoalesceTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                requestAutoScrollToLatestIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatImageBubbleDidRender)) { _ in
            guard didCompleteInitialPositioning, shouldStickToBottom || isNearBottom else { return }
            imageLayoutScrollTask?.cancel()
            imageLayoutScrollTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, shouldStickToBottom || isNearBottom else { return }
                scrollToBottom(animated: false)
            }
        }
        .onAppear {
            if usesPreviewData {
                didCompleteInitialPositioning = true
                markStuckToBottom()
            } else {
                isNearBottom = false
                shouldStickToBottom = true
                performInitialPositioningIfNeeded()
            }
        }
        .onDisappear {
            initialPositioningTask?.cancel()
            initialPositioningTask = nil
            initialPositioningGeneration += 1
            scrollTask?.cancel()
            scrollTask = nil
            bottomProximityUpdateTask?.cancel()
            bottomProximityUpdateTask = nil
            olderHeaderVisibilityTask?.cancel()
            olderHeaderVisibilityTask = nil
            autoScrollCoalesceTask?.cancel()
            autoScrollCoalesceTask = nil
            layoutStabilizationTask?.cancel()
            layoutStabilizationTask = nil
            imageLayoutScrollTask?.cancel()
            imageLayoutScrollTask = nil
            scrollProxy = nil
            replyHighlightTask?.cancel()
            replyHighlightTask = nil
            highlightedReplyTargetID = nil
        }
    }

    private var shouldShowScrollDownButton: Bool {
        didCompleteInitialPositioning && !viewModel.messages.isEmpty && !isNearBottom
    }

    private var shouldAutoScrollToNewLatestMessage: Bool {
        guard didCompleteInitialPositioning, let latestMessage = viewModel.messages.last else { return false }
        return latestMessage.isMine || isNearBottom
    }

    private func requestAutoScrollToLatestIfNeeded() {
        if shouldAutoScrollToNewLatestMessage {
            MessengerDiagnostics.event(
                .runtimeAutoScrollRequested,
                conversationID: viewModel.conversation.id,
                metadata: [
                    "reason": "newLatestMessage",
                    "messageCount": "\(viewModel.messages.count)",
                    "isNearBottom": "\(isNearBottom)",
                    "isMine": "\(viewModel.messages.last?.isMine == true)"
                ]
            )
            scheduleScrollToLatest(animated: true, force: true)
        } else {
            MessengerDiagnostics.event(
                .runtimeAutoScrollSkipped,
                conversationID: viewModel.conversation.id,
                metadata: [
                    "reason": "userReadingHistory",
                    "messageCount": "\(viewModel.messages.count)",
                    "isNearBottom": "\(isNearBottom)"
                ]
            )
        }
    }

    private var shouldSuppressBottomProximityUpdates: Bool {
        isInitialPositioningInProgress || isScrollingToBottom || isRestoringOlderMessagesScroll
    }

    private func updateBottomProximity(_ isVisible: Bool) {
        guard didCompleteInitialPositioning, !shouldSuppressBottomProximityUpdates else { return }

        bottomProximityUpdateTask?.cancel()
        bottomProximityUpdateTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !shouldSuppressBottomProximityUpdates else { return }
            applyBottomProximity(isVisible)
        }
    }

    private func applyBottomProximity(_ isVisible: Bool) {
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
        shouldStickToBottom = true
    }

    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        let isLastMessage = message.listIdentity == viewModel.messages.last?.listIdentity

        let row = MessageRow(
            message: message,
            senderName: message.isMine ? nil : viewModel.conversation.title,
            onLongPress: { frame in
                viewModel.openActionMenu(for: message, anchor: frame)
            },
            onRetry: message.canRetrySend ? {
                viewModel.retryFailedMessage(message, session: session, router: router)
            } : nil,
            onReactionTap: { reaction in
                Task {
                    await viewModel.toggleReaction(
                        reaction,
                        on: message,
                        session: session,
                        router: router
                    )
                }
            },
            onImageTap: { attachment in
                photoViewerAttachment = attachment
            },
            replyImageAttachment: replyImageAttachment(for: message),
            onReplyTap: message.replyPreview.map { preview in
                { revealRepliedMessage(preview) }
            }
        )

        Group {
            if isLastMessage {
                row
                    .padding(.bottom, Self.bottomClearance)
                    .onScrollVisibilityChange(threshold: Self.bottomVisibilityThreshold) { isVisible in
                        updateBottomProximity(isVisible)
                    }
            } else {
                row
            }
        }
        .id(message.listIdentity)
        .background {
            if highlightedReplyTargetID == message.listIdentity {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.discoverViolet.opacity(0.14))
                    .padding(.horizontal, -6)
                    .transition(.opacity)
            }
        }
        .scaleEffect(viewModel.actionMenuMessage?.id == message.id ? 1.02 : 1)
        .zIndex(viewModel.actionMenuMessage?.id == message.id ? 10 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: viewModel.actionMenuMessage?.id)
    }

    /// The reply DTO has no attachment metadata, so resolve the quoted message's photo
    /// from the already-loaded message list. Returns nil when the original isn't loaded.
    private func replyImageAttachment(for message: ChatMessage) -> ChatMessageAttachment? {
        guard let preview = message.replyPreview else { return nil }
        return viewModel.messages.first { $0.id == preview.id }?.imageAttachment
    }

    private func revealRepliedMessage(_ preview: ChatReplyPreview) {
        guard let target = viewModel.messages.first(where: { $0.id == preview.id }) else { return }
        let targetID = target.listIdentity

        scrollTo(targetID, anchor: .center, animated: true)

        replyHighlightTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3).delay(0.2)) {
            highlightedReplyTargetID = targetID
        }
        replyHighlightTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                highlightedReplyTargetID = nil
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

    private func loadOlderMessagesHeader() -> some View {
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
            Task { await loadOlderMessagesPreservingScroll() }
        }
        .onScrollVisibilityChange(threshold: 0.4) { isVisible in
            guard !usesPreviewData else { return }
            guard didCompleteInitialPositioning, !isInitialPositioningInProgress else { return }
            olderHeaderVisibilityTask?.cancel()
            olderHeaderVisibilityTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                handleOlderHeaderVisibility(isVisible)
            }
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

    private func handleOlderHeaderVisibility(_ isVisible: Bool) {
        guard !usesPreviewData else { return }
        guard didCompleteInitialPositioning, !isInitialPositioningInProgress else { return }
        guard isVisible else {
            didTriggerOlderLoadForCurrentTopReach = false
            return
        }
        guard viewModel.hasMoreOlderMessages,
              !viewModel.isLoadingOlderMessages,
              !isRestoringOlderMessagesScroll,
              !didTriggerOlderLoadForCurrentTopReach else { return }
        didTriggerOlderLoadForCurrentTopReach = true
        Task { await loadOlderMessagesPreservingScroll() }
    }

    private func loadOlderMessagesPreservingScroll() async {
        olderMessagesScrollAnchorID = viewModel.messages.first?.listIdentity
        isRestoringOlderMessagesScroll = olderMessagesScrollAnchorID != nil
        await viewModel.loadOlderMessages(session: session, router: router)

        if isRestoringOlderMessagesScroll,
           let anchor = olderMessagesScrollAnchorID,
           viewModel.messages.contains(where: { $0.listIdentity == anchor }) {
            isRestoringOlderMessagesScroll = false
            olderMessagesScrollAnchorID = nil
            scrollTo(anchor, anchor: .top, animated: false)
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
                HStack(spacing: 4) {
                    Text("chats.typing")
                        .font(Font.App.caption(weight: .semibold))
                        .foregroundStyle(Color.discoverViolet)
                    TypingDotsView(color: .discoverViolet)
                }
                .transition(.opacity)
            } else if presenceStore.isOnline(profileID: viewModel.conversation.otherParticipantProfileID) {
                Text("chats.online")
                    .font(Font.App.caption(weight: .semibold))
                    .foregroundStyle(Color.discoverOnline)
            } else {
                Text("chats.personal")
                    .font(Font.App.caption())
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOtherParticipantTyping)
        .padding(.horizontal, 20)
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

    private func performInitialPositioningIfNeeded() {
        if usesPreviewData {
            if !didCompleteInitialPositioning {
                didCompleteInitialPositioning = true
                markStuckToBottom()
            }
            return
        }

        guard !didCompleteInitialPositioning else { return }
        guard !isInitialPositioningInProgress else { return }
        guard initialPositioningTask == nil else { return }
        guard !viewModel.isAwaitingInitialMessagePage else {
            logScrollPhase("waitingForMessages", target: nil)
            return
        }
        guard !viewModel.messages.isEmpty else {
            logScrollPhase("waitingForMessages", target: nil)
            return
        }

        let target = viewModel.initialScrollTarget(pushTargetMessageID: targetMessageID)
        logInitialScrollTarget(target)
        isInitialPositioningInProgress = true
        // Every task gets its own generation stamp. This is the only thing allowed to gate
        // whether a given task may mutate the shared `@State` below. Without it: cancelling an
        // in-flight task and immediately starting a replacement races against the cancelled
        // task's own cleanup (its `defer` also resets `initialPositioningTask`/
        // `isInitialPositioningInProgress`, and Swift gives no ordering guarantee between that
        // resumption and the new task's first `await`). If the stale task's cleanup runs after
        // the new task has stored itself, it wipes out the new task's tracking — a later trigger
        // then sees "nothing in progress" and can spawn yet another concurrent task, and in the
        // worst case none of them is left to ever flip `didCompleteInitialPositioning`. That is
        // the exact "chat opens to background only, fixed by a light pull" bug this guards against.
        initialPositioningGeneration += 1
        let myGeneration = initialPositioningGeneration

        MessengerDiagnostics.event(
            .initialPositioningStarted,
            conversationID: viewModel.conversation.id,
            metadata: [
                "messageCount": "\(viewModel.messages.count)",
                "target": initialScrollTargetName(target)
            ]
        )

        initialPositioningTask = Task { @MainActor in
            defer {
                if myGeneration == initialPositioningGeneration {
                    initialPositioningTask = nil
                    isInitialPositioningInProgress = false
                }
            }

            await Task.yield()

            let target = viewModel.initialScrollTarget(pushTargetMessageID: targetMessageID)
            let messageCount = viewModel.messages.count
            let revealsBeforeStabilization = shouldRevealBeforeStabilization(for: target)
            let imagesNearBottom = hasImageMessagesNearBottom()

            for delay in positioningDelays(
                for: target,
                messageCount: messageCount,
                hasImageMessages: imagesNearBottom,
                phase: .preReveal
            ) {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled,
                      myGeneration == initialPositioningGeneration,
                      !viewModel.messages.isEmpty else { return }
                applyInitialScroll(target: target, animated: false)
            }

            guard myGeneration == initialPositioningGeneration else { return }

            if revealsBeforeStabilization {
                completeInitialPositioning(for: target)
            }

            await Task.yield()

            for delay in positioningDelays(
                for: target,
                messageCount: messageCount,
                hasImageMessages: imagesNearBottom,
                phase: .postReveal
            ) {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled,
                      myGeneration == initialPositioningGeneration,
                      !viewModel.messages.isEmpty else { return }
                applyInitialScroll(target: target, animated: false)
            }

            guard myGeneration == initialPositioningGeneration else { return }

            if !revealsBeforeStabilization {
                completeInitialPositioning(for: target)
            }

            if shouldStickToBottom, hasImageMessagesNearBottom() {
                scheduleLayoutStabilizationAfterOpen()
            }

            MessengerDiagnostics.event(
                .initialPositioningCompleted,
                conversationID: viewModel.conversation.id,
                metadata: [
                    "messageCount": "\(viewModel.messages.count)",
                    "target": initialScrollTargetName(target)
                ]
            )
            logScrollPhase("ready", target: target)
        }
    }

    private func completeInitialPositioning(for target: ChatViewModel.InitialScrollTarget) {
        didCompleteInitialPositioning = true
        switch target {
        case .bottom, .lastReadMessage:
            markStuckToBottom()
        case .unreadSeparator, .targetMessage:
            isNearBottom = false
            shouldStickToBottom = false
        }
    }

    private func shouldRevealBeforeStabilization(for target: ChatViewModel.InitialScrollTarget) -> Bool {
        switch target {
        case .bottom, .lastReadMessage:
            // LazyVStack only materializes cells in/near the visible viewport. Reveal first,
            // then run post-reveal scroll passes — otherwise bottom scroll can land on an
            // under-measured content height and the chat opens to empty background.
            return true
        case .unreadSeparator, .targetMessage:
            return false
        }
    }

    private enum InitialPositioningPhase {
        case preReveal
        case postReveal
    }

    private func scheduleLayoutStabilizationAfterOpen() {
        layoutStabilizationTask?.cancel()
        layoutStabilizationTask = Task { @MainActor in
            for delay: UInt64 in [120, 280, 500, 800] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, shouldStickToBottom else { return }
                scrollToBottom(animated: false)
            }
        }
    }

    private func hasImageMessagesNearBottom(limit: Int = 12) -> Bool {
        viewModel.messages.suffix(limit).contains { $0.imageAttachment != nil }
    }

    private func scheduleScrollToLatest(
        animated: Bool,
        delays: [UInt64] = [0],
        force: Bool = false
    ) {
        scrollRequestGeneration += 1
        let requestGeneration = scrollRequestGeneration
        scrollTask?.cancel()
        isScrollingToBottom = true
        scrollTask = Task { @MainActor in
            defer {
                scrollTask = nil
                if isScrollingToBottom, !isNearBottom {
                    isScrollingToBottom = false
                }
            }

            await Task.yield()
            guard !Task.isCancelled, requestGeneration == scrollRequestGeneration else { return }

            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled, requestGeneration == scrollRequestGeneration else { return }
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

                scrollToLatestMessage(animated: animated)
            }

            guard !Task.isCancelled,
                  requestGeneration == scrollRequestGeneration,
                  shouldStickToBottom || force else { return }

            markStuckToBottom()
            MessengerDiagnostics.event(
                .scrollToBottomCompleted,
                conversationID: viewModel.conversation.id,
                metadata: [
                    "messageCount": "\(viewModel.messages.count)",
                    "isNearBottom": "\(isNearBottom)",
                    "force": "\(force)"
                ]
            )
        }
    }

    private func requestScrollToLatestFromButton() {
        MessengerDiagnostics.event(
            .scrollToBottomRequested,
            conversationID: viewModel.conversation.id,
            metadata: [
                "reason": "button",
                "messageCount": "\(viewModel.messages.count)",
                "isNearBottom": "\(isNearBottom)"
            ]
        )
        shouldStickToBottom = true
        scheduleScrollToLatest(animated: true, delays: [0], force: true)
    }

    private func handleKeyboardVisibilityChange() {
        guard !usesPreviewData, didCompleteInitialPositioning else { return }
        guard shouldStickToBottom || isNearBottom else { return }

        keyboardVisibilityScrollTask?.cancel()
        keyboardVisibilityScrollTask = Task { @MainActor in
            // ждём, пока SwiftUI применит новый keyboard-safe-area инсет и
            // пересчитает фрейм VStack, иначе scrollTo сработает по старой геометрии
            for delay: UInt64 in [16, 60, 150] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                scrollToBottom(animated: false)
            }
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    private func logInitialScrollTarget(_ target: ChatViewModel.InitialScrollTarget) {
        NetworkDebug.log("Chat initial scroll target: \(initialScrollTargetName(target))")
        MessengerDiagnostics.event(
            .scrollInitialTargetSelected,
            conversationID: viewModel.conversation.id,
            metadata: [
                "target": initialScrollTargetName(target),
                "messageCount": "\(viewModel.messages.count)",
                "isNearBottom": "\(isNearBottom)"
            ]
        )
    }

    private func logScrollPhase(
        _ phase: String,
        target: ChatViewModel.InitialScrollTarget?
    ) {
        var metadata = [
            "phase": phase,
            "messageCount": "\(viewModel.messages.count)",
            "isLoading": "\(viewModel.isLoading)"
        ]
        if let target {
            metadata["target"] = initialScrollTargetName(target)
        }
        MessengerDiagnostics.event(
            .scrollPhase,
            conversationID: viewModel.conversation.id,
            metadata: metadata
        )
    }

    private func initialScrollTargetName(_ target: ChatViewModel.InitialScrollTarget) -> String {
        switch target {
        case .targetMessage:
            return "pushMessage"
        case .unreadSeparator:
            return "unreadSeparator"
        case .lastReadMessage:
            return "lastReadMessage"
        case .bottom:
            return "bottom"
        }
    }

    private func applyInitialScroll(
        target: ChatViewModel.InitialScrollTarget,
        animated: Bool
    ) {
        switch target {
        case .targetMessage(let messageID):
            scrollToMessage(messageID, anchor: .center, animated: animated)
        case .unreadSeparator:
            scrollTo(Self.unreadSeparatorID, anchor: .center, animated: animated)
        case .lastReadMessage(let messageID):
            scrollToMessage(messageID, anchor: .bottom, animated: animated)
        case .bottom:
            scrollToBottom(animated: animated)
        }
    }

    private func scrollToBottom(animated: Bool) {
        scrollTo(Self.bottomAnchorID, anchor: .bottom, animated: animated)
    }

    private func positioningDelays(
        for target: ChatViewModel.InitialScrollTarget,
        messageCount: Int,
        hasImageMessages: Bool,
        phase: InitialPositioningPhase
    ) -> [UInt64] {
        switch (target, phase) {
        case (.bottom, .preReveal), (.lastReadMessage, .preReveal):
            return [0]
        case (.bottom, .postReveal), (.lastReadMessage, .postReveal):
            return postRevealBottomDelays(messageCount: messageCount, hasImageMessages: hasImageMessages)
        case (.unreadSeparator, .preReveal), (.targetMessage, .preReveal):
            return hasImageMessages ? [0, 100, 250, 500] : [0, 100, 250]
        case (.unreadSeparator, .postReveal), (.targetMessage, .postReveal):
            return hasImageMessages ? [80, 200, 400] : [50, 150, 300]
        }
    }

    private func postRevealBottomDelays(messageCount: Int, hasImageMessages: Bool) -> [UInt64] {
        let scaled = min(320, max(64, UInt64(messageCount) * 6))
        if hasImageMessages {
            return [0, scaled / 4, scaled / 2, scaled, scaled + 140]
        }
        return [0, scaled / 4, scaled / 2, scaled]
    }

    private func scrollToLatestMessage(animated: Bool) {
        scrollToBottom(animated: animated)
    }

    private func scrollToMessage(
        _ messageID: UUID,
        anchor: UnitPoint,
        animated: Bool
    ) {
        let listID = viewModel.messages.first { $0.id == messageID }?.listIdentity ?? messageID.uuidString
        scrollTo(listID, anchor: anchor, animated: animated)
    }

    private func scrollTo<ID: Hashable>(
        _ id: ID,
        anchor: UnitPoint,
        animated: Bool
    ) {
        guard let scrollProxy else {
            MessengerDiagnostics.event(
                .scrollSkipped,
                conversationID: viewModel.conversation.id,
                metadata: [
                    "reason": "missingScrollProxy",
                    "messageCount": "\(viewModel.messages.count)"
                ]
            )
            return
        }
        performScroll(animated: animated) {
            scrollProxy.scrollTo(id, anchor: anchor)
        }
    }

    private func performScroll(animated: Bool, _ action: () -> Void) {
        if animated {
            withAnimation(.easeOut(duration: 0.25), action)
        } else {
            action()
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
