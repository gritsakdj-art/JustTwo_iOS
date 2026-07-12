import Foundation

/// Canonical applier for global `conversation.delivered` / `conversation.read`
/// realtime events. Serializes apply, enforces account/session guards, updates
/// the durable local store once, then refreshes observable caches.
@MainActor
final class MessengerRealtimeReceiptCoordinator {
    static let shared = MessengerRealtimeReceiptCoordinator()

    private struct RepairHint: Equatable {
        let conversationID: UUID
        let participantProfileID: UUID
        let kind: MessengerReceiptKind
        let boundaryMessageID: UUID
    }

    private var sessionGeneration = 0
    private var ownerProfileID: UUID?
    private var isApplyInFlight = false
    private var pendingApplyQueue: [() async -> Void] = []
    private var applyDrainTask: Task<Void, Never>?
    private var isRepairInFlight = false
    private var hasPendingRepair = false
    private var repairHints: [RepairHint] = []
    private var repairTask: Task<Void, Never>?

    private let localStore: MessengerLocalStore
    private let messageCache: MessageCacheStore
    private weak var conversationList: ConversationListViewModel?
    private weak var session: SessionStore?
    private weak var router: AppRouter?

    init(
        localStore: MessengerLocalStore? = nil,
        messageCache: MessageCacheStore? = nil
    ) {
        self.localStore = localStore ?? .shared
        self.messageCache = messageCache ?? .shared
    }

    func configure(
        conversationList: ConversationListViewModel?,
        session: SessionStore?,
        router: AppRouter?
    ) {
        self.conversationList = conversationList
        self.session = session
        self.router = router
        ownerProfileID = session?.currentProfile?.id
    }

    func reset() {
        sessionGeneration += 1
        applyDrainTask?.cancel()
        applyDrainTask = nil
        repairTask?.cancel()
        repairTask = nil
        ownerProfileID = nil
        pendingApplyQueue.removeAll()
        repairHints.removeAll()
        isApplyInFlight = false
        isRepairInFlight = false
        hasPendingRepair = false
        #if DEBUG
        testingSuspendBeforeLocalApply = false
        testingOnApplySuspended = nil
        testingResumeLocalApply = nil
        #endif
    }

    func handleConversationDelivered(
        conversationID: UUID,
        payload: ConversationDeliveredPayload,
        source: String = "realtime"
    ) {
        guard let messageID = payload.messageID else {
            logMalformed(eventType: "conversation.delivered", conversationID: conversationID)
            return
        }

        enqueueApply {
            await self.applyReceipt(
                conversationID: conversationID,
                participantProfileID: payload.profileID,
                kind: .delivered,
                boundaryMessageID: messageID,
                source: source
            )
        }
    }

    func handleConversationRead(
        conversationID: UUID,
        payload: ConversationReadPayload,
        source: String = "realtime"
    ) {
        guard let messageID = payload.messageID else {
            logMalformed(eventType: "conversation.read", conversationID: conversationID)
            return
        }

        enqueueApply {
            await self.applyReceipt(
                conversationID: conversationID,
                participantProfileID: payload.profileID,
                kind: .read,
                boundaryMessageID: messageID,
                source: source
            )
        }
    }

    func retryPendingRepairsAfterSync() {
        guard !repairHints.isEmpty else { return }
        let hints = repairHints
        repairHints.removeAll()
        for hint in hints {
            enqueueApply {
                await self.applyReceipt(
                    conversationID: hint.conversationID,
                    participantProfileID: hint.participantProfileID,
                    kind: hint.kind,
                    boundaryMessageID: hint.boundaryMessageID,
                    source: "repairRetry"
                )
            }
        }
    }

    private func enqueueApply(_ operation: @escaping () async -> Void) {
        pendingApplyQueue.append(operation)
        guard !isApplyInFlight else { return }
        isApplyInFlight = true
        applyDrainTask = Task { @MainActor [weak self] in
            await self?.drainApplyQueue()
        }
    }

    private func drainApplyQueue() async {
        defer {
            isApplyInFlight = false
            applyDrainTask = nil
        }
        while !pendingApplyQueue.isEmpty {
            if Task.isCancelled {
                pendingApplyQueue.removeAll()
                return
            }
            let next = pendingApplyQueue.removeFirst()
            await next()
        }
    }

    #if DEBUG
    internal var testingSuspendBeforeLocalApply = false
    internal var testingOnApplySuspended: (() -> Void)?
    private var testingResumeLocalApply: CheckedContinuation<Void, Never>?

    func testingDrainApplies() async {
        while !pendingApplyQueue.isEmpty || isApplyInFlight {
            if let task = applyDrainTask {
                await task.value
            } else if pendingApplyQueue.isEmpty, !isApplyInFlight {
                break
            } else {
                await Task.yield()
            }
        }
    }

    func testingSetOwnerProfileID(_ profileID: UUID?) {
        ownerProfileID = profileID
    }

    func testingResumeSuspendedLocalApplyForTests() {
        testingResumeLocalApply?.resume()
        testingResumeLocalApply = nil
        testingSuspendBeforeLocalApply = false
        testingOnApplySuspended = nil
    }

    var testingIsApplyInFlight: Bool {
        isApplyInFlight
    }

    var testingPendingRepairHintCount: Int {
        repairHints.count
    }
    #endif

    private func applyReceipt(
        conversationID: UUID,
        participantProfileID: UUID,
        kind: MessengerReceiptKind,
        boundaryMessageID: UUID,
        source: String
    ) async {
        let capturedGeneration = sessionGeneration
        guard let ownerProfileID = resolvedOwnerProfileID() else {
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptSessionStale,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: ["reason": "missingOwner", "source": source]
            )
            return
        }

        MessengerDiagnostics.event(
            .messengerRealtimeReceiptReceived,
            conversationID: conversationID,
            messageID: boundaryMessageID,
            metadata: [
                "eventType": kind == .read ? "conversation.read" : "conversation.delivered",
                "receiptKind": kind.rawValue,
                "source": source,
                "sessionGeneration": "\(capturedGeneration)"
            ]
        )

        if participantProfileID == ownerProfileID {
            _ = conversationList?.applyRealtimeConversationRead(
                conversationID: conversationID,
                profileID: participantProfileID,
                currentProfileID: ownerProfileID
            )
        }

        #if DEBUG
        if testingSuspendBeforeLocalApply {
            testingOnApplySuspended?()
            await withCheckedContinuation { continuation in
                testingResumeLocalApply = continuation
            }
            guard capturedGeneration == sessionGeneration,
                  ownerProfileID == resolvedOwnerProfileID() else {
                MessengerDiagnostics.event(
                    .messengerRealtimeReceiptSessionStale,
                    conversationID: conversationID,
                    messageID: boundaryMessageID,
                    metadata: ["source": source, "phase": "suspendedApply"]
                )
                return
            }
        }
        #endif

        let startedAt = Date()
        let result: MessengerReceiptApplyResult
        do {
            result = try await localStore.applyRealtimeReceipt(
                ownerProfileID: ownerProfileID,
                conversationID: conversationID,
                participantProfileID: participantProfileID,
                kind: kind,
                boundaryMessageID: boundaryMessageID
            )
        } catch MessengerLocalStoreError.staleSession {
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptSessionStale,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: ["source": source]
            )
            return
        } catch {
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptApplyFailed,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: [
                    "source": source,
                    "reason": MessengerDiagnostics.sanitizeError(error)
                ]
            )
            return
        }

        guard capturedGeneration == sessionGeneration,
              ownerProfileID == resolvedOwnerProfileID() else {
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptSessionStale,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: ["source": source, "phase": "postApply"]
            )
            return
        }

        if result.requiresSyncRepair {
            recordRepairHint(
                RepairHint(
                    conversationID: conversationID,
                    participantProfileID: participantProfileID,
                    kind: kind,
                    boundaryMessageID: boundaryMessageID
                )
            )
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptTargetMissing,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: ["source": source, "receiptKind": kind.rawValue]
            )
            scheduleCoalescedRepair(capturedGeneration: capturedGeneration)
            return
        }

        if !result.didAdvanceParticipantBoundary {
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptNoop,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: [
                    "source": source,
                    "receiptKind": kind.rawValue,
                    "reason": "staleBoundary"
                ]
            )
            return
        }

        await publishToObservableCaches(
            conversationID: conversationID,
            ownerProfileID: ownerProfileID,
            participantProfileID: participantProfileID,
            kind: kind,
            boundaryMessageID: boundaryMessageID,
            result: result
        )

        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        MessengerDiagnostics.event(
            .messengerRealtimeReceiptApplied,
            conversationID: conversationID,
            messageID: boundaryMessageID,
            metadata: [
                "source": source,
                "receiptKind": kind.rawValue,
                "updatedMessageCount": "\(result.updatedMessageCount)",
                "previewUpdated": result.updatedConversationPreview ? "true" : "false",
                "durationMs": "\(durationMs)"
            ]
        )

        if result.updatedConversationPreview {
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptPreviewUpdated,
                conversationID: conversationID,
                messageID: boundaryMessageID,
                metadata: ["source": source]
            )
        }
    }

    private func publishToObservableCaches(
        conversationID: UUID,
        ownerProfileID: UUID,
        participantProfileID: UUID,
        kind: MessengerReceiptKind,
        boundaryMessageID: UUID,
        result: MessengerReceiptApplyResult
    ) async {
        guard participantProfileID != ownerProfileID else { return }

        let status: MessageDeliveryStatus = result.previewDeliveryStatus
            ?? (kind == .read ? .read : .delivered)

        _ = messageCache.applyDeliveryStatus(
            conversationID: conversationID,
            status: status,
            messageID: boundaryMessageID,
            cutoffDate: nil
        )

        _ = await messageCache.mergeDeliveryStatusesFromLocal(
            conversationID: conversationID,
            ownerProfileID: ownerProfileID
        )

        if let status = result.previewDeliveryStatus {
            conversationList?.applyRealtimeOutgoingDeliveryStatus(
                conversationID: conversationID,
                deliveryStatus: status,
                ownerProfileID: ownerProfileID
            )
        }
    }

    private func recordRepairHint(_ hint: RepairHint) {
        if let index = repairHints.firstIndex(where: {
            $0.conversationID == hint.conversationID
                && $0.participantProfileID == hint.participantProfileID
                && $0.kind == hint.kind
        }) {
            repairHints[index] = hint
        } else {
            repairHints.append(hint)
        }
    }

    private func scheduleCoalescedRepair(capturedGeneration: Int) {
        if isRepairInFlight {
            hasPendingRepair = true
            MessengerDiagnostics.event(
                .messengerRealtimeReceiptRepairCoalesced,
                metadata: ["sessionGeneration": "\(capturedGeneration)"]
            )
            return
        }

        isRepairInFlight = true
        MessengerDiagnostics.event(
            .messengerRealtimeReceiptRepairScheduled,
            metadata: ["sessionGeneration": "\(capturedGeneration)"]
        )

        repairTask?.cancel()
        repairTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRepairInFlight = false
                self.repairTask = nil
                if self.hasPendingRepair {
                    self.hasPendingRepair = false
                    self.scheduleCoalescedRepair(capturedGeneration: self.sessionGeneration)
                }
            }

            guard !Task.isCancelled,
                  capturedGeneration == self.sessionGeneration,
                  let session = self.session,
                  let router = self.router else {
                return
            }

            await MessengerSyncEngine.shared.runGlobalSync(
                reason: .realtimeReconnect,
                session: session,
                router: router
            )

            guard !Task.isCancelled,
                  capturedGeneration == self.sessionGeneration else {
                return
            }

            MessengerDiagnostics.event(.messengerRealtimeReceiptRepairCompleted)
            self.retryPendingRepairsAfterSync()
        }
    }

    private func resolvedOwnerProfileID() -> UUID? {
        ownerProfileID ?? session?.currentProfile?.id
    }

    private func logMalformed(eventType: String, conversationID: UUID) {
        MessengerDiagnostics.event(
            .messengerRealtimeReceiptApplyFailed,
            conversationID: conversationID,
            metadata: ["eventType": eventType, "reason": "missingMessageID"]
        )
    }
}
