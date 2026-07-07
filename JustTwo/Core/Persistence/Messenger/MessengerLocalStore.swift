import Foundation
import SwiftData

@MainActor
final class MessengerLocalStore: MessengerLocalStoreProtocol {
    private static var configuredShared: MessengerLocalStore?

    static var shared: MessengerLocalStore {
        if let configuredShared {
            return configuredShared
        }
        let fallback = MessengerLocalStore(inMemoryOnly: false)
        configuredShared = fallback
        return fallback
    }

    static func configureShared(modelContainer: ModelContainer) {
        configuredShared = MessengerLocalStore(modelContainer: modelContainer)
    }

    private let backingStore: any MessengerLocalStoreProtocol
    private var sessionGeneration = 0
    private var isResetInFlight = false

    internal var sessionGenerationForTests: Int {
        sessionGeneration
    }

    /// Test-only hook: suspends reset after `isResetInFlight` is set so concurrent access can be verified.
    internal var testingSuspendResetAfterLock = false
    internal var testingOnResetSuspended: (() -> Void)?
    private var testingResumeReset: CheckedContinuation<Void, Never>?

    internal func testingResumeSuspendedResetForTests() {
        testingResumeReset?.resume()
        testingResumeReset = nil
        testingSuspendResetAfterLock = false
        testingOnResetSuspended = nil
    }

    init(
        modelContainer: ModelContainer? = nil,
        inMemoryOnly: Bool = false,
        emitInitializationDiagnostic: Bool = true
    ) {
        let container: ModelContainer
        if let modelContainer {
            container = modelContainer
        } else {
            container = try! MessengerPersistence.makeModelContainer(inMemoryOnly: inMemoryOnly)
        }

        self.backingStore = SwiftDataMessengerLocalStore(modelContainer: container)

        if emitInitializationDiagnostic {
            MessengerDiagnostics.event(
                .messengerLocalStoreInitialized,
                metadata: [
                    "entityCount": "\(MessengerPersistence.messengerModelTypes().count)",
                    "inMemory": inMemoryOnly ? "true" : "false"
                ]
            )
        }
    }

    func resetAllMessengerData() async throws {
        sessionGeneration += 1
        let resetGeneration = sessionGeneration
        isResetInFlight = true
        MessengerDiagnostics.event(
            .messengerLocalStoreResetStarted,
            metadata: ["sessionGeneration": "\(resetGeneration)"]
        )

        if testingSuspendResetAfterLock {
            testingOnResetSuspended?()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                testingResumeReset = continuation
            }
        }

        let startedAt = Date()
        defer {
            if resetGeneration == sessionGeneration {
                isResetInFlight = false
            }
        }

        do {
            try await backingStore.resetAllMessengerData()
            guard resetGeneration == sessionGeneration else {
                MessengerDiagnostics.event(
                    .messengerLocalStoreResetFailed,
                    metadata: [
                        "errorCategory": "staleSession",
                        "sessionGeneration": "\(resetGeneration)",
                        "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
                    ]
                )
                return
            }

            MessengerDiagnostics.event(
                .messengerLocalStoreResetSucceeded,
                metadata: [
                    "sessionGeneration": "\(resetGeneration)",
                    "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
                ]
            )
        } catch {
            guard resetGeneration == sessionGeneration else { return }

            MessengerDiagnostics.event(
                .messengerLocalStoreResetFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "sessionGeneration": "\(resetGeneration)",
                    "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
                ]
            )
            throw error
        }
    }

    func upsertConversations(_ conversations: [ConversationDTO]) async throws {
        let startedAt = Date()
        try await performSessionBoundOperation(operation: "upsertConversations") {
            try await backingStore.upsertConversations(conversations)
        }
        MessengerDiagnostics.event(
            .messengerLocalConversationUpserted,
            metadata: [
                "count": "\(conversations.count)",
                "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            ]
        )
    }

    func fetchLocalConversations() async throws -> [LocalConversationSnapshot] {
        try await performSessionBoundOperation(operation: "fetchLocalConversations") {
            try await backingStore.fetchLocalConversations()
        }
    }

    func patchConversationFromMessage(_ message: MessageDTO, unreadCount: Int?) async throws {
        try await performSessionBoundOperation(operation: "patchConversationFromMessage") {
            try await backingStore.patchConversationFromMessage(message, unreadCount: unreadCount)
        }
    }

    func patchConversationActivity(
        conversationID: UUID,
        lastMessageAt: Date?,
        unreadCount: Int?
    ) async throws {
        try await performSessionBoundOperation(operation: "patchConversationActivity") {
            try await backingStore.patchConversationActivity(
                conversationID: conversationID,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount
            )
        }
    }

    func upsertLastMessageSnapshot(_ message: MessageDTO) async throws {
        try await performSessionBoundOperation(operation: "upsertLastMessageSnapshot") {
            try await backingStore.upsertLastMessageSnapshot(message)
        }
    }

    func upsertMessages(
        _ messages: [MessageDTO],
        conversationID: UUID
    ) async throws {
        let startedAt = Date()
        let attachmentCount = messages.reduce(0) { $0 + ($1.deletedAt == nil ? $1.attachments.count : 0) }

        try await performSessionBoundOperation(operation: "upsertMessages") {
            try await backingStore.upsertMessages(
                messages,
                conversationID: conversationID
            )
        }
        MessengerDiagnostics.event(
            .messengerLocalMessagesUpserted,
            conversationID: conversationID,
            metadata: [
                "count": "\(messages.count)",
                "attachmentCount": "\(attachmentCount)",
                "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            ]
        )
    }

    func fetchLocalMessages(
        conversationID: UUID,
        limit: Int,
        before: Date?
    ) async throws -> [LocalMessageSnapshot] {
        try await performSessionBoundOperation(operation: "fetchLocalMessages") {
            try await backingStore.fetchLocalMessages(
                conversationID: conversationID,
                limit: limit,
                before: before
            )
        }
    }

    func markMessageDeleted(messageID: UUID, deletedAt: Date?) async throws {
        try await performSessionBoundOperation(operation: "markMessageDeleted") {
            try await backingStore.markMessageDeleted(messageID: messageID, deletedAt: deletedAt)
        }
        MessengerDiagnostics.event(
            .messengerLocalMessageDeleted,
            messageID: messageID,
            metadata: [
                "hasDeletedAt": deletedAt == nil ? "false" : "true"
            ]
        )
    }

    func upsertReactions(from message: MessageDTO) async throws {
        try await performSessionBoundOperation(operation: "upsertReactions") {
            try await backingStore.upsertReactions(from: message)
        }
    }

    func applyReceipt(_ receipt: MessengerReceiptDTO) async throws {
        try await performSessionBoundOperation(operation: "applyReceipt") {
            try await backingStore.applyReceipt(receipt)
        }
        MessengerDiagnostics.event(
            .messengerLocalReceiptApplied,
            conversationID: receipt.conversationID,
            messageID: receipt.messageID,
            metadata: [
                "hasDeliveredAt": receipt.deliveredAt == nil ? "false" : "true",
                "hasReadAt": receipt.readAt == nil ? "false" : "true"
            ]
        )
    }

    func upsertSyncMetadata(_ metadata: LocalMessengerSyncMetadataSnapshot) async throws {
        try await performSessionBoundOperation(operation: "upsertSyncMetadata") {
            try await backingStore.upsertSyncMetadata(metadata)
        }
        MessengerDiagnostics.event(
            .messengerLocalSyncMetadataUpdated,
            metadata: [
                "revision": metadata.lastAppliedRevision.map(String.init) ?? "nil",
                "schemaVersion": "\(metadata.schemaVersion)"
            ]
        )
    }

    func fetchSyncMetadata() async throws -> LocalMessengerSyncMetadataSnapshot? {
        try await performSessionBoundOperation(operation: "fetchSyncMetadata") {
            try await backingStore.fetchSyncMetadata()
        }
    }

    private func performSessionBoundOperation<T>(
        operation: String,
        _ work: () async throws -> T
    ) async throws -> T {
        guard !isResetInFlight else {
            throw MessengerLocalStoreError.storeUnavailable
        }

        let generation = sessionGeneration
        do {
            let value = try await work()
            try validateSessionGeneration(generation, operation: operation)
            return value
        } catch let error as MessengerLocalStoreError {
            throw error
        } catch {
            MessengerDiagnostics.event(
                .messengerLocalMappingFailed,
                metadata: [
                    "operation": operation,
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
            throw error
        }
    }

    private func validateSessionGeneration(_ generation: Int, operation: String) throws {
        guard generation == sessionGeneration, !isResetInFlight else {
            MessengerDiagnostics.event(
                .messengerLocalMappingFailed,
                metadata: [
                    "operation": operation,
                    "errorCategory": "staleSession",
                    "sessionGeneration": "\(generation)"
                ]
            )
            throw MessengerLocalStoreError.staleSession
        }
    }
}

enum MessengerLocalStorageFeatureFlags {
    /// PR15C will enable local reads for per-conversation message history.
    static let isLocalReadEnabled = false
    /// PR15B enables cached conversation list hydration and persistence.
    static let isCachedConversationListEnabled = true
}
