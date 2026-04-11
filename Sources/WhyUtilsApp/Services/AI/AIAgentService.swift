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

    static func live(accessMode: AIAgentAccessMode) -> AIToolExecutor {
        let basicModule = BasicToolModule(accessMode: accessMode)
        let fsModule = FileSystemModule()
        let codeModule = CodeEditModule()
        let memoryModule = MemoryModule()
        let sysModule = SystemControlModule()
        
        let allModules: [ToolProvider] = [basicModule, fsModule, codeModule, memoryModule, sysModule]
        let registry = ToolRegistry(providers: allModules)
        let executor = ToolExecutor(registry: registry, providers: allModules)
        return AIToolExecutor { step in
            let arguments = try parseArguments(step.argumentsJSON)
            let result = try await executor.execute(toolName: step.toolName, arguments: arguments)
            return result.output
        }
    }

    private static func parseArguments(_ raw: String) throws -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let data = trimmed.data(using: .utf8) else { return [:] }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return value as? [String: Any] ?? [:]
    }

    static func redactSensitiveText(_ text: String) -> String {
        BasicToolModule.redactSensitiveText(text)
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
            executor: .live(accessMode: configuration.accessMode),
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
            return "当前 `Standard` 模式下我不能直接读取你电脑上的本地文件。把权限切到 `Full Access` 后，我就可以按你给的路径读取文本文件、列目录。"
        case .fullAccess:
            return "可以。现在是 `Full Access`，我可以读取你电脑上的文本文件、查看目录内容，也可以根据路径帮你分析文件。如果你给我一个文件或目录路径，我可以继续读内容或查看目录。"
        }
    }

    private func readFilesReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly read files on your Mac. Switch to Full Access and I can read text files or inspect directories when you give me a path."
        case .fullAccess:
            return "Yes. In Full Access mode I can read local text files, inspect directories, and work from a file path you give me. Send me a file or directory path and I'll continue from there."
        }
    }

    private func runShellReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接执行 shell 命令。切到 `Full Access` 后，我就可以按你的要求运行本地命令。"
        case .fullAccess:
            return "可以。现在是 `Full Access`，我可以执行 shell 命令并读取输出结果。如果你给我具体命令，我会直接执行。"
        }
    }

    private func runShellReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly run shell commands. Switch to Full Access and I can execute local commands for you."
        case .fullAccess:
            return "Yes. In Full Access mode I can run shell commands and inspect the output. Send me the command you want to run."
        }
    }

    private func openBrowserReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接打开浏览器或网址。切到 `Full Access` 后，我就可以按 URL 或搜索目标帮你打开浏览器。"
        case .fullAccess:
            return "可以。现在是 `Full Access`，我可以帮你打开浏览器或直接打开指定 URL / 网址。你把链接或目标告诉我就行。"
        }
    }

    private func openBrowserReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly open the browser or launch URLs. Switch to Full Access and I can do that for you."
        case .fullAccess:
            return "Yes. In Full Access mode I can open the browser or launch a specific URL for you. Send me the URL or target."
        }
    }

    private func writeFilesReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接修改本地文件。切到 `Full Access` 后，我可以按路径写入或修改文件。"
        case .fullAccess:
            return "可以。现在是 `Full Access`，我可以修改文件、写入内容和覆盖文本。你直接给我文件路径和要改的内容就行。"
        }
    }

    private func writeFilesReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly modify local files. Switch to Full Access and I can write or edit files by path."
        case .fullAccess:
            return "Yes. In Full Access mode I can modify files, write content, and update text by path."
        }
    }

    private func searchDirectoriesReplyChinese() -> String {
        switch accessMode {
        case .standard:
            return "当前 `Standard` 模式下我不能直接搜索你电脑上的本地目录。切到 `Full Access` 后，我可以按路径列目录、搜索目录内容。"
        case .fullAccess:
            return "可以。现在是 `Full Access`，我可以搜索本地目录、列出目录内容，也可以按你给的路径继续往下找文件。你直接给我目录路径就行。"
        }
    }

    private func searchDirectoriesReplyEnglish() -> String {
        switch accessMode {
        case .standard:
            return "In Standard mode I can't directly search local directories on your Mac. Switch to Full Access and I can inspect paths and search directories."
        case .fullAccess:
            return "Yes. In Full Access mode I can search local directories, inspect path contents, and keep drilling down from a directory path you give me."
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
