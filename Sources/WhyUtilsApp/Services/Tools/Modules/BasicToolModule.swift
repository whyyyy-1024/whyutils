import AppKit
import Foundation

struct BasicToolModule: ToolProvider {
    let providerId = "basic"
    private let accessMode: AIAgentAccessMode
    
    init(accessMode: AIAgentAccessMode) {
        self.accessMode = accessMode
    }
    
    func tools() -> [ToolDescriptor] {
        let confirm = accessMode.requiresConfirmationForSideEffects
        
        var tools: [ToolDescriptor] = [
            .init(name: "clipboard_read_latest", description: "Read the latest clipboard entry", providerId: providerId, dangerousLevel: .safe),
            .init(name: "clipboard_list_history", description: "List clipboard history entries", providerId: providerId, dangerousLevel: .safe),
            .init(name: "json_validate", description: "Validate JSON", providerId: providerId, dangerousLevel: .safe),
            .init(name: "json_format", description: "Format JSON", providerId: providerId, dangerousLevel: .safe),
            .init(name: "json_minify", description: "Minify JSON", providerId: providerId, dangerousLevel: .safe),
            .init(name: "url_encode", description: "Encode URL text", providerId: providerId, dangerousLevel: .safe),
            .init(name: "url_decode", description: "Decode URL text", providerId: providerId, dangerousLevel: .safe),
            .init(name: "base64_encode", description: "Encode Base64", providerId: providerId, dangerousLevel: .safe),
            .init(name: "base64_decode", description: "Decode Base64", providerId: providerId, dangerousLevel: .safe),
            .init(name: "timestamp_to_date", description: "Convert timestamp to date", providerId: providerId, dangerousLevel: .safe),
            .init(name: "date_to_timestamp", description: "Convert date to timestamp", providerId: providerId, dangerousLevel: .safe),
            .init(name: "regex_find", description: "Find regex matches", providerId: providerId, dangerousLevel: .safe),
            .init(name: "regex_replace_preview", description: "Preview regex replacement", providerId: providerId, dangerousLevel: .safe),
            .init(name: "search_files", description: "Search files", providerId: providerId, dangerousLevel: .safe),
            .init(name: "search_apps", description: "Search apps", providerId: providerId, dangerousLevel: .safe),
            .init(name: "search_system_settings", description: "Search system settings", providerId: providerId, dangerousLevel: .safe),
            .init(name: "open_file", description: "Open a file", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate),
            .init(name: "open_app", description: "Open an app", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate),
            .init(name: "open_system_setting", description: "Open a system setting", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate),
            .init(name: "paste_clipboard_entry", description: "Paste clipboard content to another app", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate)
        ]
        
        if accessMode.includesFullAccessTools {
            tools.append(contentsOf: [
                .init(name: "list_directory", description: "List files and directories at a path", providerId: providerId, dangerousLevel: .safe),
                .init(name: "read_file", description: "Read a text file from disk", providerId: providerId, dangerousLevel: .safe),
                .init(name: "write_file", description: "Write text content to a file on disk", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate),
                .init(name: "run_shell_command", description: "Run a shell command locally", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate),
                .init(name: "open_url", description: "Open a URL in the default browser", requiresConfirmation: confirm, providerId: providerId, dangerousLevel: .moderate)
            ])
        }
        
        return tools
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "clipboard_read_latest":
            return await MainActor.run { latestClipboardSummary() }
        case "clipboard_list_history":
            let limit = intArg(named: "limit", in: arguments) ?? 5
            return await MainActor.run { clipboardHistorySummary(limit: limit) }
        case "json_validate":
            return try JSONService.validate(await textInput(from: arguments))
        case "json_format":
            return try JSONService.format(await textInput(from: arguments))
        case "json_minify":
            return try JSONService.minify(await textInput(from: arguments))
        case "url_encode":
            return EncodingService.urlEncode(
                await textInput(from: arguments),
                safe: stringArg(named: "safe", in: arguments) ?? ""
            )
        case "url_decode":
            return EncodingService.urlDecode(await textInput(from: arguments))
        case "base64_encode":
            return EncodingService.base64Encode(
                await textInput(from: arguments),
                urlSafe: boolArg(named: "urlSafe", in: arguments) ?? false,
                stripPadding: boolArg(named: "stripPadding", in: arguments) ?? false
            )
        case "base64_decode":
            return try EncodingService.base64Decode(
                await textInput(from: arguments),
                urlSafe: boolArg(named: "urlSafe", in: arguments) ?? false
            )
        case "timestamp_to_date":
            let result = try TimeService.timestampToDate(
                await textInput(from: arguments),
                inputUnit: timestampUnit(from: stringArg(named: "unit", in: arguments))
            )
            return format(timeResult: result)
        case "date_to_timestamp":
            let result = try TimeService.dateToTimestamp(
                await textInput(from: arguments),
                interpretAsUTC: boolArg(named: "interpretAsUTC", in: arguments) ?? false
            )
            return format(timeResult: result)
        case "regex_find":
            let pattern = try requiredStringArg(named: "pattern", in: arguments)
            let matches = try RegexService.findMatches(
                pattern: pattern,
                text: await textInput(from: arguments),
                ignoreCase: boolArg(named: "ignoreCase", in: arguments) ?? false,
                multiLine: boolArg(named: "multiLine", in: arguments) ?? false,
                dotMatchesNewLine: boolArg(named: "dotMatchesNewLine", in: arguments) ?? false
            )
            return format(matches: matches)
        case "regex_replace_preview":
            let pattern = try requiredStringArg(named: "pattern", in: arguments)
            let replacement = stringArg(named: "replacement", in: arguments) ?? ""
            return try RegexService.replace(
                pattern: pattern,
                replacement: replacement,
                text: await textInput(from: arguments),
                ignoreCase: boolArg(named: "ignoreCase", in: arguments) ?? false,
                multiLine: boolArg(named: "multiLine", in: arguments) ?? false,
                dotMatchesNewLine: boolArg(named: "dotMatchesNewLine", in: arguments) ?? false
            )
        case "search_files":
            let query = try requiredStringArg(named: "query", in: arguments)
            return try await searchFiles(query: query)
        case "search_apps":
            let query = try requiredStringArg(named: "query", in: arguments)
            return await MainActor.run {
                format(apps: AppSearchService.shared.search(query: query, limit: 8))
            }
        case "search_system_settings":
            let query = try requiredStringArg(named: "query", in: arguments)
            return await MainActor.run {
                format(settings: SystemSettingsSearchService.search(query: query, limit: 6))
            }
        case "list_directory":
            return try listDirectory(path: stringArg(named: "path", in: arguments) ?? FileManager.default.homeDirectoryForCurrentUser.path)
        case "read_file":
            let path = try requiredStringArg(named: "path", in: arguments)
            return try readFile(path: path)
        case "write_file":
            let path = try requiredStringArg(named: "path", in: arguments)
            let content = try requiredStringArg(named: "content", in: arguments)
            let append = boolArg(named: "append", in: arguments) ?? false
            return try writeFile(path: path, content: content, append: append)
        case "run_shell_command":
            let command = try requiredStringArg(named: "command", in: arguments)
            let cwd = stringArg(named: "cwd", in: arguments)
            return try runShellCommand(command: command, cwd: cwd)
        case "open_url":
            let rawURL = try requiredStringArg(named: "url", in: arguments)
            return await MainActor.run {
                guard let url = URL(string: rawURL) else { return "Invalid URL: \(rawURL)" }
                return NSWorkspace.shared.open(url) ? "Opened \(rawURL)" : "Failed to open \(rawURL)"
            }
        case "open_file":
            let path = try requiredStringArg(named: "path", in: arguments)
            return await MainActor.run {
                let url = URL(fileURLWithPath: path)
                return NSWorkspace.shared.open(url) ? "Opened \(url.lastPathComponent)" : "Failed to open \(url.path)"
            }
        case "open_app":
            return try await openApp(arguments: arguments)
        case "open_system_setting":
            return try await openSystemSetting(arguments: arguments)
        case "paste_clipboard_entry":
            return try await pasteClipboardEntry(arguments: arguments)
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    
    private func intArg(named name: String, in arguments: [String: Any]) -> Int? {
        if let value = arguments[name] as? Int { return value }
        if let value = arguments[name] as? NSNumber { return value.intValue }
        return nil
    }
    
    private func boolArg(named name: String, in arguments: [String: Any]) -> Bool? {
        if let value = arguments[name] as? Bool { return value }
        if let value = arguments[name] as? NSNumber { return value.boolValue }
        return nil
    }
    
    private func requiredStringArg(named name: String, in arguments: [String: Any]) throws -> String {
        if let value = stringArg(named: name, in: arguments),
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return value
        }
        throw ToolError.invalidArgument("Missing required argument: \(name)")
    }
    
    private func textInput(from arguments: [String: Any]) async -> String {
        if let input = stringArg(named: "input", in: arguments), input.isEmpty == false {
            return input
        }
        if let latest = await MainActor.run(body: { latestClipboardText() }), latest.isEmpty == false {
            return latest
        }
        return ""
    }
    
    @MainActor private func latestClipboardText() -> String? {
        ClipboardHistoryService.shared.entries.first(where: { $0.kind == .text })?.text
    }
    
    @MainActor private func latestClipboardSummary() -> String {
        guard let entry = ClipboardHistoryService.shared.entries.first else {
            return "Clipboard history is empty"
        }
        if entry.kind == .image {
            let width = entry.imageWidth ?? 0
            let height = entry.imageHeight ?? 0
            return "Latest clipboard entry is an image (\(width)x\(height))"
        }
        return Self.redactSensitiveText(entry.text)
    }
    
    @MainActor private func clipboardHistorySummary(limit: Int) -> String {
        let entries = ClipboardHistoryService.shared.entries.prefix(max(1, limit))
        guard entries.isEmpty == false else { return "Clipboard history is empty" }
        return entries.enumerated().map { index, entry in
            if entry.kind == .image {
                let width = entry.imageWidth ?? 0
                let height = entry.imageHeight ?? 0
                return "\(index + 1). Image (\(width)x\(height))"
            }
            return "\(index + 1). \(Self.redactSensitiveText(entry.text))"
        }.joined(separator: "\n")
    }
    
    static func redactSensitiveText(_ text: String) -> String {
        let directSecretPatterns = [
            #"sk-[A-Za-z0-9\-_]{12,}"#,
            #"(?i)sk-sp-[A-Za-z0-9]{12,}"#
        ]
        var redacted = text
        for pattern in directSecretPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: (redacted as NSString).length)
            redacted = regex.stringByReplacingMatches(in: redacted, options: [], range: range, withTemplate: "[REDACTED SECRET]")
        }
        let prefixedPatterns = [
            #"(?i)(api[_-]?key\s*[:=]\s*)([^\s"']+)"#,
            #"(?i)(authorization\s*:\s*bearer\s+)([^\s"']+)"#
        ]
        for pattern in prefixedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let source = redacted as NSString
            let matches = regex.matches(in: redacted, options: [], range: NSRange(location: 0, length: source.length)).reversed()
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let prefix = source.substring(with: match.range(at: 1))
                if let fullRange = Range(match.range, in: redacted) {
                    redacted.replaceSubrange(fullRange, with: prefix + "[REDACTED SECRET]")
                }
            }
        }
        return redacted
    }
    
    private func timestampUnit(from raw: String?) -> TimestampInputUnit {
        guard let raw else { return .auto }
        return TimestampInputUnit(rawValue: raw) ?? .auto
    }
    
    private func format(timeResult: TimeConversionResult) -> String {
        [
            "Inferred Unit: \(timeResult.inferredUnit)",
            "Seconds: \(timeResult.seconds)",
            "Milliseconds: \(timeResult.milliseconds)",
            "Local Time: \(timeResult.localTime)",
            "UTC Time: \(timeResult.utcTime)",
            "ISO8601 UTC: \(timeResult.iso8601UTC)"
        ].joined(separator: "\n")
    }
    
    private func format(matches: [RegexMatchItem]) -> String {
        guard matches.isEmpty == false else { return "No matches found" }
        return matches.map { match in "[\(match.index)] \(match.text)" }.joined(separator: "\n")
    }
    
    @MainActor private func format(settings: [SystemSettingItem]) -> String {
        guard settings.isEmpty == false else { return "No system settings found" }
        return settings.map { item in "\(item.id): \(item.title(in: .english))" }.joined(separator: "\n")
    }
    
    @MainActor private func format(apps: [AppSearchItem]) -> String {
        guard apps.isEmpty == false else { return "No apps found" }
        return apps.map { app in
            let bundle = app.bundleIdentifier ?? app.url.path
            return "\(app.name) (\(bundle))"
        }.joined(separator: "\n")
    }
    
    private func searchFiles(query: String) async throws -> String {
        await MainActor.run {
            FileSearchService.shared.update(scope: .user(userName: NSUserName()), queryText: query)
        }
        try await Task.sleep(nanoseconds: 450_000_000)
        let results = await MainActor.run {
            let values = Array(FileSearchService.shared.results.prefix(8))
            FileSearchService.shared.stop()
            return values
        }
        guard results.isEmpty == false else { return "No files found" }
        return results.map { result in "\(result.fileName) — \(result.parentPath)" }.joined(separator: "\n")
    }
    
    private func listDirectory(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let values = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard values.isEmpty == false else { return "Directory is empty" }
        return values.prefix(50).map { item in
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? "\(item.lastPathComponent)/" : item.lastPathComponent
        }.joined(separator: "\n")
    }
    
    private func readFile(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return truncateOutput(content)
    }
    
    private func writeFile(path: String, content: String, append: Bool) throws -> String {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if append, FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = content.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            return "Appended to \(path)"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return "Wrote \(content.count) characters to \(path)"
    }
    
    private func runShellCommand(command: String, cwd: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let cwd, cwd.isEmpty == false {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let merged = [out, err].filter { $0.isEmpty == false }.joined(separator: out.isEmpty || err.isEmpty ? "" : "\n")
        if merged.isEmpty { return "Exit status: \(process.terminationStatus)" }
        return truncateOutput(merged)
    }
    
    private func truncateOutput(_ text: String, limit: Int = 4000) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "\n...[truncated]"
    }
    
    private func openApp(arguments: [String: Any]) async throws -> String {
        if let bundleIdentifier = stringArg(named: "bundleIdentifier", in: arguments),
           let url = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }) {
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            return opened ? "Opened \(bundleIdentifier)" : "Failed to open \(bundleIdentifier)"
        }
        let query = try requiredStringArg(named: "query", in: arguments)
        return await MainActor.run {
            let app = AppSearchService.shared.search(query: query, limit: 1).first
            guard let app else { return "No app found for \(query)" }
            return AppSearchService.shared.open(app) ? "Opened \(app.name)" : "Failed to open \(app.name)"
        }
    }
    
    private func openSystemSetting(arguments: [String: Any]) async throws -> String {
        if let settingID = stringArg(named: "id", in: arguments) {
            return await MainActor.run {
                let match = SystemSettingsSearchService.search(query: settingID, limit: 1).first
                guard let match else { return "No system setting found for \(settingID)" }
                return SystemSettingsSearchService.open(match, language: .english)
            }
        }
        let query = try requiredStringArg(named: "query", in: arguments)
        return await MainActor.run {
            let match = SystemSettingsSearchService.search(query: query, limit: 1).first
            guard let match else { return "No system setting found for \(query)" }
            return SystemSettingsSearchService.open(match, language: .english)
        }
    }
    
    private func pasteClipboardEntry(arguments: [String: Any]) async throws -> String {
        let rawID = stringArg(named: "entryID", in: arguments)
        return await MainActor.run {
            let entry: ClipboardHistoryEntry?
            if let rawID, let uuid = UUID(uuidString: rawID) {
                entry = ClipboardHistoryService.shared.entries.first(where: { $0.id == uuid })
            } else {
                entry = ClipboardHistoryService.shared.entries.first
            }
            guard let entry else { return "Clipboard history is empty" }
            return PasteAutomationService.pasteToApplication(entry: entry, targetApp: nil)
        }
    }
}