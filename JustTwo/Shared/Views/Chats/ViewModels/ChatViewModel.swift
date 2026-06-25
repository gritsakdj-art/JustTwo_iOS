import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ChatViewModel {

    let conversation: ChatConversationPreview

    private(set) var messages: [ChatMessage] = []
    var draftText = ""
    private(set) var isLoading = false
    private(set) var isSending = false
    var errorMessage: String?

    var actionMenuMessage: ChatMessage?
    var pendingDeleteMessage: ChatMessage?
    var replyTarget: ChatMessage?
    var editingMessage: ChatMessage?

    private var currentProfileID: UUID?
    private var didOpen = false

    init(conversation: ChatConversationPreview) {
        self.conversation = conversation
    }

    static func preview(
        conversation: ChatConversationPreview,
        messages: [ChatMessage] = ChatUIMockData.messages(for: ChatUIMockData.conversations[0].id)
    ) -> ChatViewModel {
        let viewModel = ChatViewModel(conversation: conversation)
        viewModel.messages = messages
        viewModel.didOpen = true
        return viewModel
    }

    var composeBannerMode: ChatComposeBanner.Mode? {
        if let editingMessage {
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

    func reload(session: SessionStore, router: AppRouter) async {
        await loadMessages(session: session, router: router)
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
        pendingDeleteMessage = message
        dismissActionMenu()
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
            if let editingMessage {
                dto = try await MessageService.editMessage(messageID: editingMessage.id, body: trimmed)
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
            appendOrReplace(ChatUIMapping.message(from: dto, currentProfileID: profileID))
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

            appendOrReplace(ChatUIMapping.message(from: dto, currentProfileID: profileID))
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
            appendOrReplace(ChatUIMapping.message(from: dto, currentProfileID: profileID))

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
        isLoading = messages.isEmpty
        errorMessage = nil

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            currentProfileID = profileID

            let response = try await MessageService.fetchMessages(conversationID: conversation.id)
            messages = response.messages.map {
                ChatUIMapping.message(from: $0, currentProfileID: profileID)
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

    private func appendOrReplace(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }
}
