# WhyUtils Swift 代码上下文索引（低 Token 版）

更新时间：2026-04-05  
适用范围：`/Sources/WhyUtilsApp`、`/Tests/WhyUtilsAppTests`、`/scripts`

## 1. 文档目的

这份文档是后续改动时的“快速定位索引”，目标是：

- 少看全量代码，直接定位修改入口
- 减少后续沟通 token 消耗
- 给出当前架构全景和关键状态流

---

## 2. 先看这张“改哪里”速查表

| 想改什么 | 优先改这些文件 |
|---|---|
| 启动/面板显示逻辑 | `Sources/WhyUtilsApp/WhyUtilsApp.swift`, `Sources/WhyUtilsApp/AppPanel.swift`, `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift` |
| 启动器搜索和条目排序 | `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`, `Sources/WhyUtilsApp/Models/LauncherItem.swift`, `Sources/WhyUtilsApp/Models/ToolKind.swift` |
| 最近应用/应用搜索 | `Sources/WhyUtilsApp/Services/AppSearchService.swift`, `Sources/WhyUtilsApp/Models/AppSearchItem.swift`, `Sources/WhyUtilsApp/Views/LauncherView.swift` |
| 系统设置搜索与跳转（VPN/Wi-Fi 等） | `Sources/WhyUtilsApp/Services/SystemSettingsSearchService.swift`, `Sources/WhyUtilsApp/Models/SystemSettingItem.swift` |
| 全局热键行为 | `Sources/WhyUtilsApp/Hotkey/HotKeyConfiguration.swift`, `Sources/WhyUtilsApp/Hotkey/GlobalHotKeyManager.swift`, `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift` |
| 设置页（语言、热键、开机启动） | `Sources/WhyUtilsApp/Views/SettingsSheetView.swift`, `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`, `Sources/WhyUtilsApp/Localization/AppLanguage.swift`, `Sources/WhyUtilsApp/Services/LaunchAtLoginService.swift` |
| AI Assistant（聊天 UI、会话管理、规划、执行、确认） | `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`, `Sources/WhyUtilsApp/ViewModels/AIChatWorkspaceStore.swift`, `Sources/WhyUtilsApp/Models/AIChatSessionModels.swift`, `Sources/WhyUtilsApp/Services/AI/*`, `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`, `Sources/WhyUtilsApp/Views/SettingsSheetView.swift` |
| 剪贴板历史采集/回贴 | `Sources/WhyUtilsApp/Services/ClipboardHistoryService.swift`, `Sources/WhyUtilsApp/Services/PasteAutomationService.swift`, `Sources/WhyUtilsApp/Views/Tools/ClipboardHistoryToolView.swift`, `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift` |
| Search Files（文件搜索） | `Sources/WhyUtilsApp/Services/FileSearchService.swift`, `Sources/WhyUtilsApp/Views/Tools/FileSearchToolView.swift`, `Sources/WhyUtilsApp/Models/ToolKind.swift` |
| JSON/时间戳/URL/Base64/Hash/Regex 功能 | `Sources/WhyUtilsApp/Views/Tools/*ToolView.swift`, 对应 `Sources/WhyUtilsApp/Services/*.swift` |
| 打包/签名/公证 | `scripts/build_app.sh`, `scripts/notarize_release.sh` |

---

## 3. 架构总览（运行时）

### 3.1 启动链路

1. 入口 `WhyUtilsApp`（`@main`）只提供 `Settings` scene。  
2. `AppDelegate.applicationDidFinishLaunching` 创建 `RootView` + `WhyUtilsPanelController`。  
3. `AppCoordinator.shared.attachPanel(...)` 注入窗口对象。  
4. 启动后调用 `showLauncher(...)` 展示 launcher。  
5. 通过 startup watchdog + bootstrap retry 保证面板在前台可见。

关键文件：

- `Sources/WhyUtilsApp/WhyUtilsApp.swift`
- `Sources/WhyUtilsApp/AppPanel.swift`
- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`

### 3.2 UI 路由

- 全局路由在 `AppCoordinator.Route`：
  - `.launcher`
  - `.tool(ToolKind)`
- `RootView` 根据路由切换：
  - `LauncherView`
  - `ToolContainerView(tool:)`

关键文件：

- `Sources/WhyUtilsApp/Views/RootView.swift`
- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- `Sources/WhyUtilsApp/Views/ToolContainerView.swift`

### 3.3 启动器项目来源顺序

在 `AppCoordinator.launcherItems` 中拼装：

1. `SystemSettingsSearchService.search` 结果（仅 query 非空）
2. `AppSearchService.search` 结果（仅 query 非空）
3. `AI Assistant` 自然语言 handoff（仅 query 非空且 AI 已启用）
4. `GoogleSearch`（仅 query 非空）
5. 工具列表 `ToolKind`（始终存在，按匹配过滤）

---

## 4. 目录职责

### 4.1 `Sources/WhyUtilsApp`

- `WhyUtilsApp.swift`: AppDelegate 生命周期与启动展示稳定性
- `AppPanel.swift`: 自定义 `NSPanel` 行为（失焦自动隐藏逻辑）
- `ViewModels/AppCoordinator.swift`: 全局状态、路由、快捷键、launcher 行为
- `Views/*`: 页面和组件（Launcher、设置、工具页）
- `Views/Tools/*`: 各工具 UI
- `Services/*`: 业务与系统集成（搜索、编码、剪贴板、启动项等）
- `Hotkey/*`: Carbon 全局热键定义与注册
- `Localization/AppLanguage.swift`: 语言状态与中英文切换
- `Models/*`: launcher/tool/system setting/app 搜索模型

### 4.2 `Tests/WhyUtilsAppTests`

采用 `Swift Testing`（`@Test`），覆盖：

- 核心纯逻辑排序/匹配/条件判断
- 启动与面板判定逻辑
- 各服务关键分支

### 4.3 `scripts`

- `build_app.sh`: 构建 Universal `.app` + 可选签名 + zip
- `notarize_release.sh`: 公证流程
- `install_launch_agent.sh` / `uninstall_launch_agent.sh`: 脚本级开机启动兜底

---

## 5. 全局状态与持久化

### 5.1 `AppCoordinator` 关键状态

- `route`: 当前页面
- `query`: launcher 输入
- `highlightedItem`: launcher 当前高亮项
- `showSettings`: 设置弹窗是否显示
- `language`: 当前语言
- `aiDraftTask`: launcher 传给 AI Assistant 的自然语言任务
- `aiConfiguration`: AI 开关、baseURL、apiKey、model、accessMode
- `hotKeyConfiguration`: 热键配置
- `launchAtLoginEnabled`: 开机启动开关
- `clipboardHistory`: 剪贴板历史服务单例
- `appSearchVersion`: app search 数据变更版本号（驱动 UI 刷新）

### 5.2 UserDefaults key

- 语言：`whyutils.app.language`
- 热键：`whyutils.hotkey.configuration`
- AI 配置：`whyutils.ai.configuration`
- 剪贴板历史：`whyutils.clipboard.history`
- 最近应用：`whyutils.app-search.recent-apps`

---

## 6. 核心模块说明

### 6.1 启动和面板稳定性

文件：

- `Sources/WhyUtilsApp/WhyUtilsApp.swift`
- `Sources/WhyUtilsApp/AppPanel.swift`

关键点：

- `startupWatchdog` + `launchBootstrap` 反复校正面板可见/焦点状态
- `WhyUtilsPanel` 在 `resignMain/resignKey` 时可自动隐藏
- `suppressAutoHide(for:)` 用于短时抑制自动隐藏（避免 show 后瞬间被 hide）

### 6.2 Launcher 编排与键盘行为

文件：

- `Sources/WhyUtilsApp/Views/LauncherView.swift`
- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`
- `Sources/WhyUtilsApp/Models/LauncherItem.swift`

关键点：

- local key monitor 处理上下选择、回车打开、Esc 隐藏/关闭 settings
- `AppCoordinator.launcherKeyAction(...)` 是可测试的键位判定入口
- `openLauncherItem` 分发到 tool/system setting/app/google
- AI 已启用时，launcher 会额外注入 `LauncherItem.aiPrompt(query:)`
- `openAIAssistant(with:)` 会把自然语言任务写入 `aiDraftTask` 并切换到 `.tool(.aiAssistant)`

### 6.3 App 搜索（最近应用 + 全量索引）

文件：

- `Sources/WhyUtilsApp/Services/AppSearchService.swift`
- `Sources/WhyUtilsApp/Models/AppSearchItem.swift`

关键点：

- 监听 `NSWorkspace` 激活/启动/退出事件更新 recents
- query 非空时按需扫描 `/Applications`、`/System/Applications`、`~/Applications`
- 排序综合：
  - 名称匹配（exact/prefix/contains）
  - bundle/path 匹配
  - 运行态加分
  - 最近使用加分
- `shouldRefreshInstalledApplicationsIndex(...)` 控制是否重新索引

### 6.4 系统设置搜索与打开

文件：

- `Sources/WhyUtilsApp/Services/SystemSettingsSearchService.swift`

关键点：

- 内置 `entries` 维护关键词、symbol、URL candidates
- `search` 走评分匹配
- `open` 按 URL candidate 顺序尝试，失败再 fallback 打开系统设置主页
- VPN 在旧系统有 AppleScript 兼容路径

### 6.5 Search Files

文件：

- `Sources/WhyUtilsApp/Services/FileSearchService.swift`
- `Sources/WhyUtilsApp/Views/Tools/FileSearchToolView.swift`

关键点：

- 后端 `NSMetadataQuery`，scope 支持 user / thisMac
- 输入防抖（0.18s）
- 结果上限 200，去重并过滤隐藏/系统路径
- 工具页支持：
  - 上下键选中
  - `Enter` 打开
  - `Cmd+Enter` Finder 定位

### 6.6 剪贴板历史与回贴自动化

文件：

- `Sources/WhyUtilsApp/Services/ClipboardHistoryService.swift`
- `Sources/WhyUtilsApp/Services/PasteAutomationService.swift`
- `Sources/WhyUtilsApp/Views/Tools/ClipboardHistoryToolView.swift`
- `Sources/WhyUtilsApp/ViewModels/AppCoordinator.swift`（`pasteClipboardEntry`）

关键点：

- 历史采集：每 0.5s 轮询 pasteboard changeCount
- 支持文本和图片（图片以 PNG data 存储）
- 去重策略：相同内容移到前面，首项重复则跳过
- 回贴策略：
  - 优先 Accessibility 直接写入焦点元素
  - fallback `Cmd+V` CGEvent 或 AppleScript
  - 目标应用优先使用 lastExternalApp / frontmost external

### 6.7 其他工具与服务映射

### 6.7 AI Assistant

文件：

- `Sources/WhyUtilsApp/Views/Tools/AIAssistantToolView.swift`
- `Sources/WhyUtilsApp/ViewModels/AIChatWorkspaceStore.swift`
- `Sources/WhyUtilsApp/Models/AIChatSessionModels.swift`
- `Sources/WhyUtilsApp/Services/AI/AIAgentService.swift`
- `Sources/WhyUtilsApp/Services/AI/AIToolRegistry.swift`
- `Sources/WhyUtilsApp/Services/AI/OpenAICompatibleClient.swift`
- `Sources/WhyUtilsApp/Models/AIAgentTypes.swift`

关键点：

- 当前产品形态是 ChatGPT 风格双栏聊天工作区：
  - 左侧极简会话列表
  - 右侧消息流 + composer
  - tool traces / confirmation 内联到 assistant 消息里
- `AIChatWorkspaceStore` 负责：
  - 本地持久化会话
  - 当前会话选择
  - 新建 / 重命名 / 删除
  - 按 message id 增量更新流式消息
- `AIChatSessionModels` 定义持久化层：
  - `AIChatSession`
  - `AIChatMessageRecord`
  - `AIChatMessageRole`
- 标题规则：
  - 空会话默认显示 `New chat`
  - 第一条用户消息自动生成标题
  - 手动重命名后不再被自动标题覆盖
- 模型只负责“直聊 or tool plan”决策，真正执行由本地代码验证
- `AIToolRegistry` 维护可用工具白名单和是否需要确认
- `AIAgentService.submit` 流程：
  - 调 OpenAI 兼容接口决定 `message` 还是 `tool_plan`
  - 校验步数和工具合法性
  - 副作用动作先返回 `AIConfirmationRequest`
  - 安全动作直接执行并返回 `AIAgentRunResult`
- 流式行为：
  - UI 通过 `OpenAICompatibleClient.streamChat` 消费 SSE
  - `AIAssistantToolView` 持有当前 stream task，可 `Stop generating`
  - partial assistant content 直接写入 workspace store
- 权限模式定义在 `AIAgentTypes.AIAgentAccessMode`：
  - `standard`
  - `fullAccess`
  - `unrestricted`
- 当前 live executor 已接：
  - clipboard read/list
  - JSON validate/format/minify
  - URL / Base64
  - timestamp/date
  - regex find/replace preview
  - search apps / settings / files
  - open app / file / setting
  - paste clipboard entry

### 6.8 其他工具与服务映射

| Tool View | Service |
|---|---|
| `JSONToolView` | `JSONService` |
| `TimeToolView` | `TimeService` |
| `URLToolView` | `EncodingService.urlEncode/urlDecode` |
| `Base64ToolView` | `EncodingService.base64Encode/base64Decode` |
| `HashToolView` | `HashService` |
| `RegexToolView` | `RegexService` |

公共组件：

- `Sources/WhyUtilsApp/Views/Tools/ToolComponents.swift`

---

## 7. 常见改动攻略（按需求定位）

### 7.1 新增一个工具页

1. 在 `Models/ToolKind.swift` 新增 case + title/subtitle/symbol/matches。  
2. 新建 `Views/Tools/NewToolView.swift`。  
3. 在 `Views/ToolContainerView.swift` 的 switch 里接入。  
4. 如需新逻辑，在 `Services/` 新建对应 service。  
5. 补测试（至少 `ToolKind` 与路由入口相关）。

### 7.2 调整 launcher 排序或候选源

1. 先改 `AppCoordinator.launcherItems`（候选源顺序）。  
2. 若是 app 搜索权重，改 `AppSearchService.matchScore/sort/recencyBonus`。  
3. 运行 `AppSearchServiceTests` + `LauncherSearchFilesTests`。

### 7.3 调整 AI Assistant 配置或可用工具

1. 改 `Services/AI/AIToolRegistry.swift` 的工具白名单与确认标记。  
2. 改 `Services/AI/AIAgentService.swift` 的 prompt、校验和 live executor。  
3. 改 `ViewModels/AIChatWorkspaceStore.swift` 的会话 / 消息状态流。  
4. 改 `Views/Tools/AIAssistantToolView.swift` 的会话布局、消息气泡和 composer。  
5. 改 `Views/SettingsSheetView.swift` / `ViewModels/AppCoordinator.swift` 的配置项持久化。  
6. 运行 `AIChatSessionModelsTests`、`AIChatWorkspaceStoreTests`、`AIAgentTypesTests`、`AIAgentServiceTests`、`OpenAICompatibleClientTests`。

### 7.4 调整全局热键默认值或限制

1. 改 `HotKeyConfiguration.default`。  
2. 若新增按键，改 `HotKeyKey`（包含 keyCode/title）。  
3. 验证 `GlobalHotKeyManager.register` 行为。  
4. 确认设置页 `SettingsSheetView` picker 可显示新按键。

### 7.4 调整开机启动行为

1. 改 `LaunchAtLoginService`（plist 内容、路径、load/unload）。  
2. 如需脚本同步，改 `scripts/install_launch_agent.sh`。  
3. 跑 `LaunchAtLoginServiceTests`。

### 7.5 调整粘贴回贴稳定性

1. `PasteAutomationService` 里改 target 选择和 fallback 顺序。  
2. 若影响提示文案，改返回 message。  
3. 回归 `PasteAutomationServiceTests`，再做手动 smoke（权限相关）。

---

## 8. 测试覆盖地图

| 测试文件 | 关注点 |
|---|---|
| `AppSearchServiceTests.swift` | app 索引刷新条件、匹配评分、排序 |
| `FileSearchServiceTests.swift` | 搜索 scope、路径过滤、结果排序 |
| `LauncherSearchFilesTests.swift` | launcher 中 Search Files/系统设置条目行为 |
| `KeyboardNavigationTests.swift` | launcher 键盘逻辑（Esc/Enter/上下） |
| `PasteAutomationServiceTests.swift` | 粘贴目标选择、fallback 通道策略 |
| `ClipboardHistoryServiceTests.swift` | 去重/前置/容量裁剪 |
| `SystemSettingsSearchServiceTests.swift` | 设置项检索与老系统 VPN 分支 |
| `TimeServiceTests.swift` | 时间戳解析、UTC 解释、live snapshot |
| `AppPanelBehaviorTests.swift` | 面板隐藏判定 |
| `InitialLaunchPresentationTests.swift` | 启动展示条件和 bootstrap 终止条件 |
| `AppCoordinatorPanelRecoveryTests.swift` | 面板恢复条件 |
| `AppLanguageTests.swift` | 语言默认值与持久化 |
| `LaunchAtLoginServiceTests.swift` | plist 安装路径选择 |
| `GoogleSearchServiceTests.swift` | URL 构建 |
| `LaunchDiagnosticsLoggerTests.swift` | 日志路径与格式 |

常用命令：

- 全量：`swift test`
- 单测：`swift test --filter AppSearchServiceTests`

---

## 9. 风险点与修改注意事项

- 面板显示链路有多处“重复兜底”（watchdog/bootstrap/reopen），改显示逻辑时容易互相打架。  
- 粘贴自动化强依赖系统权限（Accessibility/Automation），测试通过不代表真实机器全通过。  
- `AppSearchService` 使用后台索引队列 + 主线程回写，改并发逻辑时要保持 `@MainActor` 边界。  
- `FileSearchService` 基于 `NSMetadataQuery` 通知，改监听时要注意 start/stop 与 observer 生命周期。  
- 当前很多文案是中英直接写在代码中（`coordinator.localized(...)`），非统一资源文件。

---

## 10. 后续让 AI 改代码时的低 Token 提问模板

可直接按下面格式提需求（会比“先让 AI 读全仓”省很多 token）：

```text
基于 docs/CODEBASE_CONTEXT.md：
我要改 [功能点]。
优先改 [文件A, 文件B]。
不改 [文件C]。
验收标准：
1) ...
2) ...
请直接实现并运行相关测试。
```

---

## 11. 维护规则

每次结构性改动后更新本文件的以下部分：

- 第 2 节速查表
- 第 6 节模块说明
- 第 8 节测试覆盖地图

这样后续所有迭代都能继续低 token 工作。
