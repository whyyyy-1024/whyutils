# whyutils SwiftUI (macOS)

Raycast 风格的 SwiftUI 版本，支持：

- 全局快捷键唤醒（默认 `⌘⇧Space`，可在设置中修改）
- 启动器内搜索并选择工具
- 8 个工具页：剪贴板历史、Search Files、JSON、时间戳、URL、Base64、哈希、正则
- 设置面板：自定义热键、开机启动开关
- 全局语言：English（默认）/ 中文

## 运行（开发）

```bash
cd /Users/wanghaoyu/Documents/whyutils/whyutils-swift
swift run whyutils-swift
```

## 打包为 .app

```bash
cd /Users/wanghaoyu/Documents/whyutils/whyutils-swift
./scripts/build_app.sh
open /Users/wanghaoyu/Documents/whyutils/whyutils-swift/dist/whyutils-swift.app
```

- `build_app.sh` 产物适合本机使用（默认 ad-hoc 签名）。
- 若要发给同事直接双击打开，请走“签名+公证”流程（见下方）。

### 权限稳定说明（辅助功能/自动化）

- 默认构建会使用 **ad-hoc 签名**（保证 `.app` 可直接双击启动）。
- 若需要签名，请使用固定证书身份（推荐）：

```bash
WHYUTILS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
```

- 若想完全跳过签名（部分系统可能无法双击打开）：

```bash
WHYUTILS_SIGN_MODE=none ./scripts/build_app.sh
```

- 注意：ad-hoc 每次构建会变化，可能导致辅助功能/自动化权限被系统视为新应用。

### 分发给同事（Developer ID + Notarization）

> 只有完成公证（notarization）的包，才最稳定地通过同事机器上的 Gatekeeper 检查。

1) 先在本机保存 notarytool 凭据（只需一次）：

```bash
xcrun notarytool store-credentials "whyutils-notary" \
  --apple-id "<APPLE_ID>" \
  --team-id "<TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

2) 生成可分发版本（签名 + 公证 + stapler）：

```bash
cd /Users/wanghaoyu/Documents/whyutils/whyutils-swift
WHYUTILS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WHYUTILS_NOTARY_PROFILE="whyutils-notary" \
./scripts/notarize_release.sh
```

3) 分发 `dist/whyutils-swift.zip` 给同事。

### 同事打不开时的快速自检

在同事机器执行：

```bash
spctl --assess --type execute -vv /path/to/whyutils-swift.app
```

如果显示 `Notary Ticket Missing`，说明是未公证包。

### 开机启动说明

- 优先写入 `~/Library/LaunchAgents`。
- 如果该目录不可写，会自动回退到 `~/Library/Application Support/whyutils/LaunchAgents`。

### 架构兼容说明

- 默认会构建 `arm64 + x86_64` Universal 包，兼容 Apple 芯片和 Intel Mac。
- 可通过环境变量覆盖：

```bash
WHYUTILS_ARCHS="arm64" ./scripts/build_app.sh
```

## 开机启动（脚本兜底）

```bash
cd /Users/wanghaoyu/Documents/whyutils/whyutils-swift
./scripts/install_launch_agent.sh
./scripts/uninstall_launch_agent.sh
```

## 快捷键

- `⌘⇧Space`（默认）全局唤醒/隐藏
- 启动器内 `↑/↓` 选择，`Enter` 打开
- 工具页 `Esc` 返回启动器
- Search Files 工具内：`Enter` 打开文件，`⌘Enter` 在 Finder 定位文件

## JSON bug 修复说明

JSON 操作失败时会同步刷新输出区为错误信息，不会再出现“状态报错但输出仍是旧成功结果”的不一致问题。
