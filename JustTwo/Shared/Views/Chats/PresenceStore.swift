import Foundation

enum PresenceStatus: Equatable, Sendable {
    case online
    case offline
    case unknown

    init(serverValue: String) {
        switch serverValue {
        case "online":
            self = .online
        case "offline":
            self = .offline
        default:
            self = .unknown
        }
    }
}

enum PresenceSource: String, Equatable, Sendable {
    /// Backend `presence.changed` — authoritative.
    case realtime
    /// Ephemeral local activity hint from typing.started. Not authoritative.
    case typingHint
    /// Locally retained across reconnect; provisional until realtime confirms.
    case preserved
    case unknown
}

struct PresenceState: Equatable, Sendable {
    let status: PresenceStatus
    let lastSeenAt: Date?
    let updatedAt: Date
    let source: PresenceSource
    /// Absolute expiry for ephemeral/provisional sources. Nil = no TTL.
    let expiresAt: Date?
}

struct PresenceChangedPayload: Equatable, Sendable {
    let profileID: UUID
    let status: PresenceStatus
    let lastSeenAt: Date?
}

@MainActor
@Observable
final class PresenceStore {

    static let shared = PresenceStore()

    /// Typing hints expire if typing.stopped is missed.
    static let typingHintTTL: TimeInterval = 15
    /// Preserved reconnect state expires without realtime confirmation (PR20B/C for full fix).
    static let preservedPresenceTTL: TimeInterval = 90

    private(set) var statuses: [UUID: PresenceState] = [:]
    private var nowProvider: () -> Date = { Date() }

    private init() {}

    static func makeForTesting(now: @escaping () -> Date = { Date() }) -> PresenceStore {
        let store = PresenceStore()
        store.nowProvider = now
        return store
    }

    @discardableResult
    func apply(
        profileID: UUID,
        status: PresenceStatus,
        lastSeenAt: Date?,
        source: PresenceSource = .realtime,
        expiresAt: Date? = nil
    ) -> Bool {
        guard status != .unknown else { return false }

        let previous = statuses[profileID]
        // Typing hints must not overwrite an authoritative offline from realtime.
        if source == .typingHint,
           previous?.source == .realtime,
           previous?.status == .offline {
            return false
        }
        // Preserved must not overwrite fresher realtime.
        if source == .preserved, previous?.source == .realtime {
            return false
        }

        let resolvedExpiry: Date?
        switch source {
        case .typingHint:
            resolvedExpiry = expiresAt ?? nowProvider().addingTimeInterval(Self.typingHintTTL)
        case .preserved:
            resolvedExpiry = expiresAt ?? nowProvider().addingTimeInterval(Self.preservedPresenceTTL)
        case .realtime, .unknown:
            resolvedExpiry = nil
        }

        statuses[profileID] = PresenceState(
            status: status,
            lastSeenAt: lastSeenAt,
            updatedAt: nowProvider(),
            source: source,
            expiresAt: resolvedExpiry
        )
        return true
    }

    @discardableResult
    func apply(_ payload: PresenceChangedPayload) -> Bool {
        apply(
            profileID: payload.profileID,
            status: payload.status,
            lastSeenAt: payload.lastSeenAt,
            source: .realtime,
            expiresAt: nil
        )
    }

    /// Ephemeral online hint while peer is typing. Not persisted; TTL-bounded.
    @discardableResult
    func applyTypingOnlineHint(profileID: UUID) -> Bool {
        apply(profileID: profileID, status: .online, lastSeenAt: nil, source: .typingHint)
    }

    /// Clears typing hint only; does not invent offline for realtime/preserved.
    func clearTypingHint(profileID: UUID) {
        guard let existing = statuses[profileID], existing.source == .typingHint else { return }
        statuses.removeValue(forKey: profileID)
    }

    /// Mark current entries as provisional after reconnect (bounded TTL).
    func markAllPreservedAcrossReconnect() {
        let now = nowProvider()
        var next: [UUID: PresenceState] = [:]
        for (profileID, state) in statuses {
            guard state.status == .online else { continue }
            if let expiresAt = state.expiresAt, expiresAt <= now { continue }
            next[profileID] = PresenceState(
                status: .online,
                lastSeenAt: state.lastSeenAt,
                updatedAt: now,
                source: .preserved,
                expiresAt: now.addingTimeInterval(Self.preservedPresenceTTL)
            )
        }
        statuses = next
    }

    func isOnline(profileID: UUID?) -> Bool {
        guard let profileID, let state = effectiveState(for: profileID) else { return false }
        return state.status == .online
    }

    func lastSeenAt(profileID: UUID?) -> Date? {
        guard let profileID else { return nil }
        return effectiveState(for: profileID)?.lastSeenAt
    }

    func source(for profileID: UUID?) -> PresenceSource? {
        guard let profileID else { return nil }
        return effectiveState(for: profileID)?.source
    }

    var trackedCount: Int {
        pruneExpired()
        return statuses.count
    }

    func clearAll() {
        statuses.removeAll()
    }

    private func effectiveState(for profileID: UUID) -> PresenceState? {
        pruneExpired(profileID: profileID)
        return statuses[profileID]
    }

    private func pruneExpired(profileID: UUID? = nil) {
        let now = nowProvider()
        if let profileID {
            if let state = statuses[profileID],
               let expiresAt = state.expiresAt,
               expiresAt <= now {
                statuses.removeValue(forKey: profileID)
            }
            return
        }

        statuses = statuses.filter { _, state in
            guard let expiresAt = state.expiresAt else { return true }
            return expiresAt > now
        }
    }
}
