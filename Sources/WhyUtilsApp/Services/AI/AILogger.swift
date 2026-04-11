import Foundation

enum AILogger {
    private static let queue = DispatchQueue(label: "com.whyutils.ai-logger")
    private static let maxBytes: Int64 = 5_000_000

    nonisolated static func logFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("whyutils")
            .appendingPathComponent("ai.log")
    }

    nonisolated static func formatEntry(
        kind: String,
        url: URL?,
        statusCode: Int?,
        usageSummary: String?,
        headers: [AnyHashable: Any],
        body: String,
        error: Error?,
        date: Date = Date(),
        pid: Int32 = Int32(ProcessInfo.processInfo.processIdentifier)
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: date)

        let headerLines = headers
            .map { (String(describing: $0.key), String(describing: $0.value)) }
            .sorted { lhs, rhs in
                lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
            }
            .map { "\($0): \($1)" }
            .joined(separator: "\n")

        let errorLine: String
        if let error {
            let localized = (error as NSError).localizedDescription
            errorLine = localized.isEmpty ? String(describing: error) : localized
        } else {
            errorLine = "none"
        }

        let normalizedBody = body.isEmpty ? "<empty>" : body
        let normalizedHeaders = headerLines.isEmpty ? "<none>" : headerLines
        let normalizedStatus = statusCode.map(String.init) ?? "n/a"
        let normalizedURL = url?.absoluteString ?? "n/a"
        let normalizedUsage = usageSummary ?? "n/a"

        return """
        ===== AI \(kind.uppercased()) [\(timestamp)] [pid:\(pid)] =====
        URL: \(normalizedURL)
        Status: \(normalizedStatus)
        Usage: \(normalizedUsage)
        Headers:
        \(normalizedHeaders)
        Error: \(errorLine)
        Body:
        \(normalizedBody)
        ===== END AI \(kind.uppercased()) =====

        """
    }

    static func logHTTPExchange(
        kind: String,
        url: URL?,
        response: HTTPURLResponse?,
        usageSummary: String? = nil,
        body: String,
        error: Error?
    ) {
        let entry = formatEntry(
            kind: kind,
            url: url,
            statusCode: response?.statusCode,
            usageSummary: usageSummary,
            headers: response?.allHeaderFields ?? [:],
            body: body,
            error: error
        )
        queue.async {
            writeEntry(entry)
        }
    }

    static func logTransportFailure(kind: String, url: URL?, error: Error) {
        let entry = formatEntry(
            kind: kind,
            url: url,
            statusCode: nil,
            usageSummary: nil,
            headers: [:],
            body: "",
            error: error
        )
        queue.async {
            writeEntry(entry)
        }
    }

    static func clear() {
        queue.sync {
            let url = logFileURL()
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func writeEntry(_ entry: String) {
        let url = logFileURL()
        let dir = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try rotateIfNeeded(fileURL: url)

            let payload = entry.data(using: .utf8) ?? Data()
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } catch {
            // AI logging must never break app behavior.
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
