import SwiftUI

struct ChatsView: View {
    @State private var listViewModel: ConversationListViewModel
    @State private var presenceStore = PresenceStore.shared
    @State private var route: ChatRoute?
    @State private var isInviteSheetPresented = false

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private let usesPreviewData: Bool

    private struct ChatRoute: Identifiable, Hashable {
        let conversation: ChatConversationPreview
        var targetMessageID: UUID?
        var id: UUID { conversation.id }
    }

    init(
        viewModel: ConversationListViewModel? = nil,
        previewViewModel: ConversationListViewModel? = nil
    ) {
        _listViewModel = State(initialValue: viewModel ?? previewViewModel ?? ConversationListViewModel.shared)
        usesPreviewData = previewViewModel != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.discoverBackgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationStackHostingBackgroundClear()
            .navigationDestination(item: $route) { route in
                PrivateChatView(
                    conversation: route.conversation,
                    targetMessageID: route.targetMessageID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationStackHostingBackgroundClear()
            }
            .task {
                guard !usesPreviewData else { return }
                await listViewModel.loadIfNeeded(session: session, router: router)
                listViewModel.activateRealtime(session: session, router: router)
            }
            .refreshable {
                guard !usesPreviewData else { return }
                await listViewModel.refresh(session: session, router: router)
                listViewModel.activateRealtime(session: session, router: router)
            }
            .onChange(of: route?.id) { _, newValue in
                guard newValue == nil, !usesPreviewData else { return }
                Task {
                    await listViewModel.refresh(session: session, router: router)
                    listViewModel.activateRealtime(session: session, router: router)
                }
            }
            .onChange(of: router.pendingChatConversation?.id) { _, newValue in
                if newValue != nil {
                    isInviteSheetPresented = false
                }
                guard !usesPreviewData, let conversation = router.pendingChatConversation else { return }
                presentPrivateChat(
                    conversation: conversation,
                    targetMessageID: router.pendingChatMessageID
                )
                router.clearPendingChatNavigation()
            }
            .sheet(isPresented: $isInviteSheetPresented) {
                InviteLinkView()
            }
            .onAppear {
                guard !usesPreviewData else { return }
                listViewModel.activateRealtime(session: session, router: router)

                if let conversation = router.pendingChatConversation {
                    presentPrivateChat(
                        conversation: conversation,
                        targetMessageID: router.pendingChatMessageID
                    )
                    router.clearPendingChatNavigation()
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .background {
            Color.discoverBackgroundGradient
                .ignoresSafeArea()
        }
    }

    private func presentPrivateChat(
        conversation: ChatConversationPreview,
        targetMessageID: UUID? = nil
    ) {
        MessengerDiagnostics.event(
            .navigationRequested,
            conversationID: conversation.id,
            messageID: targetMessageID,
            metadata: [
                "hasTargetMessage": "\(targetMessageID != nil)",
                "unreadCount": "\(conversation.unreadCount)"
            ]
        )
        route = ChatRoute(
            conversation: conversation,
            targetMessageID: targetMessageID
        )
    }

    private var header: some View {
        HStack {
            Text("chats.header")
                .font(Font.App.headline(size: 17, weight: .semibold))
                .foregroundStyle(Color.primaryText)

            Spacer()

            Button {
                isInviteSheetPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.discoverViolet)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("accessibility.create_invite"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.clear
                .overlay(alignment: .bottom) {
                    Divider().overlay(Color.hairline)
                }
        )
    }

    @ViewBuilder
    private var content: some View {
        if listViewModel.isLoading, listViewModel.conversations.isEmpty {
            loadingView
        } else if let errorMessage = listViewModel.errorMessage, listViewModel.conversations.isEmpty {
            errorView(message: errorMessage)
        } else {
            conversationsList
        }
    }

    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(listViewModel.conversations) { conversation in
                    ChatConversationRow(
                        conversation: conversation,
                        isOnline: presenceStore.isOnline(profileID: conversation.otherParticipantProfileID)
                    ) {
                        MessengerDiagnostics.event(
                            .conversationRowTapped,
                            conversationID: conversation.id,
                            metadata: [
                                "unreadCount": "\(conversation.unreadCount)",
                                "hasLastMessage": "\(conversation.lastMessageText != nil)",
                                "isLastMessageOwn": "unknown",
                                "isAppActive": "\(MessengerSessionSupport.isAppForegroundActive)"
                            ]
                        )
                        presentPrivateChat(conversation: conversation)
                    }

                    Divider()
                        .overlay(Color.hairline)
                }

                if listViewModel.conversations.isEmpty {
                    Text("chats.empty")
                        .font(Font.App.subheadline())
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xl)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var loadingView: some View {
        VStack(spacing: AppSpacing.sm) {
            ProgressView()
                .tint(Color.brandPrimary)
            Text("chats.loading")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)

            Text("chats.error.title")
                .font(Font.App.manrope(size: 20, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Font.App.subtitle)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            PrimaryButton("common.retry") {
                Task {
                    await listViewModel.refresh(session: session, router: router)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Chats - Loaded") {
    ChatsView(previewViewModel: .preview(conversations: ChatUIMockData.conversations))
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}

#Preview("Chats - Loading") {
    ChatsView(previewViewModel: .preview(isLoading: true))
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}

#Preview("Chats - Empty") {
    ChatsView(previewViewModel: .preview(conversations: ChatUIMockData.empty))
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}

#Preview("Chats - Error") {
    ChatsView(
        previewViewModel: .preview(
            conversations: ChatUIMockData.empty,
            errorMessage: String(localized: "network.error.no_internet")
        )
    )
    .environment(SessionStore.shared)
    .environment(AppRouter.shared)
}

#Preview("Chats - In Tab Shell") {
    MainTabView()
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
}

#Preview("Chats - Dark") {
    ChatsView(previewViewModel: .preview(conversations: ChatUIMockData.conversations))
        .environment(SessionStore.shared)
        .environment(AppRouter.shared)
        .preferredColorScheme(.dark)
}
