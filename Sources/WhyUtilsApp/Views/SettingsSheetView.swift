import SwiftUI

struct SettingsSheetView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    let onClose: () -> Void

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    languageSection
                    hotkeySection
                    launchAtLoginSection
                    if let message = coordinator.settingsMessage, !message.isEmpty {
                        statusSection(message)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.whyPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.whyPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
    }

    private var header: some View {
        HStack {
            Text(coordinator.localized("Settings", "设置"))
                .font(.system(size: 19, weight: .semibold))
            Spacer()
            Button(coordinator.localized("Close", "关闭")) {
                onClose()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.whyChromeBackground)
    }

    private var languageSection: some View {
        settingsCard(title: coordinator.localized("Language", "语言")) {
            HStack {
                Text(coordinator.localized("App Language", "应用语言"))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { coordinator.language },
                    set: { coordinator.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
        }
    }

    private var hotkeySection: some View {
        settingsCard(title: coordinator.localized("Global Hotkey", "全局唤醒热键")) {
            HStack {
                Text(coordinator.localized("Key", "按键"))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { coordinator.hotKeyConfiguration.key },
                    set: { coordinator.updateHotKey(key: $0) }
                )) {
                    ForEach(HotKeyKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            Divider()

            Toggle(coordinator.localized("Command (⌘)", "命令 (⌘)"), isOn: Binding(
                get: { coordinator.hotKeyConfiguration.command },
                set: { coordinator.updateHotKey(command: $0) }
            ))
            Toggle(coordinator.localized("Shift (⇧)", "Shift (⇧)"), isOn: Binding(
                get: { coordinator.hotKeyConfiguration.shift },
                set: { coordinator.updateHotKey(shift: $0) }
            ))
            Toggle(coordinator.localized("Option (⌥)", "Option (⌥)"), isOn: Binding(
                get: { coordinator.hotKeyConfiguration.option },
                set: { coordinator.updateHotKey(option: $0) }
            ))
            Toggle(coordinator.localized("Control (⌃)", "Control (⌃)"), isOn: Binding(
                get: { coordinator.hotKeyConfiguration.control },
                set: { coordinator.updateHotKey(control: $0) }
            ))

            Divider()

            HStack {
                Text(coordinator.localized("Current Hotkey", "当前热键"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(coordinator.hotKeyConfiguration.display)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
        }
    }

    private var launchAtLoginSection: some View {
        settingsCard(title: coordinator.localized("Launch at Login", "开机启动")) {
            Toggle(coordinator.localized("Launch whyutils automatically at login", "登录时自动启动 whyutils"), isOn: Binding(
                get: { coordinator.launchAtLoginEnabled },
                set: { coordinator.setLaunchAtLogin($0) }
            ))
            Text(coordinator.localized(
                "If installed as .app, it can launch by double-click and auto-run at login.",
                "安装在 .app 内时可实现双击启动和开机自动运行。"
            ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func statusSection(_ message: String) -> some View {
        settingsCard(title: coordinator.localized("Status", "状态")) {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(14)
        .background(Color.whyCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
