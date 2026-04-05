# WhyUtils Recent App Search Design (方案2)

## Goal
- 在主 Launcher 中支持“最近应用 + 应用搜索 + 直接打开/切换”，交互接近 Raycast。

## UX
- 空搜索词：先显示 Recent Apps，再显示工具命令。
- 有搜索词：先显示匹配应用，再显示 Search Google 与工具命令。
- Enter/双击：若应用已运行则切换到该应用，否则启动应用。

## Data Sources
- 本地最近历史：监听 `NSWorkspace.didActivateApplicationNotification`，写入 UserDefaults。
- 当前运行应用：`NSWorkspace.shared.runningApplications`。
- 全量应用索引：按需扫描 `/Applications`、`/System/Applications`、`~/Applications`。

## Ranking
- 空搜索词：按最近使用时间降序，再按是否运行排序。
- 有搜索词：名称完全匹配/前缀/包含优先，bundle id 与路径匹配次之；运行态与最近使用加分。

## Architecture Changes
- 新增 `AppSearchService`：负责数据采集、索引、排序与打开应用。
- 新增 `AppSearchItem`：统一 app 搜索结果模型。
- 扩展 `LauncherItem` 增加 `app` 类型。
- `AppCoordinator` 组合应用结果到 `launcherItems`，并处理打开逻辑。
- `LauncherView` 行渲染支持应用图标与运行态标记。

## Validation
- 增加 `AppSearchServiceTests`：覆盖匹配评分与排序行为。
- 全量回归：`swift test -q` + `./scripts/build_app.sh`。
