import Foundation

protocol StartupSessionSnapshotStoreProtocol: Sendable {
    func load() async -> StartupSessionSnapshot?
    func save(user: UserResponse, profile: UserProfileDTO?) async
    func clear() async
}

@MainActor
final class StartupSessionSnapshotStore: StartupSessionSnapshotStoreProtocol {

    static let shared = StartupSessionSnapshotStore()

    #if DEBUG
    nonisolated(unsafe) static var testingFileURL: URL?
    #endif

    private let fileManager: FileManager

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() async -> StartupSessionSnapshot? {
        let startedAt = Date()
        MessengerDiagnostics.event(.startupSessionSnapshotLoadStarted)

        let url = storageURL
        guard fileManager.fileExists(atPath: url.path) else {
            MessengerDiagnostics.event(
                .startupSessionSnapshotLoadFailed,
                metadata: [
                    "reason": "missingFile",
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONCoding.decoder.decode(StartupSessionSnapshot.self, from: data)
            MessengerDiagnostics.event(
                .startupSessionSnapshotLoadSucceeded,
                metadata: [
                    "hasCachedUser": "true",
                    "hasCachedProfile": snapshot.profile == nil ? "false" : "true",
                    "emailVerified": snapshot.user.emailVerified ? "true" : "false",
                    "userID": MessengerDiagnostics.sanitizeID(snapshot.userID),
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
            return snapshot
        } catch {
            MessengerDiagnostics.event(
                .startupSessionSnapshotLoadFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
            return nil
        }
    }

    func save(user: UserResponse, profile: UserProfileDTO?) async {
        let snapshot = StartupSessionSnapshotMapping.snapshot(user: user, profile: profile)
        await save(snapshot)
    }

    func clear() async {
        let url = storageURL
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        MessengerDiagnostics.event(.startupSessionSnapshotCleared)
    }

    private func save(_ snapshot: StartupSessionSnapshot) async {
        let url = storageURL
        let directory = url.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONCoding.encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            MessengerDiagnostics.event(
                .startupSessionSnapshotSaved,
                metadata: [
                    "hasCachedUser": "true",
                    "hasCachedProfile": snapshot.profile == nil ? "false" : "true",
                    "emailVerified": snapshot.user.emailVerified ? "true" : "false",
                    "userID": MessengerDiagnostics.sanitizeID(snapshot.userID)
                ]
            )
        } catch {
            MessengerDiagnostics.event(
                .startupSessionSnapshotLoadFailed,
                metadata: [
                    "reason": "saveFailed",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
        }
    }

    private var storageURL: URL {
        #if DEBUG
        if let testingFileURL = Self.testingFileURL {
            return testingFileURL
        }
        #endif

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("JustTwo", isDirectory: true)
            .appendingPathComponent("startup-session-snapshot.json", isDirectory: false)
    }

    private func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
