import SwiftUI

struct PrivateChatView: View {
    @State private var viewModel: ChatViewModel

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private let usesPreviewData: Bool

    @State private var bottomChromeHeight: CGFloat = 72

    init(
        conversation: ChatConversationPreview,
        previewViewModel: ChatViewModel? = nil
    ) {
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
                Task {
                    await viewModel.deletePendingMessage(session: session, router: router)
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
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8 + bottomInset)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: bottomInset) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private var chatBackground: some View {
        Color.discoverBackgroundGradient
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(viewModel.conversation.title)
                    .font(Font.App.headline(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primaryText)

                Text("chats.personal")
                    .font(Font.App.caption())
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = viewModel.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
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
