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

    init(isOnline: Bool) {
        self = isOnline ? .online : .offline
    }
}

enum PresenceSource: String, Equatable, Sendable {
    /// Cached `lastSeenAt` only — never authoritative online.
    case cache
    /// REST conversation snapshot (`GET /conversations`, read/delivered, invite accept).
    case rest
    /// Live rebuilt `ConversationDTO` from sync response — snapshot, not historical revision.
    case sync
    /// Backend `presence.changed` — authoritative for `isOnline` in the current realtime connection epoch.
    case realtime
    /// Ephemeral local activity hint from typing.started. Not authoritative.
    case typingHint
    /// Locally retained across reconnect; provisional until realtime confirms.
    case preserved
    case unknown
}

enum PresenceDisplaySemantic: String, Equatable, Sendable {
    case typing
    case online
    case lastSeen
    case unknown
}

struct PresenceDisplayState: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case typing
        case online
        case lastSeen(String)
        case unknown
    }

    let kind: Kind
    let accessibilityLabel: String?
}

struct PresenceState: Equatable, Sendable {
    let status: PresenceStatus
    let lastSeenAt: Date?
    let updatedAt: Date
    let source: PresenceSource
    /// Absolute expiry for ephemeral/provisional sources. Nil = no TTL.
    let expiresAt: Date?
    let sessionGeneration: Int?
    let realtimeConnectionEpoch: Int?
}

struct PresenceChangedPayload: Equatable, Sendable {
    let profileID: UUID
    let isOnline: Bool
    let lastSeenAt: Date?

    var status: PresenceStatus {
        PresenceStatus(isOnline: isOnline)
    }
}

@MainActor
@Observable
final class PresenceStore {

    static let shared = PresenceStore()

    /// Typing hints expire if typing.stopped is missed.
    static let typingHintTTL: TimeInterval = 15
    /// Preserved reconnect state expires without realtime confirmation.
    static let preservedPresenceTTL: TimeInterval = 90

    private(set) var statuses: [UUID: PresenceState] = [:]
    private var monotonicLastSeenAt: [UUID: Date] = [:]
    private var realtimeAuthoritativeEpochByProfile: [UUID: Int] = [:]
    private var typingHintExpiresAt: [UUID: Date] = [:]
    private var previousDisplaySemantics: [UUID: PresenceDisplaySemantic] = [:]
    private var sessionGeneration = 0
    private var realtimeConnectionEpoch = 0
    private var nowProvider: () -> Date = { Date() }

    private init() {}

    static func makeForTesting(now: @escaping () -> Date = { Date() }) -> PresenceStore {
        let store = PresenceStore()
        store.nowProvider = now
        return store
    }

    var currentSessionGeneration: Int {
        sessionGeneration
    }

    var currentRealtimeConnectionEpoch: Int {
        realtimeConnectionEpoch
    }

    #if DEBUG
    func setSessionGenerationForTesting(_ generation: Int) {
        sessionGeneration = generation
    }

    func setRealtimeConnectionEpochForTesting(_ epoch: Int) {
        realtimeConnectionEpoch = epoch
    }
    #endif

    // MARK: - Connection epoch

    /// Increments realtime connection epoch, preserves provisional online, clears epoch authority markers.
    func beginRealtimeReconnectCycle() {
        realtimeConnectionEpoch += 1
        markAllPreservedAcrossReconnect()
        MessengerDiagnostics.event(
            .presenceCacheLoaded,
            metadata: [
                "source": "preserved",
                "reason": "realtimeReconnectCycleBegan",
                "realtimeConnectionEpoch": "\(realtimeConnectionEpoch)",
                "trackedCount": "\(trackedCount)"
            ]
        )
    }

    // MARK: - Snapshot application

    @discardableResult
    func applySnapshot(
        profileID: UUID,
        isOnline: Bool,
        lastSeenAt: Date?,
        source: PresenceSource,
        observedAt: Date? = nil,
        sessionGeneration: Int? = nil,
        requestConnectionEpoch: Int? = nil,
        realtimeConnectionEpoch: Int? = nil
    ) -> Bool {
        let generation = sessionGeneration ?? self.sessionGeneration
        guard generation == self.sessionGeneration else { return false }

        let now = observedAt ?? nowProvider()
        let status = PresenceStatus(isOnline: isOnline)

        switch source {
        case .realtime:
            return applyRealtime(
                profileID: profileID,
                status: status,
                lastSeenAt: lastSeenAt,
                observedAt: now,
                sessionGeneration: generation,
                connectionEpoch: realtimeConnectionEpoch ?? self.realtimeConnectionEpoch
            )

        case .cache:
            return hydrateCachedLastSeen(
                profileID: profileID,
                lastSeenAt: lastSeenAt,
                observedAt: now,
                sessionGeneration: generation
            )

        case .rest, .sync:
            return applyRESTOrSyncSnapshot(
                profileID: profileID,
                isOnline: isOnline,
                lastSeenAt: lastSeenAt,
                source: source,
                observedAt: now,
                sessionGeneration: generation,
                requestConnectionEpoch: requestConnectionEpoch
            )

        case .preserved:
            return applyPreserved(
                profileID: profileID,
                status: status,
                lastSeenAt: lastSeenAt,
                observedAt: now,
                sessionGeneration: generation
            )

        case .typingHint, .unknown:
            return false
        }
    }

    @discardableResult
    func applyPresenceSummary(
        profileID: UUID,
        summary: PresenceSummaryDTO,
        source: PresenceSource,
        observedAt: Date? = nil,
        sessionGeneration: Int? = nil,
        requestConnectionEpoch: Int? = nil
    ) -> Bool {
        applySnapshot(
            profileID: profileID,
            isOnline: summary.isOnline,
            lastSeenAt: summary.lastSeenAt,
            source: source,
            observedAt: observedAt,
            sessionGeneration: sessionGeneration,
            requestConnectionEpoch: requestConnectionEpoch
        )
    }

    func applyFromConversation(
        _ conversation: ConversationDTO,
        source: PresenceSource,
        observedAt: Date? = nil,
        sessionGeneration: Int? = nil,
        requestConnectionEpoch: Int? = nil
    ) {
        guard let profile = conversation.otherParticipant?.profile,
              let presence = profile.presence else { return }

        MessengerDiagnostics.event(
            .presenceSnapshotReceived,
            metadata: diagnosticMetadata(
                profileID: profile.id,
                source: source,
                incomingOnline: presence.isOnline,
                previousOnline: isOnline(profileID: profile.id),
                hasLastSeenAt: presence.lastSeenAt != nil,
                sessionGeneration: sessionGeneration ?? self.sessionGeneration,
                realtimeConnectionEpoch: requestConnectionEpoch ?? realtimeConnectionEpoch
            )
        )

        _ = applyPresenceSummary(
            profileID: profile.id,
            summary: presence,
            source: source,
            observedAt: observedAt,
            sessionGeneration: sessionGeneration,
            requestConnectionEpoch: requestConnectionEpoch
        )
    }

    func applyFromConversations(
        _ conversations: [ConversationDTO],
        source: PresenceSource,
        observedAt: Date? = nil,
        sessionGeneration: Int? = nil,
        requestConnectionEpoch: Int? = nil
    ) {
        for conversation in conversations {
            applyFromConversation(
                conversation,
                source: source,
                observedAt: observedAt,
                sessionGeneration: sessionGeneration,
                requestConnectionEpoch: requestConnectionEpoch
            )
        }
    }

    func hydrateFromCacheSnapshots(
        _ snapshots: [LocalConversationSnapshot],
        sessionGeneration: Int? = nil
    ) {
        let generation = sessionGeneration ?? self.sessionGeneration
        let now = nowProvider()

        for snapshot in snapshots {
            guard let profileIDString = snapshot.otherParticipantProfileID,
                  let profileID = UUID(uuidString: profileIDString),
                  let lastSeenAt = snapshot.otherParticipantLastSeenAt else {
                continue
            }

            MessengerDiagnostics.event(
                .presenceCacheHydrated,
                metadata: diagnosticMetadata(
                    profileID: profileID,
                    source: .cache,
                    incomingOnline: false,
                    previousOnline: isOnline(profileID: profileID),
                    hasLastSeenAt: true,
                    sessionGeneration: generation,
                    realtimeConnectionEpoch: realtimeConnectionEpoch
                )
            )

            _ = hydrateCachedLastSeen(
                profileID: profileID,
                lastSeenAt: lastSeenAt,
                observedAt: now,
                sessionGeneration: generation
            )
        }
    }

    @discardableResult
    func apply(
        profileID: UUID,
        status: PresenceStatus,
        lastSeenAt: Date?,
        source: PresenceSource = .realtime,
        observedAt: Date? = nil,
        sessionGeneration: Int? = nil,
        realtimeConnectionEpoch: Int? = nil
    ) -> Bool {
        guard status != .unknown else { return false }
        return applySnapshot(
            profileID: profileID,
            isOnline: status == .online,
            lastSeenAt: lastSeenAt,
            source: source,
            observedAt: observedAt,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: realtimeConnectionEpoch
        )
    }

    @discardableResult
    func apply(
        _ payload: PresenceChangedPayload,
        connectionEpoch: Int? = nil,
        sessionGeneration: Int? = nil
    ) -> Bool {
        applySnapshot(
            profileID: payload.profileID,
            isOnline: payload.isOnline,
            lastSeenAt: payload.lastSeenAt,
            source: .realtime,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: connectionEpoch ?? realtimeConnectionEpoch
        )
    }

    /// Ephemeral typing hint — separate from authoritative presence state.
    @discardableResult
    func applyTypingOnlineHint(profileID: UUID) -> Bool {
        if hasRealtimeAuthorityInCurrentEpoch(profileID),
           statuses[profileID]?.status == .offline {
            return false
        }

        typingHintExpiresAt[profileID] = nowProvider().addingTimeInterval(Self.typingHintTTL)
        recordDisplayTransition(profileID: profileID)
        return true
    }

    func clearTypingHint(profileID: UUID) {
        guard typingHintExpiresAt[profileID] != nil else { return }
        typingHintExpiresAt.removeValue(forKey: profileID)
        recordDisplayTransition(profileID: profileID)
    }

    /// Mark current online entries as provisional after reconnect (bounded TTL).
    func markAllPreservedAcrossReconnect() {
        let now = nowProvider()
        var next: [UUID: PresenceState] = [:]
        for (profileID, state) in statuses {
            guard state.status == .online else { continue }
            if let expiresAt = state.expiresAt, expiresAt <= now { continue }
            next[profileID] = PresenceState(
                status: .online,
                lastSeenAt: resolvedLastSeen(for: profileID, incoming: state.lastSeenAt),
                updatedAt: now,
                source: .preserved,
                expiresAt: now.addingTimeInterval(Self.preservedPresenceTTL),
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch
            )
        }
        statuses = next
        for profileID in next.keys {
            recordDisplayTransition(profileID: profileID)
        }
    }

    func isOnline(profileID: UUID?) -> Bool {
        guard let profileID, let state = effectiveState(for: profileID) else { return false }
        return state.status == .online
    }

    func isTypingHint(profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        pruneTypingHints(profileID: profileID)
        guard let expiresAt = typingHintExpiresAt[profileID] else { return false }
        return expiresAt > nowProvider()
    }

    func lastSeenAt(profileID: UUID?) -> Date? {
        guard let profileID else { return nil }
        return resolvedLastSeen(for: profileID, incoming: effectiveState(for: profileID)?.lastSeenAt)
    }

    func source(for profileID: UUID?) -> PresenceSource? {
        guard let profileID else { return nil }
        return effectiveState(for: profileID)?.source
    }

    func hasKnownPresence(profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return effectiveState(for: profileID) != nil
            || monotonicLastSeenAt[profileID] != nil
            || isTypingHint(profileID: profileID)
    }

    var trackedCount: Int {
        pruneExpired()
        pruneTypingHints()
        return statuses.count
    }

    func clearAll() {
        statuses.removeAll()
        monotonicLastSeenAt.removeAll()
        realtimeAuthoritativeEpochByProfile.removeAll()
        typingHintExpiresAt.removeAll()
        previousDisplaySemantics.removeAll()
        sessionGeneration += 1
        realtimeConnectionEpoch = 0
    }

    // MARK: - Private

    private func hasRealtimeAuthorityInCurrentEpoch(_ profileID: UUID) -> Bool {
        realtimeAuthoritativeEpochByProfile[profileID] == realtimeConnectionEpoch
    }

    @discardableResult
    private func applyRealtime(
        profileID: UUID,
        status: PresenceStatus,
        lastSeenAt: Date?,
        observedAt: Date,
        sessionGeneration: Int,
        connectionEpoch: Int
    ) -> Bool {
        guard status != .unknown else { return false }

        guard connectionEpoch == realtimeConnectionEpoch else {
            MessengerDiagnostics.event(
                .presenceRealtimeEpochIgnored,
                metadata: diagnosticMetadata(
                    profileID: profileID,
                    source: .realtime,
                    incomingOnline: status == .online,
                    previousOnline: isOnline(profileID: profileID),
                    hasLastSeenAt: lastSeenAt != nil,
                    sessionGeneration: sessionGeneration,
                    realtimeConnectionEpoch: connectionEpoch,
                    reason: "staleRealtimeEpoch"
                )
            )
            return false
        }

        realtimeAuthoritativeEpochByProfile[profileID] = realtimeConnectionEpoch

        if status == .offline {
            clearTypingHint(profileID: profileID)
        }

        let previousOnline = isOnline(profileID: profileID)
        let (mergedLastSeen, didAdvance) = advanceMonotonicLastSeen(profileID: profileID, incoming: lastSeenAt)

        statuses[profileID] = PresenceState(
            status: status,
            lastSeenAt: mergedLastSeen,
            updatedAt: observedAt,
            source: .realtime,
            expiresAt: nil,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: connectionEpoch
        )

        logSnapshotApplied(
            profileID: profileID,
            source: .realtime,
            incomingOnline: status == .online,
            previousOnline: previousOnline,
            hasLastSeenAt: mergedLastSeen != nil,
            didAdvanceLastSeen: didAdvance,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: connectionEpoch
        )
        recordDisplayTransition(profileID: profileID)
        return true
    }

    @discardableResult
    private func applyRESTOrSyncSnapshot(
        profileID: UUID,
        isOnline: Bool,
        lastSeenAt: Date?,
        source: PresenceSource,
        observedAt: Date,
        sessionGeneration: Int,
        requestConnectionEpoch: Int?
    ) -> Bool {
        let previousOnline = self.isOnline(profileID: profileID)
        let (mergedLastSeen, didAdvance) = advanceMonotonicLastSeen(profileID: profileID, incoming: lastSeenAt)
        let requestEpoch = requestConnectionEpoch ?? realtimeConnectionEpoch

        if requestEpoch != realtimeConnectionEpoch {
            MessengerDiagnostics.event(
                .presenceStaleRequestIgnored,
                metadata: diagnosticMetadata(
                    profileID: profileID,
                    source: source,
                    incomingOnline: isOnline,
                    previousOnline: previousOnline,
                    hasLastSeenAt: mergedLastSeen != nil,
                    didAdvanceLastSeen: didAdvance,
                    sessionGeneration: sessionGeneration,
                    realtimeConnectionEpoch: requestEpoch,
                    reason: "staleRequestConnectionEpoch"
                )
            )
            if didAdvance {
                logLastSeenAdvanced(profileID: profileID, source: source, sessionGeneration: sessionGeneration)
            }
            recordDisplayTransition(profileID: profileID)
            return didAdvance
        }

        if hasRealtimeAuthorityInCurrentEpoch(profileID) {
            if let existing = statuses[profileID] {
                statuses[profileID] = PresenceState(
                    status: existing.status,
                    lastSeenAt: mergedLastSeen,
                    updatedAt: existing.updatedAt,
                    source: existing.source,
                    expiresAt: existing.expiresAt,
                    sessionGeneration: existing.sessionGeneration,
                    realtimeConnectionEpoch: existing.realtimeConnectionEpoch
                )
            }

            logSnapshotIgnored(
                profileID: profileID,
                source: source,
                reason: "realtimeAuthorityCurrentEpoch",
                incomingOnline: isOnline,
                previousOnline: previousOnline,
                hasLastSeenAt: mergedLastSeen != nil,
                didAdvanceLastSeen: didAdvance,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch
            )

            if didAdvance {
                logLastSeenAdvanced(profileID: profileID, source: source, sessionGeneration: sessionGeneration)
            } else if lastSeenAt != nil {
                logLastSeenIgnoredOlder(profileID: profileID, source: source, sessionGeneration: sessionGeneration)
            }

            recordDisplayTransition(profileID: profileID)
            return didAdvance
        }

        statuses[profileID] = PresenceState(
            status: PresenceStatus(isOnline: isOnline),
            lastSeenAt: mergedLastSeen,
            updatedAt: observedAt,
            source: source,
            expiresAt: nil,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: realtimeConnectionEpoch
        )

        logSnapshotApplied(
            profileID: profileID,
            source: source,
            incomingOnline: isOnline,
            previousOnline: previousOnline,
            hasLastSeenAt: mergedLastSeen != nil,
            didAdvanceLastSeen: didAdvance,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: realtimeConnectionEpoch
        )
        recordDisplayTransition(profileID: profileID)
        return true
    }

    @discardableResult
    private func hydrateCachedLastSeen(
        profileID: UUID,
        lastSeenAt: Date?,
        observedAt: Date,
        sessionGeneration: Int
    ) -> Bool {
        guard let lastSeenAt else { return false }

        let previousOnline = isOnline(profileID: profileID)
        let (mergedLastSeen, didAdvance) = advanceMonotonicLastSeen(profileID: profileID, incoming: lastSeenAt)
        guard didAdvance else {
            logLastSeenIgnoredOlder(profileID: profileID, source: .cache, sessionGeneration: sessionGeneration)
            return false
        }

        if statuses[profileID] == nil || !hasRealtimeAuthorityInCurrentEpoch(profileID) {
            let existing = statuses[profileID]
            statuses[profileID] = PresenceState(
                status: .offline,
                lastSeenAt: mergedLastSeen,
                updatedAt: observedAt,
                source: existing?.source == .preserved || existing?.source == .rest || existing?.source == .sync
                    ? existing!.source
                    : .cache,
                expiresAt: existing?.expiresAt,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: existing?.realtimeConnectionEpoch
            )
        } else if let existing = statuses[profileID] {
            statuses[profileID] = PresenceState(
                status: existing.status,
                lastSeenAt: mergedLastSeen,
                updatedAt: existing.updatedAt,
                source: existing.source,
                expiresAt: existing.expiresAt,
                sessionGeneration: existing.sessionGeneration,
                realtimeConnectionEpoch: existing.realtimeConnectionEpoch
            )
        }

        logSnapshotApplied(
            profileID: profileID,
            source: .cache,
            incomingOnline: false,
            previousOnline: previousOnline,
            hasLastSeenAt: true,
            didAdvanceLastSeen: true,
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: realtimeConnectionEpoch
        )
        recordDisplayTransition(profileID: profileID)
        return true
    }

    @discardableResult
    private func applyPreserved(
        profileID: UUID,
        status: PresenceStatus,
        lastSeenAt: Date?,
        observedAt: Date,
        sessionGeneration: Int
    ) -> Bool {
        guard status != .unknown else { return false }

        if hasRealtimeAuthorityInCurrentEpoch(profileID) {
            return false
        }

        let (mergedLastSeen, _) = advanceMonotonicLastSeen(profileID: profileID, incoming: lastSeenAt)
        statuses[profileID] = PresenceState(
            status: status,
            lastSeenAt: mergedLastSeen,
            updatedAt: observedAt,
            source: .preserved,
            expiresAt: observedAt.addingTimeInterval(Self.preservedPresenceTTL),
            sessionGeneration: sessionGeneration,
            realtimeConnectionEpoch: realtimeConnectionEpoch
        )
        recordDisplayTransition(profileID: profileID)
        return true
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
                recordDisplayTransition(profileID: profileID)
            }
            return
        }

        let expiredIDs = statuses.compactMap { key, state -> UUID? in
            guard let expiresAt = state.expiresAt, expiresAt <= now else { return nil }
            return key
        }
        for profileID in expiredIDs {
            statuses.removeValue(forKey: profileID)
            recordDisplayTransition(profileID: profileID)
        }
    }

    private func pruneTypingHints(profileID: UUID? = nil) {
        let now = nowProvider()
        if let profileID {
            if let expiresAt = typingHintExpiresAt[profileID], expiresAt <= now {
                typingHintExpiresAt.removeValue(forKey: profileID)
                recordDisplayTransition(profileID: profileID)
            }
            return
        }

        let expired = typingHintExpiresAt.filter { $0.value <= now }.map(\.key)
        for profileID in expired {
            typingHintExpiresAt.removeValue(forKey: profileID)
            recordDisplayTransition(profileID: profileID)
        }
    }

    private func resolvedLastSeen(for profileID: UUID, incoming: Date?) -> Date? {
        Self.mergeLastSeen(current: monotonicLastSeenAt[profileID], incoming: incoming)
    }

    @discardableResult
    private func advanceMonotonicLastSeen(profileID: UUID, incoming: Date?) -> (Date?, Bool) {
        let current = resolvedLastSeen(for: profileID, incoming: statuses[profileID]?.lastSeenAt)
        let merged = Self.mergeLastSeen(current: current, incoming: incoming)
        let didAdvance = merged != current && incoming != nil
        if let merged {
            monotonicLastSeenAt[profileID] = merged
        }
        return (merged, didAdvance)
    }

    static func mergeLastSeen(current: Date?, incoming: Date?) -> Date? {
        switch (current, incoming) {
        case (nil, nil):
            return nil
        case (nil, let incoming?):
            return incoming
        case (let current?, nil):
            return current
        case (let current?, let incoming?):
            return max(current, incoming)
        }
    }

    private func recordDisplayTransition(profileID: UUID) {
        let semantic = displaySemantic(for: profileID)
        let previous = previousDisplaySemantics[profileID]
        guard previous != semantic else { return }
        previousDisplaySemantics[profileID] = semantic

        #if DEBUG
        MessengerDiagnostics.event(
            .presenceDisplayStateChanged,
            metadata: diagnosticMetadata(
                profileID: profileID,
                source: source(for: profileID) ?? .unknown,
                incomingOnline: isOnline(profileID: profileID),
                previousOnline: previous == .online,
                hasLastSeenAt: lastSeenAt(profileID: profileID) != nil,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch,
                reason: semantic.rawValue
            )
        )
        #endif
    }

    func displaySemantic(for profileID: UUID) -> PresenceDisplaySemantic {
        if isTypingHint(profileID: profileID) {
            return .typing
        }
        if isOnline(profileID: profileID) {
            return .online
        }
        if lastSeenAt(profileID: profileID) != nil {
            return .lastSeen
        }
        return .unknown
    }

    private func logSnapshotApplied(
        profileID: UUID,
        source: PresenceSource,
        incomingOnline: Bool,
        previousOnline: Bool,
        hasLastSeenAt: Bool,
        didAdvanceLastSeen: Bool,
        sessionGeneration: Int,
        realtimeConnectionEpoch: Int
    ) {
        MessengerDiagnostics.event(
            .presenceSnapshotApplied,
            metadata: diagnosticMetadata(
                profileID: profileID,
                source: source,
                incomingOnline: incomingOnline,
                previousOnline: previousOnline,
                hasLastSeenAt: hasLastSeenAt,
                didAdvanceLastSeen: didAdvanceLastSeen,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch
            )
        )
        if didAdvanceLastSeen {
            logLastSeenAdvanced(profileID: profileID, source: source, sessionGeneration: sessionGeneration)
        }
    }

    private func logSnapshotIgnored(
        profileID: UUID,
        source: PresenceSource,
        reason: String,
        incomingOnline: Bool,
        previousOnline: Bool,
        hasLastSeenAt: Bool,
        didAdvanceLastSeen: Bool,
        sessionGeneration: Int,
        realtimeConnectionEpoch: Int
    ) {
        MessengerDiagnostics.event(
            .presenceSnapshotIgnoredRealtimeNewer,
            metadata: diagnosticMetadata(
                profileID: profileID,
                source: source,
                incomingOnline: incomingOnline,
                previousOnline: previousOnline,
                hasLastSeenAt: hasLastSeenAt,
                didAdvanceLastSeen: didAdvanceLastSeen,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch,
                reason: reason
            )
        )
    }

    private func logLastSeenAdvanced(profileID: UUID, source: PresenceSource, sessionGeneration: Int) {
        MessengerDiagnostics.event(
            .presenceLastSeenAdvanced,
            metadata: diagnosticMetadata(
                profileID: profileID,
                source: source,
                incomingOnline: isOnline(profileID: profileID),
                previousOnline: isOnline(profileID: profileID),
                hasLastSeenAt: true,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch
            )
        )
    }

    private func logLastSeenIgnoredOlder(profileID: UUID, source: PresenceSource, sessionGeneration: Int) {
        MessengerDiagnostics.event(
            .presenceLastSeenIgnoredOlder,
            metadata: diagnosticMetadata(
                profileID: profileID,
                source: source,
                incomingOnline: false,
                previousOnline: isOnline(profileID: profileID),
                hasLastSeenAt: true,
                sessionGeneration: sessionGeneration,
                realtimeConnectionEpoch: realtimeConnectionEpoch
            )
        )
    }

    private func diagnosticMetadata(
        profileID: UUID,
        source: PresenceSource,
        incomingOnline: Bool,
        previousOnline: Bool,
        hasLastSeenAt: Bool,
        didAdvanceLastSeen: Bool = false,
        sessionGeneration: Int,
        realtimeConnectionEpoch: Int? = nil,
        reason: String? = nil
    ) -> [String: String] {
        var metadata: [String: String] = [
            "profileID": MessengerDiagnostics.sanitizeID(profileID),
            "source": source.rawValue,
            "incomingOnline": "\(incomingOnline)",
            "previousOnline": "\(previousOnline)",
            "hasLastSeenAt": "\(hasLastSeenAt)",
            "didAdvanceLastSeen": "\(didAdvanceLastSeen)",
            "sessionGeneration": "\(sessionGeneration)"
        ]
        if let realtimeConnectionEpoch {
            metadata["realtimeConnectionEpoch"] = "\(realtimeConnectionEpoch)"
        }
        if let reason {
            metadata["reason"] = reason
        }
        return metadata
    }
}
