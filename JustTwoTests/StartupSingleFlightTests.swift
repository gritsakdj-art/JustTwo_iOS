import Foundation
import Testing
@testable import JustTwo

@MainActor
struct StartupSingleFlightTests {

    @Test
    func secondCallSkipsWhenKeyAlreadyLoaded() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        await flight.run(key: "user-1", force: false) {
            runCount += 1
        }
        await flight.run(key: "user-1", force: false) {
            runCount += 1
        }

        #expect(runCount == 1)
        #expect(flight.loadedKey == "user-1")
    }

    @Test
    func concurrentCallsCoalesceWhenSecondStartsAfterFirstClaimsTask() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        let first = Task {
            await flight.run(key: "user-1", force: false) {
                runCount += 1
                try? await Task.sleep(for: .milliseconds(40))
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
        let second = Task {
            await flight.run(key: "user-1", force: false) {
                runCount += 1
            }
        }

        await first.value
        await second.value

        #expect(runCount == 1)
    }

    @Test
    func failedOperationDoesNotSetLoadedKey() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        await flight.runReportingCompletion(key: "user-1", force: false) {
            runCount += 1
            return false
        }
        await flight.runReportingCompletion(key: "user-1", force: false) {
            runCount += 1
            return true
        }

        #expect(runCount == 2)
        #expect(flight.loadedKey == "user-1")
    }

    @Test
    func resetAllowsNextLoad() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        await flight.run(key: "user-1", force: false) {
            runCount += 1
        }
        flight.reset()
        await flight.run(key: "user-1", force: false) {
            runCount += 1
        }

        #expect(runCount == 2)
    }

    @Test
    func forceReloadRunsAgain() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        await flight.run(key: "user-1", force: false) {
            runCount += 1
        }
        await flight.run(key: "user-1", force: true) {
            runCount += 1
        }

        #expect(runCount == 2)
    }

    @Test
    func canceledTaskDoesNotSetLoadedKey() async {
        let flight = StartupSingleFlight()

        let first = Task {
            await flight.run(key: "user-1", force: false) {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
        flight.reset()
        await first.value

        #expect(flight.loadedKey == nil)
    }

    @Test
    func waiterDoesNotStartStaleOperationAfterReset() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        let first = Task {
            await flight.run(key: "user-1", force: false) {
                runCount += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
        let waiter = Task {
            await flight.run(key: "user-1", force: false) {
                runCount += 1
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
        flight.reset()

        await first.value
        await waiter.value

        #expect(runCount == 1)
        #expect(flight.loadedKey == nil)
    }

    @Test
    func waiterCoalescesAfterForceReplace() async {
        let flight = StartupSingleFlight()
        var runCount = 0

        let slow = Task {
            await flight.run(key: "user-1", force: false) {
                runCount += 1
                try? await Task.sleep(for: .milliseconds(80))
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
        await flight.run(key: "user-1", force: true) {
            runCount += 1
        }
        await slow.value

        #expect(runCount == 2)
        #expect(flight.loadedKey == "user-1")
    }
}
