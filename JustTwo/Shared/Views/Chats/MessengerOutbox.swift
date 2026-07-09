import Foundation

@MainActor
final class MessengerOutbox {

    static let shared = MessengerOutbox()

    struct Entry: Equatable, Identifiable {
        let clientMessageID: String
        let conversationID: UUID
        let payload: Payload
        let localMessageID: UUID
        let createdAt: Date
        var state: State
        var lastError: String?
        var serverMessageID: UUID?

        var id: String { clientMessageID }
    }

    enum Payload: Equatable {
        case text(TextPayload)
        case image(ImagePayload)

        var replyToID: UUID? {
            switch self {
            case .text(let payload): return payload.replyToID
            case .image(let payload): return payload.replyToID
            }
        }

        var kindName: String {
            switch self {
            case .text: return "text"
            case .image: return "image"
            }
        }

        var textBody: String? {
            switch self {
            case .text(let payload): return payload.body
            case .image: return nil
            }
        }

        var localFileURL: URL? {
            switch self {
            case .text: return nil
            case .image(let payload): return payload.prepared.localFileURL
            }
        }
    }

    struct TextPayload: Equatable {
        let body: String
        let replyToID: UUID?
    }

    struct ImagePayload: Equatable {
        let prepared: PreparedChatImage
        let replyToID: UUID?
        let caption: String?
    }

    enum State: Equatable {
        case queued
        case sending
        case sent
        case failed
    }

    private var entries: [String: Entry] = [:]
    private var sendTasks: [String: Task<Void, Never>] = [:]
    private var conversationQueues: [UUID: [String]] = [:]

    private init() {}

    func entry(for clientMessageID: String) -> Entry? {
        entries[clientMessageID]
    }

    func entries(for conversationID: UUID) -> [Entry] {
        entries.values
            .filter { $0.conversationID == conversationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func pendingCount(for conversationID: UUID) -> Int {
        entries(for: conversationID).filter { $0.state == .queued || $0.state == .sending || $0.state == .failed }.count
    }

    func serverMessageID(for clientMessageID: String) -> UUID? {
        entries[clientMessageID]?.serverMessageID
    }

    func enqueue(
        conversationID: UUID,
        body: String,
        replyToID: UUID?,
        clientMessageID: String,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        registerPersistedTextEntry(
            snapshot: MessengerOutboxItemSnapshot(
                id: UUID().uuidString,
                conversationID: conversationID.uuidString,
                clientMessageID: clientMessageID,
                kind: .text,
                body: body,
                replyToMessageID: replyToID?.uuidString,
                status: .pending,
                attemptCount: 0,
                lastErrorCode: nil,
                nextRetryAt: .now,
                createdAt: .now,
                updatedAt: .now,
                lastAttemptAt: nil,
                serverMessageID: nil,
                pendingMediaID: nil
            ),
            localMessageID: localMessageID,
            session: session,
            router: router
        )
    }

    func registerPersistedTextEntry(
        snapshot: MessengerOutboxItemSnapshot,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        guard snapshot.kind == .text,
              let conversationID = UUID(uuidString: snapshot.conversationID) else {
            return
        }

        enqueueEntry(
            conversationID: conversationID,
            payload: .text(TextPayload(
                body: snapshot.body,
                replyToID: snapshot.replyToMessageID.flatMap(UUID.init(uuidString:))
            )),
            clientMessageID: snapshot.clientMessageID,
            localMessageID: localMessageID,
            session: session,
            router: router,
            skipTextPersistence: true
        )
    }

    func registerPersistedImageEntry(
        snapshot: MessengerOutboxItemSnapshot,
        prepared: PreparedChatImage,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        guard snapshot.kind == .image,
              let conversationID = UUID(uuidString: snapshot.conversationID) else {
            return
        }

        let caption = snapshot.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCaption = caption.isEmpty ? nil : caption

        enqueueEntry(
            conversationID: conversationID,
            payload: .image(ImagePayload(
                prepared: prepared,
                replyToID: snapshot.replyToMessageID.flatMap(UUID.init(uuidString:)),
                caption: normalizedCaption
            )),
            clientMessageID: snapshot.clientMessageID,
            localMessageID: localMessageID,
            session: session,
            router: router,
            skipPersistence: true
        )
    }

    func enqueueImage(
        conversationID: UUID,
        prepared: PreparedChatImage,
        replyToID: UUID?,
        caption: String? = nil,
        clientMessageID: String,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        enqueueEntry(
            conversationID: conversationID,
            payload: .image(ImagePayload(prepared: prepared, replyToID: replyToID, caption: caption)),
            clientMessageID: clientMessageID,
            localMessageID: localMessageID,
            session: session,
            router: router
        )
    }

    private func enqueueEntry(
        conversationID: UUID,
        payload: Payload,
        clientMessageID: String,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter,
        skipTextPersistence: Bool = false,
        skipPersistence: Bool = false
    ) {
        let shouldSkipPersistence = skipPersistence || skipTextPersistence
        guard entries[clientMessageID] == nil else { return }

        let entry = Entry(
            clientMessageID: clientMessageID,
            conversationID: conversationID,
            payload: payload,
            localMessageID: localMessageID,
            createdAt: .now,
            state: .queued,
            lastError: nil,
            serverMessageID: nil
        )
        entries[clientMessageID] = entry
        conversationQueues[conversationID, default: []].append(clientMessageID)

        MessengerDiagnostics.event(
            .outboxEnqueued,
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "pendingCount": "\(pendingCount(for: conversationID))",
                "state": "queued",
                "kind": payload.kindName
            ]
        )

        if case .text = payload, !shouldSkipPersistence {
            Task {
                do {
                    _ = try await MessengerLocalStore.shared.createTextOutboxItem(
                        conversationID: conversationID,
                        clientMessageID: clientMessageID,
                        body: payload.textBody ?? "",
                        replyToMessageID: payload.replyToID
                    )
                    MessengerDiagnostics.event(
                        .outboxItemCreated,
                        conversationID: conversationID,
                        clientMessageID: clientMessageID,
                        metadata: ["kind": "text"]
                    )
                } catch {
                    MessengerDiagnostics.event(
                        .outboxItemCreated,
                        conversationID: conversationID,
                        clientMessageID: clientMessageID,
                        metadata: [
                            "kind": "text",
                            "errorCategory": MessengerDiagnostics.sanitizeError(error)
                        ]
                    )
                }
                pumpConversationQueueInternal(conversationID: conversationID, session: session, router: router)
            }
        } else {
            pumpConversationQueueInternal(conversationID: conversationID, session: session, router: router)
        }
    }

    func retry(
        clientMessageID: String,
        session: SessionStore,
        router: AppRouter,
        isManual: Bool = false
    ) {
        guard var entry = entries[clientMessageID] else { return }

        let canRetry: Bool
        if isManual {
            canRetry = entry.state == .failed || entry.state == .queued
        } else {
            canRetry = entry.state == .failed
        }
        guard canRetry else { return }

        guard sendTasks[clientMessageID] == nil else {
            MessengerDiagnostics.event(
                .outboxRetrySkipped,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID,
                metadata: [
                    "kind": entry.payload.kindName,
                    "retryReason": isManual ? "manual" : "auto"
                ]
            )
            return
        }

        entry.state = .queued
        entry.lastError = nil
        entries[clientMessageID] = entry

        let presentationState: MessageLocalSendState = isManual ? .retrying : .sending
        _ = MessageCacheStore.shared.updateOptimisticMessageState(
            clientMessageID: clientMessageID,
            conversationID: entry.conversationID,
            state: presentationState
        )
        MessengerConversationNotification.postMessagesDidChange(conversationID: entry.conversationID)

        let event: MessengerDiagnosticEvent = isManual
            ? .outboxRetryTapped
            : (entry.payload.kindName == "image" ? .imageOutboxRetryRequested : .outboxRetryRequested)
        MessengerDiagnostics.event(
            event,
            conversationID: entry.conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "kind": entry.payload.kindName,
                "retryReason": isManual ? "manual" : "auto"
            ]
        )

        Task {
            try? await MessengerLocalStore.shared.markOutboxPending(clientMessageID: clientMessageID)
            pumpConversationQueue(conversationID: entry.conversationID, session: session, router: router)
        }
    }

    func cancelPending(clientMessageID: String) {
        sendTasks[clientMessageID]?.cancel()
        sendTasks.removeValue(forKey: clientMessageID)

        if let entry = entries.removeValue(forKey: clientMessageID) {
            conversationQueues[entry.conversationID]?.removeAll { $0 == clientMessageID }
            MessengerDiagnostics.event(
                .outboxCancelTapped,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID,
                metadata: ["kind": entry.payload.kindName]
            )
        }
    }

    func outgoingEntryState(for clientMessageID: String) -> State? {
        entries[clientMessageID]?.state
    }

    func updateOutgoingPresentation(
        clientMessageID: String,
        conversationID: UUID,
        state: MessageLocalSendState
    ) {
        let updated = MessageCacheStore.shared.updateOptimisticMessageState(
            clientMessageID: clientMessageID,
            conversationID: conversationID,
            state: state
        )
        guard updated else { return }

        MessengerDiagnostics.event(
            .outboxStateChanged,
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            metadata: ["status": OutgoingMessageStatus.diagnosticName(for: state)]
        )
        MessengerConversationNotification.postMessagesDidChange(conversationID: conversationID)
    }

    func rehydrateImageItem(
        snapshot: MessengerOutboxItemSnapshot,
        prepared: PreparedChatImage,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        guard snapshot.kind == .image else { return }
        guard entries[snapshot.clientMessageID] == nil else { return }
        guard let conversationID = UUID(uuidString: snapshot.conversationID) else { return }

        let state: State
        switch snapshot.status {
        case .pending:
            state = .queued
        case .sending:
            state = .sending
        case .failed:
            state = .failed
        case .sent, .cancelled:
            return
        }

        let caption = snapshot.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCaption = caption.isEmpty ? nil : caption

        let entry = Entry(
            clientMessageID: snapshot.clientMessageID,
            conversationID: conversationID,
            payload: .image(ImagePayload(
                prepared: prepared,
                replyToID: snapshot.replyToMessageID.flatMap(UUID.init(uuidString:)),
                caption: normalizedCaption
            )),
            localMessageID: localMessageID,
            createdAt: snapshot.createdAt,
            state: state,
            lastError: snapshot.lastErrorCode,
            serverMessageID: snapshot.serverMessageID.flatMap(UUID.init(uuidString:))
        )
        entries[snapshot.clientMessageID] = entry
        if !conversationQueues[conversationID, default: []].contains(snapshot.clientMessageID) {
            conversationQueues[conversationID, default: []].append(snapshot.clientMessageID)
        }
    }

    func rehydrateTextItem(
        snapshot: MessengerOutboxItemSnapshot,
        localMessageID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        guard snapshot.kind == .text else { return }
        guard entries[snapshot.clientMessageID] == nil else { return }
        guard let conversationID = UUID(uuidString: snapshot.conversationID) else { return }

        let state: State
        switch snapshot.status {
        case .pending:
            state = .queued
        case .sending:
            state = .sending
        case .failed:
            state = .failed
        case .sent, .cancelled:
            return
        }

        let entry = Entry(
            clientMessageID: snapshot.clientMessageID,
            conversationID: conversationID,
            payload: .text(TextPayload(
                body: snapshot.body,
                replyToID: snapshot.replyToMessageID.flatMap(UUID.init(uuidString:))
            )),
            localMessageID: localMessageID,
            createdAt: snapshot.createdAt,
            state: state,
            lastError: snapshot.lastErrorCode,
            serverMessageID: snapshot.serverMessageID.flatMap(UUID.init(uuidString:))
        )
        entries[snapshot.clientMessageID] = entry
        if !conversationQueues[conversationID, default: []].contains(snapshot.clientMessageID) {
            conversationQueues[conversationID, default: []].append(snapshot.clientMessageID)
        }
    }

    func pumpConversationQueue(
        conversationID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        pumpConversationQueueInternal(conversationID: conversationID, session: session, router: router)
    }

    func markSent(clientMessageID: String, serverMessageID: UUID) {
        guard var entry = entries[clientMessageID] else { return }
        entry.state = .sent
        entry.serverMessageID = serverMessageID
        entry.lastError = nil
        entries[clientMessageID] = entry
    }

    func remove(clientMessageID: String) {
        if let entry = entries.removeValue(forKey: clientMessageID) {
            conversationQueues[entry.conversationID]?.removeAll { $0 == clientMessageID }
        }
        sendTasks[clientMessageID]?.cancel()
        sendTasks.removeValue(forKey: clientMessageID)
    }

    func clear(reason: String = "logout") {
        for task in sendTasks.values {
            task.cancel()
        }
        sendTasks.removeAll()
        for entry in entries.values {
            if case .image = entry.payload {
                continue
            }
            if let fileURL = entry.payload.localFileURL {
                ChatImagePreparer.removeTemporaryFile(fileURL)
            }
        }
        ChatImagePreparer.cleanupTemporaryDirectory()
        entries.removeAll()
        conversationQueues.removeAll()

        MessengerDiagnostics.event(
            .outboxClearedOnLogout,
            metadata: ["reason": reason]
        )
    }

    private func pumpConversationQueueInternal(
        conversationID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        guard session.isFullyAuthenticated else { return }
        guard sendTasks.values.allSatisfy({ !$0.isCancelled }) else { return }

        let hasInFlight = entries.values.contains {
            $0.conversationID == conversationID && $0.state == .sending
        }
        guard !hasInFlight else { return }

        guard let nextClientMessageID = conversationQueues[conversationID]?.first(where: { id in
            entries[id]?.state == .queued && sendTasks[id] == nil
        }) else {
            return
        }

        startSend(clientMessageID: nextClientMessageID, session: session, router: router)
    }

    private func startSend(
        clientMessageID: String,
        session: SessionStore,
        router: AppRouter
    ) {
        guard session.isFullyAuthenticated else { return }
        guard let entry = entries[clientMessageID], entry.state != .sent else { return }
        guard sendTasks[clientMessageID] == nil else { return }

        entries[clientMessageID]?.state = .sending
        updateOutgoingPresentation(
            clientMessageID: clientMessageID,
            conversationID: entry.conversationID,
            state: .sending
        )

        if entry.payload.kindName == "text" || entry.payload.kindName == "image" {
            Task {
                try? await MessengerLocalStore.shared.markOutboxSending(clientMessageID: clientMessageID)
            }
        }

        MessengerDiagnostics.event(
            .outboxSendStarted,
            conversationID: entry.conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "pendingCount": "\(pendingCount(for: entry.conversationID))",
                "kind": entry.payload.kindName
            ]
        )

        let startedAt = Date()
        sendTasks[clientMessageID] = Task { @MainActor [weak self] in
            defer {
                self?.sendTasks.removeValue(forKey: clientMessageID)
            }

            guard let self, let currentEntry = self.entries[clientMessageID] else { return }

            do {
                let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
                let dto = try await self.send(
                    entry: currentEntry,
                    clientMessageID: clientMessageID,
                    session: session
                )

                guard !Task.isCancelled else { return }

                let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
                let reconciled = MessageCacheStore.shared.replaceOptimisticMessage(
                    clientMessageID: clientMessageID,
                    with: mapped,
                    conversationID: currentEntry.conversationID,
                    source: .rest
                )

                self.markSent(clientMessageID: clientMessageID, serverMessageID: mapped.id)

                if currentEntry.payload.kindName == "text" || currentEntry.payload.kindName == "image" {
                    Task {
                        do {
                            try await MessengerLocalStore.shared.deleteOutboxItem(clientMessageID: clientMessageID)
                            let event: MessengerDiagnosticEvent = currentEntry.payload.kindName == "image"
                                ? .outboxPendingMediaCleared
                                : .outboxItemCleared
                            MessengerDiagnostics.event(
                                event,
                                conversationID: currentEntry.conversationID,
                                clientMessageID: clientMessageID,
                                metadata: ["reason": "sendSucceeded"]
                            )
                        } catch {
                            MessengerDiagnostics.event(
                                .outboxItemCleared,
                                conversationID: currentEntry.conversationID,
                                clientMessageID: clientMessageID,
                                metadata: [
                                    "reason": "sendSucceededDeleteFailed",
                                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                                ]
                            )
                        }
                    }
                }

                ConversationListViewModel.shared.applyOutgoingConfirmed(
                    conversationID: currentEntry.conversationID,
                    message: dto,
                    currentProfileID: profileID
                )

                MessengerDiagnostics.event(
                    .outboxProcessorItemSucceeded,
                    conversationID: currentEntry.conversationID,
                    messageID: mapped.id,
                    clientMessageID: clientMessageID,
                    metadata: [
                        "durationMs": "\(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))",
                        "reconciled": "\(reconciled)",
                        "kind": currentEntry.payload.kindName
                    ]
                )

                MessengerDiagnostics.event(
                    .outboxSendSucceeded,
                    conversationID: currentEntry.conversationID,
                    messageID: mapped.id,
                    clientMessageID: clientMessageID,
                    metadata: [
                        "durationMs": "\(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))",
                        "reconciled": "\(reconciled)",
                        "kind": currentEntry.payload.kindName
                    ]
                )

                if reconciled {
                    MessengerDiagnostics.event(
                        .outboxReconciledFromREST,
                        conversationID: currentEntry.conversationID,
                        messageID: mapped.id,
                        clientMessageID: clientMessageID
                    )
                }

                MessengerConversationNotification.postMessagesDidChange(conversationID: currentEntry.conversationID)

                self.pumpConversationQueueInternal(
                    conversationID: currentEntry.conversationID,
                    session: session,
                    router: router
                )
            } catch let error as NetworkError {
                guard !Task.isCancelled else { return }
                self.handleSendFailure(
                    clientMessageID: clientMessageID,
                    error: error,
                    startedAt: startedAt,
                    session: session,
                    router: router
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.handleSendFailure(
                    clientMessageID: clientMessageID,
                    error: error,
                    startedAt: startedAt,
                    session: session,
                    router: router
                )
            }
        }
    }

    private func send(
        entry: Entry,
        clientMessageID: String,
        session: SessionStore
    ) async throws -> MessageDTO {
        switch entry.payload {
        case .text(let payload):
            return try await MessageService.sendMessage(
                conversationID: entry.conversationID,
                body: payload.body,
                replyToID: payload.replyToID,
                clientMessageID: clientMessageID
            )
        case .image(let payload):
            MessengerDiagnostics.event(
                .imageUploadURLRequested,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID,
                metadata: imageMetadata(payload.prepared)
            )
            let upload: MessageAttachmentUploadDTO
            do {
                upload = try await MessageService.createAttachmentUpload(
                    conversationID: entry.conversationID,
                    contentType: payload.prepared.contentType,
                    byteSize: payload.prepared.byteSize,
                    width: payload.prepared.width,
                    height: payload.prepared.height
                )
                MessengerDiagnostics.event(
                    .imageUploadURLSucceeded,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["method": upload.method]
                )
            } catch {
                MessengerDiagnostics.event(
                    .imageUploadURLFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
                )
                throw error
            }

            updateOutgoingPresentation(
                clientMessageID: clientMessageID,
                conversationID: entry.conversationID,
                state: .uploading
            )
            MessengerDiagnostics.event(
                .outboxImageUploadStarted,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID,
                metadata: imageMetadata(payload.prepared)
            )
            MessengerDiagnostics.event(
                .imageUploadStarted,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID,
                metadata: imageMetadata(payload.prepared)
            )
            do {
                try await ObjectStorageUploader.upload(
                    fileURL: payload.prepared.localFileURL,
                    uploadURL: upload.uploadUrl,
                    method: upload.method,
                    headers: upload.headers
                )
                MessengerDiagnostics.event(
                    .outboxImageUploadSucceeded,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID
                )
                MessengerDiagnostics.event(
                    .imageUploadSucceeded,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID
                )
            } catch {
                let errorCode = MessengerOutboxErrorCode.classifyUploadFailure(error).rawValue
                MessengerDiagnostics.event(
                    .outboxImageUploadFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCode": errorCode]
                )
                MessengerDiagnostics.event(
                    .imageUploadFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": errorCode]
                )
                throw error
            }

            updateOutgoingPresentation(
                clientMessageID: clientMessageID,
                conversationID: entry.conversationID,
                state: .sending
            )
            MessengerDiagnostics.event(
                .outboxImageCreateMessageStarted,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID,
                metadata: ["optionalNotePresent": payload.caption == nil ? "false" : "true"]
            )
            MessengerDiagnostics.event(
                .imageMessageCreateStarted,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID
            )
            do {
                let dto = try await MessageService.sendImageMessage(
                    conversationID: entry.conversationID,
                    attachmentUploadID: upload.id,
                    body: payload.caption,
                    replyToID: payload.replyToID,
                    clientMessageID: clientMessageID
                )
                MessengerDiagnostics.event(
                    .outboxImageCreateMessageSucceeded,
                    conversationID: entry.conversationID,
                    messageID: dto.id,
                    clientMessageID: clientMessageID
                )
                MessengerDiagnostics.event(
                    .imageMessageCreateSucceeded,
                    conversationID: entry.conversationID,
                    messageID: dto.id,
                    clientMessageID: clientMessageID
                )
                return dto
            } catch {
                let errorCode = MessengerOutboxErrorCode.classifyCreateMessageFailure(error).rawValue
                MessengerDiagnostics.event(
                    .outboxImageCreateMessageFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCode": errorCode]
                )
                MessengerDiagnostics.event(
                    .imageMessageCreateFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": errorCode]
                )
                throw error
            }
        }
    }

    private func imageMetadata(_ prepared: PreparedChatImage) -> [String: String] {
        [
            "contentType": prepared.contentType,
            "byteSize": "\(prepared.byteSize)",
            "width": "\(prepared.width)",
            "height": "\(prepared.height)"
        ]
    }

    private func handleSendFailure(
        clientMessageID: String,
        error: Error,
        startedAt: Date,
        session: SessionStore,
        router: AppRouter
    ) {
        guard !Task.isCancelled else { return }
        guard var entry = entries[clientMessageID] else { return }

        let classified = MessengerOutboxErrorCode.classify(error)
        if classified == .cancelled {
            return
        }

        entry.state = .failed
        entry.lastError = (error as? NetworkError)?.userMessage ?? error.localizedDescription
        entries[clientMessageID] = entry

        let presentationState: MessageLocalSendState
        if classified == .networkUnavailable || NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline {
            presentationState = .waitingForNetwork
        } else {
            presentationState = .failed
        }

        updateOutgoingPresentation(
            clientMessageID: clientMessageID,
            conversationID: entry.conversationID,
            state: presentationState
        )

        if entry.payload.kindName == "text" || entry.payload.kindName == "image" {
            let errorCode = classified.rawValue
            let nextRetryAt: Date? = classified.blocksAutomaticRetry ? Date.distantFuture : nil
            Task {
                do {
                    try await MessengerLocalStore.shared.markOutboxFailed(
                        clientMessageID: clientMessageID,
                        errorCode: errorCode,
                        nextRetryAt: nextRetryAt
                    )
                    if let snapshot = try await MessengerLocalStore.shared.fetchOutboxItem(clientMessageID: clientMessageID) {
                        let retryEvent: MessengerDiagnosticEvent = entry.payload.kindName == "image"
                            ? .outboxImageRetryScheduled
                            : .outboxRetryScheduled
                        MessengerDiagnostics.event(
                            retryEvent,
                            conversationID: entry.conversationID,
                            clientMessageID: clientMessageID,
                            metadata: [
                                "attemptCount": "\(snapshot.attemptCount)",
                                "errorCode": errorCode,
                                "retryReason": "auto"
                            ]
                        )
                    }
                } catch {
                    MessengerDiagnostics.event(
                        .outboxRetryScheduled,
                        conversationID: entry.conversationID,
                        clientMessageID: clientMessageID,
                        metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
                    )
                }
            }
        }

        MessengerDiagnostics.event(
            .outboxProcessorItemFailed,
            conversationID: entry.conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "durationMs": "\(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))",
                "errorCode": classified.rawValue,
                "kind": entry.payload.kindName
            ]
        )
        MessengerDiagnostics.event(
            .outboxSendFailed,
            conversationID: entry.conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "durationMs": "\(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))",
                "errorCategory": classified.rawValue,
                "kind": entry.payload.kindName
            ]
        )

        MessengerConversationNotification.postMessagesDidChange(conversationID: entry.conversationID)

        if let networkError = error as? NetworkError {
            _ = MessengerSessionSupport.handleNetworkError(networkError, session: session, router: router)
        }

        if !classified.blocksAutomaticRetry {
            pumpConversationQueueInternal(conversationID: entry.conversationID, session: session, router: router)
        }
    }

    static func clearPersistedOutboxItem(clientMessageID: String, conversationID: UUID, reason: String) {
        Task {
            do {
                try await MessengerLocalStore.shared.deleteOutboxItem(clientMessageID: clientMessageID)
                MessengerDiagnostics.event(
                    .outboxItemCleared,
                    conversationID: conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["reason": reason]
                )
            } catch {
                MessengerDiagnostics.event(
                    .outboxItemCleared,
                    conversationID: conversationID,
                    clientMessageID: clientMessageID,
                    metadata: [
                        "reason": "\(reason)Failed",
                        "errorCategory": MessengerDiagnostics.sanitizeError(error)
                    ]
                )
            }
        }
    }
}
