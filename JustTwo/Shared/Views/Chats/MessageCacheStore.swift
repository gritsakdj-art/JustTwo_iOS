import Foundation

@MainActor
@Observable
final class MessageCacheStore {

    enum ReconciliationSource: String {
        case rest
        case realtime
        case fetch
    }

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
    private var loadGenerations: [UUID: Int] = [:]

    private init() {}

    func cancelLoad(for conversationID: UUID) {
        loadTasks[conversationID]?.cancel()
        loadTasks.removeValue(forKey: conversationID)
        entries[conversationID]?.isLoading = false
    }

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
        entries[conversationID] = Entry(messages: sortedMessages(messages), loadedAt: .now, olderMessagesCursor: nil)
    }

    func insertOptimisticMessage(_ message: ChatMessage, for conversationID: UUID) {
        guard message.localSendState != nil else { return }
        var entry = entries[conversationID] ?? Entry(messages: [], loadedAt: .now)
        guard !entry.messages.contains(where: { $0.clientMessageID == message.clientMessageID }) else { return }
        entry.messages.append(message)
        entry.messages = sortedMessages(entry.messages)
        entry.loadedAt = .now
        entries[conversationID] = entry

        MessengerDiagnostics.event(
            .optimisticMessageInserted,
            conversationID: conversationID,
            clientMessageID: message.clientMessageID,
            metadata: ["state": message.localSendState == .failed ? "failed" : "sending"]
        )
    }

    @discardableResult
    func updateOptimisticMessageState(
        clientMessageID: String,
        conversationID: UUID,
        state: MessageLocalSendState
    ) -> Bool {
        guard var entry = entries[conversationID],
              let index = entry.messages.firstIndex(where: { $0.clientMessageID == clientMessageID && $0.localSendState != nil }) else {
            return false
        }

        entry.messages[index] = entry.messages[index].replacingLocalSendState(state)
        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
    }

    @discardableResult
    func replaceOptimisticMessage(
        clientMessageID: String,
        with serverMessage: ChatMessage,
        conversationID: UUID,
        source: ReconciliationSource
    ) -> Bool {
        guard var entry = entries[conversationID],
              let index = entry.messages.firstIndex(where: { $0.clientMessageID == clientMessageID && $0.localSendState != nil }) else {
            return false
        }

        entry.messages.remove(at: index)

        if let serverIndex = entry.messages.firstIndex(where: { $0.id == serverMessage.id }) {
            entry.messages[serverIndex] = mergeLoadedMessage(serverMessage, withExisting: entry.messages[serverIndex])
        } else {
            entry.messages.append(serverMessage)
        }

        entry.messages = sortedMessages(entry.messages)
        entry.loadedAt = .now
        entries[conversationID] = entry

        let event: MessengerDiagnosticEvent = source == .realtime ? .outboxReconciledFromRealtime : .outboxReconciledFromREST
        MessengerDiagnostics.event(
            event,
            conversationID: conversationID,
            messageID: serverMessage.id,
            clientMessageID: clientMessageID,
            metadata: ["source": source.rawValue]
        )

        return true
    }

    func pendingOutgoingMessages(for conversationID: UUID) -> [ChatMessage] {
        entries[conversationID]?.messages.filter { $0.localSendState != nil } ?? []
    }

    func outgoingPendingCount(for conversationID: UUID) -> Int {
        pendingOutgoingMessages(for: conversationID).count
    }

    private enum OutgoingReconcileResult {
        case reconciled(Bool)
        case ambiguousPending
        case noMatch
    }

    private func sortedMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.listIdentity < $1.listIdentity
            }
            return $0.createdAt < $1.createdAt
        }
    }

    func loadRecentMessagesIfNeeded(
        conversationID: UUID,
        limit: Int = StartupLoadingLimits.preloadMessagesPerConversation,
        session: SessionStore,
        router: AppRouter,
        force: Bool = false,
        loadGeneration: Int = 0
    ) async -> [ChatMessage] {
        if force {
            cancelLoad(for: conversationID)
        }

        if !force, let cached = entries[conversationID]?.messages, !cached.isEmpty {
            ensurePaginationCursorIfNeeded(conversationID: conversationID, pageSize: limit)
            return cached
        }

        if let existingTask = loadTasks[conversationID], !force {
            // A fetch is already running for this conversation (e.g. startup preload or another
            // ChatViewModel instance). Reuse its result instead of firing a second, redundant
            // network request — the caller still gets fresh data without a duplicate round trip,
            // and without racing two fetches against the same cache entry.
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
            ensurePaginationCursorIfNeeded(conversationID: conversationID, pageSize: limit)
            return entries[conversationID]?.messages ?? []
        }

        var entry = entries[conversationID] ?? Entry(messages: [], loadedAt: .distantPast)
        entry.isLoading = true
        entry.errorMessage = nil
        entries[conversationID] = entry
        loadGenerations[conversationID] = loadGeneration

        let startedAt = Date()
        MessengerDiagnostics.event(
            .messengerMessageNetworkRefreshStarted,
            conversationID: conversationID,
            metadata: ["source": "rest"]
        )

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
                guard !Task.isCancelled,
                      loadGenerations[conversationID] == loadGeneration else {
                    MessengerDiagnostics.event(
                        .messengerMessageLoadStaleIgnored,
                        conversationID: conversationID,
                        metadata: ["source": "rest"]
                    )
                    return
                }
                let mapped = response.messages.map {
                    ChatUIMapping.message(from: $0, currentProfileID: profileID)
                }
                mergeLoadedMessages(mapped, for: conversationID)
                updateOlderMessagesCursor(
                    conversationID: conversationID,
                    response: response,
                    fetchedMessages: mapped
                )
                await MessengerMessageCacheService.persistRESTMessages(
                    response.messages,
                    conversationID: conversationID
                )
                MessengerDiagnostics.event(
                    .messengerMessageNetworkRefreshSucceeded,
                    conversationID: conversationID,
                    metadata: [
                        "count": "\(mapped.count)",
                        "durationMs": "\(durationMilliseconds(since: startedAt))",
                        "source": "rest"
                    ]
                )
            } catch is CancellationError {
                MessengerDiagnostics.event(
                    .messengerMessageLoadCancelled,
                    conversationID: conversationID,
                    metadata: ["source": "rest"]
                )
            } catch let error as NetworkError {
                if loadGenerations[conversationID] == loadGeneration {
                    if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                        entries[conversationID]?.errorMessage = message
                    } else {
                        entries[conversationID]?.errorMessage = error.userMessage
                    }
                }
                MessengerDiagnostics.event(
                    .messengerMessageNetworkRefreshFailed,
                    conversationID: conversationID,
                    metadata: [
                        "errorCategory": MessengerDiagnostics.sanitizeError(error),
                        "durationMs": "\(durationMilliseconds(since: startedAt))",
                        "source": "rest"
                    ]
                )
            } catch {
                if loadGenerations[conversationID] == loadGeneration {
                    entries[conversationID]?.errorMessage = error.localizedDescription
                }
                MessengerDiagnostics.event(
                    .messengerMessageNetworkRefreshFailed,
                    conversationID: conversationID,
                    metadata: [
                        "errorCategory": MessengerDiagnostics.sanitizeError(error),
                        "durationMs": "\(durationMilliseconds(since: startedAt))",
                        "source": "rest"
                    ]
                )
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
        router: AppRouter,
        loadGeneration: Int = 0
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
        let startedAt = Date()
        MessengerDiagnostics.event(
            .messengerMessagePaginationStarted,
            conversationID: conversationID,
            metadata: ["source": "pagination"]
        )

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            let response = try await MessageService.fetchMessages(
                conversationID: conversationID,
                limit: limit,
                before: before
            )
            guard !Task.isCancelled,
                  loadGenerations[conversationID] == loadGeneration else {
                MessengerDiagnostics.event(
                    .messengerMessageLoadStaleIgnored,
                    conversationID: conversationID,
                    metadata: ["source": "pagination"]
                )
                return false
            }
            let mapped = response.messages.map {
                ChatUIMapping.message(from: $0, currentProfileID: profileID)
            }
            mergeLoadedMessages(mapped, for: conversationID)
            updateOlderMessagesCursor(
                conversationID: conversationID,
                response: response,
                fetchedMessages: mapped
            )
            await MessengerMessageCacheService.persistPaginationMessages(
                response.messages,
                conversationID: conversationID
            )
            let nextCursorLabel = entries[conversationID]?.olderMessagesCursor.map { String($0.prefix(8)) } ?? "nil"
            NetworkDebug.log("Older messages loaded incoming=\(mapped.count) total=\(entries[conversationID]?.messages.count ?? 0) nextCursor=\(nextCursorLabel)")
            MessengerDiagnostics.event(
                .messengerMessagePaginationSucceeded,
                conversationID: conversationID,
                metadata: [
                    "count": "\(mapped.count)",
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "source": "pagination"
                ]
            )
        } catch is CancellationError {
            MessengerDiagnostics.event(
                .messengerMessageLoadCancelled,
                conversationID: conversationID,
                metadata: ["source": "pagination"]
            )
            return false
        } catch let error as NetworkError {
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                entries[conversationID]?.errorMessage = message
            } else {
                entries[conversationID]?.errorMessage = error.userMessage
            }
            MessengerDiagnostics.event(
                .messengerMessagePaginationFailed,
                conversationID: conversationID,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "source": "pagination"
                ]
            )
            return false
        } catch {
            entries[conversationID]?.errorMessage = error.localizedDescription
            MessengerDiagnostics.event(
                .messengerMessagePaginationFailed,
                conversationID: conversationID,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "source": "pagination"
                ]
            )
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
        if message.isMine {
            switch reconcileOutgoingMessage(message, conversationID: conversationID, source: .realtime) {
            case .reconciled(let applied):
                return applied
            case .ambiguousPending:
                if entries[conversationID]?.messages.contains(where: { $0.id == message.id }) == true {
                    break
                }
                MessengerDiagnostics.event(
                    .realtimeEventSkipped,
                    conversationID: conversationID,
                    messageID: message.id,
                    clientMessageID: message.clientMessageID,
                    metadata: [
                        "reason": "ambiguousPendingOutgoing",
                        "pendingCount": "\(outgoingPendingCount(for: conversationID))"
                    ]
                )
                return false
            case .noMatch:
                break
            }
        }

        var entry = entries[conversationID] ?? Entry(messages: [], loadedAt: .now)

        if let index = entry.messages.firstIndex(where: { $0.id == message.id }) {
            guard entry.messages[index] != message else { return false }
            entry.messages[index] = message
            entry.messages = sortedMessages(entry.messages)
            entry.loadedAt = .now
            entries[conversationID] = entry
            return false
        }

        entry.messages.append(message)
        entry.messages = sortedMessages(entry.messages)
        entry.loadedAt = .now
        entries[conversationID] = entry
        return true
    }

    @discardableResult
    private func reconcileOutgoingMessage(
        _ message: ChatMessage,
        conversationID: UUID,
        source: ReconciliationSource
    ) -> OutgoingReconcileResult {
        guard message.isMine else { return .noMatch }

        let pending = pendingOutgoingMessages(for: conversationID)

        if let clientMessageID = message.clientMessageID,
           pending.contains(where: { $0.clientMessageID == clientMessageID }) {
            let applied = replaceOptimisticMessage(
                clientMessageID: clientMessageID,
                with: message,
                conversationID: conversationID,
                source: source
            )
            return .reconciled(applied)
        }

        guard pending.count == 1,
              let clientMessageID = pending[0].clientMessageID else {
            if pending.count > 1 {
                return .ambiguousPending
            }
            return .noMatch
        }

        let applied = replaceOptimisticMessage(
            clientMessageID: clientMessageID,
            with: message,
            conversationID: conversationID,
            source: source
        )
        return .reconciled(applied)
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

        for message in existingMessages where message.localSendState == nil {
            mergedByID[message.id] = message
        }
        for message in loadedMessages {
            if let clientMessageID = message.clientMessageID,
               let pending = existingMessages.first(where: {
                   $0.clientMessageID == clientMessageID && $0.localSendState != nil
               }) {
                mergedByID.removeValue(forKey: pending.id)
                let merged = mergeLoadedMessage(
                    message,
                    withExisting: pending.replacingLocalSendState(nil)
                )
                mergedByID[message.id] = merged
                MessengerOutbox.shared.markSent(clientMessageID: clientMessageID, serverMessageID: message.id)
                continue
            }

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

        let preservedPending = existingMessages.filter { pending in
            guard pending.localSendState != nil else { return false }
            if let clientMessageID = pending.clientMessageID,
               loadedMessages.contains(where: { $0.clientMessageID == clientMessageID || MessengerOutbox.shared.serverMessageID(for: clientMessageID) == $0.id }) {
                return false
            }
            if loadedMessages.contains(where: { $0.id == pending.id }) {
                return false
            }
            mergedByID[pending.id] = pending
            return true
        }

        if !preservedPending.isEmpty {
            MessengerDiagnostics.event(
                .outboxPreservedDuringFetch,
                conversationID: conversationID,
                metadata: ["preservedCount": "\(preservedPending.count)"]
            )
        }

        let merged = sortedMessages(Array(mergedByID.values))

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

        // Any ChatViewModel currently open for this conversation (including one that didn't
        // itself trigger this fetch, e.g. because it deduplicated against an in-flight load)
        // must still learn about the new cache contents, otherwise it can be left showing an
        // empty/stale list until an unrelated action forces a resync.
        MessengerConversationNotification.postMessagesDidChange(conversationID: conversationID)
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
        guard message.isMine, !message.isDeleted, message.localSendState == nil else { return false }
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
        loadGenerations.removeAll()
        entries.removeAll()
    }

    private func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
