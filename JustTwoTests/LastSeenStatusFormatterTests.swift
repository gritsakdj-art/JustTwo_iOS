@testable import JustTwo
import Foundation
import Testing

@Suite("LastSeenStatusFormatter Tests")
struct LastSeenStatusFormatterTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    @Test("online status")
    func onlineStatus() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        #expect(formatter.displayKind(isOnline: true, lastSeenAt: nil) == .online)
        #expect(formatter.localizedStatus(isOnline: true, lastSeenAt: nil) == "Online")
    }

    @Test("minutes ago within one hour")
    func minutesAgo() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T14:55:00Z"))
        #expect(kind == .minutesAgo(5))
        let text = formatter.localizedStatus(isOnline: false, lastSeenAt: date("2026-07-10T14:55:00Z"))
        #expect(text == "last seen 5 min ago")
        #expect(text?.contains("presence.lastSeen") == false)
    }

    @Test("today uses calendar day boundary")
    func todayBoundary() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T08:30:00Z"))
        guard case .today(let time) = kind else {
            Issue.record("Expected today")
            return
        }
        #expect(!time.isEmpty)
    }

    @Test("yesterday boundary")
    func yesterdayBoundary() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-09T22:00:00Z"))
        guard case .yesterday = kind else {
            Issue.record("Expected yesterday")
            return
        }
    }

    @Test("weekday for two to seven days")
    func weekdayRange() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-05T12:00:00Z"))
        guard case .weekday = kind else {
            Issue.record("Expected weekday")
            return
        }
    }

    @Test("older than seven days")
    func longAgo() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        #expect(formatter.displayKind(isOnline: false, lastSeenAt: date("2026-06-01T12:00:00Z")) == .longAgo)
    }

    @Test("nil last seen returns no text")
    func nilLastSeen() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        #expect(formatter.localizedStatus(isOnline: false, lastSeenAt: nil) == nil)
    }

    @Test("future clock skew clamps to at least one minute")
    func futureClockSkew() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T15:10:00Z"))
        #expect(kind == .minutesAgo(1))
    }

    @Test("russian localization uses neutral wording")
    func russianLocalization() {
        let formatter = LastSeenStatusFormatter(
            now: date("2026-07-10T15:00:00Z"),
            calendar: utcCalendar,
            locale: Locale(identifier: "ru"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let text = formatter.localizedText(for: .minutesAgo(10))
        #expect(!text.isEmpty)
        #expect(text.contains("был") == false)
        #expect(text.lowercased().contains("last seen") == false)
        #expect(text.contains("presence.lastSeen") == false)
        #expect(text.contains("мин") == true)
    }

    @Test("russian one minute")
    func russianOneMinute() {
        let formatter = makeFormatter(
            now: date("2026-07-10T15:01:00Z"),
            locale: Locale(identifier: "ru")
        )
        let text = formatter.localizedStatus(isOnline: false, lastSeenAt: date("2026-07-10T15:00:00Z"))
        #expect(text?.contains("1") == true)
        #expect(text?.contains("мин") == true)
        #expect(text?.contains("presence.lastSeen") == false)
    }

    @Test("english 59 minutes")
    func english59Minutes() {
        let formatter = makeFormatter(now: date("2026-07-10T15:59:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T15:00:00Z"))
        #expect(kind == .minutesAgo(59))
    }

    @Test("exactly seven days uses weekday bucket")
    func exactlySevenDays() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-03T15:00:00Z"))
        guard case .weekday = kind else {
            Issue.record("Expected weekday for exactly 7 days")
            return
        }
    }

    @Test("year boundary yesterday")
    func yearBoundaryYesterday() {
        let formatter = makeFormatter(now: date("2026-01-01T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2025-12-31T22:00:00Z"))
        guard case .yesterday = kind else {
            Issue.record("Expected yesterday across year boundary, got \(String(describing: kind))")
            return
        }
    }

    @Test("future by 30 seconds clamps to one minute")
    func future30Seconds() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T15:00:30Z"))
        #expect(kind == .minutesAgo(1))
    }

    @Test("future by several minutes clamps without negative minutes")
    func futureSeveralMinutes() {
        let formatter = makeFormatter(now: date("2026-07-10T15:00:00Z"))
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T15:10:00Z"))
        #expect(kind == .minutesAgo(1))
    }

    @Test("12-hour locale uses shortened time not hardcoded 24h")
    func twelveHourLocale() {
        let formatter = LastSeenStatusFormatter(
            now: date("2026-07-10T20:00:00Z"),
            calendar: utcCalendar,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let kind = formatter.displayKind(isOnline: false, lastSeenAt: date("2026-07-10T08:30:00Z"))
        guard case .today(let time) = kind else {
            Issue.record("Expected today")
            return
        }
        #expect(!time.isEmpty)
        #expect(time != "08:30")
    }

    private func makeFormatter(now: Date, locale: Locale = Locale(identifier: "en_US_POSIX")) -> LastSeenStatusFormatter {
        LastSeenStatusFormatter(
            now: now,
            calendar: utcCalendar,
            locale: locale,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    @Test("stockholm spring DST uses calendar day not elapsed seconds")
    func stockholmSpringDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let formatter = LastSeenStatusFormatter(
            now: date("2026-03-29T12:00:00+01:00"),
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: calendar.timeZone
        )
        let kind = formatter.displayKind(
            isOnline: false,
            lastSeenAt: date("2026-03-28T23:30:00+01:00")
        )
        guard case .yesterday = kind else {
            Issue.record("Expected yesterday across Stockholm spring DST, got \(String(describing: kind))")
            return
        }
    }

    @Test("stockholm autumn DST uses calendar day not elapsed seconds")
    func stockholmAutumnDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let formatter = LastSeenStatusFormatter(
            now: date("2026-10-25T12:00:00+02:00"),
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: calendar.timeZone
        )
        let kind = formatter.displayKind(
            isOnline: false,
            lastSeenAt: date("2026-10-24T22:00:00+02:00")
        )
        guard case .yesterday = kind else {
            Issue.record("Expected yesterday across Stockholm autumn DST, got \(String(describing: kind))")
            return
        }
    }

    private func date(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter.date(from: iso8601)!
    }
}
