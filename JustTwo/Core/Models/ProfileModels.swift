import Foundation
import SwiftUI

struct UserProfileDTO: Decodable {
    let id: UUID
    let displayName: String
    let birthDate: String
    let gender: String
    let bio: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let moodModeEnabled: Bool
    let activityModeEnabled: Bool
    let createdAt: Date?
    let updatedAt: Date?
}

struct UpsertProfileRequestBody: Encodable {
    let displayName: String
    let birthDate: String
    let gender: String
    let bio: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let moodModeEnabled: Bool
    let activityModeEnabled: Bool
}

struct ProfileEnvelopeResponse: Decodable {
    let success: Bool
    let message: String?
    let profile: UserProfileDTO
}

enum ProfileGender: String, CaseIterable, Identifiable {
    case woman
    case man
    case nonBinary = "non_binary"
    case other
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .woman:
            return "profile.gender.woman"
        case .man:
            return "profile.gender.man"
        case .nonBinary:
            return "profile.gender.non_binary"
        case .other:
            return "profile.gender.other"
        case .preferNotToSay:
            return "profile.gender.prefer_not_to_say"
        }
    }
}

enum DateOnlyFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }
}
