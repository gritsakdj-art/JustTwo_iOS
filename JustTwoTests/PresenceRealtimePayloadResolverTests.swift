@testable import JustTwo
import Foundation
import Testing

@Suite("PresenceRealtimePayloadResolver Tests")
struct PresenceRealtimePayloadResolverTests {

    @Test("isOnline present uses isOnline")
    func isOnlinePresent() {
        let resolved = PresenceRealtimePayloadResolver.resolve(
            isOnline: true,
            status: "offline",
            lastSeenAt: nil
        )
        #expect(resolved?.isOnline == true)
        #expect(resolved?.hadStatusConflict == true)
    }

    @Test("legacy status online fallback")
    func legacyStatusOnline() {
        let resolved = PresenceRealtimePayloadResolver.resolve(
            isOnline: nil,
            status: "online",
            lastSeenAt: nil
        )
        #expect(resolved?.isOnline == true)
        #expect(resolved?.hadStatusConflict == false)
    }

    @Test("legacy status offline fallback")
    func legacyStatusOffline() {
        let resolved = PresenceRealtimePayloadResolver.resolve(
            isOnline: nil,
            status: "offline",
            lastSeenAt: Date(timeIntervalSince1970: 1_000)
        )
        #expect(resolved?.isOnline == false)
        #expect(resolved?.lastSeenAt != nil)
    }

    @Test("unknown status without isOnline returns nil")
    func unknownStatusReturnsNil() {
        let resolved = PresenceRealtimePayloadResolver.resolve(
            isOnline: nil,
            status: "away",
            lastSeenAt: nil
        )
        #expect(resolved == nil)
    }

    @Test("missing status and isOnline returns nil")
    func missingFieldsReturnsNil() {
        #expect(PresenceRealtimePayloadResolver.resolve(isOnline: nil, status: nil, lastSeenAt: nil) == nil)
    }

    @Test("isOnline false with null lastSeenAt")
    func isOnlineFalseNullLastSeen() {
        let resolved = PresenceRealtimePayloadResolver.resolve(
            isOnline: false,
            status: nil,
            lastSeenAt: nil
        )
        #expect(resolved?.isOnline == false)
        #expect(resolved?.lastSeenAt == nil)
    }
}
