import SwiftUI

struct ChatsView: View {
    @State private var listViewModel: ConversationListViewModel
    @State private var presenceStore = PresenceStore.shared
    @State private var uxStatusStore = MessengerUXStatusStore.shared
    @State private var syncEngine = MessengerSyncEngine.shared
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
                    if let statusText = listStatusText {
                        MessengerSubtleStatusStrip(
                            text: statusText,
                            showsSpinner: isListRefreshing
                        )
                    }
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
                .id(route.id)
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
                MessengerDiagnostics.event(.messengerConversationRefreshForcedManual)
                await listViewModel.refresh(session: session, router: router)
                listViewModel.activateRealtime(session: session, router: router)
            }
            .onChange(of: route?.id) { _, newValue in
                guard newValue == nil, !usesPreviewData else { return }
                MessengerDiagnostics.event(.messengerConversationRefreshSkippedChatPop)
                listViewModel.activateRealtime(session: session, router: router)
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
            .toolbar(route == nil ? .visible : .hidden, for: .tabBar)
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("chats.header")
                    .font(Font.App.manrope(size: 26, weight: .heavy))
                    .foregroundStyle(Color.discoverSelectedGradient)
                    .tracking(-0.5)

                Text(unreadSummaryText)
                    .font(Font.App.manrope(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: listViewModel.totalUnreadCount)
            }

            Spacer()

            inviteButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            Color.clear
                .overlay(alignment: .bottom) {
                    Divider().overlay(Color.hairline)
                }
        )
    }

    private var inviteButton: some View {
        Button {
            isInviteSheetPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.discoverViolet)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.hairline, lineWidth: 1)
                )
                .shadow(color: Color.brandPrimaryGlow.opacity(0.12), radius: 12, x: 0, y: 2)
        }
        .accessibilityLabel(Text("accessibility.create_invite"))
    }

    private var unreadSummaryText: String {
        let count = listViewModel.totalUnreadCount
        guard count > 0 else {
            return String(localized: "chats.header.allRead")
        }
        return String(format: String(localized: "chats.header.unreadCount"), count)
    }

    private var shouldShowOfflineNoChatsEmpty: Bool {
        !usesPreviewData
            && NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline
            && !listViewModel.hasCachedConversations
            && !listViewModel.isLoading
    }

    private var listStatusText: String? {
        guard !usesPreviewData else { return nil }
        return uxStatusStore.chatsListStatusText(listViewModel: listViewModel, session: session)
    }

    private var isListRefreshing: Bool {
        listViewModel.isRefreshingNetwork
            || syncEngine.state == .syncing
            || syncEngine.state == .bootstrapping
    }

    @ViewBuilder
    private var content: some View {
        if listViewModel.isLoading, listViewModel.conversations.isEmpty {
            if shouldShowOfflineNoChatsEmpty {
                offlineNoCacheEmptyState
            } else {
                loadingView
            }
        } else if let errorMessage = listViewModel.errorMessage,
                  listViewModel.conversations.isEmpty,
                  !shouldShowOfflineNoChatsEmpty {
            errorView(message: errorMessage)
        } else {
            conversationsList
        }
    }

    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(listViewModel.conversations) { conversation in
                    ChatConversationRow(
                        conversation: conversation,
                        isOnline: presenceStore.isOnline(profileID: conversation.otherParticipantProfileID),
                        isTyping: false,
                        onDelete: {
                            MessengerDiagnostics.event(
                                .conversationRowTapped,
                                conversationID: conversation.id,
                                metadata: ["action": "deleteSwipe"]
                            )
                        },
                        onMute: {
                            MessengerDiagnostics.event(
                                .conversationRowTapped,
                                conversationID: conversation.id,
                                metadata: ["action": "muteSwipe"]
                            )
                        }
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
                }

                if listViewModel.conversations.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var offlineNoCacheEmptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.warning.opacity(0.7))
                .padding(.bottom, 8)

            Text("chats.empty.offlineNoCache.title")
                .font(Font.App.headline(size: 20, weight: .bold))
                .foregroundStyle(Color.primaryText)

            Text("chats.empty.offlineNoCache.subtitle")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.discoverViolet.opacity(0.5))
                .padding(.bottom, 8)

            Text("chats.empty.title")
                .font(Font.App.headline(size: 20, weight: .bold))
                .foregroundStyle(Color.primaryText)

            Text("chats.empty.subtitle")
                .font(Font.App.subheadline())
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PrimaryButton("chats.empty.cta") {
                router.selectedMainTab = .discover
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
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
