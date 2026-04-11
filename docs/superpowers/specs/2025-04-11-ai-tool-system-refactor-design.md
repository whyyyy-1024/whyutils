# AI Tool System Refactor Design

## Overview

Refactor the AI assistant tool invocation system from hardcoded switch-case architecture to a modular, extensible design that is compatible with MCP (Model Context Protocol). This enables:
- Adding new tools without modifying core execution logic
- Organizing tools by functional domains
- Supporting future MCP client integration
- Enhanced local capabilities (file system, code editing, memory, system control)

## Goals

1. Modular tool architecture with provider protocol
2. Enhanced local capabilities (13 new tool features)
3. Safety and confirmation system
4. MCP-compatible interface design
5. Backward compatibility with existing tools

## Architecture

### Current Architecture (Problem)

```
AIToolRegistry (hardcoded tool list)
     ↓
AIToolExecutor (switch-case execution - 100+ lines)
     ↓
AIAgentService (coordinates transport + executor)
```

Problems:
- Adding tools requires modifying `AIToolExecutor` switch-case
- No tool grouping by domain
- No safety validation layer
- Hard to integrate external tool sources (MCP)

### New Architecture

```
ToolProvider Protocol (unified interface)
     ├── LocalToolProvider (modular tools)
     │      ├── FileSystemModule
     │      ├── CodeEditModule
     │      ├── MemoryModule
     │      ├── SystemControlModule
     │      └── BasicModule (migrated existing tools)
     │
     └── MCPToolProvider (future MCP client)
     │
     ↓
ToolRegistry (aggregates all providers)
     ↓
ToolExecutor (routes to correct provider)
     ↓
AIAgentService (unchanged orchestration)
```

## Core Protocols

### ToolProvider

```swift
protocol ToolProvider: Sendable {
    var providerId: String { get }
    func tools() -> [ToolDescriptor]
    func execute(toolName: String, arguments: [String: Any]) async throws -> String
}
```

### ToolDescriptor (Enhanced)

```swift
struct ToolDescriptor: Sendable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
    let requiresConfirmation: Bool
    let providerId: String
    let dangerousLevel: DangerLevel
}

struct ToolParameter: Sendable {
    let name: String
    let type: ParamType  // string, int, bool, object, array
    let required: Bool
    let description: String
    let defaultValue: Any?
    let constraints: ParamConstraints?
}

enum DangerLevel: Int, Sendable {
    case safe = 0        // No confirmation needed
    case moderate = 1    // Standard mode needs confirmation
    case dangerous = 2   // All modes need confirmation (delete, kill process)
}
```

### ToolRegistry

```swift
class ToolRegistry: Sendable {
    private let providers: [ToolProvider]
    private let toolCache: [String: ToolDescriptor]
    
    func tool(named: String) -> ToolDescriptor?
    func allTools() -> [ToolDescriptor]
}
```

### ToolExecutor

```swift
class ToolExecutor: Sendable {
    private let registry: ToolRegistry
    private let providers: [String: ToolProvider]
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult
}
```

## File Organization

```
Sources/WhyUtilsApp/Services/Tools/
├── ToolProvider.swift
├── ToolRegistry.swift
├── ToolExecutor.swift
├── ToolValidation.swift
├── Modules/
│   ├── BasicToolModule.swift
│   ├── FileSystemModule.swift
│   ├── CodeEditModule.swift
│   ├── MemoryModule.swift
│   └── SystemControlModule.swift
└── MCP/
    ├── MCPToolProvider.swift (reserved)
    └── MCPClient.swift (reserved)
```

## Tool Modules

### 1. FileSystemModule

| Tool | Description | Confirmation |
|------|-------------|--------------|
| fs_create_directory | Create directory (nested) | No |
| fs_delete | Delete file or directory (recursive) | Yes |
| fs_copy | Copy file or directory | Yes |
| fs_move | Move/rename file or directory | Yes |
| fs_batch_copy | Copy multiple files | Yes |
| fs_batch_move | Move multiple files | Yes |
| fs_find | Recursive file search (wildcard/regex) | No |
| fs_find_content | Search text in file contents | No |
| fs_compress | Compress to zip | Yes |
| fs_decompress | Decompress zip | Yes |
| fs_get_info | Get file details (size, mtime) | No |

Safety Constraints:
- Forbidden paths: `/System`, `/Library`, `/usr`, `/bin`, `/etc`, `~/.ssh`, `~/.gnupg`
- Max read size: 5MB
- Operation logging for delete/move/write
- Confirmation for: recursive delete, batch >10 files, crossing safe boundaries

### 2. CodeEditModule

| Tool | Description | Confirmation |
|------|-------------|--------------|
| code_read_range | Read file line range | No |
| code_edit_line | Edit single line | Yes |
| code_edit_range | Edit multiple lines | Yes |
| code_search_symbols | Search function/class/variable | No |
| code_find_references | Find symbol references | No |
| code_list_imports | List file imports | No |
| code_outline | Get file structure | No |
| code_analyze | Static analysis (syntax check) | No |

Edit Parameters:
```json
{
  "path": "/path/to/file.swift",
  "operation": "replace",  // replace, insert_before, insert_after, delete
  "lineStart": 10,
  "lineEnd": 12,
  "content": "new code"
}
```

Supported Languages: Swift, Python, JavaScript, TypeScript, Go, Rust

### 3. MemoryModule

| Tool | Description | Confirmation |
|------|-------------|--------------|
| memory_store | Store long-term memory | No |
| memory_retrieve | Retrieve memory (keyword search, sorted by relevance) | No |
| memory_list | List all memories | No |
| memory_delete | Delete specific memory | Yes |
| memory_clear | Clear all memories | Yes |
| session_summarize | Generate and store session summary | No |
| session_recall | Recall related history | No |

Memory Entry Structure:
```swift
struct MemoryEntry: Codable, Identifiable {
    let id: UUID
    let content: String
    let category: MemoryCategory
    let createdAt: Date
    let lastAccessed: Date
    let accessCount: Int
    let metadata: [String: String]
}

enum MemoryCategory: String, Codable {
    case userPreference, projectInfo, codePattern
    case usefulSnippet, importantFile, workflow, general
}
```

Storage: `~/Library/Application Support/WhyUtils/memory_store.json`
Limits: 2000 chars per entry, max 500 entries

### 4. SystemControlModule

| Tool | Description | Confirmation |
|------|-------------|--------------|
| process_list | List processes (CPU/mem sorted) | No |
| process_info | Get process details | No |
| process_kill | Terminate process | Yes |
| network_request | HTTP request (GET/POST/etc) | No |
| screenshot | Screen/window capture | No |
| screenshot_region | Capture region | No |
| window_list | List all windows | No |
| window_focus | Focus window | No |
| window_info | Get window details | No |
| window_resize | Resize window | No |
| window_move | Move window | No |

Network Safety:
- Block private networks (localhost, 127.x, 10.x, 192.168.x)
- Auto-redact sensitive data in requests (use existing `AIToolExecutor.redactSensitiveText` patterns: API keys like `sk-*`)
- Max timeout: 60s

Process Safety:
- Block system processes (kernel, launchd, WindowServer)
- Block self process

### 5. BasicToolModule (Migration)

Migrate existing tools from `AIToolExecutor` switch-case:
- clipboard_read_latest, clipboard_list_history
- json_validate, json_format, json_minify
- url_encode, url_decode
- base64_encode, base64_decode
- timestamp_to_date, date_to_timestamp
- regex_find, regex_replace_preview
- search_files, search_apps, search_system_settings
- open_file, open_app, open_system_setting
- paste_clipboard_entry
- list_directory, read_file, write_file
- run_shell_command, open_url

## Confirmation System

Rules based on `DangerLevel`:
- `safe`: Never requires confirmation
- `moderate`: Requires confirmation in Standard mode
- `dangerous`: Always requires confirmation

Plus override rules:
- Batch operations >10 items: force confirmation
- Crossing safe path boundaries: force confirmation
- Recursive delete: force confirmation

## Implementation Plan

### Phase 1: Core Architecture
1. Define ToolProvider protocol
2. Implement ToolRegistry
3. Implement ToolExecutor
4. Create ToolValidation layer

### Phase 2: Module Implementation
1. BasicToolModule (migrate existing)
2. FileSystemModule
3. CodeEditModule
4. MemoryModule
5. SystemControlModule

### Phase 3: Integration
1. Update AIAgentService to use new ToolExecutor
2. Update AIToolRegistry initialization
3. Update UI confirmation flow
4. Testing and validation

### Phase 4: MCP Preparation (Future)
1. Implement MCPToolProvider
2. Implement MCPClient
3. Integration testing

## Testing

- Unit tests for each module
- Integration tests for ToolRegistry/Executor
- Safety validation tests
- Confirmation flow tests
- Backward compatibility tests

## Migration Strategy

1. Keep existing `AIToolExecutor.live` working during transition
2. Create new modules alongside
3. Add feature flag to switch between old/new system
4. Validate with tests
5. Remove old implementation

## Success Criteria

- All 13 new features working
- Existing tools migrated successfully
- Confirmation system functional
- MCP-compatible interfaces ready
- No regression in existing functionality