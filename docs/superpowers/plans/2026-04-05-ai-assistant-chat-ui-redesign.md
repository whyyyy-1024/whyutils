# AI Assistant Chat UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current AI debug-console page with a ChatGPT-like chat workspace that supports persistent local conversation management, streaming replies, inline tool traces, and stop-generation behavior.

**Architecture:** Add a persistent AI conversation model and local store, layer a focused chat workspace state object on top of the existing agent backend, and rebuild the SwiftUI page into a two-pane conversation layout. Reuse the current OpenAI-compatible transport and agent/tool execution services instead of changing backend architecture.

**Tech Stack:** SwiftUI, Combine/Observation patterns already used in WhyUtils, UserDefaults JSON persistence, Swift Testing

---

## File Map

- Create: `Sources/WhyUtilsApp/Models/AIChatSessionModels.swift`
- Create: `Sources/WhyUtilsApp/ViewModels/AIChatWorkspaceStore.swift`
- Create: `Tests/WhyUtilsAppTests/AIChatSessionModelsTests.swift`
- Create: `Tests/WhyUtilsAppTests/AIChatWorkspaceStoreTests.swift`
- Modify: `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`
- Modify: `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- Modify: `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- Modify: `Sources/WhyUtilsApp/Models/AIAgentTypes.swift`
- Modify: `docs/CODEBASE_CONTEXT.md`

### Task 1: Persistent conversation models

**Files:**
- Create: `Sources/WhyUtilsApp/Models/AIChatSessionModels.swift`
- Test: `Tests/WhyUtilsAppTests/AIChatSessionModelsTests.swift`

- [ ] **Step 1: Write the failing tests**
Add tests for blank session creation, auto title generation, manual rename protection, and Codable round-trip for persisted chat sessions.

- [ ] **Step 2: Run test to verify it fails**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIChatSessionModelsTests`
Expected: FAIL because `AIChatSession` does not exist yet.

- [ ] **Step 3: Write minimal implementation**
Create Codable session/message models with persistence-safe trace and confirmation payloads.

- [ ] **Step 4: Run test to verify it passes**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIChatSessionModelsTests`
Expected: PASS.

### Task 2: Workspace store and local persistence

**Files:**
- Create: `Sources/WhyUtilsApp/ViewModels/AIChatWorkspaceStore.swift`
- Test: `Tests/WhyUtilsAppTests/AIChatWorkspaceStoreTests.swift`

- [ ] **Step 1: Write the failing tests**
Add tests for bootstrap, create/select, rename, delete fallback, and persistence restore.

- [ ] **Step 2: Run test to verify it fails**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIChatWorkspaceStoreTests`
Expected: FAIL because the store does not exist yet.

- [ ] **Step 3: Write minimal implementation**
Create a focused store for session CRUD, active selection, append/update messages, and persistence normalization.

- [ ] **Step 4: Run test to verify it passes**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIChatWorkspaceStoreTests`
Expected: PASS.

### Task 3: Streaming cancellation behavior

**Files:**
- Modify: `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- Modify: `Tests/WhyUtilsAppTests/AIAgentServiceTests.swift`

- [ ] **Step 1: Write the failing tests**
Add a focused test around partial streamed content ownership and cancellation-safe streaming behavior.

- [ ] **Step 2: Run test to verify it fails**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIAgentServiceTests`
Expected: FAIL on the new cancellation expectation.

- [ ] **Step 3: Write minimal implementation**
Keep the backend stable; make cancellation explicit at the caller boundary and keep partial content in workspace state.

- [ ] **Step 4: Run test to verify it passes**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIAgentServiceTests`
Expected: PASS.

### Task 4: ChatGPT-style AI workspace UI

**Files:**
- Modify: `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`
- Modify: `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift` if launcher handoff needs it

- [ ] **Step 1: Write the failing tests or view-model boundary tests**
Cover new chat creation, draft handoff, and message append/update through the workspace store.

- [ ] **Step 2: Run tests to verify they fail**
Run focused `AIChat` tests.
Expected: FAIL until the view is wired to the store.

- [ ] **Step 3: Write minimal implementation**
Rebuild the page into two panes, remove prompt chips, add session list and management actions, inline tool trace blocks, and `Stop generating` behavior.

- [ ] **Step 4: Run targeted tests to verify they pass**
Run:
- `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIChat`
- `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test --filter AIAgent`
Expected: PASS.

### Task 5: Full verification and docs

**Files:**
- Modify: `docs/CODEBASE_CONTEXT.md`

- [ ] **Step 1: Update architecture docs**
Document the chat workspace store, session persistence, and where to change layout vs agent logic.

- [ ] **Step 2: Run full test suite**
Run: `env CPLUS_INCLUDE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 swift test`
Expected: PASS.

- [ ] **Step 3: Build and smoke launch**
Run:
- `WHYUTILS_SIGN_MODE=adhoc ./scripts/build_app.sh`
- `open '/Users/wanghaoyu/VsCodeProjects/whyutils-swift/dist/whyutils-swift.app'`
Expected: build succeeds and the app launches.
