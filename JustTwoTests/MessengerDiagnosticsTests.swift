import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct MessengerDiagnosticsTests {

    @Test
    func sendEventDoesNotKeepMessageBodyMetadata() {
        let entry = MessengerDiagnostics.makeEntry(
            .sendStarted,
            conversationID: UUID(),
            clientMessageID: "client-1",
            metadata: [
                "body": "private hello",
                "draftText": "private draft",
                "messageCount": "2"
            ]
        )

        #expect(entry.metadata["body"] == nil)
        #expect(entry.metadata["draftText"] == nil)
        #expect(entry.metadata["messageCount"] == "2")
        #expect(!entry.exportLine.contains("private hello"))
        #expect(!entry.exportLine.contains("private draft"))
    }

    @Test
    func ringBufferRespectsLimit() {
        let store = MessengerDiagnosticsStore(limit: 3)

        for index in 0..<5 {
            store.append(entry(event: "event\(index)"))
        }

        #expect(store.events.count == 3)
    }

    @Test
    func ringBufferKeepsNewestEntries() {
        let store = MessengerDiagnosticsStore(limit: 3)

        for index in 0..<5 {
            store.append(entry(event: "event\(index)"))
        }

        #expect(store.events.map(\.event) == ["event2", "event3", "event4"])
    }

    @Test
    func sanitizedErrorCategoryForCancellation() {
        #expect(MessengerDiagnostics.sanitizeError(CancellationError()) == "cancelled")
    }

    @Test
    func sanitizedErrorCategoryForNetworkError() {
        let error = URLError(.networkConnectionLost)

        #expect(MessengerDiagnostics.sanitizeError(error) == "network")
    }

    @Test
    func deliveredSkipReasonLoggingIsPrivacySafe() {
        let entry = MessengerDiagnostics.makeEntry(
            .deliveredAckSkipped,
            conversationID: UUID(),
            messageID: UUID(),
            metadata: [
                "reason": "duplicate",
                "isOwnMessage": "false",
                "body": "private body"
            ]
        )

        #expect(entry.metadata["reason"] == "duplicate")
        #expect(entry.metadata["isOwnMessage"] == "false")
        #expect(entry.metadata["body"] == nil)
    }

    @Test
    func realtimeEventLoggingStoresTypeWithoutRawPayload() {
        let entry = MessengerDiagnostics.makeEntry(
            .realtimeEventReceived,
            conversationID: UUID(),
            messageID: UUID(),
            metadata: [
                "type": "message.created",
                "payload": "{\"body\":\"private\"}"
            ]
        )

        #expect(entry.metadata["type"] == "message.created")
        #expect(entry.metadata["payload"] == nil)
        #expect(!entry.exportLine.contains("private"))
    }

    @Test
    func cacheMergeDiagnosticsAppendSafely() {
        let store = MessengerDiagnosticsStore(limit: 10)
        let entry = MessengerDiagnostics.makeEntry(
            .cacheMergeCompleted,
            metadata: [
                "incomingCount": "2",
                "existingCount": "1",
                "resultCount": "3"
            ]
        )

        store.append(entry)

        #expect(store.events.first?.event == MessengerDiagnosticEvent.cacheMergeCompleted.rawValue)
        #expect(store.events.first?.metadata["resultCount"] == "3")
    }

    @Test
    func exportTextIsNotEmptyAfterAppendingEvents() {
        let store = MessengerDiagnosticsStore(limit: 10)
        store.append(MessengerDiagnostics.makeEntry(.chatAppeared))

        #expect(!store.exportText().isEmpty)
    }

    @Test
    func clipboardExportUsesSafePlaceholderWhenEmpty() async {
        let store = MessengerDiagnosticsStore(limit: 10)

        #expect(await MessengerDiagnostics.exportTextForClipboard(from: store) == MessengerDiagnostics.emptyExportText)
    }

    @Test
    func internalDiagnosticsVisibilityCompiles() {
        let isVisible = AppBuildEnvironment.showsInternalDiagnostics

        #expect(isVisible == (AppBuildEnvironment.isDebug || AppBuildEnvironment.isTestFlight))
    }

    @Test
    func diagnosticsCanBeCleared() {
        let store = MessengerDiagnosticsStore(limit: 10)
        store.append(entry(event: "one"))

        store.clear()

        #expect(store.events.isEmpty)
    }

    @Test
    func loggingFromNonMainAsyncContextDoesNotCrash() async throws {
        MessengerDiagnosticsStore.shared.clear()

        await Task.detached {
            MessengerDiagnostics.event(
                .realtimeEventReceived,
                metadata: ["type": "pong"]
            )
        }.value

        try await Task.sleep(for: .milliseconds(250))

        #expect(MessengerDiagnosticsStore.shared.events.contains {
            $0.event == MessengerDiagnosticEvent.realtimeEventReceived.rawValue
        })
    }

    private func entry(event: String) -> MessengerDiagnosticEntry {
        MessengerDiagnosticEntry(
            id: UUID(),
            timestamp: Date(),
            event: event,
            conversationID: nil,
            messageID: nil,
            clientMessageID: nil,
            metadata: [:]
        )
    }
}
