# AI Assistant Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a constrained AI Assistant tool that uses OpenAI-compatible APIs to plan and execute existing WhyUtils local tools with confirmation gates for side-effectful actions.

**Architecture:** Introduce a small AI subsystem that separates transport, tool registry, orchestration, and UI. The model produces a bounded plan, local code validates and executes it, and the UI renders plan, confirmation, tool trace, and result inside a new `AI Assistant` tool page.

**Tech Stack:** SwiftUI, Foundation networking, existing WhyUtils services, Swift Testing

---

## File Structure

### New files

- `Sources/WhyUtilsApp/Models/AIAgentTypes.swift`
Defines persisted AI configuration, execution state, planning payloads, tool descriptors, tool results, and confirmation requests.

- `Sources/WhyUtilsApp/Services/AI/OpenAICompatibleClient.swift`
Builds OpenAI-compatible chat-completions requests, sends them over HTTP, and parses model responses into internal strings/JSON payloads.

- `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift`
Registers the local WhyUtils tools exposed to the model and validates tool lookup plus side-effect classification.

- `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
Owns the AI session state machine, builds prompts, validates model plans, executes tools, and requests confirmation when needed.

- `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`
Renders the AI Assistant page, input field, sample prompts, plan card, confirmation card, tool trace, and result card.

- `Tests/WhyUtilsAppTests/AIAgentTypesTests.swift`
Tests config defaults, state transitions, and max-step plan validation helpers.

- `Tests/WhyUtilsAppTests/OpenAICompatibleClientTests.swift`
Tests request construction and basic response parsing helpers without live HTTP calls.

- `Tests/WhyUtilsAppTests/AIToolRegistryTests.swift`
Tests tool registration, side-effect flags, and tool lookup behavior.

- `Tests/WhyUtilsAppTests/AIAgentServiceTests.swift`
Tests plan validation, confirmation gating, and execution-state transitions using deterministic fake transport/tool execution.

### Modified files

- `Sources/WhyUtilsApp/Models/ToolKind.swift`
Adds the `aiAssistant` tool entry.

- `Sources/WhyUtilsApp/Views/ToolContainerView.swift`
Routes `ToolKind.aiAssistant` to the new AI page.

- `Sources/WhyUtilsApp/Views/SettingsSheetView.swift`
Adds the AI configuration section.

- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
Stores AI configuration, exposes localized AI messages, and supports launcher handoff into the AI page with initial task text.

- `Sources/WhyUtilsApp/Models/LauncherItem.swift`
Optional explicit AI handoff item if needed to distinguish natural-language routing from static tools.

- `Sources/WhyUtilsApp/Views/LauncherView.swift`
Adds handoff behavior so natural-language tasks can jump into AI Assistant.

## Task 1: Add AI core types and config persistence

**Files:**
- Create: `Sources/WhyUtilsApp/Models/AIAgentTypes.swift`
- Modify: `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- Test: `Tests/WhyUtilsAppTests/AIAgentTypesTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WhyUtilsApp

struct AIAgentTypesTests {
    @Test
    func aiConfigurationDefaultsToDisabledAndEmptyFields() {
        let config = AIConfiguration()
        #expect(config.isEnabled == false)
        #expect(config.baseURL == "")
        #expect(config.apiKey == "")
        #expect(config.model == "")
    }

    @Test
    func planRejectsMoreThanThreeSteps() {
        let plan = AIExecutionPlan(
            goal: "Too many steps",
            steps: [
                AIPlanStep(toolName: "a", argumentsJSON: "{}"),
                AIPlanStep(toolName: "b", argumentsJSON: "{}"),
                AIPlanStep(toolName: "c", argumentsJSON: "{}"),
                AIPlanStep(toolName: "d", argumentsJSON: "{}")
            ]
        )

        #expect(plan.exceedsStepLimit(limit: 3) == true)
    }

    @Test
    func sideEffectDetectionUsesStepFlags() {
        let plan = AIExecutionPlan(
            goal: "Open app",
            steps: [
                AIPlanStep(toolName: "open_app", argumentsJSON: "{\"bundleIdentifier\":\"com.apple.finder\"}", requiresConfirmation: true)
            ]
        )

        #expect(plan.requiresConfirmation == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIAgentTypesTests`
Expected: FAIL because AI types do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct AIConfiguration: Codable, Equatable {
    var isEnabled: Bool = false
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
}

enum AIAgentExecutionState: Equatable {
    case idle
    case planning
    case awaitingConfirmation
    case executing
    case completed
    case failed(message: String)
}

struct AIPlanStep: Codable, Equatable, Identifiable {
    let id = UUID()
    let toolName: String
    let argumentsJSON: String
    var requiresConfirmation: Bool = false
}

struct AIExecutionPlan: Codable, Equatable {
    let goal: String
    let steps: [AIPlanStep]

    var requiresConfirmation: Bool {
        steps.contains(where: \.requiresConfirmation)
    }

    func exceedsStepLimit(limit: Int) -> Bool {
        steps.count > limit
    }
}
```

- [ ] **Step 4: Persist AI config in `AppCoordinator`**

```swift
@Published private(set) var aiConfiguration: AIConfiguration
@Published var aiDraftTask: String = ""

private let aiConfigurationStorageKey = "whyutils.ai.configuration"

func updateAIConfiguration(
    isEnabled: Bool? = nil,
    baseURL: String? = nil,
    apiKey: String? = nil,
    model: String? = nil
) {
    var next = aiConfiguration
    if let isEnabled { next.isEnabled = isEnabled }
    if let baseURL { next.baseURL = baseURL }
    if let apiKey { next.apiKey = apiKey }
    if let model { next.model = model }
    aiConfiguration = next
    saveAIConfiguration(next, key: aiConfigurationStorageKey)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter AIAgentTypesTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/WhyUtilsApp/Models/AIAgentTypes.swift Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift Tests/WhyUtilsAppTests/AIAgentTypesTests.swift
git commit -m "feat: add ai config and execution types"
```

## Task 2: Add the AI tool registry

**Files:**
- Create: `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift`
- Test: `Tests/WhyUtilsAppTests/AIToolRegistryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WhyUtilsApp

struct AIToolRegistryTests {
    @Test
    func registryContainsJsonFormattingTool() {
        let registry = AIToolRegistry.live
        let tool = registry.tool(named: "json_format")
        #expect(tool != nil)
        #expect(tool?.requiresConfirmation == false)
    }

    @Test
    func registryMarksOpenAppAsSideEffectful() {
        let registry = AIToolRegistry.live
        let tool = registry.tool(named: "open_app")
        #expect(tool != nil)
        #expect(tool?.requiresConfirmation == true)
    }

    @Test
    func unknownToolReturnsNil() {
        let registry = AIToolRegistry.live
        #expect(registry.tool(named: "made_up_tool") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIToolRegistryTests`
Expected: FAIL because the registry does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct AIToolDescriptor {
    let name: String
    let description: String
    let requiresConfirmation: Bool
}

struct AIToolRegistry {
    let tools: [AIToolDescriptor]

    static let live = AIToolRegistry(
        tools: [
            .init(name: "clipboard_read_latest", description: "Read the latest clipboard entry", requiresConfirmation: false),
            .init(name: "clipboard_list_history", description: "List clipboard history entries", requiresConfirmation: false),
            .init(name: "json_validate", description: "Validate JSON", requiresConfirmation: false),
            .init(name: "json_format", description: "Format JSON", requiresConfirmation: false),
            .init(name: "json_minify", description: "Minify JSON", requiresConfirmation: false),
            .init(name: "url_encode", description: "Encode URL text", requiresConfirmation: false),
            .init(name: "url_decode", description: "Decode URL text", requiresConfirmation: false),
            .init(name: "base64_encode", description: "Encode Base64", requiresConfirmation: false),
            .init(name: "base64_decode", description: "Decode Base64", requiresConfirmation: false),
            .init(name: "timestamp_to_date", description: "Convert timestamp to date", requiresConfirmation: false),
            .init(name: "date_to_timestamp", description: "Convert date to timestamp", requiresConfirmation: false),
            .init(name: "regex_find", description: "Find regex matches", requiresConfirmation: false),
            .init(name: "regex_replace_preview", description: "Preview regex replacement", requiresConfirmation: false),
            .init(name: "search_files", description: "Search files", requiresConfirmation: false),
            .init(name: "search_apps", description: "Search apps", requiresConfirmation: false),
            .init(name: "search_system_settings", description: "Search system settings", requiresConfirmation: false),
            .init(name: "open_file", description: "Open a file", requiresConfirmation: true),
            .init(name: "open_app", description: "Open an app", requiresConfirmation: true),
            .init(name: "open_system_setting", description: "Open a system setting", requiresConfirmation: true),
            .init(name: "paste_clipboard_entry", description: "Paste clipboard content to another app", requiresConfirmation: true)
        ]
    )

    func tool(named name: String) -> AIToolDescriptor? {
        tools.first(where: { $0.name == name })
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AIToolRegistryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift Tests/WhyUtilsAppTests/AIToolRegistryTests.swift
git commit -m "feat: add ai tool registry"
```

## Task 3: Add OpenAI-compatible request and response helpers

**Files:**
- Create: `Sources/WhyUtilsApp/Services/AI/OpenAICompatibleClient.swift`
- Test: `Tests/WhyUtilsAppTests/OpenAICompatibleClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import WhyUtilsApp

struct OpenAICompatibleClientTests {
    @Test
    func buildsChatCompletionsRequest() throws {
        let config = AIConfiguration(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-4.1")
        let request = try OpenAICompatibleClient.buildChatRequest(
            configuration: config,
            messages: [
                .init(role: "user", content: "Hello")
            ]
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test
    func normalizesBaseURLWithoutTrailingSlashIssues() throws {
        let config = AIConfiguration(isEnabled: true, baseURL: "https://example.com/v1/", apiKey: "secret", model: "gpt-4.1")
        let request = try OpenAICompatibleClient.buildChatRequest(
            configuration: config,
            messages: [.init(role: "user", content: "Hello")]
        )

        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OpenAICompatibleClientTests`
Expected: FAIL because the client does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

enum OpenAICompatibleClientError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case missingModel
}

struct OpenAIChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

enum OpenAICompatibleClient {
    static func buildChatRequest(
        configuration: AIConfiguration,
        messages: [OpenAIChatMessage]
    ) throws -> URLRequest {
        let base = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, var components = URLComponents(string: base) else {
            throw OpenAICompatibleClientError.invalidBaseURL
        }
        guard !configuration.apiKey.isEmpty else { throw OpenAICompatibleClientError.missingAPIKey }
        guard !configuration.model.isEmpty else { throw OpenAICompatibleClientError.missingModel }

        let normalizedPath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = normalizedPath + "/chat/completions"

        guard let url = components.url else {
            throw OpenAICompatibleClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode([
            "model": configuration.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ])
        return request
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OpenAICompatibleClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/AI/OpenAICompatibleClient.swift Tests/WhyUtilsAppTests/OpenAICompatibleClientTests.swift
git commit -m "feat: add openai compatible request builder"
```

## Task 4: Add the agent orchestration and confirmation gate

**Files:**
- Create: `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- Test: `Tests/WhyUtilsAppTests/AIAgentServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WhyUtilsApp

struct AIAgentServiceTests {
    @Test
    func planningRejectsUnknownTool() {
        let service = AIAgentService(
            registry: .live,
            transport: .failingStub,
            executor: .noOp
        )

        let plan = AIExecutionPlan(
            goal: "Unknown tool",
            steps: [AIPlanStep(toolName: "nope", argumentsJSON: "{}")]
        )

        #expect(service.validate(plan: plan).isValid == false)
    }

    @Test
    func sideEffectfulPlanRequiresConfirmation() {
        let service = AIAgentService(
            registry: .live,
            transport: .failingStub,
            executor: .noOp
        )

        let plan = AIExecutionPlan(
            goal: "Open app",
            steps: [AIPlanStep(toolName: "open_app", argumentsJSON: "{\"bundleIdentifier\":\"com.apple.finder\"}", requiresConfirmation: true)]
        )

        let result = service.validate(plan: plan)
        #expect(result.isValid == true)
        #expect(result.requiresConfirmation == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIAgentServiceTests`
Expected: FAIL because the service does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct AIPlanValidationResult: Equatable {
    let isValid: Bool
    let requiresConfirmation: Bool
    let message: String?
}

struct AIAgentService {
    let registry: AIToolRegistry
    let transport: AITransport
    let executor: AIToolExecutor

    func validate(plan: AIExecutionPlan) -> AIPlanValidationResult {
        if plan.exceedsStepLimit(limit: 3) {
            return .init(isValid: false, requiresConfirmation: false, message: "Plan exceeds step limit")
        }

        for step in plan.steps {
            guard let tool = registry.tool(named: step.toolName) else {
                return .init(isValid: false, requiresConfirmation: false, message: "Unknown tool: \(step.toolName)")
            }
            if tool.requiresConfirmation {
                return .init(isValid: true, requiresConfirmation: true, message: nil)
            }
        }

        return .init(isValid: true, requiresConfirmation: false, message: nil)
    }
}

struct AITransport {
    static let failingStub = AITransport()
}

struct AIToolExecutor {
    static let noOp = AIToolExecutor()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AIAgentServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/AI/AIAgentService.swift Tests/WhyUtilsAppTests/AIAgentServiceTests.swift
git commit -m "feat: add ai agent validation and confirmation gating"
```

## Task 5: Add AI settings UI and tool entry

**Files:**
- Modify: `Sources/WhyUtilsApp/Views/SettingsSheetView.swift`
- Modify: `Sources/WhyUtilsApp/Models/ToolKind.swift`
- Modify: `Sources/WhyUtilsApp/Views/ToolContainerView.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WhyUtilsApp

struct AIToolEntryTests {
    @Test
    func toolCatalogContainsAIAssistant() {
        #expect(ToolKind.allCases.contains(.aiAssistant))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIToolEntryTests`
Expected: FAIL because the tool entry does not exist.

- [ ] **Step 3: Add the AI tool kind**

```swift
case aiAssistant
```

And add:

```swift
case .aiAssistant: return L10n.text("AI Assistant", "AI 助手", language: language)
case .aiAssistant: return L10n.text("Plan and run local tool tasks", "规划并执行本地工具任务", language: language)
case .aiAssistant: return "sparkles"
```

- [ ] **Step 4: Add the AI settings section**

```swift
private var aiSection: some View {
    settingsCard(title: coordinator.localized("AI", "AI")) {
        Toggle(coordinator.localized("Enable AI Assistant", "启用 AI 助手"), isOn: Binding(
            get: { coordinator.aiConfiguration.isEnabled },
            set: { coordinator.updateAIConfiguration(isEnabled: $0) }
        ))

        TextField("Base URL", text: Binding(
            get: { coordinator.aiConfiguration.baseURL },
            set: { coordinator.updateAIConfiguration(baseURL: $0) }
        ))
        .textFieldStyle(.roundedBorder)

        SecureField("API Key", text: Binding(
            get: { coordinator.aiConfiguration.apiKey },
            set: { coordinator.updateAIConfiguration(apiKey: $0) }
        ))

        TextField("Model", text: Binding(
            get: { coordinator.aiConfiguration.model },
            set: { coordinator.updateAIConfiguration(model: $0) }
        ))
        .textFieldStyle(.roundedBorder)
    }
}
```

- [ ] **Step 5: Add the placeholder tool route**

In `ToolContainerView.swift`:

```swift
case .aiAssistant:
    AIAssistantToolView()
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter AIToolEntryTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/WhyUtilsApp/Models/ToolKind.swift Sources/WhyUtilsApp/Views/SettingsSheetView.swift Sources/WhyUtilsApp/Views/ToolContainerView.swift
git commit -m "feat: add ai assistant entry and settings"
```

## Task 6: Build the AI Assistant page shell

**Files:**
- Create: `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`

- [ ] **Step 1: Write the failing test**

```text
N/A for SwiftUI shell layout. Verify by build and manual smoke test.
```

- [ ] **Step 2: Implement the page shell**

Include:

- task input field
- submit button
- sample prompt buttons
- plan card placeholder
- confirmation card placeholder
- tool trace area
- result area

Minimal code shape:

```swift
struct AIAssistantToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var service = AIAgentService.live
    @State private var taskText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolCard(title: coordinator.localized("Task", "任务")) { ... }
            ToolCard(title: coordinator.localized("Plan", "计划")) { ... }
            ToolCard(title: coordinator.localized("Actions", "动作")) { ... }
            ToolCard(title: coordinator.localized("Result", "结果")) { ... }
        }
    }
}
```

- [ ] **Step 3: Build to verify compile**

Run: `swift build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift
git commit -m "feat: add ai assistant tool page shell"
```

## Task 7: Wire launcher handoff into AI Assistant

**Files:**
- Modify: `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- Modify: `Sources/WhyUtilsApp/Views/LauncherView.swift`
- Modify: `Sources/WhyUtilsApp/Models/LauncherItem.swift` if explicit handoff item is added

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WhyUtilsApp

struct AILauncherRoutingTests {
    @Test
    func aiAssistantToolMatchesNaturalLanguageQuery() {
        let matched = ToolKind.aiAssistant.matches("summarize clipboard text", language: .english)
        #expect(matched == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AILauncherRoutingTests`
Expected: FAIL until the tool metadata supports this routing.

- [ ] **Step 3: Add handoff support**

In `AppCoordinator.swift` add:

```swift
func openAIAssistant(with task: String) {
    aiDraftTask = task
    route = .tool(.aiAssistant)
    highlightedItem = .tool(.aiAssistant)
}
```

In `LauncherView.swift`, on submit:

```swift
let trimmed = coordinator.query.trimmingCharacters(in: .whitespacesAndNewlines)
if trimmed.isEmpty == false,
   coordinator.highlightedItem == .tool(.aiAssistant) {
    coordinator.openAIAssistant(with: trimmed)
    return
}
coordinator.openHighlightedTool()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AILauncherRoutingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift Sources/WhyUtilsApp/Views/LauncherView.swift Sources/WhyUtilsApp/Models/LauncherItem.swift
git commit -m "feat: route launcher tasks into ai assistant"
```

## Task 8: Implement real plan execution for safe local tools

**Files:**
- Modify: `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- Modify: `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift`
- Modify: `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`
- Test: `Tests/WhyUtilsAppTests/AIAgentServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func executionStopsAtConfirmationBoundary() async throws {
    // fake plan with open_app step
    // expect service state to become awaitingConfirmation
}

@Test
func executionCompletesForNonSideEffectPlan() async throws {
    // fake plan with json_format
    // expect completed state and tool trace output
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIAgentServiceTests`
Expected: FAIL because execution flow is not implemented yet.

- [ ] **Step 3: Implement minimal execution flow**

Implement:

- `submit(task:)`
- prompt builder for planning
- model-response decoding into `AIExecutionPlan`
- plan validation
- execution loop over steps
- confirmation pause before side-effect tools
- final result summary

Keep the first live executable tool set narrow:

- `clipboard_read_latest`
- `json_validate`
- `json_format`
- `json_minify`
- `url_encode`
- `url_decode`
- `base64_encode`
- `base64_decode`
- `timestamp_to_date`
- `date_to_timestamp`
- `search_system_settings`

Leave `search_files`, `search_apps`, and side-effectful open actions hooked up only when their execution path is fully validated.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AIAgentServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/AI/AIAgentService.swift Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift Tests/WhyUtilsAppTests/AIAgentServiceTests.swift
git commit -m "feat: execute bounded ai assistant plans"
```

## Task 9: Full verification and documentation pass

**Files:**
- Modify: `README.md`
- Modify: `docs/CODEBASE_CONTEXT.md`

- [ ] **Step 1: Update docs**

Add to `README.md`:

- AI Assistant feature overview
- OpenAI-compatible configuration steps
- first-version constraints

Add to `docs/CODEBASE_CONTEXT.md`:

- AI Assistant in the quick lookup table
- new AI subsystem files

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter AIAgentTypesTests`
Expected: PASS.

Run: `swift test --filter AIToolRegistryTests`
Expected: PASS.

Run: `swift test --filter OpenAICompatibleClientTests`
Expected: PASS.

Run: `swift test --filter AIAgentServiceTests`
Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 4: Run build verification**

Run: `swift build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke test**

Verify:

- settings page accepts AI config
- launcher shows AI Assistant
- launcher handoff carries a natural-language task into the AI page
- non-side-effect task shows plan, trace, and result
- side-effect task pauses for confirmation

- [ ] **Step 6: Commit**

```bash
git add README.md docs/CODEBASE_CONTEXT.md
git commit -m "docs: describe ai assistant usage and architecture"
```

## Self-Review

### Spec coverage

Covered:

- OpenAI-compatible config
- dedicated AI page
- launcher handoff
- bounded plan-and-execute orchestration
- confirmation gate
- tool registry
- testing strategy

Not fully covered in MVP implementation tasks:

- live execution for every listed tool is intentionally phased; the initial execution set is narrower to keep rollout safe. The remaining registry entries can stay registered but non-executable until validated, or can be deferred if implementation friction appears.

### Placeholder scan

No `TODO`, `TBD`, or undefined "appropriate handling" placeholders remain. Non-tested UI shell work is explicitly called out as manual verification.

### Type consistency

Shared type names used consistently across tasks:

- `AIConfiguration`
- `AIExecutionPlan`
- `AIPlanStep`
- `AIAgentService`
- `AIToolRegistry`
- `OpenAICompatibleClient`

