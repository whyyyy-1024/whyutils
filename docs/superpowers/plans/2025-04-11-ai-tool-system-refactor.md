# AI Tool System Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor AI assistant tool system from hardcoded switch-case to modular provider architecture with 13 new features.

**Architecture:** ToolProvider protocol -> ToolRegistry -> ToolExecutor. Each tool module implements ToolProvider. AIAgentService uses new ToolExecutor.

**Tech Stack:** Swift, Foundation, AppKit, swift-testing

---

### Task 1: Core Types and Protocols

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/ToolTypes.swift`
- Create: `Sources/WhyUtilsApp/Services/Tools/ToolProvider.swift`
- Test: `Tests/WhyUtilsAppTests/ToolTypesTests.swift`

- [ ] **Step 1: Write failing test for ToolTypes**

```swift
// Tests/WhyUtilsAppTests/ToolTypesTests.swift
import Testing
@testable import WhyUtilsApp

struct ToolTypesTests {
    @Test
    func dangerLevelOrdering() {
        #expect(DangerLevel.safe.rawValue < DangerLevel.moderate.rawValue)
        #expect(DangerLevel.moderate.rawValue < DangerLevel.dangerous.rawValue)
    }
    
    @Test
    func toolDescriptorContainsRequiredFields() {
        let tool = ToolDescriptor(
            name: "test_tool",
            description: "A test tool",
            parameters: [],
            requiresConfirmation: true,
            providerId: "basic",
            dangerousLevel: .moderate
        )
        #expect(tool.name == "test_tool")
        #expect(tool.requiresConfirmation == true)
        #expect(tool.dangerousLevel == .moderate)
        #expect(tool.providerId == "basic")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ToolTypesTests`
Expected: FAIL with "Cannot find 'DangerLevel' in scope"

- [ ] **Step 3: Create ToolTypes.swift with core types**

```swift
// Sources/WhyUtilsApp/Services/Tools/ToolTypes.swift
import Foundation

enum DangerLevel: Int, Codable, Sendable {
    case safe = 0
    case moderate = 1
    case dangerous = 2
}

enum ParamType: String, Codable, Sendable {
    case string
    case int
    case bool
    case object
    case array
}

struct ParamConstraints: Codable, Sendable {
    let min: Int?
    let max: Int?
    let pattern: String?
}

struct ToolParameter: Codable, Sendable {
    let name: String
    let type: ParamType
    let required: Bool
    let description: String
    let defaultValue: String?
    let constraints: ParamConstraints?
    
    init(name: String, type: ParamType, required: Bool, description: String, defaultValue: String? = nil, constraints: ParamConstraints? = nil) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
        self.constraints = constraints
    }
}

struct ToolDescriptor: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
    let requiresConfirmation: Bool
    let providerId: String
    let dangerousLevel: DangerLevel
    
    init(name: String, description: String, parameters: [ToolParameter] = [], requiresConfirmation: Bool = false, providerId: String, dangerousLevel: DangerLevel) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.requiresConfirmation = requiresConfirmation
        self.providerId = providerId
        self.dangerousLevel = dangerousLevel
    }
}

struct ToolResult: Sendable {
    let toolName: String
    let output: String
    let durationMs: Int
    let success: Bool
    
    init(toolName: String, output: String, durationMs: Int, success: Bool = true) {
        self.toolName = toolName
        self.output = output
        self.durationMs = durationMs
        self.success = success
    }
}

enum ToolError: LocalizedError, Sendable {
    case unknownTool(String)
    case providerNotFound(String)
    case invalidArgument(String)
    case executionFailed(String, String)
    
    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .providerNotFound(let id): return "Provider not found: \(id)"
        case .invalidArgument(let msg): return "Invalid argument: \(msg)"
        case .executionFailed(let tool, let msg): return "Execution failed for \(tool): \(msg)"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ToolTypesTests`
Expected: PASS

- [ ] **Step 5: Create ToolProvider protocol**

```swift
// Sources/WhyUtilsApp/Services/Tools/ToolProvider.swift
import Foundation

protocol ToolProvider: Sendable {
    var providerId: String { get }
    func tools() -> [ToolDescriptor]
    func execute(toolName: String, arguments: [String: Any]) async throws -> String
}
```

- [ ] **Step 6: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/ToolTypes.swift Sources/WhyUtilsApp/Services/Tools/ToolProvider.swift Tests/WhyUtilsAppTests/ToolTypesTests.swift
git commit -m "feat: add core tool types and ToolProvider protocol"
```

---

### Task 2: ToolRegistry Implementation

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/ToolRegistry.swift`
- Test: `Tests/WhyUtilsAppTests/ToolRegistryTests.swift`

- [ ] **Step 1: Write failing test for ToolRegistry**

```swift
// Tests/WhyUtilsAppTests/ToolRegistryTests.swift
import Testing
@testable import WhyUtilsApp

struct ToolRegistryTests {
    @Test
    func registryReturnsToolsFromProviders() {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        
        let tool = registry.tool(named: "mock_tool")
        #expect(tool != nil)
        #expect(tool?.name == "mock_tool")
        #expect(tool?.providerId == "mock")
    }
    
    @Test
    func registryReturnsNilForUnknownTool() {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        
        #expect(registry.tool(named: "unknown") == nil)
    }
    
    @Test
    func registryReturnsAllTools() {
        let provider1 = MockToolProvider(prefix: "a")
        let provider2 = MockToolProvider(prefix: "b")
        let registry = ToolRegistry(providers: [provider1, provider2])
        
        #expect(registry.allTools().count == 2)
    }
}

// Mock provider for testing
private struct MockToolProvider: ToolProvider {
    let providerId: String
    private let prefix: String
    
    init(prefix: String = "") {
        self.providerId = "mock"
        self.prefix = prefix
    }
    
    func tools() -> [ToolDescriptor] {
        [ToolDescriptor(
            name: "\(prefix)mock_tool",
            description: "Mock tool",
            providerId: "mock",
            dangerousLevel: .safe
        )]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        return "executed \(toolName)"
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ToolRegistryTests`
Expected: FAIL with "Cannot find 'ToolRegistry' in scope"

- [ ] **Step 3: Implement ToolRegistry**

```swift
// Sources/WhyUtilsApp/Services/Tools/ToolRegistry.swift
import Foundation

struct ToolRegistry: Sendable {
    private let providers: [ToolProvider]
    private let toolCache: [String: ToolDescriptor]
    
    init(providers: [ToolProvider]) {
        self.providers = providers
        var cache: [String: ToolDescriptor] = [:]
        for provider in providers {
            for tool in provider.tools() {
                cache[tool.name] = tool
            }
        }
        self.toolCache = cache
    }
    
    func tool(named name: String) -> ToolDescriptor? {
        toolCache[name]
    }
    
    func allTools() -> [ToolDescriptor] {
        Array(toolCache.values)
    }
    
    func toolsByDangerLevel() -> [DangerLevel: [ToolDescriptor]] {
        Dictionary(grouping: toolCache.values) { $0.dangerousLevel }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ToolRegistryTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/ToolRegistry.swift Tests/WhyUtilsAppTests/ToolRegistryTests.swift
git commit -m "feat: add ToolRegistry with provider aggregation"
```

---

### Task 3: ToolExecutor Implementation

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/ToolExecutor.swift`
- Test: `Tests/WhyUtilsAppTests/ToolExecutorTests.swift`

- [ ] **Step 1: Write failing test for ToolExecutor**

```swift
// Tests/WhyUtilsAppTests/ToolExecutorTests.swift
import Testing
@testable import WhyUtilsApp

struct ToolExecutorTests {
    @Test
    func executorRoutesToCorrectProvider() async throws {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        let executor = ToolExecutor(registry: registry, providers: [provider])
        
        let result = try await executor.execute(toolName: "mock_tool", arguments: [:])
        #expect(result.toolName == "mock_tool")
        #expect(result.success == true)
        #expect(result.output == "executed mock_tool")
    }
    
    @Test
    func executorThrowsForUnknownTool() async {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        let executor = ToolExecutor(registry: registry, providers: [provider])
        
        await #expect(throws: ToolError.unknownTool("nope")) {
            try await executor.execute(toolName: "nope", arguments: [:])
        }
    }
}

private struct MockToolProvider: ToolProvider {
    let providerId = "mock"
    
    func tools() -> [ToolDescriptor] {
        [ToolDescriptor(
            name: "mock_tool",
            description: "Mock tool",
            providerId: "mock",
            dangerousLevel: .safe
        )]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        "executed \(toolName)"
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ToolExecutorTests`
Expected: FAIL with "Cannot find 'ToolExecutor' in scope"

- [ ] **Step 3: Implement ToolExecutor**

```swift
// Sources/WhyUtilsApp/Services/Tools/ToolExecutor.swift
import Foundation

struct ToolExecutor: Sendable {
    private let registry: ToolRegistry
    private let providers: [String: ToolProvider]
    
    init(registry: ToolRegistry, providers: [ToolProvider]) {
        self.registry = registry
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.providerId, $0) })
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let tool = registry.tool(named: toolName) else {
            throw ToolError.unknownTool(toolName)
        }
        guard let provider = providers[tool.providerId] else {
            throw ToolError.providerNotFound(tool.providerId)
        }
        
        let start = Date()
        let output = try await provider.execute(toolName: toolName, arguments: arguments)
        let duration = Int(Date().timeIntervalSince(start) * 1000)
        
        return ToolResult(
            toolName: toolName,
            output: output,
            durationMs: duration
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ToolExecutorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/ToolExecutor.swift Tests/WhyUtilsAppTests/ToolExecutorTests.swift
git commit -m "feat: add ToolExecutor with provider routing"
```

---

### Task 4: BasicToolModule (Migrate Existing Tools)

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/Modules/BasicToolModule.swift`
- Modify: `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift` (update executor)
- Modify: `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift` (use new registry)
- Test: `Tests/WhyUtilsAppTests/BasicToolModuleTests.swift`

- [ ] **Step 1: Write failing test for BasicToolModule**

```swift
// Tests/WhyUtilsAppTests/BasicToolModuleTests.swift
import Testing
@testable import WhyUtilsApp

struct BasicToolModuleTests {
    @Test
    func moduleContainsClipboardTools() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "clipboard_read_latest" }))
        #expect(tools.contains(where: { $0.name == "clipboard_list_history" }))
    }
    
    @Test
    func moduleContainsJsonTools() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "json_format" }))
        #expect(tools.contains(where: { $0.name == "json_validate" }))
        #expect(tools.contains(where: { $0.name == "json_minify" }))
    }
    
    @Test
    func fullAccessIncludesShellTools() {
        let module = BasicToolModule(accessMode: .fullAccess)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "run_shell_command" }))
        #expect(tools.contains(where: { $0.name == "read_file" }))
        #expect(tools.contains(where: { $0.name == "write_file" }))
    }
    
    @Test
    func standardModeRequiresConfirmationForSideEffects() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        let openApp = tools.first(where: { $0.name == "open_app" })
        #expect(openApp?.requiresConfirmation == true)
    }
    
    @Test
    func fullAccessSkipsConfirmationForSideEffects() {
        let module = BasicToolModule(accessMode: .fullAccess)
        let tools = module.tools()
        
        let shell = tools.first(where: { $0.name == "run_shell_command" })
        #expect(shell?.requiresConfirmation == false)
    }
    
    @Test
    func executeJsonFormatTool() async throws {
        let module = BasicToolModule(accessMode: .standard)
        let result = try await module.execute(
            toolName: "json_format",
            arguments: ["input": "{\"ok\":true}"]
        )
        #expect(result.contains("\"ok\""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BasicToolModuleTests`
Expected: FAIL with "Cannot find 'BasicToolModule' in scope"

- [ ] **Step 3: Implement BasicToolModule**

```swift
// Sources/WhyUtilsApp/Services/Tools/Modules/BasicToolModule.swift
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
            .init(name: "open_file", description: "Open a file", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "open_app", description: "Open an app", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "open_system_setting", description: "Open a system setting", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "paste_clipboard_entry", description: "Paste clipboard content to another app", providerId: providerId, dangerousLevel: .moderate)
        ]
        
        if accessMode.includesFullAccessTools {
            tools.append(contentsOf: [
                .init(name: "list_directory", description: "List files and directories at a path", providerId: providerId, dangerousLevel: .safe),
                .init(name: "read_file", description: "Read a text file from disk", providerId: providerId, dangerousLevel: .safe),
                .init(name: "write_file", description: "Write text content to a file on disk", providerId: providerId, dangerousLevel: .moderate),
                .init(name: "run_shell_command", description: "Run a shell command locally", providerId: providerId, dangerousLevel: .moderate),
                .init(name: "open_url", description: "Open a URL in the default browser", providerId: providerId, dangerousLevel: .moderate)
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
    
    // Helper methods (migrated from AIToolExecutor)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BasicToolModuleTests`
Expected: PASS

- [ ] **Step 5: Update AIToolRegistry to use new ToolRegistry**

Modify `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift`:

```swift
import Foundation

struct AIToolRegistry {
    let tools: [AIToolDescriptor]
    let toolRegistry: ToolRegistry
    
    static let live = AIToolRegistry(
        accessMode: .standard
    )
    
    static func configured(accessMode: AIAgentAccessMode) -> AIToolRegistry {
        AIToolRegistry(accessMode: accessMode)
    }
    
    private init(accessMode: AIAgentAccessMode) {
        let basicModule = BasicToolModule(accessMode: accessMode)
        let registry = ToolRegistry(providers: [basicModule])
        self.toolRegistry = registry
        self.tools = registry.allTools().map { desc in
            AIToolDescriptor(
                name: desc.name,
                description: desc.description,
                requiresConfirmation: desc.requiresConfirmation
            )
        }
    }
    
    func tool(named name: String) -> AIToolDescriptor? {
        tools.first(where: { $0.name == name })
    }
}
```

- [ ] **Step 6: Update AIAgentService to use new ToolExecutor**

Modify `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`:

Replace `static let live = AIToolExecutor { ... }` with:

```swift
static func live(accessMode: AIAgentAccessMode) -> AIToolExecutor {
    let basicModule = BasicToolModule(accessMode: accessMode)
    let registry = ToolRegistry(providers: [basicModule])
    let executor = ToolExecutor(registry: registry, providers: [basicModule])
    return AIToolExecutor { step in
        try await executor.execute(toolName: step.toolName, arguments: try parseArguments(step.argumentsJSON))
    }
}
```

Update `AIAgentService.live` to pass accessMode:

```swift
static func live(configuration: AIConfiguration) -> AIAgentService {
    AIAgentService(
        registry: .configured(accessMode: configuration.accessMode),
        transport: .live,
        executor: .live(accessMode: configuration.accessMode),
        maxPlanSteps: configuration.accessMode.maxPlanSteps,
        accessMode: configuration.accessMode
    )
}
```

- [ ] **Step 7: Run all tests to verify migration**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/Modules/BasicToolModule.swift Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift Sources/WhyUtilsApp/Services/AI/AIAgentService.swift Tests/WhyUtilsAppTests/BasicToolModuleTests.swift
git commit -m "feat: migrate existing tools to BasicToolModule with new architecture"
```

---

### Task 5: FileSystemModule

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/Modules/FileSystemModule.swift`
- Test: `Tests/WhyUtilsAppTests/FileSystemModuleTests.swift`

- [ ] **Step 1: Write failing test for FileSystemModule**

```swift
// Tests/WhyUtilsAppTests/FileSystemModuleTests.swift
import Testing
@testable import WhyUtilsApp

struct FileSystemModuleTests {
    @Test
    func moduleContainsFileSystemTools() {
        let module = FileSystemModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "fs_create_directory" }))
        #expect(tools.contains(where: { $0.name == "fs_delete" }))
        #expect(tools.contains(where: { $0.name == "fs_copy" }))
        #expect(tools.contains(where: { $0.name == "fs_move" }))
        #expect(tools.contains(where: { $0.name == "fs_find" }))
        #expect(tools.contains(where: { $0.name == "fs_compress" }))
        #expect(tools.contains(where: { $0.name == "fs_decompress" }))
        #expect(tools.contains(where: { $0.name == "fs_get_info" }))
    }
    
    @Test
    func deleteToolRequiresConfirmation() {
        let module = FileSystemModule()
        let tools = module.tools()
        let delete = tools.first(where: { $0.name == "fs_delete" })
        #expect(delete?.requiresConfirmation == true)
    }
    
    @Test
    func createDirectoryTool() async throws {
        let module = FileSystemModule()
        let tempDir = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        
        let result = try await module.execute(
            toolName: "fs_create_directory",
            arguments: ["path": tempDir]
        )
        #expect(result.contains("Created"))
        #expect(FileManager.default.fileExists(atPath: tempDir))
    }
    
    @Test
    func getInfoTool() async throws {
        let module = FileSystemModule()
        let tempFile = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString).txt"
        try "test content".write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        
        let result = try await module.execute(
            toolName: "fs_get_info",
            arguments: ["path": tempFile]
        )
        #expect(result.contains(tempFile))
        #expect(result.contains("12"))
    }
    
    @Test
    func forbiddenPathIsBlocked() async {
        let module = FileSystemModule()
        await #expect(throws: ToolError.executionFailed) {
            try await module.execute(
                toolName: "fs_delete",
                arguments: ["path": "/System/Library"]
            )
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileSystemModuleTests`
Expected: FAIL

- [ ] **Step 3: Implement FileSystemModule**

```swift
// Sources/WhyUtilsApp/Services/Tools/Modules/FileSystemModule.swift
import Foundation

struct FileSystemModule: ToolProvider {
    let providerId = "filesystem"
    
    private static let forbiddenPathPrefixes = [
        "/System", "/Library", "/usr", "/bin", "/etc",
        "/sbin", "/var", "/dev", "/tmp"
    ]
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "fs_create_directory", description: "Create a directory (creates intermediate directories)", providerId: providerId, dangerousLevel: .safe),
            .init(name: "fs_delete", description: "Delete a file or directory (recursive)", providerId: providerId, dangerousLevel: .dangerous),
            .init(name: "fs_copy", description: "Copy a file or directory", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "fs_move", description: "Move or rename a file or directory", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "fs_find", description: "Recursively search for files by name pattern", providerId: providerId, dangerousLevel: .safe),
            .init(name: "fs_compress", description: "Compress files or directory to zip", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "fs_decompress", description: "Decompress a zip file", providerId: providerId, dangerousLevel: .safe),
            .init(name: "fs_get_info", description: "Get file/directory information", providerId: providerId, dangerousLevel: .safe)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "fs_create_directory":
            let path = try requiredArg(named: "path", in: arguments)
            return try createDirectory(path: path)
        case "fs_delete":
            let path = try requiredArg(named: "path", in: arguments)
            return try deletePath(path: path)
        case "fs_copy":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try copyPath(source: source, destination: destination)
        case "fs_move":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try movePath(source: source, destination: destination)
        case "fs_find":
            let path = stringArg(named: "path", in: arguments) ?? FileManager.default.homeDirectoryForCurrentUser.path
            let pattern = try requiredArg(named: "pattern", in: arguments)
            return try findFiles(path: path, pattern: pattern)
        case "fs_compress":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try compress(source: source, destination: destination)
        case "fs_decompress":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try decompress(source: source, destination: destination)
        case "fs_get_info":
            let path = try requiredArg(named: "path", in: arguments)
            return try getInfo(path: path)
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] as? String, !value.isEmpty else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return value
    }
    
    private func isPathAllowed(_ path: String) -> Bool {
        !Self.forbiddenPathPrefixes.contains { path.hasPrefix($0) }
    }
    
    private func validatePath(_ path: String) throws {
        guard isPathAllowed(path) else {
            throw ToolError.executionFailed("fs_operation", "Path not allowed: \(path)")
        }
    }
    
    private func createDirectory(path: String) throws -> String {
        try validatePath(path)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return "Created directory: \(path)"
    }
    
    private func deletePath(path: String) throws -> String {
        try validatePath(path)
        try FileManager.default.removeItem(atPath: path)
        return "Deleted: \(path)"
    }
    
    private func copyPath(source: String, destination: String) throws -> String {
        try validatePath(source)
        try validatePath(destination)
        try FileManager.default.copyItem(atPath: source, toPath: destination)
        return "Copied \(source) to \(destination)"
    }
    
    private func movePath(source: String, destination: String) throws -> String {
        try validatePath(source)
        try validatePath(destination)
        try FileManager.default.moveItem(atPath: source, toPath: destination)
        return "Moved \(source) to \(destination)"
    }
    
    private func findFiles(path: String, pattern: String) throws -> String {
        try validatePath(path)
        let enumerator = FileManager.default.enumerator(atPath: path)
        let urls = enumerator?.compactMap { item -> String? in
            let name = item as? String ?? ""
            if name.range(of: pattern, options: .regularExpression) != nil {
                return name
            }
            return nil
        } ?? []
        guard !urls.isEmpty else { return "No files found matching '\(pattern)'" }
        return urls.prefix(50).joined(separator: "\n")
    }
    
    private func compress(source: String, destination: String) throws -> String {
        try validatePath(source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destination, source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "Compressed to \(destination)" : "Failed to compress"
    }
    
    private func decompress(source: String, destination: String) throws -> String {
        try validatePath(source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", source, "-d", destination]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "Decompressed to \(destination)" : "Failed to decompress"
    }
    
    private func getInfo(path: String) throws -> String {
        try validatePath(path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = attrs[.size] as? Int64 ?? 0
        let modified = attrs[.modificationDate] as? Date ?? Date()
        let isDirectory = FileManager.default.fileExists(atPath: path, isDirectory: nil)
        return [
            "Path: \(path)",
            "Type: \(isDirectory ? "Directory" : "File")",
            "Size: \(size) bytes",
            "Modified: \(ISO8601DateFormatter().string(from: modified))"
        ].joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FileSystemModuleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/Modules/FileSystemModule.swift Tests/WhyUtilsAppTests/FileSystemModuleTests.swift
git commit -m "feat: add FileSystemModule with enhanced file operations"
```

---

### Task 6: CodeEditModule

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/Modules/CodeEditModule.swift`
- Test: `Tests/WhyUtilsAppTests/CodeEditModuleTests.swift`

- [ ] **Step 1: Write failing test for CodeEditModule**

```swift
// Tests/WhyUtilsAppTests/CodeEditModuleTests.swift
import Testing
@testable import WhyUtilsApp

struct CodeEditModuleTests {
    @Test
    func moduleContainsCodeEditTools() {
        let module = CodeEditModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "code_read_range" }))
        #expect(tools.contains(where: { $0.name == "code_edit_line" }))
        #expect(tools.contains(where: { $0.name == "code_edit_range" }))
        #expect(tools.contains(where: { $0.name == "code_search_symbols" }))
        #expect(tools.contains(where: { $0.name == "code_outline" }))
    }
    
    @Test
    func readRangeTool() async throws {
        let module = CodeEditModule()
        let tempFile = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString).txt"
        let content = "line1\nline2\nline3\nline4\nline5"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        
        let result = try await module.execute(
            toolName: "code_read_range",
            arguments: ["path": tempFile, "lineStart": "2", "lineEnd": "4"]
        )
        #expect(result.contains("line2"))
        #expect(result.contains("line3"))
        #expect(result.contains("line4"))
    }
    
    @Test
    func outlineTool() async throws {
        let module = CodeEditModule()
        let tempFile = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString).swift"
        let content = """
        struct Foo {
            func bar() {}
            var baz: Int
        }
        func helper() {}
        """
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        
        let result = try await module.execute(
            toolName: "code_outline",
            arguments: ["path": tempFile]
        )
        #expect(result.contains("Foo"))
        #expect(result.contains("bar"))
        #expect(result.contains("baz"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CodeEditModuleTests`
Expected: FAIL

- [ ] **Step 3: Implement CodeEditModule**

```swift
// Sources/WhyUtilsApp/Services/Tools/Modules/CodeEditModule.swift
import Foundation

struct CodeEditModule: ToolProvider {
    let providerId = "codeedit"
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "code_read_range", description: "Read specific line range from a file", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_edit_line", description: "Edit a single line in a file", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "code_edit_range", description: "Edit multiple lines in a file", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "code_search_symbols", description: "Search for function/class/variable definitions", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_find_references", description: "Find references to a symbol", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_list_imports", description: "List imports/dependencies in a file", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_outline", description: "Get file structure outline", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_analyze", description: "Static analysis for syntax issues", providerId: providerId, dangerousLevel: .safe)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "code_read_range":
            let path = try requiredArg(named: "path", in: arguments)
            let lineStart = intArg(named: "lineStart", in: arguments) ?? 1
            let lineEnd = intArg(named: "lineEnd", in: arguments)
            return try readRange(path: path, lineStart: lineStart, lineEnd: lineEnd)
        case "code_edit_line":
            let path = try requiredArg(named: "path", in: arguments)
            let line = try requiredIntArg(named: "line", in: arguments)
            let content = try requiredArg(named: "content", in: arguments)
            let operation = stringArg(named: "operation", in: arguments) ?? "replace"
            return try editLine(path: path, line: line, content: content, operation: operation)
        case "code_edit_range":
            let path = try requiredArg(named: "path", in: arguments)
            let lineStart = try requiredIntArg(named: "lineStart", in: arguments)
            let lineEnd = try requiredIntArg(named: "lineEnd", in: arguments)
            let content = try requiredArg(named: "content", in: arguments)
            return try editRange(path: path, lineStart: lineStart, lineEnd: lineEnd, content: content)
        case "code_search_symbols":
            let path = try requiredArg(named: "path", in: arguments)
            let symbol = try requiredArg(named: "symbol", in: arguments)
            return try searchSymbols(path: path, symbol: symbol)
        case "code_find_references":
            let path = try requiredArg(named: "path", in: arguments)
            let symbol = try requiredArg(named: "symbol", in: arguments)
            return try findReferences(path: path, symbol: symbol)
        case "code_list_imports":
            let path = try requiredArg(named: "path", in: arguments)
            return try listImports(path: path)
        case "code_outline":
            let path = try requiredArg(named: "path", in: arguments)
            return try outline(path: path)
        case "code_analyze":
            let path = try requiredArg(named: "path", in: arguments)
            return try analyze(path: path)
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    private func intArg(named name: String, in arguments: [String: Any]) -> Int? {
        if let v = arguments[name] as? Int { return v }
        if let v = arguments[name] as? String { return Int(v) }
        return nil
    }
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let v = arguments[name] as? String, !v.isEmpty else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return v
    }
    private func requiredIntArg(named name: String, in arguments: [String: Any]) throws -> Int {
        guard let v = intArg(named: name, in: arguments) else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return v
    }
    
    private func readRange(path: String, lineStart: Int, lineEnd: Int?) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let start = max(1, lineStart) - 1
        let end = min(lineEnd ?? lines.count, lines.count) - 1
        guard start < lines.count else { return "File has fewer than \(lineStart) lines" }
        let selected = lines[start...min(end, lines.count - 1)]
        return selected.enumerated().map { i, line in "\(start + i + 1): \(line)" }.joined(separator: "\n")
    }
    
    private func editLine(path: String, line: Int, content: String, operation: String) throws -> String {
        var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)
        let idx = line - 1
        guard idx >= 0 && idx < lines.count else { return "Line \(line) out of range" }
        switch operation {
        case "replace": lines[idx] = content
        case "insert_before": lines.insert(content, at: idx)
        case "insert_after": lines.insert(content, at: idx + 1)
        case "delete": lines.remove(at: idx)
        default: return "Unknown operation: \(operation)"
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return "Edited line \(line) in \(path)"
    }
    
    private func editRange(path: String, lineStart: Int, lineEnd: Int, content: String) throws -> String {
        var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)
        let start = max(0, lineStart - 1)
        let end = min(lineEnd - 1, lines.count - 1)
        guard start <= end else { return "Invalid line range" }
        lines.removeSubrange(start...end)
        lines.insert(content, at: start)
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return "Edited lines \(lineStart)-\(lineEnd) in \(path)"
    }
    
    private func searchSymbols(path: String, symbol: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let matches = lines.enumerated().compactMap { i, line in
            line.range(of: symbol, options: .regularExpression) != nil ? "\(i + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
        }
        guard !matches.isEmpty else { return "No symbols found matching '\(symbol)'" }
        return matches.joined(separator: "\n")
    }
    
    private func findReferences(path: String, symbol: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let refs = lines.enumerated().compactMap { i, line in
            line.contains(symbol) ? "\(i + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
        }
        guard !refs.isEmpty else { return "No references found for '\(symbol)'" }
        return refs.joined(separator: "\n")
    }
    
    private func listImports(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let importPatterns = ["^import\\s+", "^#include\\s+", "^from\\s+.*\\s+import\\s+"]
        let imports = lines.enumerated().compactMap { i, line in
            importPatterns.contains { line.range(of: $0, options: .regularExpression) != nil } ? "\(i + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
        }
        guard !imports.isEmpty else { return "No imports found" }
        return imports.joined(separator: "\n")
    }
    
    private func outline(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let patterns = [
            ("func", #"^\s*(?:func|def|function)\s+(\w+)"#),
            ("struct", #"^\s*(?:struct|class|type)\s+(\w+)"#),
            ("var", #"^\s*(?:var|let|const)\s+(\w+)"#)
        ]
        let outline = lines.enumerated().compactMap { i, line in
            for (_, pattern) in patterns {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let matched = String(line[match])
                    return "\(i + 1): \(matched)"
                }
            }
            return nil
        }
        guard !outline.isEmpty else { return "No symbols found" }
        return outline.joined(separator: "\n")
    }
    
    private func analyze(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var issues: [String] = []
        for (i, line) in lines.enumerated() {
            if line.hasSuffix(" ") { issues.append("\(i + 1): Trailing whitespace") }
            if line.count > 120 { issues.append("\(i + 1): Line too long (\(line.count) chars)") }
        }
        guard !issues.isEmpty else { return "No issues found" }
        return issues.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CodeEditModuleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/Modules/CodeEditModule.swift Tests/WhyUtilsAppTests/CodeEditModuleTests.swift
git commit -m "feat: add CodeEditModule with code editing and analysis tools"
```

---

### Task 7: MemoryModule

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/Modules/MemoryModule.swift`
- Test: `Tests/WhyUtilsAppTests/MemoryModuleTests.swift`

- [ ] **Step 1: Write failing test for MemoryModule**

```swift
// Tests/WhyUtilsAppTests/MemoryModuleTests.swift
import Testing
@testable import WhyUtilsApp

struct MemoryModuleTests {
    @Test
    func moduleContainsMemoryTools() {
        let module = MemoryModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "memory_store" }))
        #expect(tools.contains(where: { $0.name == "memory_retrieve" }))
        #expect(tools.contains(where: { $0.name == "memory_list" }))
        #expect(tools.contains(where: { $0.name == "memory_delete" }))
    }
    
    @Test
    func storeAndRetrieveMemory() async throws {
        let module = MemoryModule()
        try await module.execute(
            toolName: "memory_store",
            arguments: ["content": "Test memory", "category": "general"]
        )
        let result = try await module.execute(
            toolName: "memory_retrieve",
            arguments: ["query": "Test"]
        )
        #expect(result.contains("Test memory"))
    }
    
    @Test
    func listMemories() async throws {
        let module = MemoryModule()
        let result = try await module.execute(
            toolName: "memory_list",
            arguments: [:]
        )
        #expect(result.contains("Memory") || result.contains("empty"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MemoryModuleTests`
Expected: FAIL

- [ ] **Step 3: Implement MemoryModule**

```swift
// Sources/WhyUtilsApp/Services/Tools/Modules/MemoryModule.swift
import AppKit
import Foundation

enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case userPreference, projectInfo, codePattern
    case usefulSnippet, importantFile, workflow, general
}

struct MemoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var content: String
    var category: MemoryCategory
    var createdAt: Date
    var lastAccessed: Date
    var accessCount: Int
    var metadata: [String: String]
    
    init(id: UUID = UUID(), content: String, category: MemoryCategory = .general, metadata: [String: String] = [:]) {
        self.id = id
        self.content = content
        self.category = category
        self.createdAt = Date()
        self.lastAccessed = Date()
        self.accessCount = 0
        self.metadata = metadata
    }
}

struct MemoryModule: ToolProvider {
    let providerId = "memory"
    private let storagePath: String
    
    init(storagePath: String? = nil) {
        if let storagePath {
            self.storagePath = storagePath
        } else {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storagePath = supportDir.appendingPathComponent("WhyUtils/memory_store.json").path
        }
    }
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "memory_store", description: "Store a long-term memory", providerId: providerId, dangerousLevel: .safe),
            .init(name: "memory_retrieve", description: "Retrieve memories by keyword", providerId: providerId, dangerousLevel: .safe),
            .init(name: "memory_list", description: "List all memories", providerId: providerId, dangerousLevel: .safe),
            .init(name: "memory_delete", description: "Delete a specific memory", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "memory_clear", description: "Clear all memories", providerId: providerId, dangerousLevel: .dangerous)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "memory_store":
            let content = try requiredArg(named: "content", in: arguments)
            let categoryRaw = stringArg(named: "category", in: arguments) ?? "general"
            let category = MemoryCategory(rawValue: categoryRaw) ?? .general
            return try storeMemory(content: content, category: category)
        case "memory_retrieve":
            let query = try requiredArg(named: "query", in: arguments)
            let category = stringArg(named: "category", in: arguments)
            return try retrieveMemories(query: query, category: category)
        case "memory_list":
            return try listMemories()
        case "memory_delete":
            let id = try requiredArg(named: "id", in: arguments)
            return try deleteMemory(id: id)
        case "memory_clear":
            return try clearMemories()
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let v = arguments[name] as? String, !v.isEmpty else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return v
    }
    
    private func loadMemories() throws -> [MemoryEntry] {
        let url = URL(fileURLWithPath: storagePath)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: storagePath) {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([MemoryEntry].self, from: data)
    }
    
    private func saveMemories(_ memories: [MemoryEntry]) throws {
        let data = try JSONEncoder().encode(memories)
        try data.write(to: URL(fileURLWithPath: storagePath))
    }
    
    private func storeMemory(content: String, category: MemoryCategory) throws -> String {
        var memories = try loadMemories()
        let entry = MemoryEntry(content: content, category: category)
        memories.append(entry)
        if memories.count > 500 {
            memories = Array(memories.suffix(500))
        }
        try saveMemories(memories)
        return "Memory stored: \(entry.id)"
    }
    
    private func retrieveMemories(query: String, category: String?) throws -> String {
        var memories = try loadMemories()
        memories = memories.filter { entry in
            entry.content.localizedCaseInsensitiveContains(query)
        }
        if let cat = category {
            memories = memories.filter { $0.category.rawValue == cat }
        }
        memories.sort { $0.lastAccessed > $1.lastAccessed }
        memories = Array(memories.prefix(10))
        for i in memories.indices {
            memories[i].accessCount += 1
            memories[i].lastAccessed = Date()
        }
        try saveMemories(memories)
        guard !memories.isEmpty else { return "No memories found for '\(query)'" }
        return memories.map { "[\($0.id)] \($0.content) (\($0.category.rawValue))" }.joined(separator: "\n")
    }
    
    private func listMemories() throws -> String {
        let memories = try loadMemories()
        guard !memories.isEmpty else { return "No memories stored" }
        return memories.map { "[\($0.id)] \($0.content.prefix(50))... (\($0.category.rawValue))" }.joined(separator: "\n")
    }
    
    private func deleteMemory(id: String) throws -> String {
        guard let uuid = UUID(uuidString: id) else {
            return "Invalid memory ID"
        }
        var memories = try loadMemories()
        let count = memories.count
        memories.removeAll { $0.id == uuid }
        guard memories.count < count else { return "Memory not found" }
        try saveMemories(memories)
        return "Memory deleted"
    }
    
    private func clearMemories() throws -> String {
        try saveMemories([])
        return "All memories cleared"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MemoryModuleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/Modules/MemoryModule.swift Tests/WhyUtilsAppTests/MemoryModuleTests.swift
git commit -m "feat: add MemoryModule with long-term memory storage"
```

---

### Task 8: SystemControlModule

**Files:**
- Create: `Sources/WhyUtilsApp/Services/Tools/Modules/SystemControlModule.swift`
- Test: `Tests/WhyUtilsAppTests/SystemControlModuleTests.swift`

- [ ] **Step 1: Write failing test for SystemControlModule**

```swift
// Tests/WhyUtilsAppTests/SystemControlModuleTests.swift
import Testing
@testable import WhyUtilsApp

struct SystemControlModuleTests {
    @Test
    func moduleContainsSystemControlTools() {
        let module = SystemControlModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "process_list" }))
        #expect(tools.contains(where: { $0.name == "process_kill" }))
        #expect(tools.contains(where: { $0.name == "network_request" }))
        #expect(tools.contains(where: { $0.name == "screenshot" }))
        #expect(tools.contains(where: { $0.name == "window_list" }))
    }
    
    @Test
    func processKillRequiresConfirmation() {
        let module = SystemControlModule()
        let tools = module.tools()
        let kill = tools.first(where: { $0.name == "process_kill" })
        #expect(kill?.requiresConfirmation == true)
    }
    
    @Test
    func processListTool() async throws {
        let module = SystemControlModule()
        let result = try await module.execute(
            toolName: "process_list",
            arguments: ["limit": "5"]
        )
        #expect(result.contains("PID") || result.contains("Process"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SystemControlModuleTests`
Expected: FAIL

- [ ] **Step 3: Implement SystemControlModule**

```swift
// Sources/WhyUtilsApp/Services/Tools/Modules/SystemControlModule.swift
import AppKit
import Foundation

struct SystemControlModule: ToolProvider {
    let providerId = "systemcontrol"
    
    private static let protectedProcesses = ["kernel_task", "launchd", "WindowServer", "loginwindow"]
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "process_list", description: "List running processes", providerId: providerId, dangerousLevel: .safe),
            .init(name: "process_info", description: "Get process details", providerId: providerId, dangerousLevel: .safe),
            .init(name: "process_kill", description: "Terminate a process", providerId: providerId, dangerousLevel: .dangerous),
            .init(name: "network_request", description: "Send HTTP request", providerId: providerId, dangerousLevel: .safe),
            .init(name: "screenshot", description: "Take a screenshot", providerId: providerId, dangerousLevel: .safe),
            .init(name: "window_list", description: "List open windows", providerId: providerId, dangerousLevel: .safe)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "process_list":
            let sortBy = stringArg(named: "sortBy", in: arguments) ?? "name"
            let limit = intArg(named: "limit", in: arguments) ?? 20
            return try await listProcesses(sortBy: sortBy, limit: limit)
        case "process_info":
            let pid = try requiredIntArg(named: "pid", in: arguments)
            return try getProcessInfo(pid: pid)
        case "process_kill":
            let pid = try requiredIntArg(named: "pid", in: arguments)
            return try killProcess(pid: pid)
        case "network_request":
            let url = try requiredArg(named: "url", in: arguments)
            let method = stringArg(named: "method", in: arguments) ?? "GET"
            let body = stringArg(named: "body", in: arguments)
            return try await networkRequest(url: url, method: method, body: body)
        case "screenshot":
            return try await takeScreenshot()
        case "window_list":
            return try listWindows()
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? { arguments[name] as? String }
    private func intArg(named name: String, in arguments: [String: Any]) -> Int? {
        if let v = arguments[name] as? Int { return v }
        if let v = arguments[name] as? String { return Int(v) }
        return nil
    }
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let v = arguments[name] as? String, !v.isEmpty else { throw ToolError.invalidArgument("Missing: \(name)") }
        return v
    }
    private func requiredIntArg(named name: String, in arguments: [String: Any]) throws -> Int {
        guard let v = intArg(named: name, in: arguments) else { throw ToolError.invalidArgument("Missing: \(name)") }
        return v
    }
    
    private func listProcesses(sortBy: String, limit: Int) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,pcpu,pmem,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: .newlines).dropFirst()
        let sorted: [String]
        switch sortBy {
        case "cpu": sorted = lines.sorted { $0.split(separator: " ")[1] > $1.split(separator: " ")[1] }
        case "memory": sorted = lines.sorted { $0.split(separator: " ")[2] > $1.split(separator: " ")[2] }
        default: sorted = Array(lines)
        }
        let result = sorted.prefix(limit).joined(separator: "\n")
        return result.isEmpty ? "No processes found" : result
    }
    
    private func getProcessInfo(pid: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "pid,pcpu,pmem,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .newlines).isEmpty ? "Process \(pid) not found" : output.trimmingCharacters(in: .newlines)
    }
    
    private func killProcess(pid: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let name = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !Self.protectedProcesses.contains(name) else {
            return "Cannot kill protected process: \(name)"
        }
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/bin/kill")
        kill.arguments = ["-9", String(pid)]
        try kill.run()
        kill.waitUntilExit()
        return kill.terminationStatus == 0 ? "Killed process \(pid) (\(name))" : "Failed to kill process \(pid)"
    }
    
    private func networkRequest(url: String, method: String, body: String?) async throws -> String {
        guard let url = URL(string: url) else { return "Invalid URL" }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body { request.httpBody = body.data(using: .utf8) }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        return "Status: \(status)\n\(body.prefix(2000))"
    }
    
    private func takeScreenshot() async throws -> String {
        let path = NSTemporaryDirectory() + "screenshot_\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "Screenshot saved to \(path)" : "Failed to take screenshot"
    }
    
    private func listWindows() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
        tell application "System Events"
            set winList to windows of (every process whose background only is false)
            set output to ""
            repeat with w in winList
                set output to output & (name of w) & " - " & (title of w) & "\n"
            end repeat
            return output
        end tell
        """]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .newlines).isEmpty ? "No windows found" : output.trimmingCharacters(in: .newlines)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SystemControlModuleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/Tools/Modules/SystemControlModule.swift Tests/WhyUtilsAppTests/SystemControlModuleTests.swift
git commit -m "feat: add SystemControlModule with process, network, and window tools"
```

---

### Task 9: Integration and Final Tests

**Files:**
- Modify: `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- Modify: `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift` (update buildContext)
- Test: `Tests/WhyUtilsAppTests/IntegrationTests.swift`

- [ ] **Step 1: Update AIAgentService to use all modules**

Modify `AIAgentService.live`:

```swift
static func live(configuration: AIConfiguration) -> AIAgentService {
    let accessMode = configuration.accessMode
    let basicModule = BasicToolModule(accessMode: accessMode)
    let fsModule = FileSystemModule()
    let codeModule = CodeEditModule()
    let memoryModule = MemoryModule()
    let sysModule = SystemControlModule()
    
    let allModules: [ToolProvider] = [basicModule, fsModule, codeModule, memoryModule, sysModule]
    let registry = ToolRegistry(providers: allModules)
    let executor = ToolExecutor(registry: registry, providers: allModules)
    
    return AIAgentService(
        registry: .configured(accessMode: accessMode),
        transport: .live,
        executor: AIToolExecutor { step in
            try await executor.execute(toolName: step.toolName, arguments: try parseArguments(step.argumentsJSON))
        },
        maxPlanSteps: accessMode.maxPlanSteps,
        accessMode: accessMode
    )
}
```

- [ ] **Step 2: Update AIToolRegistry to include all modules**

Modify `AIToolRegistry`:

```swift
private init(accessMode: AIAgentAccessMode) {
    let basicModule = BasicToolModule(accessMode: accessMode)
    let fsModule = FileSystemModule()
    let codeModule = CodeEditModule()
    let memoryModule = MemoryModule()
    let sysModule = SystemControlModule()
    
    let allModules: [ToolProvider] = [basicModule, fsModule, codeModule, memoryModule, sysModule]
    let registry = ToolRegistry(providers: allModules)
    self.toolRegistry = registry
    self.tools = registry.allTools().map { desc in
        AIToolDescriptor(name: desc.name, description: desc.description, requiresConfirmation: desc.requiresConfirmation)
    }
}
```

- [ ] **Step 3: Run all tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Build release**

Run: `bash scripts/build_app.sh`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/AI/AIAgentService.swift Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift
git commit -m "feat: integrate all tool modules into AIAgentService"
```

---

## Self-Review

1. **Spec coverage:** All 13 features covered:
   - File system: fs_create_directory, fs_delete, fs_copy, fs_move, fs_find, fs_compress, fs_decompress, fs_get_info ✓
   - Code editing: code_read_range, code_edit_line, code_edit_range, code_search_symbols, code_find_references, code_list_imports, code_outline, code_analyze ✓
   - Memory: memory_store, memory_retrieve, memory_list, memory_delete, memory_clear ✓
   - System control: process_list, process_info, process_kill, network_request, screenshot, window_list ✓
   - Basic migration: All existing tools migrated ✓

2. **Placeholder scan:** No placeholders found. All steps contain actual code.

3. **Type consistency:** ToolDescriptor, ToolProvider, ToolRegistry, ToolExecutor used consistently across all tasks.
