import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
struct NetworkTimeoutTests {

    @Test
    func withTimeoutThrowsNetworkTimeoutWhenOperationExceedsDeadline() async throws {
        let startedAt = Date()

        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "late"
            }
            Issue.record("Expected NetworkError.timeout")
        } catch NetworkError.timeout {
            #expect(Date().timeIntervalSince(startedAt) < 1)
        } catch {
            Issue.record("Expected NetworkError.timeout, got \(error)")
        }
    }

    @Test
    func withTimeoutReturnsOperationResultBeforeDeadline() async throws {
        let value = try await withTimeout(seconds: 1) {
            "ok"
        }

        #expect(value == "ok")
    }

    @Test
    func networkExecutorRunAppliesOperationTimeoutAcrossStrategies() async throws {
        let executor = NetworkExecutor()
        let startedAt = Date()

        do {
            _ = try await executor.run(
                strategies: [.primary],
                delay: 0,
                operationTimeout: 0.05
            ) { _ in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "late"
            }
            Issue.record("Expected NetworkError.timeout")
        } catch NetworkError.timeout {
            #expect(Date().timeIntervalSince(startedAt) < 1)
        } catch {
            Issue.record("Expected NetworkError.timeout, got \(error)")
        }
    }

    @Test
    func apiConfigurationDefinesOperationDeadlineShorterThanFullDefaultRetryBudget() {
        let perAttemptBudget = APIConfiguration.current.requestTimeout * Double(NetworkStrategy.defaultFlow.count)
        let retryDelayBudget = 0.5 * Double(NetworkStrategy.defaultFlow.count - 1)

        #expect(APIConfiguration.current.operationTimeout < perAttemptBudget + retryDelayBudget)
        #expect(APIConfiguration.current.operationTimeout == 30)
        #expect(APIConfiguration.splash.operationTimeout == 15)
    }
}
