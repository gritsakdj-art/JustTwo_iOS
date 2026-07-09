import Foundation

@MainActor
final class MessengerSyncStateStore {

    static let shared = MessengerSyncStateStore()

    private(set) var currentRevision: Int64?
    private(set) var lastSyncAt: Date?
    private var appliedRevisions: Set<Int64> = []

    private init() {}

    func hydrate(revision: Int64?, lastSyncAt: Date?) {
        if let revision {
            setRevision(revision)
        }
        if let lastSyncAt {
            self.lastSyncAt = lastSyncAt
        }
    }

    func setRevision(_ revision: Int64) {
        if let currentRevision {
            self.currentRevision = max(currentRevision, revision)
        } else {
            currentRevision = revision
        }
    }

    func advance(to revision: Int64) {
        guard revision >= (currentRevision ?? 0) else { return }
        currentRevision = revision
        lastSyncAt = Date()
    }

    func hasAppliedRevision(_ revision: Int64) -> Bool {
        appliedRevisions.contains(revision)
    }

    func markRevisionApplied(_ revision: Int64) {
        appliedRevisions.insert(revision)
        if appliedRevisions.count > 2_000 {
            let sorted = appliedRevisions.sorted()
            appliedRevisions = Set(sorted.suffix(1_000))
        }
    }

    func reset() {
        currentRevision = nil
        lastSyncAt = nil
        appliedRevisions.removeAll()
    }
}
