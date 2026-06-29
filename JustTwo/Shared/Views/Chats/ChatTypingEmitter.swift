import Foundation

@MainActor
final class ChatTypingEmitter {

    private let conversationID: UUID
    private let realtimeClient: RealtimeClient
    private var isTypingActive = false
    private var lastStartedSentAt: Date?
    private var stopTask: Task<Void, Never>?

    private let startThrottleInterval: TimeInterval = 4
    private let stopDebounceInterval: TimeInterval = 2

    convenience init(conversationID: UUID) {
        self.init(conversationID: conversationID, realtimeClient: RealtimeClient.shared)
    }

    init(conversationID: UUID, realtimeClient: RealtimeClient) {
        self.conversationID = conversationID
        self.realtimeClient = realtimeClient
    }

    func textDidChange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sendStoppedIfNeeded()
            return
        }

        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.stopDebounceInterval ?? 2))
            guard !Task.isCancelled else { return }
            self?.sendStoppedIfNeeded()
        }

        sendStartedIfNeeded()
    }

    func messageSent() {
        sendStoppedIfNeeded()
    }

    func chatClosed() {
        sendStoppedIfNeeded()
    }

    private func sendStartedIfNeeded() {
        let now = Date()
        if isTypingActive,
           let lastStartedSentAt,
           now.timeIntervalSince(lastStartedSentAt) < startThrottleInterval {
            return
        }

        isTypingActive = true
        lastStartedSentAt = now

        Task {
            do {
                try await realtimeClient.sendTypingStarted(conversationID: conversationID)
            } catch {
                NetworkDebug.logError(error, prefix: "Typing started send failed")
            }
        }
    }

    private func sendStoppedIfNeeded() {
        stopTask?.cancel()
        stopTask = nil
        guard isTypingActive else { return }
        isTypingActive = false

        Task {
            do {
                try await realtimeClient.sendTypingStopped(conversationID: conversationID)
            } catch {
                NetworkDebug.logError(error, prefix: "Typing stopped send failed")
            }
        }
    }
}
