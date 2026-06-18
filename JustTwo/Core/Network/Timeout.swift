import Foundation

@MainActor
func withTimeout<T>(
    seconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw NetworkError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
