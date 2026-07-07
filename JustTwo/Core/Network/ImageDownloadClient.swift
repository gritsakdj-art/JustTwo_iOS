import Foundation

enum ImageDownloadClient {
    private static let imageDownloadTimeout: TimeInterval = 20

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        let label = url.host ?? url.absoluteString
        let startedAt = Date()
        NetworkDebug.log("Image download start: \(label)")

        do {
            let result = try await withTimeout(seconds: imageDownloadTimeout) {
                try await URLSessionProvider.imageSession.data(from: url)
            }
            let duration = Date().timeIntervalSince(startedAt)
            let bytes = result.0.count
            NetworkDebug.log(
                "Image download success in \(String(format: "%.2f", duration))s bytes=\(bytes) host=\(label)"
            )
            return result
        } catch {
            let duration = Date().timeIntervalSince(startedAt)
            NetworkDebug.log(
                "Image download failed in \(String(format: "%.2f", duration))s host=\(label)"
            )
            NetworkDebug.logError(error, prefix: "Image download")
            throw error
        }
    }
}
