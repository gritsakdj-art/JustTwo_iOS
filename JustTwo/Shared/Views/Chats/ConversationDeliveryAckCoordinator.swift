import Foundation

@MainActor
final class ConversationDeliveryAckCoordinator {

    static let shared = ConversationDeliveryAckCoordinator()

    private struct AckKey: Hashable {
        let conversationID: UUID
        let messageID: UUID
    }

    private struct AckEnvelope {
        let boundary: MessageReceiptBoundary
        let currentProfileID: UUID
        let session: SessionStore
        let router: AppRouter
        let source: String
        let generation: Int
    }

    private var deliveredAckedKeys: Set<AckKey> = []
    private var readAckedKeys: Set<AckKey> = []
    private var highestAppliedInboundBoundaryByConversation: [UUID: MessageReceiptBoundary] = [:]
    private var highestProvenSafeBoundaryByConversation: [UUID: MessageReceiptBoundary] = [:]
    private var highestPendingAckBoundaryByConversation: [UUID: MessageReceiptBoundary] = [:]
    private var highestConfirmedAckBoundaryByConversation: [UUID: MessageReceiptBoundary] = [:]
    private var inFlightBoundaryByConversation: [UUID: MessageReceiptBoundary] = [:]
    private var pendingEnvelopeByConversation: [UUID: AckEnvelope] = [:]
    private var retryTaskByConversation: [UUID: Task<Void, Never>] = [:]
    private var retryAttemptByConversation: [UUID: Int] = [:]
    private var sessionGeneration = 0
    private var networkHandlerID: UUID?
    private var bootstrapInFlight = false

    var markDeliveredHandler: ((UUID, UUID) async throws -> Void)?

    /// Durable proven-safe boundary persistence. When `nil` (unit tests that do
    /// not exercise persistence) cold-start bootstrap and post-ACK cleanup are
    /// no-ops. Production wires this to `MessengerLocalStore.shared` at bootstrap.
    weak var boundaryStore: ConversationDeliveryAckBoundaryStore?

    private init() {
        networkHandlerID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            guard NetworkPathMonitor.shared.isNetworkSatisfied else { return }
            self?.retryPendingAfterNetworkRestore()
        }
    }

    static func makeForTesting() -> ConversationDeliveryAckCoordinator {
        ConversationDeliveryAckCoordinator()
    }

    func reset() {
        sessionGeneration += 1
        bootstrapInFlight = false
        deliveredAckedKeys.removeAll()
        readAckedKeys.removeAll()
        highestAppliedInboundBoundaryByConversation.removeAll()
        highestProvenSafeBoundaryByConversation.removeAll()
        highestPendingAckBoundaryByConversation.removeAll()
        highestConfirmedAckBoundaryByConversation.removeAll()
        inFlightBoundaryByConversation.removeAll()
        pendingEnvelopeByConversation.removeAll()
        retryAttemptByConversation.removeAll()
        retryTaskByConversation.values.forEach { $0.cancel() }
        retryTaskByConversation.removeAll()
        MessengerDiagnostics.event(
            .messengerDeliveryAckPendingCleared,
            metadata: ["reason": "reset", "sessionGeneration": "\(sessionGeneration)"]
        )
    }

    func retryPendingAcks(reason: String) {
        MessengerDiagnostics.event(
            .messengerDeliveryAckNetworkRestored,
            metadata: ["pendingCount": "\(pendingEnvelopeByConversation.count)", "reason": reason]
        )
        for conversationID in pendingEnvelopeByConversation.keys {
            retryTaskByConversation[conversationID]?.cancel()
            retryTaskByConversation[conversationID] = nil
            Task { [weak self] in
                await self?.sendPendingIfPossible(conversationID: conversationID)
            }
        }
    }

    /// Loads durable proven-safe boundaries for the current owner and re-schedules
    /// the delivered-ACK pipeline for each. Runs at authenticated messenger session
    /// startup without requiring any chat view to open. Serialized via
    /// `bootstrapInFlight` and guarded by `sessionGeneration` + owner across awaits.
    func bootstrapPersistedBoundaries(
        ownerProfileID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async {
        guard let boundaryStore else { return }
        guard !bootstrapInFlight else {
            MessengerDiagnostics.event(
                .messengerDeliveryAckBootstrapIgnoredStaleSession,
                metadata: ["reason": "bootstrapAlreadyInFlight"]
            )
            return
        }

        bootstrapInFlight = true
        let generation = sessionGeneration
        defer {
            if generation == sessionGeneration {
                bootstrapInFlight = false
            }
        }

        MessengerDiagnostics.event(
            .messengerDeliveryAckBootstrapStarted,
            metadata: ["sessionGeneration": "\(generation)"]
        )

        let boundaries: [UUID: MessageReceiptBoundary]
        do {
            boundaries = try await boundaryStore.loadPendingDeliveryBoundaries(ownerProfileID: ownerProfileID)
        } catch {
            MessengerDiagnostics.event(
                .messengerDeliveryAckBootstrapIgnoredStaleSession,
                metadata: ["reason": "loadFailed", "errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            return
        }

        guard generation == sessionGeneration else {
            MessengerDiagnostics.event(
                .messengerDeliveryAckBootstrapIgnoredStaleSession,
                metadata: ["reason": "generationChanged", "sessionGeneration": "\(generation)"]
            )
            return
        }
        guard markDeliveredHandler != nil || session.currentProfile?.id == ownerProfileID else {
            MessengerDiagnostics.event(
                .messengerDeliveryAckIgnoredWrongOwner,
                metadata: ["reason": "ownerMismatchAtBootstrap", "phase": "bootstrap"]
            )
            return
        }

        MessengerDiagnostics.event(
            .messengerDeliveryAckBootstrapLoaded,
            metadata: ["count": "\(boundaries.count)", "sessionGeneration": "\(generation)"]
        )

        for (conversationID, boundary) in boundaries {
            await scheduleAuthoritativeBoundary(
                conversationID: conversationID,
                boundary: boundary,
                currentProfileID: ownerProfileID,
                session: session,
                router: router,
                source: "bootstrap",
                evidence: .persistedSafeBoundary
            )
            MessengerDiagnostics.event(
                .messengerDeliveryAckBootstrapScheduled,
                conversationID: conversationID,
                messageID: boundary.messageID,
                metadata: ["sessionGeneration": "\(generation)"]
            )
        }
    }

    /// Schedules a delivered-ACK for an already-validated authoritative boundary
    /// (proven-safe committed sync boundary or a durably persisted boundary),
    /// bypassing message-level coverage checks that were performed at commit time.
    func scheduleAuthoritativeBoundary(
        conversationID: UUID,
        boundary: MessageReceiptBoundary,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter,
        source: String,
        evidence: DeliveryCoverageEvidence
    ) async {
        if markDeliveredHandler == nil {
            guard session.isFullyAuthenticated else {
                logSkip(conversationID: conversationID, messageID: boundary.messageID, reason: "unauthenticated", source: source)
                return
            }
            guard session.currentProfile?.id == currentProfileID else {
                logSkip(conversationID: conversationID, messageID: boundary.messageID, reason: "accountMismatch", source: source)
                return
            }
        }

        await scheduleAppliedBoundary(
            boundary,
            conversationID: conversationID,
            currentProfileID: currentProfileID,
            session: session,
            router: router,
            source: source,
            evidence: evidence
        )
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
        router: AppRouter,
        evidence: DeliveryCoverageEvidence = .previewOnly
    ) async {
        for conversation in conversations {
            logSkip(
                conversationID: conversation.id,
                messageID: conversation.lastMessage?.id,
                reason: "conversationPreviewOnly",
                source: "conversationList"
            )
        }
    }

    func acknowledgeDeliveredIfNeeded(
        conversation: ConversationDTO,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter,
        evidence: DeliveryCoverageEvidence = .previewOnly
    ) async {
        guard let message = conversation.lastMessage else {
            logSkip(conversationID: conversation.id, messageID: nil, reason: "missingMessageID", source: "conversationList")
            return
        }

        if let lastReadAt = conversation.lastReadAt,
           let createdAt = message.createdAt,
           lastReadAt >= createdAt {
            markReadAcked(conversationID: conversation.id, messageID: message.id)
            logSkip(conversationID: conversation.id, messageID: message.id, reason: "alreadyRead", source: "conversationList")
            return
        }

        await acknowledgeAppliedInboundMessage(
            conversationID: conversation.id,
            message: message,
            currentProfileID: currentProfileID,
            session: session,
            router: router,
            source: "conversationList",
            evidence: evidence
        )
    }

    func acknowledgeDeliveredIfNeeded(
        conversationID: UUID,
        message: MessageDTO,
        currentProfileID: UUID,
        session: SessionStore?,
        router: AppRouter?,
        source: String = "realtime",
        evidence: DeliveryCoverageEvidence = .realtimeUnverified(connectionEpoch: 0)
    ) async {
        guard let session, let router else {
            logSkip(conversationID: conversationID, messageID: message.id, reason: "missingSessionOrRouter", source: source)
            return
        }

        await acknowledgeAppliedInboundMessage(
            conversationID: conversationID,
            message: message,
            currentProfileID: currentProfileID,
            session: session,
            router: router,
            source: source,
            evidence: evidence
        )
    }

    func acknowledgeAppliedInboundBoundary(
        conversationID: UUID,
        messageID: UUID,
        createdAt: Date,
        kind: MessageKind,
        isMine: Bool,
        isDeleted: Bool,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter,
        source: String,
        evidence: DeliveryCoverageEvidence = .realtimeUnverified(connectionEpoch: 0)
    ) async {
        guard !isDeleted else {
            logSkip(conversationID: conversationID, messageID: messageID, reason: "deletedMessage", source: source)
            return
        }
        guard kind == .text || kind == .image else {
            logSkip(conversationID: conversationID, messageID: messageID, reason: "unsupportedKind", source: source)
            return
        }
        guard !isMine else {
            logSkip(conversationID: conversationID, messageID: messageID, reason: "ownMessage", source: source, extra: ["isOwnMessage": "true"])
            return
        }
        await scheduleAppliedBoundary(
            MessageReceiptBoundary(createdAt: createdAt, messageID: messageID),
            conversationID: conversationID,
            currentProfileID: currentProfileID,
            session: session,
            router: router,
            source: source,
            evidence: evidence
        )
    }

    func acknowledgeAppliedInboundMessage(
        conversationID: UUID,
        message: MessageDTO,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter,
        source: String,
        evidence: DeliveryCoverageEvidence
    ) async {
        guard message.conversationID == conversationID else {
            logSkip(conversationID: conversationID, messageID: message.id, reason: "conversationMismatch", source: source)
            return
        }
        guard message.deletedAt == nil else {
            logSkip(conversationID: conversationID, messageID: message.id, reason: "deletedMessage", source: source)
            return
        }
        guard message.kind == .text || message.kind == .image else {
            logSkip(conversationID: conversationID, messageID: message.id, reason: "unsupportedKind", source: source)
            return
        }
        guard message.senderProfileID != currentProfileID else {
            logSkip(conversationID: conversationID, messageID: message.id, reason: "ownMessage", source: source, extra: ["isOwnMessage": "true"])
            return
        }
        guard let boundary = MessageReceiptBoundary(message: message) else {
            logSkip(conversationID: conversationID, messageID: message.id, reason: "missingCreatedAt", source: source)
            return
        }
        if markDeliveredHandler == nil {
            guard session.isFullyAuthenticated else {
                logSkip(conversationID: conversationID, messageID: message.id, reason: "unauthenticated", source: source)
                return
            }
            guard session.currentProfile?.id == currentProfileID else {
                logSkip(conversationID: conversationID, messageID: message.id, reason: "accountMismatch", source: source)
                return
            }
        }

        await scheduleAppliedBoundary(
            boundary,
            conversationID: conversationID,
            currentProfileID: currentProfileID,
            session: session,
            router: router,
            source: source,
            evidence: evidence
        )
    }

    private func scheduleAppliedBoundary(
        _ boundary: MessageReceiptBoundary,
        conversationID: UUID,
        currentProfileID: UUID,
        session: SessionStore,
        router: AppRouter,
        source: String,
        evidence: DeliveryCoverageEvidence
    ) async {
        highestAppliedInboundBoundaryByConversation[conversationID] = max(
            highestAppliedInboundBoundaryByConversation[conversationID],
            boundary
        )

        guard evidence.permitsAck else {
            MessengerDiagnostics.event(
                .messengerDeliveryAckDeferredCoverage,
                conversationID: conversationID,
                messageID: boundary.messageID,
                metadata: ["source": source, "evidence": evidence.diagnosticName]
            )
            return
        }

        highestProvenSafeBoundaryByConversation[conversationID] = max(
            highestProvenSafeBoundaryByConversation[conversationID],
            boundary
        )

        guard shouldAdvance(candidate: boundary, over: highestConfirmedAckBoundaryByConversation[conversationID]) else {
            logSkip(conversationID: conversationID, messageID: boundary.messageID, reason: "coveredByConfirmedBoundary", source: source, extra: ["isDuplicate": "true"])
            return
        }
        guard shouldAdvance(candidate: boundary, over: highestPendingAckBoundaryByConversation[conversationID]) else {
            logSkip(conversationID: conversationID, messageID: boundary.messageID, reason: "coveredByPendingBoundary", source: source, extra: ["isDuplicate": "true"])
            return
        }

        let envelope = AckEnvelope(
            boundary: boundary,
            currentProfileID: currentProfileID,
            session: session,
            router: router,
            source: source,
            generation: sessionGeneration
        )
        highestPendingAckBoundaryByConversation[conversationID] = boundary
        pendingEnvelopeByConversation[conversationID] = envelope
        MessengerDiagnostics.event(
            .messengerDeliveryAckScheduled,
            conversationID: conversationID,
            messageID: boundary.messageID,
            metadata: [
                "source": source,
                "evidence": evidence.diagnosticName,
                "sessionGeneration": "\(sessionGeneration)",
                "isAppForeground": "\(MessengerSessionSupport.isAppForegroundActive)"
            ]
        )
        await sendPendingIfPossible(conversationID: conversationID)
    }

    private func sendPendingIfPossible(conversationID: UUID) async {
        guard let envelope = pendingEnvelopeByConversation[conversationID] else { return }
        guard envelope.generation == sessionGeneration else {
            clearPending(conversationID: conversationID, reason: "staleGeneration")
            return
        }
        guard inFlightBoundaryByConversation[conversationID] == nil else { return }
        guard markDeliveredHandler != nil || envelope.session.isFullyAuthenticated else {
            logSkip(conversationID: conversationID, messageID: envelope.boundary.messageID, reason: "unauthenticated", source: envelope.source)
            scheduleRetry(conversationID: conversationID)
            return
        }
        guard markDeliveredHandler != nil || envelope.session.currentProfile?.id == envelope.currentProfileID else {
            clearPending(conversationID: conversationID, reason: "accountMismatch")
            return
        }
        guard !NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline else {
            logSkip(conversationID: conversationID, messageID: envelope.boundary.messageID, reason: "networkOffline", source: envelope.source)
            scheduleRetry(conversationID: conversationID)
            return
        }

        inFlightBoundaryByConversation[conversationID] = envelope.boundary
        do {
            if let markDeliveredHandler {
                try await markDeliveredHandler(conversationID, envelope.boundary.messageID)
            } else {
                _ = try await ConversationService.markDelivered(
                    conversationID: conversationID,
                    messageID: envelope.boundary.messageID
                )
            }

            guard envelope.generation == sessionGeneration else { return }
            markDeliveredAcked(conversationID: conversationID, messageID: envelope.boundary.messageID)
            highestConfirmedAckBoundaryByConversation[conversationID] = max(
                highestConfirmedAckBoundaryByConversation[conversationID],
                envelope.boundary
            )
            retryAttemptByConversation[conversationID] = nil
            retryTaskByConversation[conversationID]?.cancel()
            retryTaskByConversation[conversationID] = nil
            inFlightBoundaryByConversation[conversationID] = nil
            if highestPendingAckBoundaryByConversation[conversationID] == envelope.boundary {
                highestPendingAckBoundaryByConversation[conversationID] = nil
                pendingEnvelopeByConversation[conversationID] = nil
            }
            NetworkDebug.log("Messenger delivered ack sent from \(envelope.source): \(conversationID)")
            MessengerDiagnostics.event(
                .deliveredAckSent,
                conversationID: conversationID,
                messageID: envelope.boundary.messageID,
                metadata: ["source": envelope.source, "isAppForeground": "\(MessengerSessionSupport.isAppForegroundActive)"]
            )
            MessengerDiagnostics.event(
                .messengerDeliveryAckSucceeded,
                conversationID: conversationID,
                messageID: envelope.boundary.messageID,
                metadata: ["source": envelope.source]
            )

            await clearPersistedBoundaryAfterAck(
                conversationID: conversationID,
                boundary: envelope.boundary,
                ownerProfileID: envelope.currentProfileID,
                generation: envelope.generation
            )

            if pendingEnvelopeByConversation[conversationID] != nil {
                await sendPendingIfPossible(conversationID: conversationID)
            }
        } catch let error as NetworkError {
            inFlightBoundaryByConversation[conversationID] = nil
            logFailure(error, envelope: envelope, conversationID: conversationID)
            _ = MessengerSessionSupport.handleNetworkError(error, session: envelope.session, router: envelope.router)
            scheduleRetry(conversationID: conversationID)
        } catch {
            inFlightBoundaryByConversation[conversationID] = nil
            logFailure(error, envelope: envelope, conversationID: conversationID)
            scheduleRetry(conversationID: conversationID)
        }
    }

    private func retryPendingAfterNetworkRestore() {
        retryPendingAcks(reason: "networkRestored")
    }

    private func scheduleRetry(conversationID: UUID) {
        guard pendingEnvelopeByConversation[conversationID] != nil else { return }
        guard retryTaskByConversation[conversationID] == nil else { return }
        let attempt = (retryAttemptByConversation[conversationID] ?? 0) + 1
        retryAttemptByConversation[conversationID] = attempt
        let delay = min(pow(2.0, Double(attempt - 1)), 30.0)

        MessengerDiagnostics.event(
            .messengerDeliveryAckRetryScheduled,
            conversationID: conversationID,
            metadata: ["attempt": "\(attempt)", "delaySeconds": "\(Int(delay))"]
        )

        let generation = sessionGeneration
        retryTaskByConversation[conversationID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.sessionGeneration == generation else { return }
                self.retryTaskByConversation[conversationID] = nil
                Task { [weak self] in
                    await self?.sendPendingIfPossible(conversationID: conversationID)
                }
            }
        }
    }

    /// Clears the durable pending boundary after a confirmed backend ACK. Only the
    /// covered boundary is cleared; a strictly higher persisted boundary is retained
    /// by the store. A cleanup failure never lowers the in-memory confirmed state:
    /// the durable record may survive and a duplicate ACK after restart is a safe
    /// backend no-op that will clear the record on the next success.
    private func clearPersistedBoundaryAfterAck(
        conversationID: UUID,
        boundary: MessageReceiptBoundary,
        ownerProfileID: UUID,
        generation: Int
    ) async {
        guard let boundaryStore else { return }
        do {
            try await boundaryStore.clearPendingDeliveryBoundary(
                ownerProfileID: ownerProfileID,
                conversationID: conversationID,
                through: boundary
            )
            guard generation == sessionGeneration else { return }
            MessengerDiagnostics.event(
                .messengerDeliveryAckPendingCleared,
                conversationID: conversationID,
                messageID: boundary.messageID,
                metadata: ["reason": "ackConfirmed", "sessionGeneration": "\(generation)"]
            )
        } catch {
            MessengerDiagnostics.event(
                .messengerDeliveryAckPendingCleanupFailed,
                conversationID: conversationID,
                messageID: boundary.messageID,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
        }
    }

    private func clearPending(conversationID: UUID, reason: String) {
        highestPendingAckBoundaryByConversation[conversationID] = nil
        pendingEnvelopeByConversation[conversationID] = nil
        inFlightBoundaryByConversation[conversationID] = nil
        retryAttemptByConversation[conversationID] = nil
        retryTaskByConversation[conversationID]?.cancel()
        retryTaskByConversation[conversationID] = nil
        MessengerDiagnostics.event(
            .messengerDeliveryAckPendingCleared,
            conversationID: conversationID,
            metadata: ["reason": reason, "sessionGeneration": "\(sessionGeneration)"]
        )
    }

    private func shouldAdvance(
        candidate: MessageReceiptBoundary,
        over existing: MessageReceiptBoundary?
    ) -> Bool {
        guard let existing else { return true }
        return existing < candidate
    }

    private func max(
        _ lhs: MessageReceiptBoundary?,
        _ rhs: MessageReceiptBoundary
    ) -> MessageReceiptBoundary {
        guard let lhs else { return rhs }
        return Swift.max(lhs, rhs)
    }

    private func logSkip(
        conversationID: UUID,
        messageID: UUID?,
        reason: String,
        source: String,
        extra: [String: String] = [:]
    ) {
        NetworkDebug.log("Messenger delivered ack skipped: \(reason) \(conversationID)")
        MessengerDiagnostics.event(
            .deliveredAckSkipped,
            conversationID: conversationID,
            messageID: messageID,
            metadata: ["reason": reason, "source": source].merging(extra) { current, _ in current }
        )
    }

    private func logFailure(
        _ error: Error,
        envelope: AckEnvelope,
        conversationID: UUID
    ) {
        MessengerDiagnostics.event(
            .deliveredAckFailed,
            conversationID: conversationID,
            messageID: envelope.boundary.messageID,
            metadata: ["source": envelope.source, "errorCategory": MessengerDiagnostics.sanitizeError(error)]
        )
        MessengerDiagnostics.event(
            .messengerDeliveryAckFailed,
            conversationID: conversationID,
            messageID: envelope.boundary.messageID,
            metadata: ["source": envelope.source, "errorCategory": MessengerDiagnostics.sanitizeError(error)]
        )
    }
}
