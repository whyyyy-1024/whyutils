import AppKit
import SwiftUI

struct LauncherView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @FocusState private var focusSearch: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(coordinator.localized("Search for apps and commands...", "搜索应用和命令..."), text: $coordinator.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .focused($focusSearch)
                    .onSubmit {
                        coordinator.openHighlightedTool()
                    }

                Spacer(minLength: 8)

                Button {
                    coordinator.showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .padding(8)
                        .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.whyChromeBackground)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(coordinator.launcherItems) { item in
                        LauncherRowView(
                            item: item,
                            language: coordinator.language,
                            active: item == coordinator.highlightedItem,
                            onSelect: {
                                coordinator.highlightedItem = item
                            },
                            onOpen: {
                                coordinator.openLauncherItem(item)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }

            Divider()

            HStack(spacing: 18) {
                Text(coordinator.localized("↑↓ Select", "↑↓ 选择"))
                Text(coordinator.localized("Enter Open", "Enter 打开"))
                Text(coordinator.localized("Double Click Open", "双击 打开"))
                Text(coordinator.localized("Esc Back", "Esc 返回"))
                Text(coordinator.localized("\(coordinator.hotKeyConfiguration.display) Toggle", "\(coordinator.hotKeyConfiguration.display) 唤醒"))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(Color.whyChromeBackground)
        }
        .overlay(alignment: .center) {
            if coordinator.showSettings {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture {
                            coordinator.showSettings = false
                        }

                    SettingsSheetView {
                        coordinator.showSettings = false
                    }
                    .environmentObject(coordinator)
                    .frame(width: 560, height: 460)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            focusSearch = true
            if coordinator.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let first = coordinator.launcherItems.first {
                coordinator.highlightedItem = first
            } else if !coordinator.launcherItems.contains(coordinator.highlightedItem),
                      let first = coordinator.launcherItems.first {
                coordinator.highlightedItem = first
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: coordinator.query) { _ in
            let items = coordinator.launcherItems
            if coordinator.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               let first = items.first {
                coordinator.highlightedItem = first
                return
            }
            if !items.contains(coordinator.highlightedItem), let first = items.first {
                coordinator.highlightedItem = first
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .down: coordinator.selectNextInLauncher()
            case .up: coordinator.selectPrevInLauncher()
            default: break
            }
        }
        .onExitCommand {
            NSApp.hide(nil)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch AppCoordinator.launcherKeyAction(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isSettingsPresented: coordinator.showSettings
            ) {
            case .selectNext:
                coordinator.selectNextInLauncher()
                return nil
            case .selectPrev:
                coordinator.selectPrevInLauncher()
                return nil
            case .openHighlighted:
                coordinator.openHighlightedTool()
                return nil
            case .hideLauncher:
                NSApp.hide(nil)
                return nil
            case .closeSettings:
                coordinator.showSettings = false
                return nil
            case .passThrough:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct LauncherRowView: View {
    let item: LauncherItem
    let language: AppLanguage
    let active: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var hovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        if active {
            return Color.teal
        }
        if hovering {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        }
        return Color.clear
    }

    private var titleColor: Color {
        active ? .white : .primary
    }

    private var subtitleColor: Color {
        active ? Color.white.opacity(0.85) : .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title(in: language))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(titleColor)
                Text(item.subtitle(in: language))
                    .font(.system(size: 13))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            Spacer()
            trailingIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hovering && !active ? Color.teal.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering in
            hovering = isHovering
            if isHovering {
                onSelect()
            }
        }
        .animation(.easeInOut(duration: 0.12), value: active)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .onTapGesture {
            onSelect()
            onOpen()
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .app(let app):
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 28, alignment: .center)
        case .googleSearch, .systemSetting, .tool:
            Image(systemName: item.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? .white : .teal)
                .frame(width: 28)
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch item {
        case .app(let app):
            if app.isRunning {
                Text(language == .english ? "Running" : "运行中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? Color.white.opacity(0.9) : .secondary)
            } else {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? Color.white.opacity(0.8) : .secondary)
            }
        case .systemSetting:
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? Color.white.opacity(0.8) : .secondary)
        case .googleSearch:
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? Color.white.opacity(0.8) : .secondary)
        case .tool:
            Image(systemName: "return")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? Color.white.opacity(0.8) : .secondary)
        }
    }
}
