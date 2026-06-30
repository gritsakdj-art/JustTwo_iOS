import Foundation

actor NetworkExecutor {

    static let shared = NetworkExecutor()

    private var lastTLSResetAt: Date = .distantPast

    private func maybeResetSessionsForTLS(opID: String) async {
        let now = Date()
        guard now.timeIntervalSince(lastTLSResetAt) > 3 else { return }
        lastTLSResetAt = now

        NetworkDebug.log("🧯 [\(opID)] TLS failure → resetting URL sessions")
        URLSessionProvider.resetNetworkingSessions()

        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    func run<T>(
        strategies: [NetworkStrategy] = NetworkStrategy.defaultFlow,
        delay: UInt64 = 500_000_000,
        operation: @escaping @Sendable (URLSession) async throws -> T
    ) async throws -> T {
        precondition(!strategies.isEmpty, "strategies must not be empty")

        let opID = UUID().uuidString
        NetworkDebug.log("🌐 [\(opID)] operation start, strategies=\(strategies.map(\.name))")

        var lastError: Error?
        var didRestartAfterTLS = false

        for pass in 0..<2 {
            for (index, strategy) in strategies.enumerated() {
                try Task.checkCancellation()

                let attempt = index + 1
                let attemptStart = Date()
                NetworkDebug.log("➡️ [\(opID)] attempt \(attempt) using strategy=\(strategy.name)")

                do {
                    let result = try await operation(strategy.session)
                    let duration = Date().timeIntervalSince(attemptStart)
                    NetworkDebug.log(
                        "✅ [\(opID)] attempt \(attempt) success in \(String(format: "%.2f", duration))s via \(strategy.name)"
                    )
                    return result
                } catch is CancellationError {
                    NetworkDebug.log("⛔️ [\(opID)] cancelled")
                    throw CancellationError()
                } catch {
                    let duration = Date().timeIntervalSince(attemptStart)
                    NetworkDebug.log(
                        "❌ [\(opID)] attempt \(attempt) failed in \(String(format: "%.2f", duration))s via \(strategy.name)"
                    )
                    NetworkDebug.logError(error)

                    let ns = error as NSError
                    if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                        if Task.isCancelled {
                            NetworkDebug.log("⛔️ [\(opID)] task cancelled")
                            throw CancellationError()
                        }
                        NetworkDebug.log("⚠️ [\(opID)] URLSession cancelled without task cancel, will retry if possible")
                        lastError = error
                        guard attempt < strategies.count else {
                            throw NetworkError.connectionLost
                        }
                        NetworkDebug.log(
                            "🔁 [\(opID)] switching strategy → \(strategies[attempt].name) after \(delay / 1_000_000)ms"
                        )
                        try await Task.sleep(nanoseconds: delay)
                        continue
                    }

                    lastError = error
                    let mapped = (error as? NetworkError) ?? NetworkError.map(error)

                    if case .tlsFailure = mapped {
                        await maybeResetSessionsForTLS(opID: opID)

                        if pass == 0, !didRestartAfterTLS {
                            didRestartAfterTLS = true
                            NetworkDebug.log("🔄 [\(opID)] restarting strategies after TLS reset")
                            break
                        }
                    }

                    guard mapped.shouldRetry, attempt < strategies.count else {
                        NetworkDebug.log("🛑 [\(opID)] giving up after strategy=\(strategy.name), error=\(mapped)")
                        throw mapped
                    }

                    NetworkDebug.log(
                        "🔁 [\(opID)] switching strategy → \(strategies[attempt].name) after \(delay / 1_000_000)ms"
                    )
                    try await Task.sleep(nanoseconds: delay)
                }
            }

            if !didRestartAfterTLS { break }
        }

        if let networkError = lastError as? NetworkError {
            NetworkDebug.log("🔥 [\(opID)] exhausted strategies, final error=\(networkError)")
            throw networkError
        }

        let fallback = NetworkError.map(lastError ?? URLError(.unknown))
        NetworkDebug.log("🔥 [\(opID)] exhausted strategies, final error=\(fallback)")
        throw fallback
    }

    func send<R: APIRequest>(
        _ request: R,
        strategies: [NetworkStrategy] = NetworkStrategy.defaultFlow,
        configuration: APIConfiguration = .current
    ) async throws -> R.Response where R.Response: Decodable {
        try await run(strategies: strategies) { session in
            let client = HTTPClient(session: session, configuration: configuration)
            return try await client.send(request)
        }
    }
}
