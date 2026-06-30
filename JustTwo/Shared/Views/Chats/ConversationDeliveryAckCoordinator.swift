import Foundation

@MainActor
final class ConversationDeliveryAckCoordinator {

    static let shared = ConversationDeliveryAckCoordinator()

    private struct AckKey: Hashable {
        let conversationID: UUID
        let messageID: UUID
    }

    private var deliveredAckedKeys: Set<AckKey> = []
    private var readAckedKeys: Set<AckKey> = []
    var markDeliveredHandler: ((UUID, UUID) async throws -> Void)?

    private init() {}

    static func makeForTesting() -> ConversationDeliveryAckCoordinator {
        ConversationDeliveryAckCoordinator()
    }

    func reset() {
        deliveredAckedKeys.removeAll()
        readAckedKeys.removeAll()
    }

    func shouldSendDelivered(conversationID: UUID, messageID: UUID) -> Bool {
        let key = AckKey(conversationID: conversationID, messageID: messageID)
        if readAckedKeys.contains(key) {
            return false
        }
        return !deliveredAckedKeys.contains(key)
    }

    func shouldSendRead(conversationID: UUID, messageID: UUID) -> Bool {
        let key = AckKey(conversationID: conversationID, messageID: messageID)
        return !readAckedKeys.contains(key)
    }

    func markDeliveredAcked(conversationID: UUID, messageID: UUID) {
        let key = AckKey(conversationID: conversationID, messageID: messageID)
        deliveredAckedKeys.insert(key)
    }

    func markReadAcked(conversationID: UUID, messageID: UUID) {
        let key = AckKey(conversationID: conversationID, messageID: messageID)
        readAckedKeys.insert(key)
        deliveredAckedKeys.insert(key)
    }

    func acknowledgeDeliveredForConversations(
        _ conversations: [ConversationDTO],
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async {
        if markDeliveredHandler == nil {
            guard session.isFullyAuthenticated else {
                NetworkDebug.log("Messenger delivered ack batch skipped: unauthenticated")
                return
            }
            guard MessengerSessionSupport.isAppForegroundActive else {
                NetworkDebug.log("Messenger delivered ack batch skipped: background")
                return
            }
        }

        for conversation in conversations {
            await acknowledgeDeliveredIfNeeded(
                conversation: conversation,
                currentProfileID: currentProfileID,
                session: session,
                router: router
            )
        }
    }

    func acknowledgeDeliveredIfNeeded(
        conversation: ConversationDTO,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async {
        guard let message = conversation.lastMessage else {
            NetworkDebug.log("Messenger delivered ack skipped: no lastMessage \(conversation.id)")
            return
        }

        await sendDeliveredIfNeeded(
            conversationID: conversation.id,
            messageID: message.id,
            senderProfileID: message.senderProfileID,
            currentProfileID: currentProfileID,
            lastReadAt: conversation.lastReadAt,
            messageCreatedAt: message.createdAt,
            isDeleted: message.deletedAt != nil,
            session: session,
            router: router,
            source: "conversation list"
        )
    }

    func acknowledgeDeliveredIfNeeded(
        conversationID: UUID,
        message: MessageDTO,
        currentProfileID: UUID,
        session: SessionStore?,
        router: AppRouter?
    ) async {
        guard let session, let router else {
            NetworkDebug.log("Messenger delivered ack skipped: missing session/router")
            return
        }

        await sendDeliveredIfNeeded(
            conversationID: conversationID,
            messageID: message.id,
            senderProfileID: message.senderProfileID,
            currentProfileID: currentProfileID,
            lastReadAt: nil,
            messageCreatedAt: message.createdAt,
            isDeleted: message.deletedAt != nil,
            session: session,
            router: router,
            source: "realtime inactive conversation"
        )
    }

    private func sendDeliveredIfNeeded(
        conversationID: UUID,
        messageID: UUID,
        senderProfileID: UUID,
        currentProfileID: UUID,
        lastReadAt: Date?,
        messageCreatedAt: Date?,
        isDeleted: Bool,
        session: SessionStore,
        router: AppRouter,
        source: String
    ) async {
        guard !isDeleted else {
            NetworkDebug.log("Messenger delivered ack skipped: deleted message \(conversationID)")
            return
        }
        guard senderProfileID != currentProfileID else {
            NetworkDebug.log("Messenger delivered ack skipped: own message \(conversationID)")
            return
        }
        if markDeliveredHandler == nil {
            guard session.isFullyAuthenticated else {
                NetworkDebug.log("Messenger delivered ack skipped: unauthenticated")
                return
            }
            guard MessengerSessionSupport.isAppForegroundActive else {
                NetworkDebug.log("Messenger delivered ack skipped: background")
                return
            }
        }
        if let lastReadAt, let messageCreatedAt, lastReadAt >= messageCreatedAt {
            markReadAcked(conversationID: conversationID, messageID: messageID)
            NetworkDebug.log("Messenger delivered ack skipped: already read \(conversationID)")
            return
        }
        guard shouldSendDelivered(conversationID: conversationID, messageID: messageID) else {
            NetworkDebug.log("Messenger delivered ack skipped: duplicate \(conversationID)")
            return
        }

        do {
            if let markDeliveredHandler {
                try await markDeliveredHandler(conversationID, messageID)
            } else {
                _ = try await ConversationService.markDelivered(
                    conversationID: conversationID,
                    messageID: messageID
                )
            }
            markDeliveredAcked(conversationID: conversationID, messageID: messageID)
            NetworkDebug.log("Messenger delivered ack sent from \(source): \(conversationID)")
        } catch let error as NetworkError {
            _ = MessengerSessionSupport.handleNetworkError(error, session: session, router: router)
        } catch {
            NetworkDebug.log("Messenger delivered ack failed: \(conversationID)")
        }
    }
}
