# WhyUtils AI Assistant Chat UI Redesign

Date: 2026-04-05
Status: Draft for review
Supersedes: `docs/superpowers/specs/2026-04-05-ai-assistant-agent-design.md` sections related to AI page presentation

## Goal

Refactor the current AI Assistant page from a debug-style task console into a ChatGPT-like conversation workspace.

This redesign should:

- replace the rigid plan/result layout with a two-pane chat interface
- support full local conversation history management
- keep the existing AI agent and tool-calling core
- present tool execution inline inside assistant messages instead of as primary UI blocks
- remove preset prompt buttons and other debug-style affordances
- preserve streaming replies, confirmation gates, and WhyUtils local-tool execution

This redesign should not:

- introduce web-like side navigation for the rest of the app
- add cloud sync or account-based conversation storage
- add prompt templates, prompt libraries, or preset chips
- replace the existing AI transport or tool execution architecture

## Product Definition

The AI Assistant becomes a local chat workspace with agent capabilities.

User promise:

- chat naturally when they just want to talk
- let the assistant invoke local tools when work needs to be done
- review and manage past conversations like a normal chat product
- switch between safe and high-permission modes in Settings without cluttering the chat UI

The primary interaction target is no longer "run one task". It is "maintain an ongoing local conversation that can call tools when useful".

## Core UX Direction

The visual target is closer to ChatGPT than to a developer console.

### Layout

The AI Assistant page uses a fixed two-column structure:

1. Left sidebar
- narrow, persistent conversation list
- `New chat` action at the top
- each row shows only title and relative or absolute time
- no preview text in the list
- selected conversation has a clear active state

2. Right main pane
- lightweight top bar with model/access-mode status
- central scrollable message timeline
- bottom composer with multiline input
- no preset prompt chips
- no large configuration banner card

### Visual Rules

- Keep the chat canvas visually quiet and spacious.
- Keep chrome minimal and secondary.
- User messages remain visually distinct, but assistant messages should feel closer to content blocks than boxed dashboard cards.
- Tool execution should read as part of the assistant response, not as a separate debugging dashboard.
- The page should feel usable even when a conversation contains no tool calls.

## Conversation Management

The redesign must support the full local conversation lifecycle.

### Required Actions

- create new conversation
- switch active conversation
- rename conversation
- delete conversation
- persist conversations across app restarts

### Title Rules

- a new conversation starts untitled
- after the first user message, the app auto-generates a concise title from that message
- users may rename a conversation at any time
- manual titles must not be overwritten by later auto-title logic

### Persistence Rules

Persist locally only.

MVP storage can use local JSON via `UserDefaults` or another existing lightweight persistence path already used by the app. Do not add a database dependency for this feature.

Stored conversation data should include at least:

- `id`
- `title`
- `isUserRenamed`
- `createdAt`
- `updatedAt`
- `messages`
- `lastAccessedAt` if useful for sorting

Default conversation ordering:

- most recently updated first

## Message Model

The page should move from a transient in-view message struct to a persistent conversation-backed message model.

Each message should capture:

- `id`
- `role` (`user`, `assistant`, optional internal/system if needed)
- `text`
- `createdAt`
- `toolTraces`
- `confirmationRequest` when the assistant is awaiting approval
- `isStreaming`
- `status` when helpful for rendering in-progress states

The stored model should be stable enough that reloading the app reconstructs the conversation timeline without recomputing the UI state from scratch.

## Message Presentation

### User Messages

- render on the right
- compact bubble
- visually distinct but not oversized

### Assistant Messages

- render on the left
- emphasize readable text flow over card-heavy framing
- streaming text should grow in place
- tool traces should appear inline below the assistant response as expandable execution blocks

### Tool Call Presentation

Tool use should feel similar to modern AI products:

- small inline tool pill or execution header
- expandable detail block for arguments and outputs
- output should be truncated visually when very large, with explicit expand affordance if needed later
- do not dump raw traces into the main message body unless the model intentionally summarizes them there

### Confirmation Presentation

When a plan contains side effects, the assistant message should include an inline confirmation block with:

- concise explanation
- clear list of gated actions
- `Confirm` and `Cancel` actions

This block belongs inside the message stream, not in a detached global panel.

## Composer and Streaming Behavior

### Composer

The bottom composer should support:

- multiline input
- `Enter` to send
- `Shift+Enter` for newline
- disabled send when input is empty

### Streaming

Streaming remains required.

Behavior:

- assistant placeholder appears immediately after send
- content streams into the active assistant message
- while streaming, show a `Stop generating` action in place of the send action
- stopping generation should cancel the current stream cleanly and preserve the partial response already shown

### Clipboard Shortcut

The existing "use latest clipboard" helper should not remain a prominent preset-style action in the main layout.

If retained, it should be demoted to a subtle secondary control near the composer, not a large button row.

## Top Bar

The current large configuration banner should be replaced by a slim top bar.

It should show only compact operational context such as:

- current model
- current access mode
- readiness / configuration warning when setup is incomplete

It should not dominate the page.

## Access Modes

The existing access-mode system remains valid:

- `Standard`
- `Full Access`
- `Unrestricted`

The redesign changes how this is expressed in the UI.

### Rules

- access mode is configured in Settings
- the chat page only displays the current mode compactly
- `Unrestricted` must still allow direct chat and high-permission tool execution without confirmation
- `Standard` and `Full Access` must continue to respect confirmation policy and plan-step limits defined by the current agent core

The redesign must not weaken the existing execution policy logic. It only changes how that logic is surfaced visually.

## Agent Integration

The current AI backend direction remains in place:

- SSE streaming
- direct message vs tool-plan decisioning
- tool registry
- side-effect confirmation gates
- local execution traces

The redesign should reuse that backend instead of re-architecting it.

Expected integration changes:

- feed conversation-backed message history into the agent
- save user and assistant messages to the active conversation as they evolve
- persist post-stream final assistant content
- attach tool traces and confirmation requests to the correct stored assistant message

## State and Lifecycle

The AI Assistant page now needs explicit page-level state for:

- active conversation id
- list of conversations
- active stream task or cancellation token
- rename sheet or inline rename state
- delete confirmation state if needed

The page should bootstrap like this:

1. load conversations from local persistence
2. if none exist, create one empty conversation and select it
3. if conversations exist, restore the most recently active conversation
4. focus the composer when the page opens

## Error Handling

Errors should be represented inside the conversation flow when possible.

Examples:

- model/network errors appear as assistant-side error messages
- failed tool execution appears as part of the assistant response with an execution detail block
- configuration errors may also surface in the slim top bar

Avoid detached global error cards unless the whole page cannot function.

## Testing

Add or update coverage for:

- conversation creation
- auto-title generation and manual rename protection
- conversation deletion and selection fallback
- persistence encode/decode for conversation history
- stop-stream behavior preserving partial assistant content
- agent reply attachment to the correct conversation/message
- confirmation request persistence and restoration behavior where applicable

Existing AI execution and OpenAI transport tests should remain green.

## Implementation Boundaries

### Files Expected to Change

- `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`
- new AI conversation model/store files under `Sources/WhyUtilsApp/Models` or `ViewModels`
- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift` only if needed for handoff and persistence hooks
- AI tests for new conversation state and persistence

### Files Not Intended for Major Rework

- `OpenAICompatibleClient.swift`
- core utility services unrelated to AI UI
- launcher search architecture outside the existing AI handoff path

## Acceptance Criteria

The redesign is complete when:

1. the AI page is visually a two-pane chat workspace rather than a tool console
2. preset prompt buttons are gone
3. users can create, switch, rename, and delete local conversations
4. conversations persist across app relaunches
5. assistant replies stream in place and can be stopped
6. tool executions appear inline inside the relevant assistant message
7. existing Standard / Full Access / Unrestricted behavior still works
8. tests cover the new conversation model and pass with the existing suite

## Risks

- Persisting in-progress streaming state can create messy restore behavior if not normalized when the app closes.
- Embedding confirmation and tool traces into persistent messages increases message model complexity.
- A direct SwiftUI-only refactor inside one large view could become hard to maintain if not split into smaller subviews and a conversation store.

## Recommendation

Split the redesign into three layers:

1. persistent conversation model and store
2. chat workspace view model / state coordinator
3. SwiftUI presentation layer with smaller chat subviews

Do not keep expanding `AIAssistantToolView` as a single state-heavy file. The redesign should use this opportunity to establish cleaner boundaries.
