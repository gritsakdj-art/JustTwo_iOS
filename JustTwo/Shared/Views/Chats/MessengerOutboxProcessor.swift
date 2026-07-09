import Foundation

@MainActor
final class MessengerOutboxProcessor {

    static let shared = MessengerOutboxProcessor()

    private var networkHandlerID: UUID?
    private var isRecovering = false

    private init() {}

    func activate(session: SessionStore, router: AppRouter) {
        guard networkHandlerID == nil else { return }
        networkHandlerID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.processReadyItems(session: session, router: router)
            }
        }
    }

    func deactivate() {
        if let networkHandlerID {
            NetworkPathMonitor.shared.unregisterHandler(networkHandlerID)
            self.networkHandlerID = nil
        }
    }

    func recoverOnLaunch() async {
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }

        do {
            let resetCount = try await localStore.resetStaleOutboxSendingItems()
            if resetCount > 0 {
                MessengerDiagnostics.event(
                    .outboxReset,
                    metadata: [
                        "reason": "staleSending",
                        "count": "\(resetCount)"
                    ]
                )
            }
        } catch {
            MessengerDiagnostics.event(
                .outboxReset,
                metadata: [
                    "reason": "staleSendingFailed",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
        }

        do {
            let validPaths = try await localStore.fetchPendingMediaRelativePaths()
            let prunedCount = MessengerPendingMediaStore.pruneOrphans(validRelativePaths: validPaths)
            if prunedCount > 0 {
                MessengerDiagnostics.event(
                    .outboxPendingMediaCleared,
                    metadata: [
                        "reason": "pruneOrphans",
                        "count": "\(prunedCount)"
                    ]
                )
            }
        } catch {
            MessengerDiagnostics.event(
                .outboxPendingMediaCleared,
                metadata: [
                    "reason": "pruneOrphansFailed",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
        }
    }

    func reconcileConversation(
        conversationID: UUID,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async {
        guard session.isFullyAuthenticated else { return }
        await recoverOnLaunch()

        do {
            let outboxItems = try await localStore.fetchOutboxItems(conversationID: conversationID)
            let activeItems = outboxItems.filter { item in
                switch item.status {
                case .pending, .sending, .failed:
                    return true
                case .sent, .cancelled:
                    return false
                }
            }

            guard !activeItems.isEmpty else { return }

            let cachedMessages = MessageCacheStore.shared.messages(for: conversationID) ?? []
            var insertedCount = 0
            var imageRehydratedCount = 0

            for item in activeItems {
                if let serverMessageID = item.serverMessageID,
                   cachedMessages.contains(where: { $0.id.uuidString == serverMessageID }) {
                    try? await localStore.deleteOutboxItem(clientMessageID: item.clientMessageID)
                    MessengerDiagnostics.event(
                        .outboxItemCleared,
                        conversationID: conversationID,
                        clientMessageID: item.clientMessageID,
                        metadata: ["reason": "alreadyConfirmed"]
                    )
                    continue
                }

                if cachedMessages.contains(where: {
                    $0.clientMessageID == item.clientMessageID && $0.localSendState == nil
                }) {
                    try? await localStore.deleteOutboxItem(clientMessageID: item.clientMessageID)
                    MessengerDiagnostics.event(
                        .outboxItemCleared,
                        conversationID: conversationID,
                        clientMessageID: item.clientMessageID,
                        metadata: ["reason": "confirmedInCache"]
                    )
                    continue
                }

                if cachedMessages.contains(where: { $0.clientMessageID == item.clientMessageID }) {
                    await rehydrateInMemoryOutboxItem(
                        item: item,
                        localMessageID: OptimisticMessageIdentity.localMessageID(for: item.clientMessageID),
                        session: session,
                        router: router
                    )
                    continue
                }

                let replyPreview = replyPreview(from: item, messages: cachedMessages)
                let localState: MessageLocalSendState = item.status == .failed ? .failed : .sending

                switch item.kind {
                case .text:
                    let optimistic = ChatMessage.optimisticOutgoing(
                        clientMessageID: item.clientMessageID,
                        body: item.body,
                        replyPreview: replyPreview,
                        createdAt: item.createdAt
                    ).replacingLocalSendState(localState)

                    MessageCacheStore.shared.insertOptimisticMessage(optimistic, for: conversationID)
                    MessengerOutbox.shared.rehydrateTextItem(
                        snapshot: item,
                        localMessageID: optimistic.id,
                        session: session,
                        router: router
                    )
                    insertedCount += 1

                case .image:
                    guard let prepared = try await loadPreparedImage(for: item) else {
                        try? await localStore.markOutboxFailed(
                            clientMessageID: item.clientMessageID,
                            errorCode: "pendingMediaMissing",
                            nextRetryAt: nil
                        )
                        MessengerDiagnostics.event(
                            .outboxPendingMediaMissing,
                            conversationID: conversationID,
                            clientMessageID: item.clientMessageID,
                            metadata: [
                                "pendingMediaID": item.pendingMediaID.map {
                                    MessengerPendingMediaStore.sanitizedPendingMediaIDForDiagnostics($0)
                                } ?? "none"
                            ]
                        )
                        continue
                    }

                    let caption = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedCaption = caption.isEmpty ? nil : caption
                    let optimistic = ChatMessage.optimisticOutgoingImage(
                        clientMessageID: item.clientMessageID,
                        prepared: prepared,
                        replyPreview: replyPreview,
                        caption: normalizedCaption,
                        createdAt: item.createdAt
                    ).replacingLocalSendState(localState)

                    MessageCacheStore.shared.insertOptimisticMessage(optimistic, for: conversationID)
                    MessengerOutbox.shared.rehydrateImageItem(
                        snapshot: item,
                        prepared: prepared,
                        localMessageID: optimistic.id,
                        session: session,
                        router: router
                    )
                    insertedCount += 1
                    imageRehydratedCount += 1
                }
            }

            if insertedCount > 0 {
                MessengerDiagnostics.event(
                    .outboxRehydrated,
                    conversationID: conversationID,
                    metadata: ["count": "\(insertedCount)"]
                )
            }
            if imageRehydratedCount > 0 {
                MessengerDiagnostics.event(
                    .outboxImageRehydrated,
                    conversationID: conversationID,
                    metadata: ["count": "\(imageRehydratedCount)"]
                )
            }
            if insertedCount > 0 || imageRehydratedCount > 0 {
                MessengerConversationNotification.postMessagesDidChange(conversationID: conversationID)
            }

            await processReadyItems(
                session: session,
                router: router,
                conversationID: conversationID
            )
        } catch {
            MessengerDiagnostics.event(
                .outboxRehydrated,
                conversationID: conversationID,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "count": "0"
                ]
            )
        }
    }

    func manualRetry(
        clientMessageID: String,
        session: SessionStore,
        router: AppRouter
    ) async {
        MessengerDiagnostics.event(
            .outboxManualRetry,
            clientMessageID: clientMessageID
        )

        MessengerOutbox.shared.retry(
            clientMessageID: clientMessageID,
            session: session,
            router: router,
            isManual: true
        )
    }

    func processReadyItems(
        session: SessionStore,
        router: AppRouter,
        conversationID: UUID? = nil
    ) async {
        guard session.isFullyAuthenticated else { return }
        if NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline {
            return
        }

        do {
            let pendingItems = try await localStore.fetchPendingOutboxItems()
            let readyItems = pendingItems.filter { item in
                guard item.kind == .text || item.kind == .image else { return false }
                if MessengerOutbox.shared.entry(for: item.clientMessageID)?.state == .sending {
                    return false
                }
                if let conversationID {
                    return item.conversationID == conversationID.uuidString
                }
                return true
            }

            for item in readyItems {
                guard let conversationUUID = UUID(uuidString: item.conversationID) else { continue }

                await rehydrateInMemoryOutboxItem(
                    item: item,
                    localMessageID: OptimisticMessageIdentity.localMessageID(for: item.clientMessageID),
                    session: session,
                    router: router
                )

                _ = conversationUUID
            }

            let conversationIDs = Set(readyItems.compactMap { UUID(uuidString: $0.conversationID) })
            for id in conversationIDs {
                MessengerOutbox.shared.pumpConversationQueue(
                    conversationID: id,
                    session: session,
                    router: router
                )
            }
        } catch {
            MessengerDiagnostics.event(
                .outboxRetryScheduled,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
        }
    }

    func clearOutboxOnLogout() async {
        do {
            try await localStore.clearPendingMedia()
            try await localStore.clearOutbox()
            MessengerDiagnostics.event(.outboxReset, metadata: ["reason": "logout"])
        } catch {
            MessengerDiagnostics.event(
                .outboxReset,
                metadata: [
                    "reason": "logoutFailed",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
        }
    }

    private var localStore: MessengerLocalStore {
        #if DEBUG
        if let testingStore = MessengerMessageCacheService.testingStore {
            return testingStore
        }
        #endif
        return .shared
    }

    private func rehydrateInMemoryOutboxItem(
        item: MessengerOutboxItemSnapshot,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async {
        switch item.kind {
        case .text:
            MessengerOutbox.shared.rehydrateTextItem(
                snapshot: item,
                localMessageID: localMessageID,
                session: session,
                router: router
            )
        case .image:
            guard let prepared = try? await loadPreparedImage(for: item) else { return }
            MessengerOutbox.shared.rehydrateImageItem(
                snapshot: item,
                prepared: prepared,
                localMessageID: localMessageID,
                session: session,
                router: router
            )
        }
    }

    private func loadPreparedImage(for item: MessengerOutboxItemSnapshot) async throws -> PreparedChatImage? {
        if let mediaSnapshot = try await localStore.fetchPendingMedia(clientMessageID: item.clientMessageID) {
            return try ChatImagePreparer.preparedFromPendingMedia(mediaSnapshot)
        }
        if let pendingMediaID = item.pendingMediaID,
           let mediaSnapshot = try await localStore.fetchPendingMedia(pendingMediaID: pendingMediaID) {
            return try ChatImagePreparer.preparedFromPendingMedia(mediaSnapshot)
        }
        return nil
    }

    private func replyPreview(
        from item: MessengerOutboxItemSnapshot,
        messages: [ChatMessage]
    ) -> ChatReplyPreview? {
        guard let replyIDString = item.replyToMessageID,
              let replyID = UUID(uuidString: replyIDString) else {
            return nil
        }

        if let replyMessage = messages.first(where: { $0.id == replyID }) {
            return ChatReplyPreview(
                id: replyID,
                body: replyMessage.displayText,
                isDeleted: replyMessage.isDeleted
            )
        }

        return ChatReplyPreview(id: replyID, body: "", isDeleted: false)
    }
}
