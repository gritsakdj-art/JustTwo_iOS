import Foundation

@MainActor
final class StartupSingleFlight {

    private var task: Task<Void, Never>?
    private(set) var loadedKey: String?

    func run(
        key: String,
        force: Bool,
        operation: @escaping @MainActor () async -> Void
    ) async {
        if !force, loadedKey == key {
            return
        }

        if let task, !force {
            await task.value
            if loadedKey == key {
                return
            }
        }

        if force {
            task?.cancel()
            task = nil
            loadedKey = nil
        }

        let newTask = Task { @MainActor in
            await operation()
        }
        task = newTask
        await newTask.value

        if task == newTask {
            task = nil
            loadedKey = key
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        loadedKey = nil
    }
}
