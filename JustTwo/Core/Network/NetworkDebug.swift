import Foundation

enum NetworkDebug {
    nonisolated static func log(_ message: String, file: StaticString = #file, line: UInt = #line) {
        #if DEBUG
        let name = (String(describing: file) as NSString).lastPathComponent
        print("🌐 [\(name):\(line)] \(message)")
        #endif
    }

    nonisolated static func logError(_ error: Error, prefix: String = "❌") {
        #if DEBUG
        log("\(prefix) \(type(of: error)): \(error.localizedDescription)")

        let ns = error as NSError
        if !ns.userInfo.isEmpty {
            log("userInfo: \(ns.userInfo)")
        }

        let candidates: [String] = [
            ns.localizedDescription,
            (ns.userInfo["message"] as? String) ?? "",
            (ns.userInfo["details"] as? String) ?? ""
        ].filter { !$0.isEmpty }

        for text in candidates {
            if let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
               let string = String(data: pretty, encoding: .utf8) {
                log("parsed JSON:\n\(string)")
                break
            }
        }
        #endif
    }
}
