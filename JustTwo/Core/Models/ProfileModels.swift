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
    let isVisibleInDiscovery: Bool
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case birthDate
        case gender
        case bio
        case city
        case latitude
        case longitude
        case moodModeEnabled
        case activityModeEnabled
        case isVisibleInDiscovery
        case createdAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        birthDate = try container.decode(String.self, forKey: .birthDate)
        gender = try container.decode(String.self, forKey: .gender)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        moodModeEnabled = try container.decode(Bool.self, forKey: .moodModeEnabled)
        activityModeEnabled = try container.decode(Bool.self, forKey: .activityModeEnabled)
        isVisibleInDiscovery = try container.decodeIfPresent(Bool.self, forKey: .isVisibleInDiscovery) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct UpsertProfileRequestBody: Encodable {
    let displayName: String?
    let birthDate: String?
    let gender: String?
    let bio: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let moodModeEnabled: Bool?
    let activityModeEnabled: Bool?
    let isVisibleInDiscovery: Bool?

    init(
        displayName: String? = nil,
        birthDate: String? = nil,
        gender: String? = nil,
        bio: String? = nil,
        city: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        moodModeEnabled: Bool? = nil,
        activityModeEnabled: Bool? = nil,
        isVisibleInDiscovery: Bool? = nil
    ) {
        self.displayName = displayName
        self.birthDate = birthDate
        self.gender = gender
        self.bio = bio
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.moodModeEnabled = moodModeEnabled
        self.activityModeEnabled = activityModeEnabled
        self.isVisibleInDiscovery = isVisibleInDiscovery
    }
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
