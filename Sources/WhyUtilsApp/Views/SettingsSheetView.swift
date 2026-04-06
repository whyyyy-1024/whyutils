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
                    aiSection
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

    private var aiSection: some View {
        let enabled = Binding(
            get: { coordinator.aiConfiguration.isEnabled },
            set: { coordinator.updateAIConfiguration(isEnabled: $0) }
        )
        let baseURL = Binding(
            get: { coordinator.aiConfiguration.baseURL },
            set: { coordinator.updateAIConfiguration(baseURL: $0) }
        )
        let apiKey = Binding(
            get: { coordinator.aiConfiguration.apiKey },
            set: { coordinator.updateAIConfiguration(apiKey: $0) }
        )
        let model = Binding(
            get: { coordinator.aiConfiguration.model },
            set: { coordinator.updateAIConfiguration(model: $0) }
        )
        let accessMode = Binding(
            get: { coordinator.aiConfiguration.accessMode },
            set: { coordinator.updateAIConfiguration(accessMode: $0) }
        )

        return settingsCard(title: coordinator.localized("AI Assistant", "AI 助手")) {
            Toggle(coordinator.localized("Enable OpenAI-compatible AI Assistant", "启用 OpenAI 兼容 AI 助手"), isOn: enabled)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Base URL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("https://api.openai.com/v1", text: baseURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(enabled.wrappedValue == false)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(enabled.wrappedValue == false)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("gpt-4.1-mini", text: model)
                    .textFieldStyle(.roundedBorder)
                    .disabled(enabled.wrappedValue == false)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(coordinator.localized("Access Mode", "权限模式"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("", selection: accessMode) {
                    Text(coordinator.localized("Standard", "标准")).tag(AIAgentAccessMode.standard)
                    Text("Full Access").tag(AIAgentAccessMode.fullAccess)
                    Text(coordinator.localized("Unrestricted", "无限制")).tag(AIAgentAccessMode.unrestricted)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(enabled.wrappedValue == false)
            }

            Text(accessModeDescription(accessMode.wrappedValue))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            if accessMode.wrappedValue != .standard {
                Text(coordinator.localized(
                    "Higher access modes expose shell execution and direct file operations to the model. Only enable them for trusted providers and keys.",
                    "更高权限模式会向模型开放 shell 执行和直接文件操作。仅在你信任当前模型供应商与密钥时开启。"
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            }
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

    private func accessModeDescription(_ mode: AIAgentAccessMode) -> String {
        switch mode {
        case .standard:
            return coordinator.localized(
                "Standard mode keeps the agent inside WhyUtils tools and asks before side-effect actions. Plans are limited to 3 steps.",
                "标准模式只允许使用 WhyUtils 内置工具，并在副作用动作前先确认。执行计划最多 3 步。"
            )
        case .fullAccess:
            return coordinator.localized(
                "Full Access adds shell, file, and URL tools, but still asks before side-effect actions. Plans are limited to 3 steps.",
                "Full Access 会开放 shell、文件和 URL 工具，但副作用动作仍会先确认。执行计划最多 3 步。"
            )
        case .unrestricted:
            return coordinator.localized(
                "Unrestricted mode allows direct chat plus shell, file, URL, app, and paste actions without confirmation. Plans can expand up to 8 steps.",
                "无限制模式允许直接聊天，并可无确认执行 shell、文件、URL、应用和粘贴动作。执行计划最多 8 步。"
            )
        }
    }
}
