@testable import JustTwo
import Foundation
import Testing

@Suite("PresenceDisplayResolver Tests", .serialized)
@MainActor
struct PresenceDisplayResolverTests {

    @Test("typing wins over online")
    func typingWinsOverOnline() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        _ = store.applyTypingOnlineHint(profileID: profileID)
        _ = store.applySnapshot(profileID: profileID, isOnline: true, lastSeenAt: nil, source: .realtime)

        let display = PresenceDisplayResolver.resolve(
            presenceStore: store,
            profileID: profileID,
            isTyping: store.isTypingHint(profileID: profileID)
        )

        #expect(display.text == String(localized: "chats.typing"))
    }

    @Test("offline last seen shown when not typing")
    func offlineLastSeenShown() {
        let store = PresenceStore.makeForTesting()
        let profileID = fixedProfileID()
        let lastSeen = Date(timeIntervalSince1970: 1_000)
        let formatter = LastSeenStatusFormatter(
            now: Date(timeIntervalSince1970: 2_000),
            calendar: utcCalendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        _ = store.applySnapshot(profileID: profileID, isOnline: false, lastSeenAt: lastSeen, source: .rest)

        let display = PresenceDisplayResolver.resolve(
            presenceStore: store,
            profileID: profileID,
            isTyping: false,
            formatter: formatter
        )

        #expect(display.text != nil)
        #expect(display.text?.contains("Online") == false)
    }

    @Test("nil profile returns nil display")
    func nilProfileReturnsNil() {
        let store = PresenceStore.makeForTesting()
        let display = PresenceDisplayResolver.resolve(
            presenceStore: store,
            profileID: nil,
            isTyping: false
        )
        #expect(display.text == nil)
        #expect(display.accessibilityLabel == nil)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func fixedProfileID() -> UUID {
        UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    }
}
