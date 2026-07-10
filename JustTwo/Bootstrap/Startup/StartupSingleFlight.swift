import Foundation

@MainActor
final class StartupSingleFlight {

    private var task: Task<Bool, Never>?
    private var activeOperationID: UUID?
    private var resetGeneration = 0
    private(set) var loadedKey: String?

    func run(
        key: String,
        force: Bool,
        operation: @escaping @MainActor () async -> Void
    ) async {
        await runReportingCompletion(key: key, force: force) {
            await operation()
            return !Task.isCancelled
        }
    }

    @discardableResult
    func runReportingCompletion(
        key: String,
        force: Bool,
        operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if !force, loadedKey == key {
            return false
        }

        let resetGenerationAtStart = resetGeneration
        while let existing = task, !force {
            _ = await existing.value
            guard resetGeneration == resetGenerationAtStart else { return false }
            if loadedKey == key {
                return false
            }
        }

        if force {
            task?.cancel()
            task = nil
            loadedKey = nil
            activeOperationID = nil
        }

        let operationID = UUID()
        activeOperationID = operationID
        let newTask = Task { @MainActor in
            await operation()
        }
        task = newTask
        let didComplete = await newTask.value

        guard activeOperationID == operationID else { return false }
        task = nil
        activeOperationID = nil

        guard !newTask.isCancelled, didComplete else { return false }
        loadedKey = key
        return true
    }

    func reset() {
        task?.cancel()
        task = nil
        loadedKey = nil
        activeOperationID = nil
        resetGeneration += 1
    }
}
