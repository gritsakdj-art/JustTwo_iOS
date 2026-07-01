import Foundation

enum AppBuildEnvironment {
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    static var showsInternalDiagnostics: Bool {
        isDebug || isTestFlight
    }
}
