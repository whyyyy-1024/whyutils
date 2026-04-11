# WhyUtils Kill Process Feature

Date: 2026-04-11
Status: Draft for review

## Goal

Add a Kill Process tool to WhyUtils, similar to Raycast's process management feature.

This feature should:

- display a list of running processes with name, PID, CPU%, and memory usage
- support search/filter by process name or PID
- allow users to terminate selected processes with confirmation
- integrate seamlessly into the existing launcher and tool architecture
- use consistent visual design language with other WhyUtils tools

This feature should not:

- require complex permission setup beyond standard macOS process termination
- add background monitoring when the tool is not active
- support advanced features like process trees, parent process tracking, or force-kill options in MVP

## Product Definition

The Kill Process tool is a lightweight process management utility for everyday use.

User promise:

- quickly find a process by name or PID
- see which processes are consuming CPU or memory
- terminate unresponsive or unwanted processes safely
- use keyboard-first navigation for speed

The primary interaction target is "search → select → terminate", similar to the File Search tool.

## Core UX Direction

The visual target follows WhyUtils' existing tool page patterns, especially File Search.

### Layout

The Kill Process page uses a similar structure to File Search:

1. Top bar
   - back button (arrow.left)
   - search field (large, centered)
   - refresh button or auto-refresh indicator

2. Main content
   - single column list of processes
   - no separate preview pane (process info is concise enough to show inline)

3. Action bar
   - tool name and icon
   - Terminate button with keyboard shortcut hint
   - Refresh button

### Visual Rules

- Use existing theme colors: `Color.whyPanelBackground`, `Color.whyCardBackground`, `Color.whyChromeBackground`, etc.
- Process rows should match FileSearchRow styling: icon + name/subtitle, hover/selection states
- Keep the UI quiet and spacious
- CPU and memory values should be formatted cleanly (e.g., "12.5%" not "12.500000%")

## Data Model

### ProcessItem

```swift
struct ProcessItem: Identifiable, Equatable {
    let id: Int32          // PID
    let pid: Int32         // redundant for clarity, same as id
    let name: String       // process name (from COMMAND column)
    let cpu: Double        // CPU percentage
    let memory: Double     // memory percentage
    let user: String       // owning user
}
```

### Sorting

Default sort: by CPU usage descending (highest CPU first).

This matches the `-r` flag behavior in `ps aux -r`.

### Filtering

Search query should match:
- process name (contains, case-insensitive)
- PID (exact or prefix match)

## Service Layer

### ProcessListService

**Responsibilities:**

- fetch process list via `ps aux -r`
- parse output into `ProcessItem` structs
- filter out WhyUtils' own process
- provide kill functionality via `kill(pid, SIGTERM)`
- handle errors (permission denied, process not found)

**API:**

```swift
enum ProcessListService {
    static func fetchProcesses() async -> [ProcessItem]
    static func killProcess(pid: Int32) -> KillResult
}

enum KillResult {
    case success
    case failure(message: String)
}
```

**Implementation Details:**

- Use `Process` to execute `ps aux -r`
- Parse output lines: `USER PID %CPU %MEM VSZ RSS TT STAT STARTED TIME COMMAND`
- Extract: user, pid, cpu%, mem%, command
- Command parsing: handle paths, extract last component as process name
- Self-filter: compare PID with `ProcessInfo.processInfo.processIdentifier`

**Refresh Strategy:**

- Fetch on page appear
- Optional: background refresh every 2 seconds while page is active
- Manual refresh button in action bar

**Kill Implementation:**

- Use Darwin `kill(pid, SIGTERM)` C function
- Check return value: 0 = success, -1 = failure
- On failure, use `errno` to determine error type
- Common errors: EPERM (permission denied), ESRCH (process not found)

## UI Layer

### KillProcessToolView

**Structure:**

```swift
struct KillProcessToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel: KillProcessViewModel
    
    @State private var query: String = ""
    @State private var selectedProcessID: Int32?
    @State private var showKillConfirmation: Bool = false
    @State private var killError: String?
    @FocusState private var focusSearch: Bool
    
    // body: topBar + processList + actionBar
}
```

**Top Bar:**

- Back button → `coordinator.backToLauncher()`
- Search field → large font, placeholder "Search processes..."
- Refresh indicator or manual refresh button

**Process List:**

- Use `LazyVStack` similar to FileSearchToolView
- Each row shows: process icon (generic or app icon if available), name, PID, CPU%, MEM%
- Row styling: hover state, selection highlight
- Double-click = trigger kill confirmation
- Single-click = select

**Row Layout:**

```
[Icon] [Process Name]
       PID: 1234  CPU: 12.5%  MEM: 3.2%
```

Or more compact:

```
[Icon] Process Name    1234    12.5%    3.2%
```

Follow FileSearchRow pattern for consistency.

**Action Bar:**

- Tool name: "Kill Process" + icon
- Terminate button with shortcut hint (Enter)
- Refresh button with shortcut hint (Cmd+R or F5)
- Error message display area if kill fails

### Confirmation Dialog

Before terminating a process, show a confirmation dialog:

```
Title: Terminate "Chrome" (PID 1234)?
Message: This will send SIGTERM to the process. It may not terminate immediately if unresponsive.
Buttons: [Terminate] [Cancel]
```

Localized:

- English: "Terminate \"{name}\" (PID {pid})?"
- Chinese: "终止 \"{name}\" (PID {pid})？"

### Keyboard Navigation

Similar to File Search:

- `↑/↓` - move selection
- `Enter` - trigger kill confirmation for selected process
- `Esc` - back to launcher
- `Cmd+R` or `F5` - refresh process list

### Error Handling

If kill fails, show error inline in action bar or as a temporary status:

- Permission denied: "Permission denied. Try terminating processes owned by your user."
- Process not found: "Process not found. It may have already terminated."

Use `StatusLine` component from ToolComponents.

## Localization

Add strings for:

| English | Chinese |
|---------|---------|
| Kill Process | 终止进程 |
| Search processes... | 搜索进程... |
| Processes | 进程 |
| No processes found | 未找到进程 |
| Loading... | 加载中... |
| Terminate | 终止 |
| Refresh | 刷新 |
| Terminate "{name}" (PID {pid})? | 终止 "{name}" (PID {pid})？ |
| Permission denied | 权限不足 |
| Process not found | 进程不存在 |
| Search and terminate running processes | 搜索并终止运行中的进程 |

## Integration Points

### ToolKind

Add new case:

```swift
// ToolKind.swift
case killProcess

// title(in:)
case .killProcess: return L10n.text("Kill Process", "终止进程", language: language)

// subtitle(in:)
case .killProcess: return L10n.text("Search and terminate running processes", "搜索并终止运行中的进程", language: language)

// symbol
case .killProcess: return "xmark.circle"
```

### ToolContainerView

Add routing:

```swift
// ToolContainerView.swift switch
case .killProcess:
    KillProcessToolView()
```

### LauncherItem

Already covered by `LauncherItem.tool(ToolKind)`. No changes needed.

### AppCoordinator

Potential changes:

- If passing query from launcher, handle `killProcess` case
- Otherwise, no changes needed

## Testing

Add `ProcessListServiceTests.swift`:

- Test parsing `ps aux` output
- Test self-filtering (exclude WhyUtils PID)
- Test search filter logic
- Test kill result handling (mock kill call)

Test cases:

1. Parse valid ps output line
2. Handle malformed ps output gracefully
3. Filter out self process
4. Search by name matches correctly
5. Search by PID matches correctly
6. Sort by CPU descending
7. Kill success result
8. Kill failure result with EPERM
9. Kill failure result with ESRCH

## Implementation Boundaries

### Files Expected to Add/Change

**Add:**
- `Sources/WhyUtilsApp/Services/ProcessListService.swift`
- `Sources/WhyUtilsApp/Views/Tools/KillProcessToolView.swift`
- `Sources/WhyUtilsApp/ViewModels/KillProcessViewModel.swift` (optional, if state needs separation)
- `Tests/WhyUtilsAppTests/ProcessListServiceTests.swift`

**Change:**
- `Sources/WhyUtilsApp/Models/ToolKind.swift` - add `killProcess` case
- `Sources/WhyUtilsApp/Views/ToolContainerView.swift` - add routing

### Files Not Intended for Major Rework

- `AppCoordinator.swift` - minimal or no changes
- `LauncherView.swift` - no changes
- Other tool views - no changes
- Theme/colors - no changes

## Acceptance Criteria

The feature is complete when:

1. Users can open Kill Process from the launcher
2. Process list displays name, PID, CPU%, MEM% correctly
3. Search filter works by name and PID
4. Keyboard navigation (↑/↓, Enter, Esc) works
5. Terminate action shows confirmation dialog
6. Confirmation dialog is localized
7. Successful termination removes process from list (after refresh)
8. Failed termination shows appropriate error message
9. UI styling matches existing WhyUtils tools
10. Tests pass and cover core logic

## Risks

- Permission errors for system processes: users may try to kill processes they don't own. Clear messaging needed.
- Process list accuracy: `ps` output may have slight delay. Refresh helps.
- Process name parsing: COMMAND column can be paths, arguments, etc. Need robust extraction.
- Self-termination: if user somehow selects WhyUtils itself, should be filtered out or show warning.

## Recommendation

Implement in order:

1. Service layer (ProcessListService) with tests
2. Data model (ProcessItem)
3. UI skeleton (KillProcessToolView layout)
4. Integration (ToolKind, ToolContainerView)
5. Polish (styling, localization, keyboard shortcuts)
6. Error handling and edge cases

Keep the view simple. Use existing patterns from FileSearchToolView. Avoid over-engineering the process list - it's a read-only snapshot with a single action.