import Foundation

enum MessengerStorageFormatting {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(for byteCount: Int64) -> String {
        formatter.string(fromByteCount: byteCount)
    }

    static func string(for byteCount: Int) -> String {
        string(for: Int64(byteCount))
    }
}
