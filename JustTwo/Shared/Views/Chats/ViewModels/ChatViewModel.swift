import Foundation
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
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var typingTimeoutTasks: [UUID: Task<Void, Never>] = [:]
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
        if let lastMessageID = messages.last?.id {
            return .lastReadMessage(lastMessageID)
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
        MessengerDiagnostics.event(
            .chatOpenStarted,
            conversationID: conversation.id,
            metadata: lifecycleMetadata(generation: generation)
        )

        if !didOpen {
            await loadMessages(session: session, router: router, generation: generation)
            guard generation == lifecycleGeneration, isOpen else {
                MessengerDiagnostics.event(
                    .loadMessagesIgnoredStaleGeneration,
                    conversationID: conversation.id,
                    metadata: lifecycleMetadata(generation: generation)
                )
                return
            }
            didOpen = true
        } else if let cached = messageCache.messages(for: conversation.id), !cached.isEmpty {
            messages = cached
            syncPaginationStateFromCache()
        }

        await markDelivered(session: session, router: router)
        await markRead(session: session, router: router)
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
        isOpen = false
        isLoading = false
        loadTask?.cancel()
        loadTask = nil
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
        let generation = lifecycleGeneration
        await loadMessages(session: session, router: router, generation: generation)
    }

    func loadOlderMessages(session: SessionStore, router: AppRouter) async {
        guard hasMoreOlderMessages, !isLoadingOlderMessages else { return }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        let didLoad = await messageCache.loadOlderMessages(
            conversationID: conversation.id,
            session: session,
            router: router
        )
        messages = messageCache.messages(for: conversation.id) ?? messages
        syncPaginationStateFromCache()
        NetworkDebug.log("Chat older messages load finished didLoad=\(didLoad) count=\(messages.count) hasMore=\(hasMoreOlderMessages)")
    }

    func refreshFromRealtime(session: SessionStore, router: AppRouter) async {
        guard isOpen else { return }
        let generation = lifecycleGeneration
        await loadMessages(session: session, router: router, generation: generation)
        guard generation == lifecycleGeneration, isOpen else { return }
        await markDelivered(session: session, router: router)
        await markRead(session: session, router: router)
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

    func send(session: SessionStore, router: AppRouter) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSending, sendTask == nil else {
            MessengerDiagnostics.event(
                .sendSkippedAlreadySending,
                conversationID: conversation.id,
                metadata: [
                    "isSendingBefore": "\(isSending)",
                    "hasSendTask": "\(sendTask != nil)"
                ]
            )
            return
        }
        guard trimmed.count <= MessengerLimits.maxMessageLength else {
            errorMessage = String(localized: "chats.error.message_too_long")
            return
        }

        let originalDraftText = draftText
        let activeReplyTarget = replyTarget
        let activeEditingMessage = editingMessage
        let clientMessageID = UUID().uuidString

        isSending = true
        errorMessage = nil
        draftText = ""
        typingEmitter.messageSent()
        MessengerDiagnostics.event(
            .sendStarted,
            conversationID: conversation.id,
            clientMessageID: clientMessageID,
            metadata: [
                "isSendingBefore": "false",
                "isSendingAfter": "true",
                "draftCleared": "true",
                "isEditing": "\(activeEditingMessage != nil)",
                "hasReply": "\(activeReplyTarget != nil)"
            ]
        )

        sendTask = Task { @MainActor [weak self] in
            await self?.performSend(
                body: trimmed,
                originalDraftText: originalDraftText,
                replyTarget: activeReplyTarget,
                editingMessage: activeEditingMessage,
                clientMessageID: clientMessageID,
                session: session,
                router: router
            )
        }
    }

    private func performSend(
        body trimmed: String,
        originalDraftText: String,
        replyTarget activeReplyTarget: ChatMessage?,
        editingMessage activeEditingMessage: ChatMessage?,
        clientMessageID: String,
        session: SessionStore,
        router: AppRouter
    ) async {
        let startedAt = Date()
        defer {
            isSending = false
            sendTask = nil
            MessengerDiagnostics.event(
                .isSendingReset,
                conversationID: conversation.id,
                clientMessageID: clientMessageID
            )
        }

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let dto: MessageDTO
            if let editing = activeEditingMessage {
                dto = try await MessageService.editMessage(messageID: editing.id, body: trimmed)
            } else {
                dto = try await MessageService.sendMessage(
                    conversationID: conversation.id,
                    body: trimmed,
                    replyToID: activeReplyTarget?.id,
                    clientMessageID: clientMessageID
                )
            }

            if editingMessage?.id == activeEditingMessage?.id {
                editingMessage = nil
            }
            if replyTarget?.id == activeReplyTarget?.id {
                replyTarget = nil
            }
            let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
            appendOrReplace(mapped)
            MessengerDiagnostics.event(
                .sendSucceeded,
                conversationID: conversation.id,
                messageID: mapped.id,
                clientMessageID: clientMessageID,
                metadata: [
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "isEditing": "\(activeEditingMessage != nil)"
                ]
            )
        } catch let error as NetworkError {
            restoreDraftAfterFailedSend(
                originalDraftText,
                replyTarget: activeReplyTarget,
                editingMessage: activeEditingMessage,
                clientMessageID: clientMessageID
            )
            MessengerDiagnostics.event(
                .sendFailed,
                conversationID: conversation.id,
                clientMessageID: clientMessageID,
                metadata: [
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
            if error.isUserBlocked {
                errorMessage = String(localized: "chats.error.user_blocked")
            } else if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            restoreDraftAfterFailedSend(
                originalDraftText,
                replyTarget: activeReplyTarget,
                editingMessage: activeEditingMessage,
                clientMessageID: clientMessageID
            )
            MessengerDiagnostics.event(
                MessengerDiagnostics.sanitizeError(error) == "cancelled" ? .sendCancelled : .sendFailed,
                conversationID: conversation.id,
                clientMessageID: clientMessageID,
                metadata: [
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
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

    private func restoreDraftAfterFailedSend(
        _ originalDraftText: String,
        replyTarget activeReplyTarget: ChatMessage?,
        editingMessage activeEditingMessage: ChatMessage?,
        clientMessageID: String
    ) {
        if draftText.isEmpty {
            draftText = originalDraftText
            MessengerDiagnostics.event(
                .draftRestoredAfterFailure,
                conversationID: conversation.id,
                clientMessageID: clientMessageID
            )
        } else {
            MessengerDiagnostics.event(
                .draftRestoreSkippedUserTypedNewText,
                conversationID: conversation.id,
                clientMessageID: clientMessageID
            )
        }
        if replyTarget == nil {
            replyTarget = activeReplyTarget
        }
        if editingMessage == nil {
            editingMessage = activeEditingMessage
        }
    }

    private func loadMessages(
        session: SessionStore,
        router: AppRouter,
        generation: Int
    ) async {
        let startedAt = Date()
        let cachedCountBefore = messageCache.messages(for: conversation.id)?.count ?? 0
        MessengerDiagnostics.event(
            .loadMessagesStarted,
            conversationID: conversation.id,
            metadata: [
                "generation": "\(generation)",
                "cachedCountBefore": "\(cachedCountBefore)",
                "isOpen": "\(isOpen)"
            ]
        )
        defer {
            if generation == lifecycleGeneration {
                isLoading = false
            }
        }

        if let cached = messageCache.messages(for: conversation.id), !cached.isEmpty {
            messages = cached
            isLoading = false
        } else {
            isLoading = true
        }
        errorMessage = nil

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

            if loadTask == nil {
                loadTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.messageCache.loadRecentMessagesIfNeeded(
                        conversationID: self.conversation.id,
                        limit: MessengerLimits.defaultMessagePageSize,
                        session: session,
                        router: router,
                        force: true
                    )
                }
            } else {
                MessengerDiagnostics.event(
                    .loadSkippedInFlight,
                    conversationID: conversation.id,
                    metadata: [
                        "generation": "\(generation)",
                        "cachedCountBefore": "\(cachedCountBefore)"
                    ]
                )
            }

            await loadTask?.value
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
            let loaded = messageCache.messages(for: conversation.id) ?? []
            messages = loaded
            syncPaginationStateFromCache()
            if let cacheError = messageCache.entry(for: conversation.id)?.errorMessage {
                errorMessage = cacheError
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
            errorMessage = error.localizedDescription
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
        } catch let error as NetworkError {
            MessengerDiagnostics.event(
                .readAckFailed,
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
        clearTyping(for: dto.senderProfileID)
        let message = ChatUIMapping.message(from: dto, currentProfileID: currentProfileID)
        messageCache.upsertMessage(message, conversationID: conversation.id)
        return appendOrReplace(message)
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
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            guard messages[index] != message else {
                NetworkDebug.log("Duplicate realtime message ignored: \(message.id)")
                return false
            }
            messages[index] = message
            messageCache.upsertMessage(message, conversationID: conversation.id)
            return false
        } else {
            messages.append(message)
            messageCache.upsertMessage(message, conversationID: conversation.id)
            return true
        }
    }

    private func latestInboundMessageID() -> UUID? {
        messages.last(where: { !$0.isMine && !$0.isDeleted })?.id
    }

    private func shouldApplyReceipt(
        to message: ChatMessage,
        messageID: UUID?,
        cutoffDate: Date?
    ) -> Bool {
        guard message.isMine, !message.isDeleted else { return false }
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

    private func syncPaginationStateFromCache() {
        hasMoreOlderMessages = messageCache.hasMoreOlderMessages(for: conversation.id)
    }

    private func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
