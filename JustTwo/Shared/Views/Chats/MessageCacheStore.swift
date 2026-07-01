import Foundation

@MainActor
@Observable
final class MessageCacheStore {

    static let shared = MessageCacheStore()

    struct Entry {
        var messages: [ChatMessage]
        var loadedAt: Date
        var isLoading = false
        var isLoadingOlder = false
        var errorMessage: String?
        var olderMessagesCursor: String?
    }

    private(set) var entries: [UUID: Entry] = [:]
    private var loadTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func messages(for conversationID: UUID) -> [ChatMessage]? {
        entries[conversationID]?.messages
    }

    func entry(for conversationID: UUID) -> Entry? {
        entries[conversationID]
    }

    func hasCachedMessages(for conversationID: UUID) -> Bool {
        guard let messages = entries[conversationID]?.messages else { return false }
        return !messages.isEmpty
    }

    func setMessages(_ messages: [ChatMessage], for conversationID: UUID) {
        entries[conversationID] = Entry(messages: messages, loadedAt: .now, olderMessagesCursor: nil)
    }

    func loadRecentMessagesIfNeeded(
        conversationID: UUID,
        limit: Int = StartupLoadingLimits.preloadMessagesPerConversation,
        session: SessionStore,
        router: AppRouter,
        force: Bool = false
    ) async -> [ChatMessage] {
        if !force, let cached = entries[conversationID]?.messages, !cached.isEmpty {
            ensurePaginationCursorIfNeeded(conversationID: conversationID, pageSize: limit)
            return cached
        }

        if let existingTask = loadTasks[conversationID] {
            MessengerDiagnostics.event(
                .loadSkippedInFlight,
                conversationID: conversationID,
                metadata: [
                    "source": "messageCache",
                    "force": "\(force)",
                    "cachedCountBefore": "\(entries[conversationID]?.messages.count ?? 0)"
                ]
            )
            await existingTask.value
            if !force {
                ensurePaginationCursorIfNeeded(conversationID: conversationID, pageSize: limit)
                return entries[conversationID]?.messages ?? []
            }
        }

        var entry = entries[conversationID] ?? Entry(messages: [], loadedAt: .distantPast)
        entry.isLoading = true
        entry.errorMessage = nil
        entries[conversationID] = entry

        let task = Task { @MainActor in
            defer {
                loadTasks.removeValue(forKey: conversationID)
                entries[conversationID]?.isLoading = false
            }

            do {
                let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
                let response = try await MessageService.fetchMessages(
                    conversationID: conversationID,
                    limit: limit
                )
                let mapped = response.messages.map {
                    ChatUIMapping.message(from: $0, currentProfileID: profileID)
                }
                mergeLoadedMessages(mapped, for: conversationID)
                updateOlderMessagesCursor(
                    conversationID: conversationID,
                    response: response,
                    fetchedMessages: mapped
                )
            } catch let error as NetworkError {
                if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                    entries[conversationID]?.errorMessage = message
                } else {
                    entries[conversationID]?.errorMessage = error.userMessage
                }
            } catch {
                entries[conversationID]?.errorMessage = error.localizedDescription
            }
        }

        loadTasks[conversationID] = task
        await task.value
        return entries[conversationID]?.messages ?? []
    }

    @discardableResult
    func loadOlderMessages(
        conversationID: UUID,
        limit: Int = MessengerLimits.defaultMessagePageSize,
        session: SessionStore,
        router: AppRouter
    ) async -> Bool {
        guard var entry = entries[conversationID],
              let before = entry.olderMessagesCursor,
              !entry.isLoadingOlder else {
            NetworkDebug.log("Older messages load skipped: cursor=\(entries[conversationID]?.olderMessagesCursor != nil) loading=\(entries[conversationID]?.isLoadingOlder == true)")
            return false
        }

        NetworkDebug.log("Loading older messages conversation=\(conversationID.uuidString.prefix(8)) before=\(before.prefix(8)) count=\(entry.messages.count)")

        entry.isLoadingOlder = true
        entry.errorMessage = nil
        entries[conversationID] = entry

        defer {
            entries[conversationID]?.isLoadingOlder = false
        }

        let previousCount = entries[conversationID]?.messages.count ?? 0

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            let response = try await MessageService.fetchMessages(
                conversationID: conversationID,
                limit: limit,
                before: before
            )
            let mapped = response.messages.map {
                ChatUIMapping.message(from: $0, currentProfileID: profileID)
            }
            mergeLoadedMessages(mapped, for: conversationID)
            updateOlderMessagesCursor(
                conversationID: conversationID,
                response: response,
                fetchedMessages: mapped
            )
            let nextCursorLabel = entries[conversationID]?.olderMessagesCursor.map { String($0.prefix(8)) } ?? "nil"
            NetworkDebug.log("Older messages loaded incoming=\(mapped.count) total=\(entries[conversationID]?.messages.count ?? 0) nextCursor=\(nextCursorLabel)")
        } catch let error as NetworkError {
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                entries[conversationID]?.errorMessage = message
            } else {
                entries[conversationID]?.errorMessage = error.userMessage
            }
            return false
        } catch {
            entries[conversationID]?.errorMessage = error.localizedDescription
            return false
        }

        let nextCount = entries[conversationID]?.messages.count ?? previousCount
        return nextCount > previousCount
    }

    func hasMoreOlderMessages(for conversationID: UUID) -> Bool {
        entries[conversationID]?.olderMessagesCursor != nil
    }

    func setOlderMessagesCursorForTesting(_ cursor: String?, for conversationID: UUID) {
        guard var entry = entries[conversationID] else { return }
        entry.olderMessagesCursor = cursor
        entries[conversationID] = entry
    }

    private func updateOlderMessagesCursor(
        conversationID: UUID,
        response: MessagesResponseDTO,
        fetchedMessages: [ChatMessage]
    ) {
        guard var entry = entries[conversationID] else { return }

        if let nextCursor = response.nextCursor {
            entry.olderMessagesCursor = nextCursor
        } else if let oldestCached = entry.messages.first,
                  let oldestFetched = fetchedMessages.first,
                  oldestCached.createdAt < oldestFetched.createdAt {
            entry.olderMessagesCursor = oldestCached.id.uuidString
        } else {
            entry.olderMessagesCursor = nil
        }

        entries[conversationID] = entry
    }

    private func ensurePaginationCursorIfNeeded(conversationID: UUID, pageSize: Int) {
        guard var entry = entries[conversationID] else { return }
        guard entry.olderMessagesCursor == nil else { return }
        guard entry.messages.count >= pageSize,
              let oldest = entry.messages.first else { return }

        entry.olderMessagesCursor = oldest.id.uuidString
        entries[conversationID] = entry
        NetworkDebug.log("Pagination cursor inferred from cache conversation=\(conversationID.uuidString.prefix(8)) count=\(entry.messages.count)")
    }

    func preloadRecentMessages(
        for conversations: [ChatConversationPreview],
        session: SessionStore,
        router: AppRouter,
        maxConversations: Int = StartupLoadingLimits.preloadConversationCount,
        messagesPerConversation: Int = StartupLoadingLimits.preloadMessagesPerConversation
    ) async {
        let targets = Array(conversations.prefix(maxConversations))

        await withTaskGroup(of: Void.self) { group in
            for conversation in targets {
                group.addTask { @MainActor in
                    _ = await self.loadRecentMessagesIfNeeded(
                        conversationID: conversation.id,
                        limit: messagesPerConversation,
                        session: session,
                        router: router
                    )
                }
            }
            await group.waitForAll()
        }
    }

    @discardableResult
    func upsertMessage(_ message: ChatMessage, conversationID: UUID) -> Bool {
        var entry = entries[conversationID] ?? Entry(messages: [], loadedAt: .now)

        if let index = entry.messages.firstIndex(where: { $0.id == message.id }) {
            guard entry.messages[index] != message else { return false }
            entry.messages[index] = message
        } else {
            entry.messages.append(message)
        }

        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
    }

    func mergeLoadedMessages(_ loadedMessages: [ChatMessage], for conversationID: UUID) {
        let existingMessages = entries[conversationID]?.messages ?? []
        var preservedDeleteCount = 0
        var preservedEditCount = 0
        var preservedReceiptCount = 0

        MessengerDiagnostics.event(
            .cacheMergeStarted,
            conversationID: conversationID,
            metadata: [
                "incomingCount": "\(loadedMessages.count)",
                "existingCount": "\(existingMessages.count)"
            ]
        )

        var mergedByID: [UUID: ChatMessage] = [:]

        for message in existingMessages {
            mergedByID[message.id] = message
        }
        for message in loadedMessages {
            if let existing = mergedByID[message.id] {
                let merged = mergeLoadedMessage(message, withExisting: existing)
                if existing.isDeleted, !message.isDeleted, merged.isDeleted {
                    preservedDeleteCount += 1
                }
                if existing.isEdited, !message.isEdited, !message.isDeleted, merged.isEdited {
                    preservedEditCount += 1
                }
                if let existingStatus = existing.deliveryStatus,
                   existingStatus.rank > (message.deliveryStatus?.rank ?? -1),
                   merged.deliveryStatus == existingStatus {
                    preservedReceiptCount += 1
                }
                mergedByID[message.id] = merged
            } else {
                mergedByID[message.id] = message
            }
        }

        let merged = mergedByID.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }

        entries[conversationID] = Entry(messages: merged, loadedAt: .now, olderMessagesCursor: entries[conversationID]?.olderMessagesCursor)
        if preservedDeleteCount > 0 || preservedEditCount > 0 || preservedReceiptCount > 0 {
            MessengerDiagnostics.event(
                .cacheMergePreservedRealtimeState,
                conversationID: conversationID,
                metadata: [
                    "preservedDeleteCount": "\(preservedDeleteCount)",
                    "preservedEditCount": "\(preservedEditCount)",
                    "preservedReceiptCount": "\(preservedReceiptCount)"
                ]
            )
        }
        MessengerDiagnostics.event(
            .cacheMergeCompleted,
            conversationID: conversationID,
            metadata: [
                "incomingCount": "\(loadedMessages.count)",
                "existingCount": "\(existingMessages.count)",
                "resultCount": "\(merged.count)",
                "preservedDeleteCount": "\(preservedDeleteCount)",
                "preservedEditCount": "\(preservedEditCount)",
                "preservedReceiptCount": "\(preservedReceiptCount)"
            ]
        )
    }

    private func mergeLoadedMessage(_ loaded: ChatMessage, withExisting existing: ChatMessage) -> ChatMessage {
        let candidate: ChatMessage

        if existing.isDeleted, !loaded.isDeleted {
            candidate = existing
        } else if existing.isEdited, !loaded.isEdited, !loaded.isDeleted {
            candidate = existing
        } else {
            candidate = loaded
        }

        guard let highestStatus = highestDeliveryStatus(existing.deliveryStatus, loaded.deliveryStatus) else {
            return candidate
        }
        return candidate.replacingDeliveryStatus(highestStatus)
    }

    private func highestDeliveryStatus(
        _ lhs: MessageDeliveryStatus?,
        _ rhs: MessageDeliveryStatus?
    ) -> MessageDeliveryStatus? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case (.some(let status), .none), (.none, .some(let status)):
            return status
        case (.some(let lhs), .some(let rhs)):
            return lhs.rank >= rhs.rank ? lhs : rhs
        }
    }

    @discardableResult
    func applyRealtimeMessage(
        _ dto: MessageDTO,
        conversationID: UUID,
        currentProfileID: UUID
    ) -> Bool {
        let message = ChatUIMapping.message(from: dto, currentProfileID: currentProfileID)
        return upsertMessage(message, conversationID: conversationID)
    }

    @discardableResult
    func markMessageDeleted(
        conversationID: UUID,
        messageID: UUID,
        deletedAt: Date?
    ) -> Bool {
        guard var entry = entries[conversationID],
              let index = entry.messages.firstIndex(where: { $0.id == messageID }) else {
            return false
        }

        entry.messages[index] = entry.messages[index].markingDeleted(deletedAt: deletedAt)
        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
    }

    @discardableResult
    func applyRealtimeReactionAdded(
        _ payload: ReactionAddedPayload,
        conversationID: UUID
    ) -> Bool {
        guard var entry = entries[conversationID],
              let index = entry.messages.firstIndex(where: { $0.id == payload.messageID }) else {
            return false
        }

        let normalizedEmoji = ReactionEmoji.normalized(payload.reaction.emoji)
        var reactions = entry.messages[index].reactions

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

        entry.messages[index] = entry.messages[index].replacingReactions(
            reactions.sorted { $0.displayEmoji < $1.displayEmoji }
        )
        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
    }

    @discardableResult
    func applyRealtimeReactionRemoved(
        _ payload: ReactionRemovedPayload,
        conversationID: UUID,
        currentProfileID: UUID?
    ) -> Bool {
        guard var entry = entries[conversationID],
              let index = entry.messages.firstIndex(where: { $0.id == payload.messageID }) else {
            return false
        }

        let normalizedEmoji = ReactionEmoji.normalized(payload.emoji)
        var reactions = entry.messages[index].reactions
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

        entry.messages[index] = entry.messages[index].replacingReactions(reactions)
        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
    }

    @discardableResult
    func applyDeliveryStatus(
        conversationID: UUID,
        status: MessageDeliveryStatus,
        messageID: UUID?,
        cutoffDate: Date?
    ) -> Bool {
        guard var entry = entries[conversationID] else { return false }
        var didUpdate = false
        let targetDate = cutoffDate ?? messageID.flatMap { id in
            entry.messages.first(where: { $0.id == id })?.createdAt
        }

        for index in entry.messages.indices {
            let message = entry.messages[index]
            guard shouldApplyReceipt(to: message, messageID: messageID, cutoffDate: targetDate) else {
                continue
            }

            let updated = message.replacingDeliveryStatus(status)
            guard updated != message else { continue }
            entry.messages[index] = updated
            didUpdate = true
        }

        guard didUpdate else { return false }
        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
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

    func reset() {
        for task in loadTasks.values {
            task.cancel()
        }
        loadTasks.removeAll()
        entries.removeAll()
    }
}
