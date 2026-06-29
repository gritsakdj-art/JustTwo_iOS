import Foundation

struct RegisterPushDeviceRequestBody: Encodable {
    let platform: String
    let token: String
    let environment: String
    let bundleId: String
    let installationId: String
    let appVersion: String?
    let buildNumber: String?
    let deviceModel: String?
    let osVersion: String?
    let locale: String?
    let timezone: String?
    let authorizationStatus: String?
}

struct UnregisterPushDeviceRequestBody: Encodable {
    let installationId: String
    let environment: String
}

struct RegisterPushDeviceRequest: EncodableAPIRequest {
    typealias Response = EmptyResponse
    typealias Body = RegisterPushDeviceRequestBody

    let bodyValue: RegisterPushDeviceRequestBody?

    var path: String { "push/devices" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }
}

struct UnregisterPushDeviceRequest: EncodableAPIRequest {
    typealias Response = EmptyResponse
    typealias Body = UnregisterPushDeviceRequestBody

    let bodyValue: UnregisterPushDeviceRequestBody?
    let accessToken: String

    var headers: [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }

    var path: String { "push/devices/current" }
    var method: HTTPMethod { .delete }
}
