import Foundation

enum LastSeenDisplayKind: Equatable, Sendable {
    case online
    case minutesAgo(Int)
    case today(String)
    case yesterday(String)
    case weekday(String)
    case longAgo
}

struct LastSeenStatusFormatter: Sendable, Equatable {
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone

    init(
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.now = now
        var resolvedCalendar = calendar
        resolvedCalendar.locale = locale
        resolvedCalendar.timeZone = timeZone
        self.calendar = resolvedCalendar
        self.locale = locale
        self.timeZone = timeZone
    }

    func displayKind(isOnline: Bool, lastSeenAt: Date?) -> LastSeenDisplayKind? {
        if isOnline {
            return .online
        }
        guard let lastSeenAt else { return nil }

        let effectiveLastSeen = min(lastSeenAt, now)
        let elapsedMinutes = max(0, Int(now.timeIntervalSince(effectiveLastSeen) / 60))

        if elapsedMinutes < 60 {
            return .minutesAgo(max(1, elapsedMinutes))
        }

        if calendar.isDate(effectiveLastSeen, inSameDayAs: now) {
            return .today(formattedTime(effectiveLastSeen))
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(effectiveLastSeen, inSameDayAs: yesterday) {
            return .yesterday(formattedTime(effectiveLastSeen))
        }

        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: effectiveLastSeen), to: calendar.startOfDay(for: now)).day,
           days <= 7 {
            return .weekday(formattedWeekday(effectiveLastSeen))
        }

        return .longAgo
    }

    func localizedText(for kind: LastSeenDisplayKind) -> String {
        switch kind {
        case .online:
            return localized("presence.online")

        case .minutesAgo(let minutes):
            let format = localized("%lld presence.lastSeen.minutes")
            return String(format: format, locale: locale, minutes)

        case .today(let time):
            return String(
                format: localized("presence.lastSeen.today"),
                locale: locale,
                time
            )

        case .yesterday(let time):
            return String(
                format: localized("presence.lastSeen.yesterday"),
                locale: locale,
                time
            )

        case .weekday(let label):
            return String(
                format: localized("presence.lastSeen.weekday"),
                locale: locale,
                label
            )

        case .longAgo:
            return localized("presence.lastSeen.longAgo")
        }
    }

    func localizedStatus(isOnline: Bool, lastSeenAt: Date?) -> String? {
        guard let kind = displayKind(isOnline: isOnline, lastSeenAt: lastSeenAt) else { return nil }
        return localizedText(for: kind)
    }

    func accessibilityLabel(isTyping: Bool, isOnline: Bool, lastSeenAt: Date?) -> String? {
        if isTyping {
            return localized("chats.typing")
        }
        return localizedStatus(isOnline: isOnline, lastSeenAt: lastSeenAt)
    }

    private func localized(_ key: String) -> String {
        if let languageCode = locale.language.languageCode?.identifier,
           let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            let value = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
            if !value.isEmpty, value != key {
                return value
            }
        }
        return String(localized: String.LocalizationValue(key), locale: locale)
    }

    private func formattedTime(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
            .locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    private func formattedWeekday(_ date: Date) -> String {
        var style = Date.FormatStyle()
            .weekday(.wide)
            .locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

enum PresenceDisplayResolver {
    @MainActor
    static func resolve(
        presenceStore: PresenceStore,
        profileID: UUID?,
        isTyping: Bool,
        formatter: LastSeenStatusFormatter? = nil
    ) -> (text: String?, accessibilityLabel: String?) {
        let formatter = formatter ?? LastSeenStatusFormatter(now: Date())
        guard let profileID else { return (nil, nil) }

        if isTyping {
            let typing = String(localized: "chats.typing", locale: formatter.locale)
            return (typing, typing)
        }

        let isOnline = presenceStore.isOnline(profileID: profileID)
        let lastSeenAt = presenceStore.lastSeenAt(profileID: profileID)
        let text = formatter.localizedStatus(isOnline: isOnline, lastSeenAt: lastSeenAt)
        let accessibility = formatter.accessibilityLabel(
            isTyping: false,
            isOnline: isOnline,
            lastSeenAt: lastSeenAt
        )
        return (text, accessibility)
    }
}
