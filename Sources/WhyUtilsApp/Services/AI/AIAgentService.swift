import AppKit
import Foundation

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
        return entry.text
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
            return "\(index + 1). \(entry.text)"
        }.joined(separator: "\n")
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

    static let live = AIAgentService(
        registry: .live,
        transport: .live,
        executor: .live
    )

    func submit(
        task: String,
        configuration: AIConfiguration,
        context: AIAgentContext
    ) async throws -> AIAgentSubmissionResult {
        let content = try await transport.completeChat(
            configuration,
            planningMessages(task: task, context: context)
        )
        let plan = try decodePlan(from: content)
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

        return .completed(try await execute(plan: markConfirmationSteps(plan)))
    }

    func confirm(_ request: AIConfirmationRequest) async throws -> AIAgentRunResult {
        try await execute(plan: request.plan)
    }

    func validate(plan: AIExecutionPlan) -> AIPlanValidationResult {
        if plan.steps.isEmpty {
            return AIPlanValidationResult(
                isValid: false,
                requiresConfirmation: false,
                message: "Plan must include at least one step"
            )
        }

        if plan.exceedsStepLimit(limit: 3) {
            return AIPlanValidationResult(
                isValid: false,
                requiresConfirmation: false,
                message: "Plan exceeds step limit"
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

    private func execute(plan: AIExecutionPlan) async throws -> AIAgentRunResult {
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

        return AIAgentRunResult(
            plan: plan,
            traces: traces,
            finalMessage: traces.last?.output ?? plan.goal
        )
    }

    private func planningMessages(task: String, context: AIAgentContext) -> [OpenAIChatMessage] {
        let toolLines = registry.tools.map { tool in
            let confirmation = tool.requiresConfirmation ? "requires confirmation" : "safe"
            return "- \(tool.name): \(tool.description) (\(confirmation))"
        }.joined(separator: "\n")

        let clipboardContext = context.latestClipboardText ?? "none"
        let recentClipboard = context.recentClipboardTexts.joined(separator: "\n")

        let systemPrompt = """
        You are an AI planner for WhyUtils.
        Return only compact JSON with this shape:
        {"goal":"...","steps":[{"toolName":"...","argumentsJSON":"{...}"}]}
        Rules:
        - Use 1 to 3 steps.
        - Only use these tools:
        \(toolLines)
        - If a tool uses the latest clipboard text, pass an empty JSON object.
        - Never wrap JSON in markdown fences.
        """

        let userPrompt = """
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

    private func decodePlan(from content: String) throws -> AIExecutionPlan {
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
        return try JSONDecoder().decode(AIExecutionPlan.self, from: data)
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
}
