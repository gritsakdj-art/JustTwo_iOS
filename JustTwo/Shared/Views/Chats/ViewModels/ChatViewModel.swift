import Foundation
import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ChatViewModel {

    let conversation: ChatConversationPreview
    let initialUnreadCount: Int

    private(set) var messages: [ChatMessage] = []
    var draftText = "" {
        didSet {
            guard draftText != oldValue else { return }
            handleDraftTextChange(draftText)
        }
    }
    private(set) var isLoading = false
    private(set) var isLoadingOlderMessages = false
    private(set) var hasMoreOlderMessages = false
    private(set) var isSending = false
    private(set) var isPreparingImage = false
    #if canImport(UIKit)
    private(set) var composerPreviewImage: UIImage?
    #endif
    private var composerPhotoItem: PhotosPickerItem?
    var hasComposerImagePreview: Bool { composerPhotoItem != nil }
    private(set) var typingProfileIDs: Set<UUID> = []
    var errorMessage: String?

    var actionMenuMessage: ChatMessage?
    var actionMenuAnchor: CGRect = .zero
    var pendingDeleteMessage: ChatMessage?
    var replyTarget: ChatMessage?
    var editingMessage: ChatMessage?

    private var currentProfileID: UUID?
    private var didOpen = false
    private var isOpen = false
    private var isRealtimeActive = false
    private var lifecycleGeneration = 0
    private var messageContentGeneration = 0
    private var messageLoadGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var typingTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var cacheNotificationObserver: NSObjectProtocol?
    private let typingEmitter: ChatTypingEmitter
    private let typingTimeout: TimeInterval = 5
    private let deliveryAckCoordinator: ConversationDeliveryAckCoordinator

    private var messageCache: MessageCacheStore { MessageCacheStore.shared }

    init(
        conversation: ChatConversationPreview,
        deliveryAckCoordinator: ConversationDeliveryAckCoordinator
    ) {
        self.conversation = conversation
        self.initialUnreadCount = conversation.unreadCount
        self.typingEmitter = ChatTypingEmitter(conversationID: conversation.id)
        self.deliveryAckCoordinator = deliveryAckCoordinator
        hydrateFromMessageCacheIfAvailable()
        subscribeToCacheNotifications()
    }

    deinit {
        if let cacheNotificationObserver {
            NotificationCenter.default.removeObserver(cacheNotificationObserver)
        }
    }

    /// `true` only while the first page is still loading and nothing is available to render yet.
    var isAwaitingInitialMessagePage: Bool {
        isLoading && messages.isEmpty
    }

    convenience init(conversation: ChatConversationPreview) {
        self.init(conversation: conversation, deliveryAckCoordinator: .shared)
    }

    var isOtherParticipantTyping: Bool {
        guard let currentProfileID else {
            return !typingProfileIDs.isEmpty
        }
        return typingProfileIDs.contains { $0 != currentProfileID }
    }

    static func preview(
        conversation: ChatConversationPreview,
        messages: [ChatMessage],
        typingProfileIDs: Set<UUID> = []
    ) -> ChatViewModel {
        let viewModel = ChatViewModel(conversation: conversation)
        viewModel.messages = messages
        viewModel.typingProfileIDs = typingProfileIDs
        viewModel.didOpen = true
        MessageCacheStore.shared.setMessages(messages, for: conversation.id)
        return viewModel
    }

    static func preview(conversation: ChatConversationPreview) -> ChatViewModel {
        preview(
            conversation: conversation,
            messages: ChatUIMockData.messages(for: ChatUIMockData.conversations[0].id)
        )
    }

    var composeMode: MessageInputComposeMode? {
        if editingMessage != nil {
            return .edit
        }
        if let replyTarget {
            let author = replyTarget.isMine
                ? String(localized: "chats.you")
                : conversation.title
            let preview = replyTarget.rawBody ?? replyTarget.displayText
            return .reply(authorName: author, preview: preview)
        }
        return nil
    }

    var firstUnreadMessageID: UUID? {
        guard initialUnreadCount > 0, !messages.isEmpty else { return nil }
        let index = max(0, messages.count - initialUnreadCount)
        guard messages.indices.contains(index) else { return nil }
        return messages[index].id
    }

    var lastReadMessageIDForInitialScroll: UUID? {
        guard initialUnreadCount > 0, !messages.isEmpty else { return nil }
        let firstUnreadIndex = max(0, messages.count - initialUnreadCount)
        let lastReadIndex = firstUnreadIndex - 1
        guard messages.indices.contains(lastReadIndex) else { return nil }
        return messages[lastReadIndex].id
    }

    var lastReadVisibilityMessageID: UUID? {
        if let lastReadMessageID = lastReadMessageIDForInitialScroll {
            return lastReadMessageID
        }
        return messages.last?.id
    }

    enum InitialScrollTarget: Equatable {
        case targetMessage(UUID)
        case unreadSeparator
        case lastReadMessage(UUID)
        case bottom
    }

    func initialScrollTarget(pushTargetMessageID: UUID?) -> InitialScrollTarget {
        if let pushTargetMessageID,
           messages.contains(where: { $0.id == pushTargetMessageID }) {
            return .targetMessage(pushTargetMessageID)
        }
        if firstUnreadMessageID != nil {
            return .unreadSeparator
        }
        return .bottom
    }

    static func isMessageVisibleInViewport(
        frame: CGRect,
        viewportHeight: CGFloat,
        tolerance: CGFloat = 2
    ) -> Bool {
        guard viewportHeight > 0 else { return true }
        return frame.maxY > tolerance && frame.minY < viewportHeight - tolerance
    }

    func open(session: SessionStore, router: AppRouter) async {
        isOpen = true
        let generation = lifecycleGeneration
        // Re-subscribe defensively: `close()` tears the observer down, and the same
        // ChatViewModel instance can be reopened (e.g. tab switch, backgrounded app) without
        // being recreated, so `open()` must guarantee we're listening again before any load
        // starts — otherwise a concurrently-completing fetch could finish without us noticing.
        subscribeToCacheNotifications()
        MessengerDiagnostics.event(
            .chatOpenStarted,
            conversationID: conversation.id,
            metadata: lifecycleMetadata(generation: generation)
        )

        if !didOpen {
            await loadMessages(
                session: session,
                router: router,
                generation: generation,
                isInitialLoad: true,
                loadReason: .open
            )
            guard generation == lifecycleGeneration, isOpen else {
                MessengerDiagnostics.event(
                    .chatInitialLoadIgnoredStaleGeneration,
                    conversationID: conversation.id,
                    metadata: lifecycleMetadata(generation: generation)
                )
                return
            }
            didOpen = true
        } else {
            await hydrateFromLocalMessageCacheIfNeeded(
                session: session,
                generation: generation,
                limit: MessengerLimits.defaultMessagePageSize
            )
            syncMessagesFromCache()
            syncPaginationStateFromCache()
        }

        markDeliveredAndReadInBackground(session: session, router: router)

        Task {
            await MessengerDeltaSyncService.shared.syncDeltas(
                reason: .chatOpened,
                session: session,
                router: router
            )
        }

        Task {
            if let profileID = try? await MessengerSessionSupport.resolveCurrentProfileID(session: session) {
                await MessengerOutboxProcessor.shared.reconcileConversation(
                    conversationID: conversation.id,
                    currentProfileID: profileID,
                    session: session,
                    router: router
                )
                guard generation == lifecycleGeneration, isOpen else { return }
                syncMessagesFromCache()
            }
        }

        MessengerDiagnostics.event(
            .chatOpenCompleted,
            conversationID: conversation.id,
            metadata: lifecycleMetadata(generation: generation)
        )
    }

    func activateRealtime(session: SessionStore, router: AppRouter) {
        guard !isRealtimeActive else { return }
        isRealtimeActive = true
        MessengerRealtimeCoordinator.shared.activateChat(self, session: session, router: router)
    }

    func deactivateRealtime() {
        guard isRealtimeActive else { return }
        isRealtimeActive = false
        stopTyping()
        MessengerRealtimeCoordinator.shared.deactivateChat(self)
    }

    func close() {
        MessengerDiagnostics.event(
            .chatCloseStarted,
            conversationID: conversation.id,
            metadata: lifecycleMetadata(generation: lifecycleGeneration)
        )
        lifecycleGeneration += 1
        messageContentGeneration += 1
        messageLoadGeneration += 1
        isOpen = false
        isLoading = false
        loadTask?.cancel()
        loadTask = nil
        messageCache.cancelLoad(for: conversation.id)
        unsubscribeFromCacheNotifications()
        clearTypingState()
        deactivateRealtime()
        MessengerDiagnostics.event(
            .chatCloseCompleted,
            conversationID: conversation.id,
            metadata: lifecycleMetadata(generation: lifecycleGeneration)
        )
    }

    func stopTyping() {
        typingEmitter.chatClosed()
        clearTypingState()
    }

    func clearTypingState() {
        typingProfileIDs.removeAll()
        for task in typingTimeoutTasks.values {
            task.cancel()
        }
        typingTimeoutTasks.removeAll()
    }

    func applyTypingStarted(profileID: UUID) {
        typingProfileIDs.insert(profileID)
        scheduleTypingTimeout(for: profileID)
    }

    func applyTypingStopped(profileID: UUID) {
        typingProfileIDs.remove(profileID)
        typingTimeoutTasks[profileID]?.cancel()
        typingTimeoutTasks.removeValue(forKey: profileID)
    }

    private func handleDraftTextChange(_ text: String) {
        typingEmitter.textDidChange(text)
    }

    private func scheduleTypingTimeout(for profileID: UUID) {
        typingTimeoutTasks[profileID]?.cancel()
        typingTimeoutTasks[profileID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.typingTimeout ?? 5))
            guard !Task.isCancelled else { return }
            self?.applyTypingStopped(profileID: profileID)
        }
    }

    private func clearTyping(for profileID: UUID) {
        applyTypingStopped(profileID: profileID)
    }

    func reload(session: SessionStore, router: AppRouter) async {
        lifecycleGeneration += 1
        messageLoadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        messageCache.cancelLoad(for: conversation.id)
        let generation = lifecycleGeneration
        await loadMessages(
            session: session,
            router: router,
            generation: generation,
            loadReason: .manualRefresh
        )
    }

    func loadOlderMessages(session: SessionStore, router: AppRouter) async {
        guard hasMoreOlderMessages, !isLoadingOlderMessages else { return }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        let didLoad = await messageCache.loadOlderMessages(
            conversationID: conversation.id,
            session: session,
            router: router,
            loadGeneration: messageLoadGeneration
        )
        syncMessagesFromCache()
        syncPaginationStateFromCache()
        NetworkDebug.log("Chat older messages load finished didLoad=\(didLoad) count=\(messages.count) hasMore=\(hasMoreOlderMessages)")
    }

    func refreshFromRealtime(session: SessionStore, router: AppRouter) async {
        guard isOpen else { return }
        let generation = lifecycleGeneration
        await loadMessages(
            session: session,
            router: router,
            generation: generation,
            loadReason: .reconnectRepair
        )
        guard generation == lifecycleGeneration, isOpen else { return }
        markDeliveredAndReadInBackground(session: session, router: router)
    }

    func openActionMenu(for message: ChatMessage, anchor: CGRect) {
        #if canImport(UIKit)
        HapticFeedback.impact(.medium)
        #endif
        actionMenuAnchor = anchor
        actionMenuMessage = message
    }

    func dismissActionMenu() {
        actionMenuMessage = nil
        actionMenuAnchor = .zero
    }

    func startReply(to message: ChatMessage) {
        replyTarget = message
        editingMessage = nil
        dismissActionMenu()
    }

    func startEdit(message: ChatMessage) {
        editingMessage = message
        replyTarget = nil
        draftText = message.rawBody ?? ""
        dismissActionMenu()
    }

    func cancelCompose() {
        let wasEditing = editingMessage != nil
        replyTarget = nil
        editingMessage = nil
        if wasEditing {
            draftText = ""
        }
    }

    private func currentReplyPreview() -> ChatReplyPreview? {
        guard let activeReplyTarget = replyTarget else { return nil }
        // Always quote the target itself. Reusing the target's own replyPreview here
        // would point the quote at the target's original instead of the target.
        return ChatReplyPreview(
            id: activeReplyTarget.id,
            body: activeReplyTarget.rawBody ?? activeReplyTarget.displayText,
            isDeleted: activeReplyTarget.isDeleted
        )
    }

    func copyMessage(_ message: ChatMessage) {
        #if canImport(UIKit)
        UIPasteboard.general.string = message.rawBody
        #endif
        dismissActionMenu()
    }

    func requestDelete(_ message: ChatMessage) {
        dismissActionMenu()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            pendingDeleteMessage = message
        }
    }

    var blocksComposeSend: Bool {
        isSending || isPreparingImage
    }

    @discardableResult
    func syncMessagesFromCache() -> Bool {
        guard let cached = messageCache.messages(for: conversation.id) else { return false }
        guard cached != messages else { return false }
        messages = cached
        return true
    }

    /// Listens for cache updates that this ChatViewModel didn't itself trigger (e.g. a load that
    /// was already in-flight when `open()` ran, or a startup preload that finished afterward).
    /// Without this, a currently active chat can be left showing an empty/stale list until an
    /// unrelated action (like pull-to-refresh) happens to force a resync from cache.
    private func subscribeToCacheNotifications() {
        guard cacheNotificationObserver == nil else { return }
        let conversationID = conversation.id
        // `queue: nil` delivers synchronously on the posting thread. Every poster
        // (MessageCacheStore, MessengerOutbox) is already MainActor-isolated, so this always
        // runs on the main actor without an extra run-loop hop — no window where a completed
        // load's result can be "missed" between posting and delivery.
        cacheNotificationObserver = NotificationCenter.default.addObserver(
            forName: .messengerConversationMessagesDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let notifiedConversationID = notification.userInfo?[MessengerConversationNotification.conversationIDKey] as? UUID,
                  notifiedConversationID == conversationID else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleCacheNotification()
            }
        }
    }

    private func unsubscribeFromCacheNotifications() {
        guard let cacheNotificationObserver else { return }
        NotificationCenter.default.removeObserver(cacheNotificationObserver)
        self.cacheNotificationObserver = nil
    }

    private func handleCacheNotification() {
        let countBefore = messages.count
        let didChangeMessages = syncMessagesFromCache()
        syncPaginationStateFromCache()
        MessengerDiagnostics.event(
            .chatCacheNotificationReceived,
            conversationID: conversation.id,
            metadata: [
                "messageCountBefore": "\(countBefore)",
                "messageCountAfter": "\(messages.count)",
                "didChangeMessages": "\(didChangeMessages)"
            ]
        )
    }

    func retryFailedMessage(_ message: ChatMessage, session: SessionStore, router: AppRouter) {
        guard let clientMessageID = message.clientMessageID, message.canRetrySend else { return }
        Task {
            await MessengerOutboxProcessor.shared.manualRetry(
                clientMessageID: clientMessageID,
                session: session,
                router: router
            )
            syncMessagesFromCache()
        }
    }

    func send(session: SessionStore, router: AppRouter) {
        if composerPhotoItem != nil {
            sendComposerImage(session: session, router: router)
            return
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.count <= MessengerLimits.maxMessageLength else {
            errorMessage = String(localized: "chats.error.message_too_long")
            return
        }

        if let editingMessage {
            sendEdit(
                editingMessage,
                body: trimmed,
                session: session,
                router: router
            )
            return
        }

        let activeReplyTarget = replyTarget
        let clientMessageID = UUID().uuidString
        let replyPreview = currentReplyPreview()

        draftText = ""
        replyTarget = nil
        errorMessage = nil
        typingEmitter.messageSent()

        Task {
            do {
                let snapshot = try await MessengerLocalStore.shared.createTextOutboxItem(
                    conversationID: conversation.id,
                    clientMessageID: clientMessageID,
                    body: trimmed,
                    replyToMessageID: activeReplyTarget?.id
                )

                MessengerDiagnostics.event(
                    .outboxItemCreated,
                    conversationID: conversation.id,
                    clientMessageID: snapshot.clientMessageID,
                    metadata: ["kind": "text", "status": snapshot.status.rawValue]
                )

                let optimistic = ChatMessage.optimisticOutgoing(
                    clientMessageID: snapshot.clientMessageID,
                    body: snapshot.body,
                    replyPreview: replyPreview,
                    createdAt: snapshot.createdAt
                )

                messageCache.insertOptimisticMessage(optimistic, for: conversation.id)
                syncMessagesFromCache()

                MessengerDiagnostics.event(
                    .sendStarted,
                    conversationID: conversation.id,
                    clientMessageID: snapshot.clientMessageID,
                    metadata: [
                        "draftCleared": "true",
                        "hasReply": "\(activeReplyTarget != nil)",
                        "optimistic": "true"
                    ]
                )

                ConversationListViewModel.shared.applyOptimisticOutgoing(
                    conversationID: conversation.id,
                    previewText: snapshot.body,
                    sentAt: optimistic.createdAt
                )

                MessengerOutbox.shared.registerPersistedTextEntry(
                    snapshot: snapshot,
                    localMessageID: optimistic.id,
                    session: session,
                    router: router
                )
            } catch {
                draftText = trimmed
                if activeReplyTarget != nil {
                    replyTarget = activeReplyTarget
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                MessengerDiagnostics.event(
                    .sendFailed,
                    conversationID: conversation.id,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
                )
            }
        }
    }


    func selectComposerPhoto(from item: PhotosPickerItem) async {
        guard editingMessage == nil else { return }
        guard !isPreparingImage else { return }

        isPreparingImage = true
        defer { isPreparingImage = false }

        do {
            #if canImport(UIKit)
            composerPreviewImage = try await ChatImagePreparer.loadPreviewImage(from: item)
            #endif
            composerPhotoItem = item
            MessengerDiagnostics.event(
                .outboxImageComposerPreviewSelected,
                conversationID: conversation.id
            )
        } catch {
            composerPhotoItem = nil
            #if canImport(UIKit)
            composerPreviewImage = nil
            #endif
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "chats.image.error.prepare_failed")
            MessengerDiagnostics.event(
                .imagePrepareFailed,
                conversationID: conversation.id,
                metadata: ["reason": "composerPreview", "errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
        }
    }

    func removeComposerImagePreview() {
        composerPhotoItem = nil
        #if canImport(UIKit)
        composerPreviewImage = nil
        #endif
        MessengerDiagnostics.event(
            .outboxImageComposerPreviewRemoved,
            conversationID: conversation.id
        )
    }

    private func sendComposerImage(session: SessionStore, router: AppRouter) {
        guard let item = composerPhotoItem else { return }
        guard editingMessage == nil else { return }
        guard !isPreparingImage else { return }

        let caption = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCaption = caption.isEmpty ? nil : caption
        let activeReplyTarget = replyTarget
        let replyPreview = currentReplyPreview()
        let clientMessageID = UUID().uuidString
        let pendingMediaID = UUID().uuidString

        isPreparingImage = true

        Task {
            defer { isPreparingImage = false }

            do {
                let prepared = try await ChatImagePreparer.preparePersistent(
                    item,
                    clientMessageID: clientMessageID,
                    pendingMediaID: pendingMediaID
                )
                let relativePath = try MessengerPendingMediaStore.makeRelativePath(
                    pendingMediaID: pendingMediaID,
                    clientMessageID: clientMessageID
                )

                let snapshot = try await MessengerLocalStore.shared.createImageOutboxItem(
                    conversationID: conversation.id,
                    clientMessageID: clientMessageID,
                    caption: normalizedCaption,
                    replyToMessageID: activeReplyTarget?.id,
                    pendingMediaID: pendingMediaID,
                    localRelativePath: relativePath,
                    contentType: prepared.contentType,
                    byteSize: prepared.byteSize,
                    width: prepared.width,
                    height: prepared.height
                )

                MessengerDiagnostics.event(
                    .outboxImageItemCreated,
                    conversationID: conversation.id,
                    clientMessageID: snapshot.clientMessageID,
                    metadata: [
                        "pendingMediaID": MessengerPendingMediaStore.sanitizedPendingMediaIDForDiagnostics(pendingMediaID),
                        "byteSize": "\(prepared.byteSize)",
                        "contentType": prepared.contentType,
                        "optionalNotePresent": normalizedCaption == nil ? "false" : "true"
                    ]
                )
                MessengerDiagnostics.event(
                    .outboxPendingMediaStored,
                    conversationID: conversation.id,
                    clientMessageID: snapshot.clientMessageID,
                    metadata: [
                        "pendingMediaID": MessengerPendingMediaStore.sanitizedPendingMediaIDForDiagnostics(pendingMediaID),
                        "byteSize": "\(prepared.byteSize)",
                        "width": "\(prepared.width)",
                        "height": "\(prepared.height)"
                    ]
                )

                let optimistic = ChatMessage.optimisticOutgoingImage(
                    clientMessageID: snapshot.clientMessageID,
                    prepared: prepared,
                    replyPreview: replyPreview,
                    caption: normalizedCaption,
                    createdAt: snapshot.createdAt
                )

                messageCache.insertOptimisticMessage(optimistic, for: conversation.id)
                syncMessagesFromCache()

                draftText = ""
                replyTarget = nil
                composerPhotoItem = nil
                #if canImport(UIKit)
                composerPreviewImage = nil
                #endif
                errorMessage = nil
                typingEmitter.messageSent()

                let previewText = normalizedCaption ?? ChatUIMapping.imageMessagePreviewText
                ConversationListViewModel.shared.applyOptimisticOutgoing(
                    conversationID: conversation.id,
                    previewText: previewText,
                    sentAt: optimistic.createdAt
                )

                MessengerOutbox.shared.registerPersistedImageEntry(
                    snapshot: snapshot,
                    prepared: prepared,
                    localMessageID: optimistic.id,
                    session: session,
                    router: router
                )
            } catch {
                if let relativePath = try? MessengerPendingMediaStore.makeRelativePath(
                    pendingMediaID: pendingMediaID,
                    clientMessageID: clientMessageID
                ) {
                    MessengerPendingMediaStore.delete(relativePath: relativePath)
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                MessengerDiagnostics.event(
                    .outboxImageItemCreated,
                    conversationID: conversation.id,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
                )
            }
        }
    }

    #if canImport(UIKit)
    var composerPreviewSwiftUIImage: Image? {
        guard let composerPreviewImage else { return nil }
        return Image(uiImage: composerPreviewImage)
    }
    #endif

    private func sendEdit(
        _ editingMessage: ChatMessage,
        body trimmed: String,
        session: SessionStore,
        router: AppRouter
    ) {
        guard !isSending, sendTask == nil else {
            MessengerDiagnostics.event(
                .sendSkippedAlreadySending,
                conversationID: conversation.id,
                metadata: [
                    "isSendingBefore": "\(isSending)",
                    "hasSendTask": "\(sendTask != nil)",
                    "isEditing": "true"
                ]
            )
            return
        }

        let originalDraftText = draftText
        isSending = true
        errorMessage = nil
        draftText = ""

        sendTask = Task { @MainActor [weak self] in
            await self?.performEditSend(
                editingMessage: editingMessage,
                body: trimmed,
                originalDraftText: originalDraftText,
                session: session,
                router: router
            )
        }
    }

    private func performEditSend(
        editingMessage: ChatMessage,
        body trimmed: String,
        originalDraftText: String,
        session: SessionStore,
        router: AppRouter
    ) async {
        let startedAt = Date()
        defer {
            isSending = false
            sendTask = nil
            MessengerDiagnostics.event(
                .isSendingReset,
                conversationID: conversation.id
            )
        }

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let dto = try await MessageService.editMessage(messageID: editingMessage.id, body: trimmed)
            if self.editingMessage?.id == editingMessage.id {
                self.editingMessage = nil
            }
            let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
            appendOrReplace(mapped)
            Task {
                await MessengerMessageCacheService.persistDeltaMessage(dto, eventType: "message.edited")
            }
            MessengerDiagnostics.event(
                .sendSucceeded,
                conversationID: conversation.id,
                messageID: mapped.id,
                metadata: [
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "isEditing": "true"
                ]
            )
        } catch let error as NetworkError {
            if draftText.isEmpty {
                draftText = originalDraftText
            }
            if self.editingMessage == nil {
                self.editingMessage = editingMessage
            }
            MessengerDiagnostics.event(
                .sendFailed,
                conversationID: conversation.id,
                metadata: [
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "isEditing": "true"
                ]
            )
            if error.isUserBlocked {
                errorMessage = String(localized: "chats.error.user_blocked")
            } else if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            if draftText.isEmpty {
                draftText = originalDraftText
            }
            if self.editingMessage == nil {
                self.editingMessage = editingMessage
            }
            MessengerDiagnostics.event(
                MessengerDiagnostics.sanitizeError(error) == "cancelled" ? .sendCancelled : .sendFailed,
                conversationID: conversation.id,
                metadata: [
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "isEditing": "true"
                ]
            )
            errorMessage = error.localizedDescription
        }
    }

    func deletePendingMessage(session: SessionStore, router: AppRouter) async {
        guard let message = pendingDeleteMessage else { return }
        pendingDeleteMessage = nil
        await deleteConfirmedMessage(message, session: session, router: router)
    }

    func deleteConfirmedMessage(
        _ message: ChatMessage?,
        session: SessionStore,
        router: AppRouter
    ) async {
        guard let message else { return }
        await deleteMessage(message, session: session, router: router)
    }

    func applyReaction(
        _ emoji: String,
        to message: ChatMessage,
        session: SessionStore,
        router: AppRouter
    ) async {
        dismissActionMenu()

        let rawEmoji = ReactionEmoji.normalized(emoji)

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let existing = message.reactions.first {
                ReactionEmoji.normalized($0.emoji) == rawEmoji
            }
            let dto: MessageDTO
            if existing?.reactedByMe == true {
                dto = try await MessageService.removeReaction(messageID: message.id, emoji: rawEmoji)
            } else {
                dto = try await MessageService.addReaction(messageID: message.id, emoji: rawEmoji)
            }

            let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
            appendOrReplace(mapped)
        } catch let error as NetworkError {
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleReaction(
        _ reaction: ChatMessageReaction,
        on message: ChatMessage,
        session: SessionStore,
        router: AppRouter
    ) async {
        await applyReaction(reaction.displayEmoji, to: message, session: session, router: router)
    }

    private func deleteMessage(
        _ message: ChatMessage,
        session: SessionStore,
        router: AppRouter
    ) async {
        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let dto = try await MessageService.deleteMessage(messageID: message.id)
            let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
            appendOrReplace(mapped)
            Task {
                await MessengerMessageCacheService.persistDeltaMessage(dto, eventType: "message.deleted")
            }

            if editingMessage?.id == message.id {
                cancelCompose()
                draftText = ""
            }
            if replyTarget?.id == message.id {
                cancelCompose()
            }
        } catch let error as NetworkError {
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markDeliveredAndReadInBackground(session: SessionStore, router: AppRouter) {
        Task { [weak self] in
            guard let self else { return }
            MessengerDiagnostics.event(
                .messengerDeliveryAckScheduled,
                conversationID: self.conversation.id,
                metadata: ["source": "chatOpen"]
            )
            MessengerDiagnostics.event(
                .messengerReadAckScheduled,
                conversationID: self.conversation.id,
                metadata: ["source": "chatOpen"]
            )
            await self.markDelivered(session: session, router: router)
            await self.markRead(session: session, router: router)
        }
    }

    private func loadMessages(
        session: SessionStore,
        router: AppRouter,
        generation: Int,
        isInitialLoad: Bool = false,
        loadReason: MessageLoadReason = .open
    ) async {
        let startedAt = Date()
        let cachedCountBefore = messageCache.messages(for: conversation.id)?.count ?? 0
        let networkLoadGeneration = messageLoadGeneration
        let contentGenerationAtStart = messageContentGeneration
        MessengerDiagnostics.event(
            .loadMessagesStarted,
            conversationID: conversation.id,
            metadata: [
                "generation": "\(generation)",
                "cachedCountBefore": "\(cachedCountBefore)",
                "isOpen": "\(isOpen)"
            ]
        )
        if isInitialLoad {
            MessengerDiagnostics.event(
                .chatInitialLoadRequested,
                conversationID: conversation.id,
                metadata: [
                    "generation": "\(generation)",
                    "cachedCountBefore": "\(cachedCountBefore)"
                ]
            )
        }
        defer {
            if generation == lifecycleGeneration {
                isLoading = false
            }
        }

        var showedCachedMessages = applyInMemoryMessageCacheIfAvailable(isInitialLoad: isInitialLoad)
        errorMessage = nil

        if !showedCachedMessages, let profileID = session.currentProfile?.id {
            currentProfileID = profileID
            await hydrateFromLocalMessageCacheIfNeeded(
                profileID: profileID,
                generation: generation,
                contentGenerationAtStart: contentGenerationAtStart,
                limit: MessengerLimits.defaultMessagePageSize
            )
            if let hydrated = messageCache.messages(for: conversation.id), !hydrated.isEmpty {
                messages = hydrated
                syncPaginationStateFromCache()
                showedCachedMessages = true
                MessengerDiagnostics.event(
                    .messengerMessageCacheHydratedUI,
                    conversationID: conversation.id,
                    metadata: [
                        "count": "\(hydrated.count)",
                        "source": "localDBBeforeNetwork"
                    ]
                )
            }
        }

        isLoading = !showedCachedMessages

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            guard generation == lifecycleGeneration, isOpen else {
                MessengerDiagnostics.event(
                    .loadMessagesIgnoredStaleGeneration,
                    conversationID: conversation.id,
                    metadata: [
                        "generation": "\(generation)",
                        "currentGeneration": "\(lifecycleGeneration)",
                        "isOpen": "\(isOpen)"
                    ]
                )
                return
            }
            currentProfileID = profileID

            if !showedCachedMessages {
                await hydrateFromLocalMessageCacheIfNeeded(
                    profileID: profileID,
                    generation: generation,
                    contentGenerationAtStart: contentGenerationAtStart,
                    limit: MessengerLimits.defaultMessagePageSize
                )
                if let hydrated = messageCache.messages(for: conversation.id), !hydrated.isEmpty {
                    messages = hydrated
                    syncPaginationStateFromCache()
                    showedCachedMessages = true
                    isLoading = false
                }
            }

            if isInitialLoad, loadReason == .manualRefresh {
                messageCache.cancelLoad(for: conversation.id)
                loadTask?.cancel()
                loadTask = nil
            }

            let refreshTask = startNetworkMessageRefresh(
                session: session,
                router: router,
                networkLoadGeneration: networkLoadGeneration,
                isInitialLoad: isInitialLoad,
                cachedCountBefore: cachedCountBefore,
                generation: generation,
                loadReason: loadReason
            )

            if showedCachedMessages {
                if let refreshTask {
                    Task { @MainActor [weak self] in
                        await refreshTask.value
                        guard let self,
                              generation == self.lifecycleGeneration,
                              self.isOpen else { return }
                        self.applyNetworkRefreshResult(
                            generation: generation,
                            networkLoadGeneration: networkLoadGeneration,
                            showedCachedMessages: true,
                            startedAt: startedAt,
                            cachedCountBefore: cachedCountBefore,
                            isInitialLoad: isInitialLoad
                        )
                    }
                }
                return
            }

            await refreshTask?.value
            if generation == lifecycleGeneration {
                loadTask = nil
            }
            guard generation == lifecycleGeneration, isOpen else {
                MessengerDiagnostics.event(
                    .loadMessagesIgnoredStaleGeneration,
                    conversationID: conversation.id,
                    metadata: [
                        "generation": "\(generation)",
                        "currentGeneration": "\(lifecycleGeneration)",
                        "isOpen": "\(isOpen)"
                    ]
                )
                return
            }

            applyNetworkRefreshResult(
                generation: generation,
                networkLoadGeneration: networkLoadGeneration,
                showedCachedMessages: showedCachedMessages,
                startedAt: startedAt,
                cachedCountBefore: cachedCountBefore,
                isInitialLoad: isInitialLoad
            )
        } catch let error as NetworkError {
            let errorCategory = MessengerDiagnostics.sanitizeError(error)
            MessengerDiagnostics.event(
                errorCategory == "cancelled" ? .loadMessagesCancelled : .loadMessagesFailed,
                conversationID: conversation.id,
                metadata: [
                    "generation": "\(generation)",
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "errorCategory": errorCategory
                ]
            )
            if showedCachedMessages {
                syncMessagesFromCache()
                syncPaginationStateFromCache()
                MessengerDiagnostics.event(
                    .messengerMessageFallbackToCache,
                    conversationID: conversation.id,
                    metadata: ["count": "\(messages.count)"]
                )
            }
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            MessengerDiagnostics.event(
                MessengerDiagnostics.sanitizeError(error) == "cancelled" ? .loadMessagesCancelled : .loadMessagesFailed,
                conversationID: conversation.id,
                metadata: [
                    "generation": "\(generation)",
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
            if showedCachedMessages {
                syncMessagesFromCache()
                syncPaginationStateFromCache()
                MessengerDiagnostics.event(
                    .messengerMessageFallbackToCache,
                    conversationID: conversation.id,
                    metadata: ["count": "\(messages.count)"]
                )
            }
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func applyInMemoryMessageCacheIfAvailable(isInitialLoad: Bool) -> Bool {
        guard let cached = messageCache.messages(for: conversation.id), !cached.isEmpty else { return false }
        messages = cached
        syncPaginationStateFromCache()
        if isInitialLoad {
            MessengerDiagnostics.event(
                .chatInitialCacheSync,
                conversationID: conversation.id,
                metadata: ["messageCount": "\(cached.count)"]
            )
        }
        return true
    }

    private func startNetworkMessageRefresh(
        session: SessionStore,
        router: AppRouter,
        networkLoadGeneration: Int,
        isInitialLoad: Bool,
        cachedCountBefore: Int,
        generation: Int,
        loadReason: MessageLoadReason
    ) -> Task<Void, Never>? {
        let shouldForceNetwork = loadReason == .manualRefresh

        if loadTask == nil {
            loadTask = Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.messageCache.loadRecentMessagesIfNeeded(
                    conversationID: self.conversation.id,
                    limit: MessengerLimits.defaultMessagePageSize,
                    session: session,
                    router: router,
                    force: shouldForceNetwork,
                    loadGeneration: networkLoadGeneration,
                    reason: loadReason,
                    conversationLastMessageAt: self.conversation.lastMessageAt
                )
            }
            return loadTask
        }

        MessengerDiagnostics.event(
            .loadSkippedInFlight,
            conversationID: conversation.id,
            metadata: [
                "generation": "\(generation)",
                "cachedCountBefore": "\(cachedCountBefore)"
            ]
        )
        if isInitialLoad {
            MessengerDiagnostics.event(
                .chatInitialLoadSkippedInFlight,
                conversationID: conversation.id,
                metadata: ["generation": "\(generation)"]
            )
        }
        return loadTask
    }

    private func applyNetworkRefreshResult(
        generation: Int,
        networkLoadGeneration: Int,
        showedCachedMessages: Bool,
        startedAt: Date,
        cachedCountBefore: Int,
        isInitialLoad: Bool
    ) {
        guard networkLoadGeneration == messageLoadGeneration else {
            MessengerDiagnostics.event(
                .messengerMessageLoadStaleIgnored,
                conversationID: conversation.id,
                metadata: ["generation": "\(generation)"]
            )
            if showedCachedMessages {
                syncMessagesFromCache()
                syncPaginationStateFromCache()
            }
            return
        }

        let loaded = messageCache.messages(for: conversation.id) ?? messages
        messages = loaded
        syncPaginationStateFromCache()
        if let cacheError = messageCache.entry(for: conversation.id)?.errorMessage {
            errorMessage = cacheError
        } else if showedCachedMessages, !loaded.isEmpty {
            MessengerDiagnostics.event(
                .messengerMessageLoadingStateRecovered,
                conversationID: conversation.id,
                metadata: ["count": "\(loaded.count)"]
            )
        }

        MessengerDiagnostics.event(
            .loadMessagesSucceeded,
            conversationID: conversation.id,
            metadata: [
                "generation": "\(generation)",
                "durationMs": "\(durationMilliseconds(since: startedAt))",
                "resultCount": "\(loaded.count)",
                "cachedCountBefore": "\(cachedCountBefore)",
                "cachedCountAfter": "\(messageCache.messages(for: conversation.id)?.count ?? 0)"
            ]
        )
        if isInitialLoad {
            MessengerDiagnostics.event(
                loaded.isEmpty ? .chatInitialLoadNoMessages : .chatInitialLoadApplied,
                conversationID: conversation.id,
                metadata: [
                    "generation": "\(generation)",
                    "resultCount": "\(loaded.count)"
                ]
            )
        }
    }

    private func markRead(session: SessionStore, router: AppRouter) async {
        guard didOpen, isOpen, MessengerSessionSupport.isAppForegroundActive else {
            NetworkDebug.log("Messenger read ack skipped: inactive chat or background")
            MessengerDiagnostics.event(
                .readAckSkipped,
                conversationID: conversation.id,
                metadata: [
                    "reason": didOpen && isOpen ? "background" : "inactiveConversation",
                    "isAppForeground": "\(MessengerSessionSupport.isAppForegroundActive)",
                    "isActiveConversation": "\(isOpen)"
                ]
            )
            return
        }
        guard let messageID = latestInboundMessageID() else {
            NetworkDebug.log("Messenger read ack skipped: no inbound message")
            MessengerDiagnostics.event(
                .readAckSkipped,
                conversationID: conversation.id,
                metadata: ["reason": "noInboundMessage"]
            )
            return
        }
        guard deliveryAckCoordinator.shouldSendRead(
            conversationID: conversation.id,
            messageID: messageID
        ) else {
            NetworkDebug.log("Messenger read ack skipped: duplicate \(conversation.id)")
            MessengerDiagnostics.event(
                .readAckSkipped,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["reason": "duplicate"]
            )
            return
        }

        do {
            _ = try await ConversationService.markRead(
                conversationID: conversation.id,
                lastReadMessageID: messageID
            )
            deliveryAckCoordinator.markReadAcked(conversationID: conversation.id, messageID: messageID)
            MessengerRealtimeCoordinator.shared.markActiveConversationReadLocally(conversationID: conversation.id)
            NetworkDebug.log("Messenger read ack sent: \(conversation.id)")
            MessengerDiagnostics.event(
                .readAckSent,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: [
                    "isActiveConversation": "\(isOpen)",
                    "isAppForeground": "\(MessengerSessionSupport.isAppForegroundActive)"
                ]
            )
            MessengerDiagnostics.event(
                .messengerReadAckSucceeded,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["source": "chatOpen"]
            )
        } catch let error as NetworkError {
            MessengerDiagnostics.event(
                .readAckFailed,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            MessengerDiagnostics.event(
                .messengerReadAckFailed,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            _ = MessengerSessionSupport.handleNetworkError(error, session: session, router: router)
        } catch {
            MessengerDiagnostics.event(
                .readAckFailed,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            // Non-blocking: read receipt failure should not block chat UI.
        }
    }

    private func markDelivered(session: SessionStore, router: AppRouter) async {
        guard isOpen else {
            NetworkDebug.log("Messenger delivered ack skipped: inactive chat")
            MessengerDiagnostics.event(
                .deliveredAckSkipped,
                conversationID: conversation.id,
                metadata: ["reason": "inactiveConversation"]
            )
            return
        }
        guard MessengerSessionSupport.isAppForegroundActive else {
            NetworkDebug.log("Messenger delivered ack skipped: background")
            MessengerDiagnostics.event(
                .deliveredAckSkipped,
                conversationID: conversation.id,
                metadata: [
                    "reason": "background",
                    "isAppForeground": "false"
                ]
            )
            return
        }
        guard let messageID = latestInboundMessageID() else {
            NetworkDebug.log("Messenger delivered ack skipped: no inbound message")
            MessengerDiagnostics.event(
                .deliveredAckSkipped,
                conversationID: conversation.id,
                metadata: ["reason": "noInboundMessage"]
            )
            return
        }
        guard deliveryAckCoordinator.shouldSendDelivered(
            conversationID: conversation.id,
            messageID: messageID
        ) else {
            NetworkDebug.log("Messenger delivered ack skipped: duplicate \(conversation.id)")
            MessengerDiagnostics.event(
                .deliveredAckSkipped,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["reason": "duplicate"]
            )
            return
        }

        do {
            _ = try await ConversationService.markDelivered(
                conversationID: conversation.id,
                messageID: messageID
            )
            deliveryAckCoordinator.markDeliveredAcked(conversationID: conversation.id, messageID: messageID)
            NetworkDebug.log("Messenger delivered ack sent from active chat: \(conversation.id)")
            MessengerDiagnostics.event(
                .deliveredAckSent,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: [
                    "isActiveConversation": "\(isOpen)",
                    "isAppForeground": "\(MessengerSessionSupport.isAppForegroundActive)"
                ]
            )
        } catch let error as NetworkError {
            MessengerDiagnostics.event(
                .deliveredAckFailed,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            _ = MessengerSessionSupport.handleNetworkError(error, session: session, router: router)
        } catch {
            MessengerDiagnostics.event(
                .deliveredAckFailed,
                conversationID: conversation.id,
                messageID: messageID,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            // Non-blocking: delivery receipt failure should not block chat UI.
        }
    }

    @discardableResult
    func applyRealtimeMessage(_ dto: MessageDTO, currentProfileID: UUID) -> Bool {
        self.currentProfileID = currentProfileID
        messageContentGeneration += 1
        clearTyping(for: dto.senderProfileID)
        let applied = messageCache.applyRealtimeMessage(
            dto,
            conversationID: conversation.id,
            currentProfileID: currentProfileID
        )
        syncMessagesFromCache()
        return applied
    }

    func acknowledgeVisibleMessages(session: SessionStore?, router: AppRouter?) {
        guard let session, let router else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.markDelivered(session: session, router: router)
            await self.markRead(session: session, router: router)
        }
    }

    @discardableResult
    func applyDeliveryStatus(
        _ status: MessageDeliveryStatus,
        messageID: UUID?,
        cutoffDate: Date?
    ) -> Bool {
        messageContentGeneration += 1
        let targetDate = cutoffDate ?? messageID.flatMap { id in
            messages.first(where: { $0.id == id })?.createdAt
        }
        var didUpdate = false

        for index in messages.indices {
            let message = messages[index]
            guard shouldApplyReceipt(to: message, messageID: messageID, cutoffDate: targetDate) else {
                continue
            }

            let updated = message.replacingDeliveryStatus(status)
            if updated == message {
                NetworkDebug.log("Messenger receipt status ignored because it would downgrade")
                continue
            }

            messages[index] = updated
            messageCache.upsertMessage(updated, conversationID: conversation.id)
            didUpdate = true
        }

        return didUpdate
    }

    @discardableResult
    func applyRealtimeDeletedMessage(_ payload: MessageDeletedPayload) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == payload.messageID }) else {
            return false
        }

        let updated = messages[index].markingDeleted(deletedAt: payload.deletedAt)
        messages[index] = updated
        messageCache.upsertMessage(updated, conversationID: conversation.id)

        if editingMessage?.id == payload.messageID {
            cancelCompose()
            draftText = ""
        }
        if replyTarget?.id == payload.messageID {
            cancelCompose()
        }

        return true
    }

    @discardableResult
    func applyRealtimeReactionAdded(_ payload: ReactionAddedPayload) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == payload.messageID }) else {
            return false
        }

        let normalizedEmoji = ReactionEmoji.normalized(payload.reaction.emoji)
        var reactions = messages[index].reactions

        if let reactionIndex = reactions.firstIndex(where: { ReactionEmoji.normalized($0.emoji) == normalizedEmoji }) {
            let current = reactions[reactionIndex]
            let nextCount = payload.reaction.count.intValue ?? max(current.count, 1)
            reactions[reactionIndex] = current.replacing(
                count: max(current.count, nextCount),
                reactedByMe: current.reactedByMe
            )
        } else {
            reactions.append(
                ChatMessageReaction(
                    emoji: normalizedEmoji,
                    count: payload.reaction.count.intValue ?? 1,
                    reactedByMe: false
                )
            )
        }

        messages[index] = messages[index].replacingReactions(reactions.sorted { $0.displayEmoji < $1.displayEmoji })
        messageCache.upsertMessage(messages[index], conversationID: conversation.id)
        return true
    }

    @discardableResult
    func applyRealtimeReactionRemoved(
        _ payload: ReactionRemovedPayload,
        currentProfileID: UUID?
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == payload.messageID }) else {
            return false
        }

        let normalizedEmoji = ReactionEmoji.normalized(payload.emoji)
        var reactions = messages[index].reactions
        guard let reactionIndex = reactions.firstIndex(where: { ReactionEmoji.normalized($0.emoji) == normalizedEmoji }) else {
            return true
        }

        let current = reactions[reactionIndex]
        let nextCount = max(0, current.count - 1)
        let nextReactedByMe = payload.profileID == currentProfileID ? false : current.reactedByMe

        if nextCount == 0 {
            reactions.remove(at: reactionIndex)
        } else {
            reactions[reactionIndex] = current.replacing(
                count: nextCount,
                reactedByMe: nextReactedByMe
            )
        }

        messages[index] = messages[index].replacingReactions(reactions)
        messageCache.upsertMessage(messages[index], conversationID: conversation.id)
        return true
    }

    @discardableResult
    private func appendOrReplace(_ message: ChatMessage) -> Bool {
        let inserted = messageCache.upsertMessage(message, conversationID: conversation.id)
        syncMessagesFromCache()
        return inserted
    }

    private func latestInboundMessageID() -> UUID? {
        messages.last(where: { !$0.isMine && !$0.isDeleted })?.id
    }

    private func shouldApplyReceipt(
        to message: ChatMessage,
        messageID: UUID?,
        cutoffDate: Date?
    ) -> Bool {
        guard message.isMine, !message.isDeleted, message.localSendState == nil else { return false }
        if let cutoffDate {
            return message.createdAt <= cutoffDate
        }
        if let messageID {
            return message.id == messageID
        }
        return false
    }

    private func lifecycleMetadata(generation: Int) -> [String: String] {
        [
            "lifecycleGeneration": "\(generation)",
            "messageCount": "\(messages.count)",
            "didOpen": "\(didOpen)",
            "isOpen": "\(isOpen)"
        ]
    }

    private func hydrateFromLocalMessageCacheIfNeeded(
        session: SessionStore,
        generation: Int,
        limit: Int
    ) async {
        guard let profileID = try? await MessengerSessionSupport.resolveCurrentProfileID(session: session) else {
            return
        }
        guard generation == lifecycleGeneration, isOpen else { return }
        currentProfileID = profileID
        await hydrateFromLocalMessageCacheIfNeeded(
            profileID: profileID,
            generation: generation,
            contentGenerationAtStart: messageContentGeneration,
            limit: limit
        )
    }

    private func hydrateFromLocalMessageCacheIfNeeded(
        profileID: UUID,
        generation: Int,
        contentGenerationAtStart: Int,
        limit: Int
    ) async {
        guard generation == lifecycleGeneration, isOpen else { return }
        guard messageCache.messages(for: conversation.id)?.isEmpty != false else { return }

        guard let cached = await MessengerMessageCacheService.hydrateCachedMessages(
            conversationID: conversation.id,
            currentProfileID: profileID,
            limit: limit
        ), !cached.isEmpty else {
            return
        }

        guard generation == lifecycleGeneration,
              contentGenerationAtStart == messageContentGeneration,
              isOpen else {
            MessengerDiagnostics.event(
                .messengerMessageLoadStaleIgnored,
                conversationID: conversation.id,
                metadata: ["source": "cache"]
            )
            return
        }

        messageCache.mergeLoadedMessages(cached, for: conversation.id, marksRecentPageLoaded: false)
        messages = messageCache.messages(for: conversation.id) ?? cached
        syncPaginationStateFromCache()
        MessengerDiagnostics.event(
            .messengerMessageCacheHydratedUI,
            conversationID: conversation.id,
            metadata: ["count": "\(cached.count)", "source": "cache"]
        )
    }

    private func hydrateFromMessageCacheIfAvailable() {
        guard let cached = messageCache.messages(for: conversation.id), !cached.isEmpty else { return }
        messages = cached
        syncPaginationStateFromCache()
        MessengerDiagnostics.event(
            .cacheMergeCompleted,
            conversationID: conversation.id,
            metadata: [
                "source": "chatViewModelInit",
                "messageCount": "\(cached.count)",
                "hasMoreOlder": "\(hasMoreOlderMessages)"
            ]
        )
    }

    private func syncPaginationStateFromCache() {
        hasMoreOlderMessages = messageCache.hasMoreOlderMessages(for: conversation.id)
    }

    private func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
