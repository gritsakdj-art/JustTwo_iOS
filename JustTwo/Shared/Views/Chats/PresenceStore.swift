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

struct PresenceState: Equatable, Sendable {
    let status: PresenceStatus
    let lastSeenAt: Date?
    let updatedAt: Date
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

    private(set) var statuses: [UUID: PresenceState] = [:]

    private init() {}

    static func makeForTesting() -> PresenceStore {
        PresenceStore()
    }

    func apply(profileID: UUID, status: PresenceStatus, lastSeenAt: Date?) {
        guard status != .unknown else { return }

        statuses[profileID] = PresenceState(
            status: status,
            lastSeenAt: lastSeenAt,
            updatedAt: Date()
        )
    }

    func apply(_ payload: PresenceChangedPayload) {
        apply(
            profileID: payload.profileID,
            status: payload.status,
            lastSeenAt: payload.lastSeenAt
        )
    }

    func isOnline(profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return statuses[profileID]?.status == .online
    }

    func lastSeenAt(profileID: UUID?) -> Date? {
        guard let profileID else { return nil }
        return statuses[profileID]?.lastSeenAt
    }

    func clearAll() {
        statuses.removeAll()
    }
}
