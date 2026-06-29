import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ChatViewModel {

    let conversation: ChatConversationPreview

    private(set) var messages: [ChatMessage] = []
    var draftText = "" {
        didSet {
            guard draftText != oldValue else { return }
            handleDraftTextChange(draftText)
        }
    }
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var typingProfileIDs: Set<UUID> = []
    var errorMessage: String?

    var actionMenuMessage: ChatMessage?
    var pendingDeleteMessage: ChatMessage?
    var replyTarget: ChatMessage?
    var editingMessage: ChatMessage?

    private var currentProfileID: UUID?
    private var didOpen = false
    private var isRealtimeActive = false
    private var typingTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private let typingEmitter: ChatTypingEmitter
    private let typingTimeout: TimeInterval = 5

    private var messageCache: MessageCacheStore { MessageCacheStore.shared }

    init(conversation: ChatConversationPreview) {
        self.conversation = conversation
        self.typingEmitter = ChatTypingEmitter(conversationID: conversation.id)
    }

    var isOtherParticipantTyping: Bool {
        guard let currentProfileID else {
            return !typingProfileIDs.isEmpty
        }
        return typingProfileIDs.contains { $0 != currentProfileID }
    }

    static func preview(
        conversation: ChatConversationPreview,
        messages: [ChatMessage]
    ) -> ChatViewModel {
        let viewModel = ChatViewModel(conversation: conversation)
        viewModel.messages = messages
        viewModel.didOpen = true
        return viewModel
    }

    static func preview(conversation: ChatConversationPreview) -> ChatViewModel {
        preview(
            conversation: conversation,
            messages: ChatUIMockData.messages(for: ChatUIMockData.conversations[0].id)
        )
    }

    var composeBannerMode: ChatComposeBanner.Mode? {
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

    func open(session: SessionStore, router: AppRouter) async {
        guard !didOpen else { return }
        didOpen = true
        await loadMessages(session: session, router: router)
        await markRead(session: session, router: router)
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
        await loadMessages(session: session, router: router)
    }

    func refreshFromRealtime(session: SessionStore, router: AppRouter) async {
        await loadMessages(session: session, router: router)
        await markRead(session: session, router: router)
    }

    func openActionMenu(for message: ChatMessage) {
        actionMenuMessage = message
    }

    func dismissActionMenu() {
        actionMenuMessage = nil
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
        replyTarget = nil
        editingMessage = nil
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

    func send(session: SessionStore, router: AppRouter) async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard trimmed.count <= MessengerLimits.maxMessageLength else {
            errorMessage = String(localized: "chats.error.message_too_long")
            return
        }

        isSending = true
        errorMessage = nil

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let dto: MessageDTO
            if let editing = editingMessage {
                dto = try await MessageService.editMessage(messageID: editing.id, body: trimmed)
                self.editingMessage = nil
            } else {
                dto = try await MessageService.sendMessage(
                    conversationID: conversation.id,
                    body: trimmed,
                    replyToID: replyTarget?.id,
                    clientMessageID: UUID().uuidString
                )
                replyTarget = nil
            }

            draftText = ""
            typingEmitter.messageSent()
            let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
            appendOrReplace(mapped)
            messageCache.upsertMessage(mapped, conversationID: conversation.id)
            await markRead(session: session, router: router)
        } catch let error as NetworkError {
            if error.isUserBlocked {
                errorMessage = String(localized: "chats.error.user_blocked")
            } else if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
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
            messageCache.upsertMessage(mapped, conversationID: conversation.id)
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
            messageCache.upsertMessage(mapped, conversationID: conversation.id)

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

    private func loadMessages(session: SessionStore, router: AppRouter) async {
        if let cached = messageCache.messages(for: conversation.id), !cached.isEmpty {
            messages = cached
            isLoading = false
        } else {
            isLoading = true
        }
        errorMessage = nil

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let loaded = await messageCache.loadRecentMessagesIfNeeded(
                conversationID: conversation.id,
                limit: MessengerLimits.defaultMessagePageSize,
                session: session,
                router: router,
                force: true
            )
            messages = loaded
            if let cacheError = messageCache.entry(for: conversation.id)?.errorMessage {
                errorMessage = cacheError
            }
        } catch let error as NetworkError {
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func markRead(session: SessionStore, router: AppRouter) async {
        do {
            _ = try await ConversationService.markRead(
                conversationID: conversation.id,
                lastReadMessageID: messages.last?.id
            )
        } catch let error as NetworkError {
            _ = MessengerSessionSupport.handleNetworkError(error, session: session, router: router)
        } catch {
            // Non-blocking: read receipt failure should not block chat UI.
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
}
