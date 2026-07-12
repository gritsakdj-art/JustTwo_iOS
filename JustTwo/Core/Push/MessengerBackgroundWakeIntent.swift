import Foundation

/// Minimal routing hint parsed from a messenger background-capable push.
/// Not delivery evidence — authoritative apply happens only via delta sync (PR20D3B).
struct MessengerBackgroundWakeIntent: Sendable, Equatable {
    let conversationID: UUID
    let messageID: UUID?
}

enum MessengerBackgroundSyncRunOutcome: Sendable, Equatable {
    case newData(appliedEventCount: Int, advancedRevision: Bool, pendingDeliveryAckCount: Int)
    case noData
    case failed(reason: String)
}

struct MessengerSyncRunResult: Sendable, Equatable {
    let outcome: MessengerBackgroundSyncRunOutcome
    let didApplyChanges: Bool
    let appliedEventCount: Int
    let advancedRevision: Bool
    let pendingDeliveryAckCount: Int

    nonisolated static let noData = MessengerSyncRunResult(
        outcome: .noData,
        didApplyChanges: false,
        appliedEventCount: 0,
        advancedRevision: false,
        pendingDeliveryAckCount: 0
    )

    nonisolated static func failed(_ reason: String) -> MessengerSyncRunResult {
        MessengerSyncRunResult(
            outcome: .failed(reason: reason),
            didApplyChanges: false,
            appliedEventCount: 0,
            advancedRevision: false,
            pendingDeliveryAckCount: 0
        )
    }
}

/// One bounded background reconciliation cycle (session prepare → authoritative
/// sync → durable ACK bootstrap → best-effort ACK flush) executed within a single
/// absolute `deadline`. Injectable so the coordinator's batching/cohort/deadline
/// orchestration can be tested without the network or singletons.
protocol MessengerBackgroundCycleRunning: Sendable {
    func runCycle(
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) async -> MessengerSyncRunResult
}

struct DeliveryAckFlushResult: Sendable, Equatable {
    let attemptedCount: Int
    let succeededCount: Int
    let deferredCount: Int
    let expired: Bool
}

struct MessengerBackgroundSessionContext: Sendable, Equatable {
    let ownerProfileID: UUID
    let userID: UUID
    let syncEngineGeneration: Int
    let ackCoordinatorGeneration: Int
}

struct MessengerBackgroundSyncConfiguration: Sendable {
    let operationDeadline: Duration
    let dependencyReadinessDeadline: Duration
    let ackFlushSubDeadline: Duration

    nonisolated static let production = MessengerBackgroundSyncConfiguration(
        operationDeadline: .seconds(25),
        dependencyReadinessDeadline: .seconds(5),
        ackFlushSubDeadline: .seconds(8)
    )

    nonisolated static let testing = MessengerBackgroundSyncConfiguration(
        operationDeadline: .milliseconds(500),
        dependencyReadinessDeadline: .milliseconds(150),
        ackFlushSubDeadline: .milliseconds(150)
    )
}
