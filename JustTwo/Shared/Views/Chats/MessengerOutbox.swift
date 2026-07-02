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
        enqueueEntry(
            conversationID: conversationID,
            payload: .text(TextPayload(body: body, replyToID: replyToID)),
            clientMessageID: clientMessageID,
            localMessageID: localMessageID,
            session: session,
            router: router
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
        router: AppRouter
    ) {
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

        pumpConversationQueue(conversationID: conversationID, session: session, router: router)
    }

    func retry(
        clientMessageID: String,
        session: SessionStore,
        router: AppRouter
    ) {
        guard var entry = entries[clientMessageID], entry.state == .failed else { return }
        guard sendTasks[clientMessageID] == nil else {
            MessengerDiagnostics.event(
                .outboxRetrySkippedAlreadySending,
                conversationID: entry.conversationID,
                clientMessageID: clientMessageID
            )
            return
        }

        entry.state = .queued
        entry.lastError = nil
        entries[clientMessageID] = entry
        _ = MessageCacheStore.shared.updateOptimisticMessageState(
            clientMessageID: clientMessageID,
            conversationID: entry.conversationID,
            state: .sending
        )
        MessengerConversationNotification.postMessagesDidChange(conversationID: entry.conversationID)

        MessengerDiagnostics.event(
            entry.payload.kindName == "image" ? .imageOutboxRetryRequested : .outboxRetryRequested,
            conversationID: entry.conversationID,
            clientMessageID: clientMessageID,
            metadata: ["kind": entry.payload.kindName]
        )

        pumpConversationQueue(conversationID: entry.conversationID, session: session, router: router)
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

    private func pumpConversationQueue(
        conversationID: UUID,
        session: SessionStore,
        router: AppRouter
    ) {
        guard sendTasks.values.allSatisfy({ !$0.isCancelled }) else { return }

        let hasInFlight = entries.values.contains {
            $0.conversationID == conversationID && $0.state == .sending
        }
        guard !hasInFlight else { return }

        guard let nextClientMessageID = conversationQueues[conversationID]?.first(where: { id in
            entries[id]?.state == .queued
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
        guard let entry = entries[clientMessageID], entry.state != .sent else { return }
        guard sendTasks[clientMessageID] == nil else { return }

        entries[clientMessageID]?.state = .sending
        _ = MessageCacheStore.shared.updateOptimisticMessageState(
            clientMessageID: clientMessageID,
            conversationID: entry.conversationID,
            state: .sending
        )

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
                let dto = try await self.send(entry: currentEntry, clientMessageID: clientMessageID)

                guard !Task.isCancelled else { return }

                let mapped = ChatUIMapping.message(from: dto, currentProfileID: profileID)
                let reconciled = MessageCacheStore.shared.replaceOptimisticMessage(
                    clientMessageID: clientMessageID,
                    with: mapped,
                    conversationID: currentEntry.conversationID,
                    source: .rest
                )

                self.markSent(clientMessageID: clientMessageID, serverMessageID: mapped.id)
                ConversationListViewModel.shared.applyOutgoingConfirmed(
                    conversationID: currentEntry.conversationID,
                    message: dto,
                    currentProfileID: profileID
                )

                if case .image(let payload) = currentEntry.payload {
                    ChatImagePreparer.removeTemporaryFile(payload.prepared.localFileURL)
                    MessengerDiagnostics.event(
                        .imageTempFileCleaned,
                        conversationID: currentEntry.conversationID,
                        clientMessageID: clientMessageID
                    )
                }

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

                self.pumpConversationQueue(
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

    private func send(entry: Entry, clientMessageID: String) async throws -> MessageDTO {
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
                    .imageUploadSucceeded,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID
                )
            } catch {
                MessengerDiagnostics.event(
                    .imageUploadFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
                )
                throw error
            }

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
                    .imageMessageCreateSucceeded,
                    conversationID: entry.conversationID,
                    messageID: dto.id,
                    clientMessageID: clientMessageID
                )
                return dto
            } catch {
                MessengerDiagnostics.event(
                    .imageMessageCreateFailed,
                    conversationID: entry.conversationID,
                    clientMessageID: clientMessageID,
                    metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
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
        guard var entry = entries[clientMessageID] else { return }

        entry.state = .failed
        entry.lastError = (error as? NetworkError)?.userMessage ?? error.localizedDescription
        entries[clientMessageID] = entry

        _ = MessageCacheStore.shared.updateOptimisticMessageState(
            clientMessageID: clientMessageID,
            conversationID: entry.conversationID,
            state: .failed
        )

        MessengerDiagnostics.event(
            .outboxSendFailed,
            conversationID: entry.conversationID,
            clientMessageID: clientMessageID,
            metadata: [
                "durationMs": "\(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))",
                "errorCategory": MessengerDiagnostics.sanitizeError(error),
                "kind": entry.payload.kindName
            ]
        )

        MessengerConversationNotification.postMessagesDidChange(conversationID: entry.conversationID)

        if let networkError = error as? NetworkError {
            _ = MessengerSessionSupport.handleNetworkError(networkError, session: session, router: router)
        }

        pumpConversationQueue(conversationID: entry.conversationID, session: session, router: router)
    }
}
