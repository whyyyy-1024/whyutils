import AppKit
import Foundation

private enum AIAgentDecision {
    case directMessage(String)
    case toolPlan(AIExecutionPlan)
}

struct AIPlanValidationResult: Equatable, Sendable {
    let isValid: Bool
    let requiresConfirmation: Bool
    let message: String?
}

struct AITransport: Sendable {
    let completeChat: @Sendable (_ configuration: AIConfiguration, _ messages: [OpenAIChatMessage]) async throws -> String

    init(
        completeChat: @escaping @Sendable (_ configuration: AIConfiguration, _ messages: [OpenAIChatMessage]) async throws -> String
    ) {
        self.completeChat = completeChat
    }

    static let live = AITransport { configuration, messages in
        try await OpenAICompatibleClient.completeChat(
            configuration: configuration,
            messages: messages
        )
    }

    static let failingStub = AITransport { _, _ in
        throw OpenAICompatibleClientError.invalidResponse
    }
}

struct AIToolExecutor: Sendable {
    let execute: @Sendable (_ step: AIPlanStep) async throws -> String

    init(execute: @escaping @Sendable (_ step: AIPlanStep) async throws -> String) {
        self.execute = execute
    }

    static let noOp = AIToolExecutor { step in
        throw NSError(
            domain: "AIAgentService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No tool executor registered for \(step.toolName)"]
        )
    }

    static let live = AIToolExecutor { step in
        let arguments = try parseArguments(step.argumentsJSON)

        switch step.toolName {
        case "clipboard_read_latest":
            return await MainActor.run {
                latestClipboardSummary()
            }
        case "clipboard_list_history":
            let limit = intArgument(named: "limit", in: arguments) ?? 5
            return await MainActor.run {
                clipboardHistorySummary(limit: limit)
            }
        case "json_validate":
            let input = try await textInput(from: arguments)
            return try JSONService.validate(input)
        case "json_format":
            let input = try await textInput(from: arguments)
            return try JSONService.format(input)
        case "json_minify":
            let input = try await textInput(from: arguments)
            return try JSONService.minify(input)
        case "url_encode":
            return EncodingService.urlEncode(
                try await textInput(from: arguments),
                safe: stringArgument(named: "safe", in: arguments) ?? ""
            )
        case "url_decode":
            return EncodingService.urlDecode(try await textInput(from: arguments))
        case "base64_encode":
            return EncodingService.base64Encode(
                try await textInput(from: arguments),
                urlSafe: boolArgument(named: "urlSafe", in: arguments) ?? false,
                stripPadding: boolArgument(named: "stripPadding", in: arguments) ?? false
            )
        case "base64_decode":
            return try EncodingService.base64Decode(
                try await textInput(from: arguments),
                urlSafe: boolArgument(named: "urlSafe", in: arguments) ?? false
            )
        case "timestamp_to_date":
            let result = try TimeService.timestampToDate(
                try await textInput(from: arguments),
                inputUnit: timestampUnit(from: stringArgument(named: "unit", in: arguments))
            )
            return format(timeResult: result)
        case "date_to_timestamp":
            let result = try TimeService.dateToTimestamp(
                try await textInput(from: arguments),
                interpretAsUTC: boolArgument(named: "interpretAsUTC", in: arguments) ?? false
            )
            return format(timeResult: result)
        case "regex_find":
            let pattern = try requiredStringArgument(named: "pattern", in: arguments)
            let matches = try RegexService.findMatches(
                pattern: pattern,
                text: try await textInput(from: arguments),
                ignoreCase: boolArgument(named: "ignoreCase", in: arguments) ?? false,
                multiLine: boolArgument(named: "multiLine", in: arguments) ?? false,
                dotMatchesNewLine: boolArgument(named: "dotMatchesNewLine", in: arguments) ?? false
            )
            return format(matches: matches)
        case "regex_replace_preview":
            let pattern = try requiredStringArgument(named: "pattern", in: arguments)
            let replacement = stringArgument(named: "replacement", in: arguments) ?? ""
            return try RegexService.replace(
                pattern: pattern,
                replacement: replacement,
                text: try await textInput(from: arguments),
                ignoreCase: boolArgument(named: "ignoreCase", in: arguments) ?? false,
                multiLine: boolArgument(named: "multiLine", in: arguments) ?? false,
                dotMatchesNewLine: boolArgument(named: "dotMatchesNewLine", in: arguments) ?? false
            )
        case "search_system_settings":
            let query = try requiredStringArgument(named: "query", in: arguments)
            return await MainActor.run {
                format(settings: SystemSettingsSearchService.search(query: query, limit: 6))
            }
        case "search_apps":
            let query = try requiredStringArgument(named: "query", in: arguments)
            return await MainActor.run {
                format(apps: AppSearchService.shared.search(query: query, limit: 8))
            }
        case "search_files":
            let query = try requiredStringArgument(named: "query", in: arguments)
            return try await searchFiles(query: query)
        case "list_directory":
            let path = stringArgument(named: "path", in: arguments) ?? FileManager.default.homeDirectoryForCurrentUser.path
            return try listDirectory(path: path)
        case "read_file":
            let path = try requiredStringArgument(named: "path", in: arguments)
            return try readFile(path: path)
        case "write_file":
            let path = try requiredStringArgument(named: "path", in: arguments)
            let content = try requiredStringArgument(named: "content", in: arguments)
            let append = boolArgument(named: "append", in: arguments) ?? false
            return try writeFile(path: path, content: content, append: append)
        case "run_shell_command":
            let command = try requiredStringArgument(named: "command", in: arguments)
            let cwd = stringArgument(named: "cwd", in: arguments)
            return try runShellCommand(command: command, cwd: cwd)
        case "open_url":
            let rawURL = try requiredStringArgument(named: "url", in: arguments)
            return await MainActor.run {
                guard let url = URL(string: rawURL) else {
                    return "Invalid URL: \(rawURL)"
                }
                let opened = NSWorkspace.shared.open(url)
                return opened ? "Opened \(rawURL)" : "Failed to open \(rawURL)"
            }
        case "open_file":
            let path = try requiredStringArgument(named: "path", in: arguments)
            return await MainActor.run {
                let url = URL(fileURLWithPath: path)
                let opened = NSWorkspace.shared.open(url)
                return opened ? "Opened \(url.lastPathComponent)" : "Failed to open \(url.path)"
            }
        case "open_app":
            return try await openApp(arguments: arguments)
        case "open_system_setting":
            return try await openSystemSetting(arguments: arguments)
        case "paste_clipboard_entry":
            return try await pasteClipboardEntry(arguments: arguments)
        default:
            throw NSError(
                domain: "AIAgentService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported tool: \(step.toolName)"]
            )
        }
    }

    private static func parseArguments(_ raw: String) throws -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let data = trimmed.data(using: .utf8) else { return [:] }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return value as? [String: Any] ?? [:]
    }

    private static func textInput(from arguments: [String: Any]) async throws -> String {
        if let input = stringArgument(named: "input", in: arguments), input.isEmpty == false {
            return input
        }
        if let latest = await MainActor.run(body: {
            latestClipboardText()
        }), latest.isEmpty == false {
            return latest
        }
        throw NSError(
            domain: "AIAgentService",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Missing text input and latest clipboard text is empty"]
        )
    }

    @MainActor
    private static func latestClipboardText() -> String? {
        ClipboardHistoryService.shared.entries.first(where: { $0.kind == .text })?.text
    }

    @MainActor
    private static func latestClipboardSummary() -> String {
        guard let entry = ClipboardHistoryService.shared.entries.first else {
            return "Clipboard history is empty"
        }
        if entry.kind == .image {
            let width = entry.imageWidth ?? 0
            let height = entry.imageHeight ?? 0
            return "Latest clipboard entry is an image (\(width)x\(height))"
        }
        return redactSensitiveText(entry.text)
    }

    @MainActor
    private static func clipboardHistorySummary(limit: Int) -> String {
        let entries = ClipboardHistoryService.shared.entries.prefix(max(1, limit))
        guard entries.isEmpty == false else {
            return "Clipboard history is empty"
        }
        return entries.enumerated().map { index, entry in
            if entry.kind == .image {
                let width = entry.imageWidth ?? 0
                let height = entry.imageHeight ?? 0
                return "\(index + 1). Image (\(width)x\(height))"
            }
            return "\(index + 1). \(redactSensitiveText(entry.text))"
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
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                options: [],
                range: range,
                withTemplate: "[REDACTED SECRET]"
            )
        }

        let prefixedPatterns = [
            #"(?i)(api[_-]?key\s*[:=]\s*)([^\s"']+)"#,
            #"(?i)(authorization\s*:\s*bearer\s+)([^\s"']+)"#
        ]

        for pattern in prefixedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let source = redacted as NSString
            let matches = regex.matches(
                in: redacted,
                options: [],
                range: NSRange(location: 0, length: source.length)
            ).reversed()

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

    private static func stringArgument(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }

    private static func intArgument(named name: String, in arguments: [String: Any]) -> Int? {
        if let value = arguments[name] as? Int {
            return value
        }
        if let value = arguments[name] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func boolArgument(named name: String, in arguments: [String: Any]) -> Bool? {
        if let value = arguments[name] as? Bool {
            return value
        }
        if let value = arguments[name] as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private static func requiredStringArgument(named name: String, in arguments: [String: Any]) throws -> String {
        if let value = stringArgument(named: name, in: arguments),
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return value
        }
        throw NSError(
            domain: "AIAgentService",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Missing required argument: \(name)"]
        )
    }

    private static func timestampUnit(from raw: String?) -> TimestampInputUnit {
        guard let raw else { return .auto }
        return TimestampInputUnit(rawValue: raw) ?? .auto
    }

    private static func format(timeResult: TimeConversionResult) -> String {
        [
            "Inferred Unit: \(timeResult.inferredUnit)",
            "Seconds: \(timeResult.seconds)",
            "Milliseconds: \(timeResult.milliseconds)",
            "Local Time: \(timeResult.localTime)",
            "UTC Time: \(timeResult.utcTime)",
            "ISO8601 UTC: \(timeResult.iso8601UTC)"
        ].joined(separator: "\n")
    }

    private static func format(matches: [RegexMatchItem]) -> String {
        guard matches.isEmpty == false else {
            return "No matches found"
        }
        return matches.map { match in
            "[\(match.index)] \(match.text)"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func format(settings: [SystemSettingItem]) -> String {
        guard settings.isEmpty == false else {
            return "No system settings found"
        }
        return settings.map { item in
            "\(item.id): \(item.title(in: .english))"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func format(apps: [AppSearchItem]) -> String {
        guard apps.isEmpty == false else {
            return "No apps found"
        }
        return apps.map { app in
            let bundle = app.bundleIdentifier ?? app.url.path
            return "\(app.name) (\(bundle))"
        }.joined(separator: "\n")
    }

    private static func searchFiles(query: String) async throws -> String {
        await MainActor.run {
            FileSearchService.shared.update(
                scope: .user(userName: NSUserName()),
                queryText: query
            )
        }
        try await Task.sleep(nanoseconds: 450_000_000)
        let results = await MainActor.run {
            let values = Array(FileSearchService.shared.results.prefix(8))
            FileSearchService.shared.stop()
            return values
        }
        guard results.isEmpty == false else {
            return "No files found"
        }
        return results.map { result in
            "\(result.fileName) — \(result.parentPath)"
        }.joined(separator: "\n")
    }

    private static func listDirectory(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let values = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard values.isEmpty == false else {
            return "Directory is empty"
        }
        return values.prefix(50).map { item in
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? "\(item.lastPathComponent)/" : item.lastPathComponent
        }.joined(separator: "\n")
    }

    private static func readFile(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return truncateOutput(content)
    }

    private static func writeFile(path: String, content: String, append: Bool) throws -> String {
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

    private static func runShellCommand(command: String, cwd: String?) throws -> String {
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
        let merged = [out, err]
            .filter { $0.isEmpty == false }
            .joined(separator: out.isEmpty || err.isEmpty ? "" : "\n")

        if merged.isEmpty {
            return "Exit status: \(process.terminationStatus)"
        }
        return truncateOutput(merged)
    }

    private static func truncateOutput(_ text: String, limit: Int = 4000) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "\n...[truncated]"
    }

    private static func openApp(arguments: [String: Any]) async throws -> String {
        if let bundleIdentifier = stringArgument(named: "bundleIdentifier", in: arguments),
           let url = await MainActor.run(body: {
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
           }) {
            let opened = await MainActor.run {
                NSWorkspace.shared.open(url)
            }
            return opened ? "Opened \(bundleIdentifier)" : "Failed to open \(bundleIdentifier)"
        }

        let query = try requiredStringArgument(named: "query", in: arguments)
        return await MainActor.run {
            let app = AppSearchService.shared.search(query: query, limit: 1).first
            guard let app else {
                return "No app found for \(query)"
            }
            let opened = AppSearchService.shared.open(app)
            return opened ? "Opened \(app.name)" : "Failed to open \(app.name)"
        }
    }

    private static func openSystemSetting(arguments: [String: Any]) async throws -> String {
        if let settingID = stringArgument(named: "id", in: arguments) {
            return await MainActor.run {
                let match = SystemSettingsSearchService.search(query: settingID, limit: 1).first
                guard let match else {
                    return "No system setting found for \(settingID)"
                }
                return SystemSettingsSearchService.open(match, language: .english)
            }
        }

        let query = try requiredStringArgument(named: "query", in: arguments)
        return await MainActor.run {
            let match = SystemSettingsSearchService.search(query: query, limit: 1).first
            guard let match else {
                return "No system setting found for \(query)"
            }
            return SystemSettingsSearchService.open(match, language: .english)
        }
    }

    private static func pasteClipboardEntry(arguments: [String: Any]) async throws -> String {
        let rawID = stringArgument(named: "entryID", in: arguments)
        return await MainActor.run {
            let entry: ClipboardHistoryEntry?
            if let rawID,
               let uuid = UUID(uuidString: rawID) {
                entry = ClipboardHistoryService.shared.entries.first(where: { $0.id == uuid })
            } else {
                entry = ClipboardHistoryService.shared.entries.first
            }

            guard let entry else {
                return "Clipboard history is empty"
            }

            return PasteAutomationService.pasteToApplication(
                entry: entry,
                targetApp: nil
            )
        }
    }
}

struct AIAgentService: Sendable {
    let registry: AIToolRegistry
    let transport: AITransport
    let executor: AIToolExecutor
    let maxPlanSteps: Int
    let accessMode: AIAgentAccessMode

    init(
        registry: AIToolRegistry,
        transport: AITransport,
        executor: AIToolExecutor,
        maxPlanSteps: Int = AIAgentAccessMode.standard.maxPlanSteps,
        accessMode: AIAgentAccessMode = .standard
    ) {
        self.registry = registry
        self.transport = transport
        self.executor = executor
        self.maxPlanSteps = maxPlanSteps
        self.accessMode = accessMode
    }

    static func live(configuration: AIConfiguration) -> AIAgentService {
        AIAgentService(
            registry: .configured(accessMode: configuration.accessMode),
            transport: .live,
            executor: .live,
            maxPlanSteps: configuration.accessMode.maxPlanSteps,
            accessMode: configuration.accessMode
        )
    }

    func submit(
        task: String,
        configuration: AIConfiguration,
        context: AIAgentContext,
        conversation: [OpenAIChatMessage] = []
    ) async throws -> AIAgentSubmissionResult {
        if let capabilityMessage = capabilityReply(for: task) {
            return .completed(
                AIAgentRunResult(
                    plan: AIExecutionPlan(goal: task, steps: []),
                    traces: [],
                    finalMessage: capabilityMessage
                )
            )
        }

        let decision = try await decide(
            task: task,
            configuration: configuration,
            context: context,
            conversation: conversation
        )

        switch decision {
        case .directMessage(let message):
            return .completed(
                AIAgentRunResult(
                    plan: AIExecutionPlan(goal: task, steps: []),
                    traces: [],
                    finalMessage: message
                )
            )
        case .toolPlan(let plan):
            let validation = validate(plan: plan)
            guard validation.isValid else {
                throw NSError(
                    domain: "AIAgentService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: validation.message ?? "Plan validation failed"]
                )
            }

            if validation.requiresConfirmation {
                let gatedPlan = markConfirmationSteps(plan)
                return .awaitingConfirmation(AIConfirmationRequest(plan: gatedPlan))
            }

            return .completed(
                try await execute(
                    plan: markConfirmationSteps(plan),
                    task: task,
                    configuration: nil
                )
            )
        }
    }

    func confirm(
        _ request: AIConfirmationRequest,
        configuration: AIConfiguration?
    ) async throws -> AIAgentRunResult {
        try await execute(
            plan: request.plan,
            task: request.plan.goal,
            configuration: configuration
        )
    }

    func streamDirectReply(
        task: String,
        configuration: AIConfiguration,
        context: AIAgentContext,
        conversation: [OpenAIChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let messages = directReplyMessages(
            task: task,
            context: context,
            conversation: conversation
        )
        return OpenAICompatibleClient.streamChat(
            configuration: configuration,
            messages: messages
        )
    }

    func streamRunSummary(
        task: String,
        run: AIAgentRunResult,
        configuration: AIConfiguration,
        conversation: [OpenAIChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let messages = summaryMessages(
            task: task,
            run: run,
            conversation: conversation
        )
        return OpenAICompatibleClient.streamChat(
            configuration: configuration,
            messages: messages
        )
    }

    func validate(plan: AIExecutionPlan) -> AIPlanValidationResult {
        if plan.steps.isEmpty {
            return AIPlanValidationResult(
                isValid: false,
                requiresConfirmation: false,
                message: "Plan must include at least one step"
            )
        }

        if plan.exceedsStepLimit(limit: maxPlanSteps) {
            return AIPlanValidationResult(
                isValid: false,
                requiresConfirmation: false,
                message: "Plan exceeds step limit of \(maxPlanSteps)"
            )
        }

        var needsConfirmation = false
        for step in plan.steps {
            guard let tool = registry.tool(named: step.toolName) else {
                return AIPlanValidationResult(
                    isValid: false,
                    requiresConfirmation: false,
                    message: "Unknown tool: \(step.toolName)"
                )
            }
            if tool.requiresConfirmation {
                needsConfirmation = true
            }
        }

        return AIPlanValidationResult(
            isValid: true,
            requiresConfirmation: needsConfirmation,
            message: nil
        )
    }

    private func execute(
        plan: AIExecutionPlan,
        task: String,
        configuration: AIConfiguration?
    ) async throws -> AIAgentRunResult {
        var traces: [AIToolExecutionTrace] = []
        for step in plan.steps {
            let output = try await executor.execute(step)
            traces.append(
                AIToolExecutionTrace(
                    toolName: step.toolName,
                    argumentsJSON: step.argumentsJSON,
                    output: output
                )
            )
        }

        let finalMessage = configuration == nil
            ? (traces.last?.output ?? plan.goal)
            : (traces.last?.output ?? task)

        return AIAgentRunResult(
            plan: plan,
            traces: traces,
            finalMessage: finalMessage
        )
    }

    private func decide(
        task: String,
        configuration: AIConfiguration,
        context: AIAgentContext,
        conversation: [OpenAIChatMessage]
    ) async throws -> AIAgentDecision {
        let content = try await transport.completeChat(
            configuration,
            decisionMessages(
                task: task,
                context: context,
                conversation: conversation
            )
        )
        return try decodeDecision(from: content)
    }

    private func decisionMessages(
        task: String,
        context: AIAgentContext,
        conversation: [OpenAIChatMessage]
    ) -> [OpenAIChatMessage] {
        let toolLines = registry.tools.map { tool in
            let confirmation = tool.requiresConfirmation ? "requires confirmation" : "safe"
            return "- \(tool.name): \(tool.description) (\(confirmation))"
        }.joined(separator: "\n")

        let clipboardContext = context.latestClipboardText.map(AIToolExecutor.redactSensitiveText) ?? "none"
        let recentClipboard = context.recentClipboardTexts
            .map(AIToolExecutor.redactSensitiveText)
            .joined(separator: "\n")
        let conversationSummary = conversation.suffix(8).map { message in
            "\(message.role): \(message.content)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are an AI assistant for WhyUtils.
        Decide whether the user needs direct conversation or local tool execution.
        Current access mode: \(accessMode.rawValue)
        Return only compact JSON in one of these shapes:
        {"type":"message","message":"..."}
        {"type":"tool_plan","goal":"...","steps":[{"toolName":"...","argumentsJSON":"{...}"}]}
        Rules:
        - Use "message" when the user is just chatting or does not need local tool execution.
        - Use "tool_plan" when local tools are useful.
        - Tool plans must use 1 to \(maxPlanSteps) steps.
        - Only use these tools:
        \(toolLines)
        - If a tool uses the latest clipboard text, pass an empty JSON object.
        - In unrestricted mode, you may use shell and file tools to complete broader local tasks.
        - Never wrap JSON in markdown fences.
        """

        let userPrompt = """
        Recent conversation:
        \(conversationSummary.isEmpty ? "none" : conversationSummary)

        Task: \(task)
        Latest clipboard text: \(clipboardContext)
        Recent clipboard text history:
        \(recentClipboard.isEmpty ? "none" : recentClipboard)
        Paste target app name: \(context.pasteTargetAppName)
        """

        return [
            OpenAIChatMessage(role: "system", content: systemPrompt),
            OpenAIChatMessage(role: "user", content: userPrompt)
        ]
    }

    private func decodeDecision(from content: String) throws -> AIAgentDecision {
        struct DecisionEnvelope: Decodable {
            let type: String
            let message: String?
            let goal: String?
            let steps: [AIPlanStep]?
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawJSON: String
        if trimmed.hasPrefix("```") {
            rawJSON = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rawJSON = trimmed
        }

        guard let data = rawJSON.data(using: .utf8) else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        let envelope = try JSONDecoder().decode(DecisionEnvelope.self, from: data)
        switch envelope.type {
        case "message":
            guard let message = envelope.message,
                  message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw OpenAICompatibleClientError.invalidResponse
            }
            return .directMessage(message)
        case "tool_plan":
            guard let goal = envelope.goal, let steps = envelope.steps else {
                throw OpenAICompatibleClientError.invalidResponse
            }
            return .toolPlan(AIExecutionPlan(goal: goal, steps: steps))
        default:
            throw OpenAICompatibleClientError.invalidResponse
        }
    }

    private func markConfirmationSteps(_ plan: AIExecutionPlan) -> AIExecutionPlan {
        AIExecutionPlan(
            goal: plan.goal,
            steps: plan.steps.map { step in
                let requiresConfirmation = registry.tool(named: step.toolName)?.requiresConfirmation ?? step.requiresConfirmation
                return AIPlanStep(
                    id: step.id,
                    toolName: step.toolName,
                    argumentsJSON: step.argumentsJSON,
                    requiresConfirmation: requiresConfirmation
                )
            }
        )
    }

    private enum CapabilityIntent {
        case readFiles
        case runShell
        case openBrowser
        case writeFiles
        case searchDirectories
    }

    private func capabilityReply(for task: String) -> String? {
        let normalized = task
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalized.isEmpty == false else { return nil }
        guard let intent = capabilityIntent(for: normalized) else { return nil }

        let chinese = containsChineseText(task)
        switch intent {
        case .readFiles:
            return chinese ? readFilesReplyChinese() : readFilesReplyEnglish()
        case .runShell:
            return chinese ? runShellReplyChinese() : runShellReplyEnglish()
        case .openBrowser:
            return chinese ? openBrowserReplyChinese() : openBrowserReplyEnglish()
        case .writeFiles:
            return chinese ? writeFilesReplyChinese() : writeFilesReplyEnglish()
        case .searchDirectories:
            return chinese ? searchDirectoriesReplyChinese() : searchDirectoriesReplyEnglish()
        }
    }

    private func capabilityIntent(for normalizedTask: String) -> CapabilityIntent? {
        let capabilityLanguage = normalizedTask.contains("?")
            || normalizedTask.contains("吗")
            || normalizedTask.contains("能")
            || normalizedTask.contains("can you")

        guard capabilityLanguage else { return nil }

        if matchesCapability(
            normalizedTask,
            englishSignals: ["modify file", "write file", "edit file", "change file"],
            chineseSignals: ["修改文件", "写文件", "编辑文件", "改文件"]
        ) {
            return .writeFiles
        }

        if matchesCapability(
            normalizedTask,
            englishSignals: ["run shell", "run command", "execute command", "terminal command"],
            chineseSignals: ["执行命令", "跑命令", "终端命令", "shell命令", "shell 命令"]
        ) {
            return .runShell
        }

        if matchesCapability(
            normalizedTask,
            englishSignals: ["open browser", "launch browser", "open url", "open the browser"],
            chineseSignals: ["打开浏览器", "打开网页", "打开网址", "打开链接"]
        ) {
            return .openBrowser
        }

        if matchesCapability(
            normalizedTask,
            englishSignals: ["search directory", "search directories", "search local directory", "browse directory"],
            chineseSignals: ["搜索本地目录", "搜索目录", "本地目录", "查目录"]
        ) {
            return .searchDirectories
        }

        if matchesCapability(
            normalizedTask,
            englishSignals: ["can you read", "can you access", "read files", "read my files", "access my files", "local file", "local files", "my mac"],
            chineseSignals: ["读取", "读到", "访问", "本地文件", "电脑上的文件", "我电脑上", "文件吗"]
        ) {
            return .readFiles
        }

        return nil
    }

    private func matchesCapability(
        _ normalizedTask: String,
        englishSignals: [String],
        chineseSignals: [String]
    ) -> Bool {
        englishSignals.contains(where: normalizedTask.contains)
            || chineseSignals.contains(where: normalizedTask.contains)
    }

    private func readFilesReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接读取你电脑上的本地文件。把权限切到 `Full Access` 或 `Unrestricted` 后，我就可以按你给的路径读取文本文件、列目录。"
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            let extra = accessMode == .unrestricted
                ? "在 `Unrestricted` 下还可以继续执行更强的本地动作。"
                : "如果你给我一个文件或目录路径，我可以继续读内容或查看目录。"
            return "可以。现在是 `\(modeLabel)`，我可以读取你电脑上的文本文件、查看目录内容，也可以根据路径帮你分析文件。\(extra)"
        }
    }

    private func readFilesReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly read files on your Mac. Switch to Full Access or Unrestricted and I can read text files or inspect directories when you give me a path."
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            let extra = accessMode == .unrestricted
                ? "In Unrestricted mode I can also continue with broader local actions."
                : "Send me a file or directory path and I'll continue from there."
            return "Yes. In \(modeLabel) mode I can read local text files, inspect directories, and work from a file path you give me. \(extra)"
        }
    }

    private func runShellReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接执行 shell 命令。切到 `Full Access` 或 `Unrestricted` 后，我就可以按你的要求运行本地命令。"
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            let extra = accessMode == .unrestricted
                ? "在 `Unrestricted` 下我可以把这类本地命令执行流程走得更完整。"
                : "如果你给我具体命令，我会按当前模式执行。"
            return "可以。现在是 `\(modeLabel)`，我可以执行 shell 命令并读取输出结果。\(extra)"
        }
    }

    private func runShellReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly run shell commands. Switch to Full Access or Unrestricted and I can execute local commands for you."
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            return "Yes. In \(modeLabel) mode I can run shell commands and inspect the output. Send me the command you want to run."
        }
    }

    private func openBrowserReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接打开浏览器或网址。切到 `Full Access` 或 `Unrestricted` 后，我就可以按 URL 或搜索目标帮你打开浏览器。"
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            return "可以。现在是 `\(modeLabel)`，我可以帮你打开浏览器或直接打开指定 URL / 网址。你把链接或目标告诉我就行。"
        }
    }

    private func openBrowserReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly open the browser or launch URLs. Switch to Full Access or Unrestricted and I can do that for you."
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            return "Yes. In \(modeLabel) mode I can open the browser or launch a specific URL for you. Send me the URL or target."
        }
    }

    private func writeFilesReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接修改本地文件。切到 `Full Access` 或 `Unrestricted` 后，我可以按路径写入或修改文件。"
        case .fullAccess, .unrestricted:
            let confirmation = accessMode == .fullAccess ? "在 `Full Access` 下这类写文件动作会先确认。" : "在 `Unrestricted` 下也可以继续直接执行更强的本地改动。"
            return "可以。现在的模式允许我修改文件、写入内容和覆盖文本。\(confirmation) 你直接给我文件路径和要改的内容就行。"
        }
    }

    private func writeFilesReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly modify local files. Switch to Full Access or Unrestricted and I can write or edit files by path."
        case .fullAccess, .unrestricted:
            let confirmation = accessMode == .fullAccess ? "In Full Access, file writes still go through confirmation." : "In Unrestricted, I can continue with broader local edits as well."
            return "Yes. In the current mode I can modify files, write content, and update text by path. \(confirmation)"
        }
    }

    private func searchDirectoriesReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接搜索你电脑上的本地目录。切到 `Full Access` 或 `Unrestricted` 后，我可以按路径列目录、搜索目录内容。"
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            return "可以。现在是 `\(modeLabel)`，我可以搜索本地目录、列出目录内容，也可以按你给的路径继续往下找文件。你直接给我目录路径就行。"
        }
    }

    private func searchDirectoriesReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly search local directories on your Mac. Switch to Full Access or Unrestricted and I can inspect paths and search directories."
        case .fullAccess, .unrestricted:
            let modeLabel = accessMode == .fullAccess ? "Full Access" : "Unrestricted"
            return "Yes. In \(modeLabel) mode I can search local directories, inspect path contents, and keep drilling down from a directory path you give me."
        }
    }

    private func containsChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic
        }
    }

    private func directReplyMessages(
        task: String,
        context: AIAgentContext,
        conversation: [OpenAIChatMessage]
    ) -> [OpenAIChatMessage] {
        let clipboardContext = context.latestClipboardText.map(AIToolExecutor.redactSensitiveText) ?? "none"
        let history = conversation.suffix(8)
        return [
            OpenAIChatMessage(
                role: "system",
                content: """
                You are the chat reply writer for WhyUtils.
                Reply naturally and concisely.
                Never expose secret-like values.
                """
            )
        ] + history + [
            OpenAIChatMessage(
                role: "user",
                content: """
                User request:
                \(task)

                Latest clipboard text:
                \(clipboardContext)
                """
            )
        ]
    }

    private func summaryMessages(
        task: String,
        run: AIAgentRunResult,
        conversation: [OpenAIChatMessage]
    ) -> [OpenAIChatMessage] {
        let history = conversation.suffix(8)
        let toolOutputs = run.traces.map { trace in
            """
            Tool: \(trace.toolName)
            Arguments: \(trace.argumentsJSON)
            Output:
            \(trace.output)
            """
        }.joined(separator: "\n\n")

        return [
            OpenAIChatMessage(
                role: "system",
                content: """
                You are the assistant reply writer for WhyUtils.
                Write a concise, user-facing answer in plain text.
                Summarize the tool results instead of echoing raw traces.
                Never expose secret-like values.
                """
            )
        ] + history + [
            OpenAIChatMessage(
                role: "user",
                content: """
                Original task:
                \(task)

                Executed plan:
                \(run.plan.goal)

                Tool outputs:
                \(toolOutputs)
                """
            )
        ]
    }
}
