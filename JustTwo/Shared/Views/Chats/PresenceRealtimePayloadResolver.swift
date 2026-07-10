import Foundation

enum PresenceRealtimePayloadResolver {

    struct Resolved: Equatable, Sendable {
        let isOnline: Bool
        let lastSeenAt: Date?
        let hadStatusConflict: Bool
    }

    /// `isOnline` wins when present; `status` is backward-compatible fallback only.
    static func resolve(
        isOnline: Bool?,
        status: String?,
        lastSeenAt: Date?
    ) -> Resolved? {
        let resolvedOnline: Bool?
        var hadConflict = false

        if let isOnline {
            resolvedOnline = isOnline
            if let status {
                let statusOnline: Bool?
                switch status {
                case "online": statusOnline = true
                case "offline": statusOnline = false
                default: statusOnline = nil
                }
                if let statusOnline, statusOnline != isOnline {
                    hadConflict = true
                }
            }
        } else if let status {
            switch status {
            case "online":
                resolvedOnline = true
            case "offline":
                resolvedOnline = false
            default:
                resolvedOnline = nil
            }
        } else {
            resolvedOnline = nil
        }

        guard let resolvedOnline else { return nil }

        return Resolved(
            isOnline: resolvedOnline,
            lastSeenAt: lastSeenAt,
            hadStatusConflict: hadConflict
        )
    }
}
