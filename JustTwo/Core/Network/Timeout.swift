import Foundation

func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    guard seconds.isFinite, seconds > 0 else {
        throw NetworkError.timeout
    }

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds(for: seconds))
            throw NetworkError.timeout
        }

        guard let result = try await group.next() else {
            throw NetworkError.timeout
        }

        group.cancelAll()
        return result
    }
}

private func timeoutNanoseconds(for seconds: TimeInterval) -> UInt64 {
    let nanoseconds = seconds * 1_000_000_000
    guard nanoseconds.isFinite, nanoseconds > 0 else { return 1 }
    return UInt64(min(nanoseconds.rounded(.up), Double(UInt64.max)))
}
