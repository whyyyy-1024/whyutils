# AI Thread-Chat System Design

## Overview

Refactor the AI assistant session management from flat session list to hierarchical Thread-Chat structure, similar to Codex. Each Thread is bound to a working directory, and contains multiple Chats. Git branch information is displayed at Thread level. File change statistics are tracked per Chat and displayed in AI responses.

## Goals

1. Thread-Chat hierarchical structure (Thread = directory, Chat = conversation)
2. Working directory binding per Thread
3. Real-time git branch detection at Thread level
4. File change statistics per Chat
5. Clear change summary in AI responses

## Data Model

### AIThread

```swift
struct AIThread: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String                    // User-defined title (optional)
    let workingDirectory: String         // Working directory path
    let createdAt: Date
    var updatedAt: Date
    var chats: [AIChatSession]           // Child Chat list
    
    var displayName: String {
        title.isEmpty ? URL(fileURLWithPath: workingDirectory).lastPathComponent : title
    }
    
    static func create(workingDirectory: String, now: Date) -> AIThread {
        AIThread(
            id: UUID(),
            title: "",
            workingDirectory: workingDirectory,
            createdAt: now,
            updatedAt: now,
            chats: []
        )
    }
}
```

### AIChatSession (Updated)

```swift
struct AIChatSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var isUserRenamed: Bool
    let createdAt: Date
    var updatedAt: Date
    var messages: [AIChatMessageRecord]
    var fileChangeSummary: FileChangeSummary
    
    // workingDirectory moved to Thread level
}
```

### FileChangeSummary

```swift
struct FileChangeSummary: Codable, Equatable, Sendable {
    var modifiedFiles: [FileChangeRecord]
    var createdFiles: [String]
    var deletedFiles: [String]
    var totalLinesAdded: Int
    var totalLinesRemoved: Int
    
    init() {
        modifiedFiles = []
        createdFiles = []
        deletedFiles = []
        totalLinesAdded = 0
        totalLinesRemoved = 0
    }
    
    var hasChanges: Bool {
        !modifiedFiles.isEmpty || !createdFiles.isEmpty || !deletedFiles.isEmpty
    }
    
    var summaryText: String {
        if !hasChanges { return "无变更" }
        return "+\(totalLinesAdded)/-\(totalLinesRemoved)"
    }
}

struct FileChangeRecord: Codable, Equatable, Sendable {
    let path: String
    let linesAdded: Int
    let linesRemoved: Int
    let modifiedAt: Date
}
```

### AIChatWorkspaceStore (Updated)

```swift
@MainActor
final class AIChatWorkspaceStore: ObservableObject {
    @Published private(set) var threads: [AIThread] = []
    @Published var activeThreadID: UUID?
    @Published var activeChatID: UUID?
    
    var activeThread: AIThread? {
        guard let activeThreadID else { return threads.first }
        return threads.first(where: { $0.id == activeThreadID })
    }
    
    var activeChat: AIChatSession? {
        guard let thread = activeThread else { return nil }
        guard let activeChatID else { return thread.chats.first }
        return thread.chats.first(where: { $0.id == activeChatID })
    }
    
    func createNewThread(directory: String) {
        let thread = AIThread.create(workingDirectory: directory, now: Date())
        threads.insert(thread, at: 0)
        activeThreadID = thread.id
        createNewChat(in: thread.id)
        persist()
    }
    
    func createNewChat(in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let chat = AIChatSession.empty(now: Date())
        threads[threadIndex].chats.insert(chat, at: 0)
        threads[threadIndex].updatedAt = Date()
        activeChatID = chat.id
        persist()
    }
    
    func selectThread(id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        activeThreadID = id
        activeChatID = threads.first(where: { $0.id == id })?.chats.first?.id
    }
    
    func selectChat(threadID: UUID, chatID: UUID) {
        activeThreadID = threadID
        activeChatID = chatID
    }
}
```

## UI Layout

### Left Panel - Dual List Structure

```
┌─────────────────────────────┐
│ 📁 Threads                  │
│ ┌───────────────────────┐   │
│ │ whyutils-swift 🌿main▼│   │← Thread (directory + git branch)
│ │   ├ 修复bug  10:30📝+12│   │← Chat (title + time + change summary)
│ │   ├ 添加功能 昨天📝+45 │   │
│ │   └ 重构代码 3天前     │   │
│ │   [+ 新建Chat]         │   │← New Chat button (inside Thread)
│ └───────────────────────┘   │
│ ┌───────────────────────┐   │
│ │ other-project    ▶    │   │← Thread (collapsed, non-git)
│ └───────────────────────┘   │
│                             │
│ [+ 新建Thread]              │← New Thread button
└─────────────────────────────┘
```

### Thread Row Display

- Directory name (last path component or user-defined title)
- Git branch label (real-time detection, green if present)
- Expand/collapse arrow
- Child count indicator (optional)

### Chat Row Display

- Chat title (auto-generated or user-defined)
- Update time
- File change summary: `📝+X/-Y` (if has changes)

### Chat Top Area

```
┌────────────────────────────────────────┐
│ 📁 /Users/xxx/projects/whyutils-swift │← Working directory (inherited from Thread)
│ 🌿 main                               │← Git branch (real-time)
│ ───────────────────────────────────── │
│ 📝 本次变更：修改3文件 (+45/-12)       │← Change summary for this Chat
└────────────────────────────────────────┘
```

## Git Branch Detection

### GitService

```swift
struct GitService {
    static func detectBranch(directory: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "branch", "--show-current"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 { return nil }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
            return branch?.isEmpty == false ? branch : nil
        } catch {
            return nil
        }
    }
    
    static func isGitRepository(directory: String) -> Bool {
        FileManager.default.fileExists(atPath: directory + "/.git")
    }
}
```

### Real-time Detection

- Git branch is detected when Thread list renders
- Async detection to avoid UI blocking
- Branch label updates automatically when Thread expands
- Non-git repositories: no branch label shown

## File Change Tracking

### Tracking Rules

| Tool | Tracking |
|------|----------|
| `write_file` | New file → createdFiles, existing → modifiedFiles |
| `fs_create_directory` | createdFiles (directory) |
| `fs_delete` | deletedFiles |
| `code_edit_line` / `code_edit_range` | modifiedFiles, line diff calculation |

### Line Diff Calculation

```swift
func calculateLineDiff(original: String?, new: String) -> (added: Int, removed: Int) {
    guard let original else {
        return (new.components(separatedBy: .newlines).count, 0)
    }
    let originalLines = original.components(separatedBy: .newlines).count
    let newLines = new.components(separatedBy: .newlines).count
    if newLines > originalLines {
        return (newLines - originalLines, 0)
    } else {
        return (0, originalLines - newLines)
    }
}
```

### Change Summary in AI Response

```
AI response content...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 本次操作变更：

✏️ 修改文件 (3个):
   Sources/AI/AIAgentService.swift (+12/-3)
   Sources/Models/AIChatSession.swift (+8/-0)
   Tests/ServiceTests.swift (+5/-2)

➕ 新增文件 (1个):
   Sources/Tools/NewTool.swift (28行)

❌ 删除文件 (0个)

📊 总计: +25行 / -5行
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Flows

### Create New Thread

1. Click "[+ 新建Thread]" button
2. System folder picker (NSOpenPanel) appears
3. User selects working directory
4. Create Thread with selected directory
5. Detect git branch (async)
6. Auto-create first empty Chat
7. Expand new Thread, activate first Chat

### Create New Chat

1. Click "[+ 新建Chat]" inside expanded Thread
2. Create new Chat under current Thread
3. Activate new Chat
4. Inherit Thread's working directory

### Thread/Chat Selection

- Click Thread → expand/collapse
- Click Thread when collapsed → expand and activate first Chat
- Click Chat → activate Chat, keep Thread expanded

## File Organization

```
Sources/WhyUtilsApp/
├── Models/
│   ├── AIThreadModels.swift          // AIThread, FileChangeSummary
│   ├── AIChatSessionModels.swift     // AIChatSession (updated)
│   └── AIAgentTypes.swift            // Existing
│
├── Services/
│   ├── GitService.swift              // Git branch detection
│   ├── AI/
│   │   └── ...                       // Existing AI services
│   └── Tools/
│   │   └── Modules/
│   │       ├── BasicToolModule.swift  // Update to track changes
│   │       ├── CodeEditModule.swift   // Update to track changes
│   │       └── FileSystemModule.swift // Update to track changes
│
├── ViewModels/
│   ├── AIChatWorkspaceStore.swift    // Updated for Thread-Chat
│   └
├── Views/
│   └ Tools/
│   │   ├── AIThreadListView.swift    // New: Thread list component
│   │   ├── AIChatListView.swift      // New: Chat list component
│   │   └── AIAssistantToolView.swift // Updated: integrate Thread-Chat
```

## Migration

- Existing sessions → convert to single Thread + single Chat
- Thread title = session's working directory (if available) or "Legacy Session"
- Preserve all existing messages and data

## Testing

- Thread creation with directory selection
- Chat creation within Thread
- Git branch detection (git/non-git directories)
- File change tracking (write, edit, delete)
- Change summary formatting
- Thread-Chat navigation
- Persistence and restoration