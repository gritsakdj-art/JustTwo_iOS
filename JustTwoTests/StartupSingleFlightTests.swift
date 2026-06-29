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

        await flight.run(key: "user-1", force: false) {
            runCount += 1
            try? await Task.sleep(for: .milliseconds(30))
        }
        await flight.run(key: "user-1", force: false) {
            runCount += 1
        }

        #expect(runCount == 1)
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
}
