# WhyUtils AI Assistant Agent Design

Date: 2026-04-05
Status: Draft for review

## Goal

Add an AI capability to WhyUtils that is useful because it can invoke existing local tools, not because it can chat.

The first version should:

- support OpenAI-compatible APIs
- let users configure `baseURL`, `apiKey`, and `model`
- expose a new `AI Assistant` tool page
- allow Launcher to route natural-language tasks into that page
- execute only a constrained set of existing WhyUtils capabilities
- require user confirmation before any side-effectful action

The first version should not:

- browse the web
- automate browsers
- run shell commands
- write files
- maintain long-term memory
- become a general-purpose autonomous agent

## Product Definition

WhyUtils AI is a local efficiency agent with a narrow tool boundary.

It is not a free-form chatbot. The product value comes from:

- understanding natural-language intent
- selecting the right built-in WhyUtils tool
- optionally composing up to 3 tool calls
- presenting a short execution plan
- executing with confirmation gates for unsafe actions

User promise:

"Describe a small task in natural language, and WhyUtils will use its built-in tools to complete it safely."

## Primary Use Cases

The MVP should focus on these task classes:

1. Clipboard understanding and transformation
- summarize clipboard text
- rewrite or translate clipboard text
- detect JSON in clipboard content and format it

2. Existing utility orchestration
- validate or format JSON
- convert timestamps or dates
- encode or decode URL/Base64
- run regex matching or replacement preview

3. Lightweight launcher actions
- search apps
- search system settings
- search files
- optionally open the selected result after confirmation

Representative examples:

- "Check whether the clipboard content is valid JSON and format it"
- "Summarize this clipboard text into three bullets"
- "Find the config file I edited today"
- "Open Bluetooth settings"
- "Decode this URL query string"

## Entrypoints

### AI Assistant Tool Page

This is the primary interface.

It should behave like a task execution console rather than a messaging app:

- task input at the top
- execution plan card
- tool-call trace card
- confirmation card when needed
- result card

### Launcher Entry

Launcher should expose a new `AI Assistant` tool in the normal tool list.

Additionally, when the user enters a natural-language task that does not clearly map to an existing direct launcher item, the app may route the text into the AI Assistant page as the initial prompt.

The Launcher should remain a launcher. The AI page owns the actual task session.

## Scope and Constraints

### Hard MVP Constraints

- max 3 tool steps per run
- only built-in WhyUtils tools are callable
- no dynamic tool registration
- no recursive replanning after execution starts
- no background autonomous loops
- one task at a time in the AI Assistant page

### Side-Effect Policy

These actions require explicit confirmation:

- open file
- open app
- open system setting
- paste clipboard entry into another app

These actions do not require confirmation:

- local text transformation
- JSON validation/formatting
- regex preview
- timestamp conversion
- listing clipboard history
- searching files/apps/settings without opening

## OpenAI-Compatible API Support

Users configure:

- `baseURL`
- `apiKey`
- `model`

Optional future settings:

- timeout
- temperature
- custom headers

MVP should keep settings minimal and stable.

The client should target an OpenAI-compatible chat-completions style endpoint first, because that gives the widest compatibility across hosted providers and self-hosted gateways.

The internal integration should abstract the transport so the project can later add Responses API or provider-specific variants without changing the AI page.

## Agent Execution Model

### High-Level Flow

1. User submits a task
2. Model produces a structured plan
3. App validates plan structure and tool legality
4. If side effects exist, app asks for confirmation
5. App executes tool calls in order
6. Model produces a final summary from tool outputs
7. UI renders result and trace

### Planning Rules

The model is allowed to:

- choose from registered tools
- decide tool-call order
- extract tool arguments from the user task
- stop early if the answer can be given directly

The model is not allowed to:

- invent tools
- bypass confirmation gates
- execute more than 3 tool calls
- emit arbitrary code for execution

### State Machine

The AI Assistant session should use a simple explicit state machine:

- `idle`
- `planning`
- `awaitingConfirmation`
- `executing`
- `completed`
- `failed`

Recommended transitions:

- `idle -> planning`
- `planning -> awaitingConfirmation`
- `planning -> executing`
- `awaitingConfirmation -> executing`
- `awaitingConfirmation -> idle`
- `executing -> completed`
- `executing -> failed`
- `completed -> planning`
- `failed -> planning`

## Tool Model

The AI layer should not call SwiftUI views directly. It should call a tool registry that wraps existing services.

### Read/Transform Tools

- `clipboard_read_latest`
- `clipboard_list_history`
- `json_validate`
- `json_format`
- `json_minify`
- `url_encode`
- `url_decode`
- `base64_encode`
- `base64_decode`
- `timestamp_to_date`
- `date_to_timestamp`
- `regex_find`
- `regex_replace_preview`
- `search_files`
- `search_apps`
- `search_system_settings`

### Side-Effect Tools

- `open_file`
- `open_app`
- `open_system_setting`
- `paste_clipboard_entry`

### Tool Contract

Each tool should expose:

- `name`
- `description`
- structured input schema
- side-effect flag
- execution closure

Each tool should return:

- structured success payload
- structured failure payload
- user-display summary

This contract must be owned by the AI subsystem, not duplicated inside the view layer.

## UI Design

### AI Assistant Page

The page should match the existing WhyUtils visual language and use the current tool-page shell.

Core sections:

1. Task Input
- single input area
- submit action
- a few example prompts

2. Plan Card
- short goal summary
- 1-3 execution steps

3. Tool Trace Card
- tool name
- arguments summary
- success or failure state

4. Confirmation Card
- shown only for side-effectful actions
- clear description of what will happen
- confirm or cancel

5. Result Card
- final answer
- optionally structured output payload

The page should feel like "task execution with visibility", not a conversational message feed.

### Settings UI

The existing settings sheet should gain an `AI` section with:

- enable switch
- base URL field
- API key field
- model field
- connection status or last error text

For MVP, storing the API key in `UserDefaults` is acceptable if the UI clearly treats it as local configuration and the implementation is isolated for later Keychain migration.

## Architecture and File Layout

Add these files:

- `Sources/WhyUtilsApp/Models/AIAgentTypes.swift`
- `Sources/WhyUtilsApp/Services/AI/OpenAICompatibleClient.swift`
- `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift`
- `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`

Modify these files:

- `Sources/WhyUtilsApp/Models/ToolKind.swift`
- `Sources/WhyUtilsApp/Views/ToolContainerView.swift`
- `Sources/WhyUtilsApp/Views/SettingsSheetView.swift`
- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- `Sources/WhyUtilsApp/Models/LauncherItem.swift` if launcher routing needs an explicit AI handoff item

### Responsibility Split

`AIAgentTypes.swift`
- shared request/response/state/plan models

`OpenAICompatibleClient.swift`
- HTTP request construction
- response parsing
- network and auth error mapping

`AIToolRegistry.swift`
- tool registration
- safety classification
- argument validation
- bridging existing services into tool functions

`AIAgentService.swift`
- orchestration
- state machine
- plan generation
- confirmation gating
- final response generation

`AIAssistantToolView.swift`
- task input and execution UI
- observing agent state
- rendering plan/trace/result

## Existing Service Reuse

The design intentionally reuses the current codebase:

- `ClipboardHistoryService`
- `PasteAutomationService`
- `JSONService`
- `EncodingService`
- `TimeService`
- `RegexService`
- `FileSearchService`
- `AppSearchService`
- `SystemSettingsSearchService`

The AI subsystem should adapt these services rather than duplicate business logic.

## Error Handling

The AI page should distinguish these failure classes:

1. Configuration failure
- missing base URL
- missing API key
- missing model

2. Transport failure
- timeout
- network unreachable
- invalid HTTP response

3. Model output failure
- malformed plan
- unknown tool
- invalid arguments

4. Tool execution failure
- JSON parsing error
- base64 decode error
- system setting open failure
- file open failure

User-facing errors should be short and actionable. Raw payloads should not be dumped into the UI unless explicitly useful for debugging.

## Testing Strategy

Add focused tests for:

- OpenAI-compatible request building
- plan validation
- side-effect confirmation gating
- tool registry lookup and schema validation
- AI state transitions
- launcher handoff into the AI page

Prefer deterministic tests around:

- malformed plan rejection
- side-effect tool requiring confirmation
- max-step enforcement
- no-tool direct-answer handling

The first implementation should avoid claiming end-to-end correctness against live model providers unless there is a controllable mock transport.

## MVP Delivery Order

1. Add AI config model and settings UI
2. Add AI tool type definitions and registry
3. Add OpenAI-compatible client
4. Add agent orchestration state machine
5. Add AI Assistant tool page
6. Add launcher handoff
7. Add tests

## Risks

1. The largest product risk is drifting into "chat UI with weak actions".
Mitigation: keep the UI structured around plan, tool trace, confirmation, and result.

2. The largest engineering risk is letting model output directly control execution.
Mitigation: validate every tool call locally and gate side effects.

3. Another risk is exposing too many tools too early.
Mitigation: launch with a narrow curated tool set and expand later.

## Explicit Non-Goals

- full autonomous desktop agent
- web-browsing agent
- coding assistant
- memory-based personal assistant
- infinite-loop planner
- arbitrary plugin system for external tools

## Recommendation

Ship the first version as a constrained "plan then act" agent, centered on WhyUtils' existing local utilities.

That gives the product a real agent identity while staying inside the architecture and safety boundaries that the current macOS utility can support.
