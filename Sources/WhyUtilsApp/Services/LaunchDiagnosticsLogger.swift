import Foundation

enum LaunchDiagnosticsLogger {
    private static let queue = DispatchQueue(label: "com.whyutils.launch-diagnostics")
    private static let maxBytes: Int64 = 1_500_000

    nonisolated static func logFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("whyutils")
            .appendingPathComponent("launch.log")
    }

    nonisolated static func formatLine(message: String, date: Date = Date(), pid: Int32 = Int32(ProcessInfo.processInfo.processIdentifier)) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: date)
        return "[\(timestamp)] [pid:\(pid)] \(message)"
    }

    static func log(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        let source = "\(file):\(line) \(function)"
        let text = formatLine(message: "\(message) | \(source)")
        queue.async {
            writeLine(text)
        }
    }

    static func clear() {
        queue.sync {
            let url = logFileURL()
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func writeLine(_ line: String) {
        let url = logFileURL()
        let dir = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try rotateIfNeeded(fileURL: url)

            let payload = (line + "\n").data(using: .utf8) ?? Data()
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } catch {
            // Diagnostics must never break app behavior.
        }
    }

    private static func rotateIfNeeded(fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        guard size > maxBytes else { return }

        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}

