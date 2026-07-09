import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerOfflineUXTests {

    @Test
    func onlineWithCacheMapsToOnline() {
        let context = MessengerUXContext(
            isNetworkOffline: false,
            sessionConnectivity: .online,
            syncEngineState: .idle,
            hasConversationCache: true,
            hasMessageCache: false,
            isListRefreshing: false,
            isChatRefreshing: false,
            lastRefreshFailed: false,
            showingConnectionRestoredRefreshing: false
        )

        #expect(MessengerConnectivityPresentationResolver.resolve(context) == .online)
        #expect(MessengerConnectivityPresentationResolver.globalBanner(for: context) == nil)
    }

    @Test
    func offlineWithCacheMapsToOfflineShowingCache() {
        let context = MessengerUXContext(
            isNetworkOffline: true,
            sessionConnectivity: .offlineUsingCache,
            syncEngineState: .idle,
            hasConversationCache: true,
            hasMessageCache: false,
            isListRefreshing: false,
            isChatRefreshing: false,
            lastRefreshFailed: false,
            showingConnectionRestoredRefreshing: false
        )

        #expect(MessengerConnectivityPresentationResolver.resolve(context) == .offlineShowingCache)
        #expect(MessengerConnectivityPresentationResolver.globalBanner(for: context) == .offlineShowingCache)
    }

    @Test
    func offlineWithoutMessengerCacheMapsToOfflineNoCachePresentation() {
        let context = MessengerUXContext(
            isNetworkOffline: true,
            sessionConnectivity: .online,
            syncEngineState: .idle,
            hasConversationCache: false,
            hasMessageCache: false,
            isListRefreshing: false,
            isChatRefreshing: false,
            lastRefreshFailed: false,
            showingConnectionRestoredRefreshing: false
        )

        #expect(MessengerConnectivityPresentationResolver.resolve(context) == .offlineNoCache)
        #expect(MessengerConnectivityPresentationResolver.globalBanner(for: context) == nil)
    }

    @Test
    func syncRunningWithCacheMapsToRefreshingWithoutHidingCache() {
        let context = MessengerUXContext(
            isNetworkOffline: false,
            sessionConnectivity: .online,
            syncEngineState: .syncing,
            hasConversationCache: true,
            hasMessageCache: true,
            isListRefreshing: false,
            isChatRefreshing: false,
            lastRefreshFailed: false,
            showingConnectionRestoredRefreshing: false
        )

        #expect(MessengerConnectivityPresentationResolver.resolve(context) == .refreshing)
        #expect(MessengerConnectivityPresentationResolver.chatsListStatusKey(for: context) == "messenger.status.refreshing")
    }

    @Test
    func syncFailedWithCacheMapsToRefreshFailedShowingCache() {
        let context = MessengerUXContext(
            isNetworkOffline: false,
            sessionConnectivity: .online,
            syncEngineState: .failed,
            hasConversationCache: true,
            hasMessageCache: true,
            isListRefreshing: false,
            isChatRefreshing: false,
            lastRefreshFailed: true,
            showingConnectionRestoredRefreshing: false
        )

        #expect(MessengerConnectivityPresentationResolver.resolve(context) == .refreshFailedShowingCache)
        #expect(MessengerConnectivityPresentationResolver.globalBanner(for: context) == .refreshFailed)
    }

    @Test
    func connectionRestoredShowsRefreshingBanner() {
        let context = MessengerUXContext(
            isNetworkOffline: false,
            sessionConnectivity: .online,
            syncEngineState: .syncing,
            hasConversationCache: true,
            hasMessageCache: false,
            isListRefreshing: true,
            isChatRefreshing: false,
            lastRefreshFailed: false,
            showingConnectionRestoredRefreshing: true
        )

        #expect(MessengerConnectivityPresentationResolver.globalBanner(for: context) == .connectionRestoredRefreshing)
    }

    @Test
    func offlinePendingTextUsesWillSendWhenOnlineLabel() {
        let label = OutgoingMessageStatus.label(for: .waitingForNetwork, isImage: false, isNetworkOffline: true)
        #expect(label == String(localized: "chats.message.willSendWhenOnline"))
    }

    @Test
    func onlinePendingTextUsesWaitingForNetworkLabel() {
        let label = OutgoingMessageStatus.label(for: .waitingForNetwork, isImage: false, isNetworkOffline: false)
        #expect(label == String(localized: "chats.message.waitingForNetwork"))
    }

    @Test
    func imageUploadingUsesUploadingPhotoLabel() {
        let label = OutgoingMessageStatus.label(for: .uploading, isImage: true)
        #expect(label == String(localized: "chats.message.uploadingPhoto"))
    }

    @Test
    func failedOutgoingUsesTapToRetryLabel() {
        let label = OutgoingMessageStatus.label(for: .failed, isImage: false)
        #expect(label == String(localized: "chats.message.sendFailed"))
    }

    @Test
    func confirmedMessageHasNoPendingControls() {
        #expect(MessageLocalSendState.sending.isRetryable == false)
        #expect(MessageLocalSendState.failed.isRetryable == true)
    }

    @Test
    func offlineManualRefreshPreservesConversationCache() async {
        let preview = ChatUIMockData.conversations.first!
        let viewModel = ConversationListViewModel.preview(conversations: [preview])
        let session = SessionStore.shared
        session.applyStartupSnapshot(makeSnapshot())

        #if DEBUG
        NetworkPathMonitor.testingForceOffline = true
        defer { NetworkPathMonitor.testingForceOffline = nil }
        #endif

        await viewModel.refreshNetwork(session: session, router: AppRouter.shared)

        #expect(viewModel.conversations.count == 1)
        #expect(viewModel.lastRefreshSkippedOffline == true)
    }

    @Test
    func diagnosticsSummaryContainsCountsAndStates() {
        let summary = MessengerDiagnostics.exportSummaryHeader()

        #expect(summary.contains("messengerSummary=offlineUX"))
        #expect(summary.contains("syncEngineState="))
        #expect(summary.contains("outboxPendingCount="))
        #expect(summary.contains("conversationCacheAvailable="))
    }

    @Test
    func diagnosticsSummaryDoesNotLeakSensitiveContent() async {
        MessengerDiagnostics.event(
            .outboxItemCreated,
            metadata: [
                "body": "secret body",
                "caption": "secret caption",
                "authorization": "Bearer secret",
                "downloadUrl": "https://example.com/file?X-Amz-Signature=abc"
            ]
        )

        let export = await MessengerDiagnostics.exportTextForClipboard()
        let lowercased = export.lowercased()

        #expect(!lowercased.contains("secret body"))
        #expect(!lowercased.contains("secret caption"))
        #expect(!lowercased.contains("bearer"))
        #expect(!lowercased.contains("x-amz-signature"))
    }

    private func makeSnapshot() -> StartupSessionSnapshot {
        StartupSessionSnapshotMapping.snapshot(
            user: UserResponse(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                email: "user@example.com",
                emailVerified: true
            ),
            profile: UserProfileDTO(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                displayName: "Test User",
                birthDate: "1990-01-01",
                gender: "woman",
                moodModeEnabled: true,
                activityModeEnabled: true
            )
        )
    }
}
