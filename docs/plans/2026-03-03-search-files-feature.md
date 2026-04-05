# Search Files Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 whyutils 中新增 Raycast 风格的 Search Files 工具，支持 User/This Mac 范围切换、Recent Files、打开与 Finder 定位。

**Architecture:** 采用 `NSMetadataQuery` 作为搜索后端，新增 `FileSearchService` 负责查询与结果映射，新增 `FileSearchToolView` 承载 UI 与交互。Launcher 增加入口，Tool 路由接入新工具。右侧预览和 metadata 复用现有卡片风格组件并保持暗色/亮色兼容。

**Tech Stack:** SwiftUI、AppKit、NSMetadataQuery、NSWorkspace、Swift Testing

---

### Task 1: Add Failing Tests for Search Core Logic

**Files:**
- Create: `Tests/WhyUtilsAppTests/FileSearchServiceTests.swift`
- Test: `Tests/WhyUtilsAppTests/FileSearchServiceTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func scopeUserHasExpectedDisplayName() {
    let scope = FileSearchScope.user(userName: "wanghaoyu")
    #expect(scope.displayTitle == "User (wanghaoyu)")
}

@Test
func shouldExcludeSystemAndHiddenPathsForThisMac() {
    #expect(FileSearchService.shouldExcludePath("/System/Library/CoreServices/Finder.app", scope: .thisMac))
    #expect(FileSearchService.shouldExcludePath("/private/var/tmp/file.txt", scope: .thisMac))
    #expect(FileSearchService.shouldExcludePath("/Users/wanghaoyu/.git/config", scope: .thisMac))
    #expect(!FileSearchService.shouldExcludePath("/Users/wanghaoyu/Documents/report.txt", scope: .thisMac))
}

@Test
func shouldNotExcludeRegularUserFilesForUserScope() {
    #expect(!FileSearchService.shouldExcludePath("/Users/wanghaoyu/Documents/demo.txt", scope: .user(userName: "wanghaoyu")))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FileSearchServiceTests`
Expected: FAIL because `FileSearchScope` / `FileSearchService.shouldExcludePath` do not exist.

**Step 3: Write minimal implementation**

```swift
// Create basic FileSearchScope + shouldExcludePath stubs to satisfy tests
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter FileSearchServiceTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/WhyUtilsAppTests/FileSearchServiceTests.swift Sources/WhyUtilsApp/Services/FileSearchService.swift
git commit -m "test: add file search scope and exclusion tests"
```

### Task 2: Implement NSMetadataQuery-backed File Search Service

**Files:**
- Create: `Sources/WhyUtilsApp/Services/FileSearchService.swift`
- Modify: `Sources/WhyUtilsApp/Services/JSONService.swift` (none, no change; keep isolated)
- Test: `Tests/WhyUtilsAppTests/FileSearchServiceTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func resultSortsByModifiedDateDescending() {
    // construct two mock rows and assert newer first via service sorting helper
}

@Test
func emptyQueryBuildsRecentPredicate() {
    // assert predicate string contains content type filtering and no query text
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FileSearchServiceTests`
Expected: FAIL due missing sort/predicate helpers.

**Step 3: Write minimal implementation**

```swift
// Add FileSearchResult model
// Add FileSearchService with:
// - update(scope:query:)
// - results publisher (@Published)
// - NSMetadataQuery notifications handling
// - recent files mode for empty query
// - result cap (200)
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter FileSearchServiceTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Services/FileSearchService.swift Tests/WhyUtilsAppTests/FileSearchServiceTests.swift
git commit -m "feat: add NSMetadataQuery file search service"
```

### Task 3: Wire Tool and Launcher Entries

**Files:**
- Modify: `Sources/WhyUtilsApp/Models/ToolKind.swift`
- Modify: `Sources/WhyUtilsApp/Models/LauncherItem.swift`
- Modify: `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- Test: `Tests/WhyUtilsAppTests/LauncherItemTests.swift` (if needed, else extend existing)

**Step 1: Write the failing test**

```swift
@Test
func launcherItemsContainsSearchFilesTool() {
    // assert ToolKind includes .searchFiles and appears in launcher items
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter Launcher`
Expected: FAIL until new enum case and item mapping exist.

**Step 3: Write minimal implementation**

```swift
// Add ToolKind.searchFiles title/subtitle/symbol/matches
// Ensure launcher rendering uses it like other tool entries
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter Launcher`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Models/ToolKind.swift Sources/WhyUtilsApp/Models/LauncherItem.swift Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift Tests/WhyUtilsAppTests
git commit -m "feat: add Search Files launcher integration"
```

### Task 4: Build Search Files Tool UI

**Files:**
- Create: `Sources/WhyUtilsApp/Views/Tools/FileSearchToolView.swift`
- Modify: `Sources/WhyUtilsApp/Views/ToolContainerView.swift`
- Modify: `Sources/WhyUtilsApp/Views/ThemeColors.swift` (only if missing supporting colors)

**Step 1: Write the failing test**

```swift
@Test
func shouldOpenFileURLOnEnterAction() {
    // test action dispatch helper resolves selected row and open action
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FileSearch`
Expected: FAIL until action helper exists.

**Step 3: Write minimal implementation**

```swift
// FileSearchToolView layout:
// - top bar: back + query + scope picker
// - left list: recent/results with hover + selection
// - right pane: preview/metadata
// - bottom bar actions
// Keyboard:
// - up/down selection
// - enter open
// - cmd+enter reveal
// - esc back
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter FileSearch`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/WhyUtilsApp/Views/Tools/FileSearchToolView.swift Sources/WhyUtilsApp/Views/ToolContainerView.swift Tests/WhyUtilsAppTests
git commit -m "feat: add Raycast-style file search view"
```

### Task 5: End-to-End Verification and Packaging

**Files:**
- Modify: `README.md` (feature note and shortcuts)
- Build artifact: `dist/whyutils-swift.app`

**Step 1: Write the failing test**

```text
N/A (verification task)
```

**Step 2: Run verification commands**

Run: `swift test`
Expected: all tests pass.

Run: `./scripts/build_app.sh`
Expected: app bundle rebuilt successfully.

**Step 3: Manual smoke checks**

- Launcher shows `Search Files`.
- Empty query shows `Recent Files`.
- Enter opens file.
- Cmd+Enter reveals in Finder.
- Esc returns launcher.

**Step 4: Commit**

```bash
git add README.md docs/plans/2026-03-03-search-files-feature.md
git commit -m "docs: add search files plan and usage notes"
```
