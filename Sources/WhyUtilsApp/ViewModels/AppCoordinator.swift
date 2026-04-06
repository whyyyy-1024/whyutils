import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    enum Route: Equatable {
        case launcher
        case tool(ToolKind)
    }

    @Published var route: Route = .launcher
    @Published var query: String = ""
    @Published var highlightedItem: LauncherItem = .tool(.clipboard)
    @Published var showSettings: Bool = false
    @Published var settingsMessage: String?
    @Published var language: AppLanguage
    @Published var aiDraftTask: String = ""
    @Published private(set) var pasteTargetAppName: String = "Current App"

    @Published private(set) var aiConfiguration: AIConfiguration
    @Published private(set) var hotKeyConfiguration: HotKeyConfiguration
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var clipboardHistory = ClipboardHistoryService.shared
    @Published private(set) var appSearchVersion: Int = 0

    enum LauncherKeyAction: Equatable {
        case passThrough
        case selectNext
        case selectPrev
        case openHighlighted
        case hideLauncher
        case closeSettings
    }

    private let aiConfigurationStorageKey = "whyutils.ai.configuration"
    private let hotKeyStorageKey = "whyutils.hotkey.configuration"
    private let appSearchService: AppSearchService
    private var hotKeyManager: GlobalHotKeyManager?
    private var lastExternalApp: NSRunningApplication?
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        LaunchDiagnosticsLogger.log("AppCoordinator.init begin")
        let loadedLanguage = AppLanguage.load()
        let loadedAIConfiguration = Self.loadAIConfiguration(key: aiConfigurationStorageKey)
        let loadedHotKey = Self.loadHotKeyConfiguration(key: hotKeyStorageKey)
        let launchAtLogin = LaunchAtLoginService.isEnabled()
        let appSearch = AppSearchService.shared
        language = loadedLanguage
        aiConfiguration = loadedAIConfiguration
        hotKeyConfiguration = loadedHotKey
        launchAtLoginEnabled = launchAtLogin
        appSearchService = appSearch
        LaunchDiagnosticsLogger.log("AppCoordinator.init language loaded=\(loadedLanguage.rawValue)")
        LaunchDiagnosticsLogger.log("AppCoordinator.init ai enabled=\(loadedAIConfiguration.isEnabled)")
        LaunchDiagnosticsLogger.log("AppCoordinator.init hotKey loaded=\(loadedHotKey.display)")
        LaunchDiagnosticsLogger.log("AppCoordinator.init launchAtLoginEnabled=\(launchAtLogin)")

        hotKeyManager = GlobalHotKeyManager { [weak self] in
            Task { @MainActor in
                self?.toggleLauncher()
            }
        }
        LaunchDiagnosticsLogger.log("AppCoordinator.init hotKey manager created")

        DispatchQueue.main.async { [weak self] in
            self?.registerGlobalHotKeyAfterLaunch()
        }

        NotificationCenter.default.publisher(for: AppSearchService.dataDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appSearchVersion &+= 1
            }
            .store(in: &cancellables)
        LaunchDiagnosticsLogger.log("AppCoordinator.init end")
    }

    nonisolated static func shouldHandleEscape(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == 53 else { return false }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) || flags.contains(.shift) {
            return false
        }
        return true
    }

    nonisolated static func launcherKeyAction(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isSettingsPresented: Bool
    ) -> LauncherKeyAction {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return .passThrough
        }

        if isSettingsPresented {
            if keyCode == 53 {
                return .closeSettings
            }
            return .passThrough
        }

        switch keyCode {
        case 125:
            return .selectNext
        case 126:
            return .selectPrev
        case 36, 76:
            return .openHighlighted
        case 53:
            return .hideLauncher
        default:
            return .passThrough
        }
    }

    nonisolated static func shouldRecoverPanel(currentPanelMissing: Bool, discoveredPanelCount: Int) -> Bool {
        currentPanelMissing && discoveredPanelCount > 0
    }

    var filteredTools: [ToolKind] {
        let tools = ToolKind.allCases.filter { $0.matches(query, language: language) }
        if tools.isEmpty { return ToolKind.allCases }
        return tools
    }

    var launcherItems: [LauncherItem] {
        var items: [LauncherItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let settingsItems = SystemSettingsSearchService.search(
                query: trimmed,
                limit: 8
            ).map { LauncherItem.systemSetting($0) }
            let appItems = appSearchService.search(
                query: trimmed,
                limit: 50
            ).map { LauncherItem.app($0) }
            items.append(contentsOf: settingsItems)
            items.append(contentsOf: appItems)
            if aiConfiguration.isEnabled {
                items.append(.aiPrompt(query: trimmed))
            }
            items.append(.googleSearch(query: trimmed))
        }
        items.append(contentsOf: filteredTools.map { .tool($0) })
        return items
    }

    func attachPanel(_ panel: NSPanel) {
        self.panel = panel
        configureWindow(panel)
        LaunchDiagnosticsLogger.log(
            "attachPanel visible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)"
        )
    }

    func showLauncher(resetState: Bool = false) {
        rememberCurrentExternalApp()
        LaunchDiagnosticsLogger.log(
            "showLauncher start resetState=\(resetState) appActive=\(NSApp.isActive)"
        )
        if resetState {
            route = .launcher
            query = ""
            highlightedItem = launcherItems.first ?? .tool(.clipboard)
        }

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        if let panel = recoverPanelIfNeeded() {
            LaunchDiagnosticsLogger.log(
                "showLauncher before show panelVisible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)"
            )
            configureWindow(panel)
            panel.setContentSize(WhyUtilsPanelController.panelSize)
            centerWindowOnMouseScreen(panel)
            (panel as? WhyUtilsPanel)?.suppressAutoHide(for: 1.2)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            LaunchDiagnosticsLogger.log(
                "showLauncher after show panelVisible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)"
            )
        } else {
            let panelWindowCount = NSApp.windows.compactMap { $0 as? WhyUtilsPanel }.count
            LaunchDiagnosticsLogger.log(
                "showLauncher no panel resolved; NSApp.windows=\(NSApp.windows.count) panelWindows=\(panelWindowCount)"
            )
        }
    }

    func toggleLauncher() {
        let activePanel = recoverPanelIfNeeded()
        LaunchDiagnosticsLogger.log(
            "toggleLauncher panelVisible=\(activePanel?.isVisible ?? false) appActive=\(NSApp.isActive)"
        )
        if let activePanel, activePanel.isVisible {
            activePanel.orderOut(nil)
            NSApp.hide(nil)
            LaunchDiagnosticsLogger.log("toggleLauncher hide launcher")
            return
        }
        showLauncher(resetState: false)
    }

    func selectTool(_ tool: ToolKind) {
        route = .tool(tool)
        highlightedItem = .tool(tool)
    }

    func openAIAssistant(with task: String) {
        aiDraftTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        route = .tool(.aiAssistant)
        highlightedItem = .tool(.aiAssistant)
    }

    func backToLauncher() {
        route = .launcher
    }

    func selectNextInLauncher() {
        let list = launcherItems
        guard !list.isEmpty else { return }
        guard let idx = list.firstIndex(of: highlightedItem) else {
            highlightedItem = list[0]
            return
        }
        highlightedItem = list[(idx + 1) % list.count]
    }

    func selectPrevInLauncher() {
        let list = launcherItems
        guard !list.isEmpty else { return }
        guard let idx = list.firstIndex(of: highlightedItem) else {
            highlightedItem = list[0]
            return
        }
        highlightedItem = list[(idx - 1 + list.count) % list.count]
    }

    func openHighlightedTool() {
        openLauncherItem(highlightedItem)
    }

    func openLauncherItem(_ item: LauncherItem) {
        switch item {
        case .aiPrompt(let query):
            openAIAssistant(with: query)
        case .tool(let tool):
            selectTool(tool)
        case .systemSetting(let setting):
            settingsMessage = SystemSettingsSearchService.open(setting, language: language)
            NSApp.hide(nil)
        case .app(let app):
            let opened = appSearchService.open(app)
            if !opened {
                settingsMessage = localized(
                    "Failed to open \(app.name)",
                    "打开 \(app.name) 失败"
                )
            }
            NSApp.hide(nil)
        case .googleSearch(let query):
            settingsMessage = GoogleSearchService.searchInChrome(query: query)
            NSApp.hide(nil)
        }
    }

    func pasteClipboardEntry(_ entry: ClipboardHistoryEntry) -> String {
        rememberCurrentExternalApp()
        let ownBundleID = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostExternal: NSRunningApplication? = {
            guard let frontmost else { return nil }
            if frontmost.bundleIdentifier == ownBundleID { return nil }
            return frontmost
        }()
        let target = lastExternalApp ?? frontmostExternal

        panel?.orderOut(nil)
        NSApp.deactivate()
        NSApp.hide(nil)
        return PasteAutomationService.pasteToApplication(entry: entry, targetApp: target)
    }

    func updateHotKey(key: HotKeyKey? = nil, command: Bool? = nil, shift: Bool? = nil, option: Bool? = nil, control: Bool? = nil) {
        var next = hotKeyConfiguration
        if let key { next.key = key }
        if let command { next.command = command }
        if let shift { next.shift = shift }
        if let option { next.option = option }
        if let control { next.control = control }

        next = next.normalized
        hotKeyConfiguration = next
        saveHotKeyConfiguration(next, key: hotKeyStorageKey)
        hotKeyManager?.register(next)
        settingsMessage = localized("Hotkey updated to \(next.display)", "热键已更新为 \(next.display)")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled()
            settingsMessage = launchAtLoginEnabled
                ? localized("Launch at login enabled", "已启用开机启动")
                : localized("Launch at login disabled", "已关闭开机启动")
        } catch {
            settingsMessage = localized(
                "Failed to configure launch at login: \(error.localizedDescription)",
                "设置开机启动失败: \(error.localizedDescription)"
            )
        }
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        AppLanguage.save(language)
        settingsMessage = localized(
            "Language switched to \(language.displayName)",
            "语言已切换为 \(language.displayName)"
        )
    }

    func updateAIConfiguration(
        isEnabled: Bool? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        model: String? = nil,
        accessMode: AIAgentAccessMode? = nil
    ) {
        var next = aiConfiguration
        if let isEnabled { next.isEnabled = isEnabled }
        if let baseURL { next.baseURL = baseURL }
        if let apiKey { next.apiKey = apiKey }
        if let model { next.model = model }
        if let accessMode { next.accessMode = accessMode }
        aiConfiguration = next
        saveAIConfiguration(next, key: aiConfigurationStorageKey)
    }

    func localized(_ english: String, _ chinese: String) -> String {
        L10n.text(english, chinese, language: language)
    }

    private static func loadAIConfiguration(key: String) -> AIConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return AIConfiguration()
        }
        do {
            return try JSONDecoder().decode(AIConfiguration.self, from: data)
        } catch {
            return AIConfiguration()
        }
    }

    private static func loadHotKeyConfiguration(key: String) -> HotKeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return .default
        }
        do {
            let value = try JSONDecoder().decode(HotKeyConfiguration.self, from: data)
            return value.normalized
        } catch {
            return .default
        }
    }

    private func saveAIConfiguration(_ value: AIConfiguration, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func saveHotKeyConfiguration(_ value: HotKeyConfiguration, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func registerGlobalHotKeyAfterLaunch() {
        LaunchDiagnosticsLogger.log("registerGlobalHotKeyAfterLaunch start")
        hotKeyManager?.register(hotKeyConfiguration)
        LaunchDiagnosticsLogger.log("registerGlobalHotKeyAfterLaunch end")
    }

    private func rememberCurrentExternalApp() {
        let ownBundleID = Bundle.main.bundleIdentifier
        var app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier == ownBundleID {
            app = NSWorkspace.shared.menuBarOwningApplication
        }
        guard let app else { return }
        if app.bundleIdentifier == ownBundleID { return }
        lastExternalApp = app
        pasteTargetAppName = app.localizedName ?? localized("Current App", "当前应用")
        }

    private func recoverPanelIfNeeded() -> NSPanel? {
        if let panel {
            return panel
        }

        let discovered = NSApp.windows.compactMap { $0 as? WhyUtilsPanel }
        if Self.shouldRecoverPanel(currentPanelMissing: true, discoveredPanelCount: discovered.count),
           let recovered = discovered.first {
            panel = recovered
            LaunchDiagnosticsLogger.log(
                "recoverPanelIfNeeded recovered panel from windows discoveredCount=\(discovered.count)"
            )
            return recovered
        }
        return nil
    }

    private func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior.insert(.transient)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func centerWindowOnMouseScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let originX = screenFrame.midX - windowSize.width / 2
        let originY = screenFrame.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: round(originX), y: round(originY)))
    }
}
