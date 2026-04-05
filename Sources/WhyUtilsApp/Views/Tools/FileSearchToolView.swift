import AppKit
import SwiftUI

private enum FileSearchScopeOption: String, CaseIterable, Identifiable {
    case user
    case thisMac

    var id: String { rawValue }
}

struct FileSearchToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var service = FileSearchService.shared

    @State private var query: String = ""
    @State private var selectedScope: FileSearchScopeOption = .user
    @State private var selectedResultID: FileSearchResult.ID?
    @State private var keyMonitor: Any?
    @FocusState private var focusSearch: Bool

    private var activeScope: FileSearchScope {
        switch selectedScope {
        case .user:
            return .user(userName: NSUserName())
        case .thisMac:
            return .thisMac
        }
    }

    private var selectedResult: FileSearchResult? {
        guard let selectedResultID else { return service.results.first }
        return service.results.first(where: { $0.id == selectedResultID }) ?? service.results.first
    }

    private var scopeDisplayTitle: String {
        switch selectedScope {
        case .user:
            return coordinator.localized("User (\(NSUserName()))", "用户（\(NSUserName())）")
        case .thisMac:
            return coordinator.localized("This Mac", "这台 Mac")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                leftPane
                    .frame(width: 420)
                    .background(Color.whySidebarBackground)
                Divider()
                rightPane
            }
            Divider()
            actionBar
        }
        .onAppear {
            if !coordinator.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                query = coordinator.query
            }
            focusSearch = true
            runSearch()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
            service.stop()
        }
        .onChange(of: query) { _ in
            runSearch()
        }
        .onChange(of: selectedScope) { _ in
            runSearch()
        }
        .onChange(of: service.results) { _ in
            syncSelection()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                coordinator.backToLauncher()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .bold))
                    .padding(8)
                    .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(coordinator.localized("Search files...", "搜索文件..."), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .focused($focusSearch)
                    .onSubmit {
                        openSelection()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer(minLength: 10)

                Menu {
                    Button(coordinator.localized("User (\(NSUserName()))", "用户（\(NSUserName())）")) {
                        selectedScope = .user
                    }
                    Button(coordinator.localized("This Mac", "这台 Mac")) {
                        selectedScope = .thisMac
                    }
                } label: {
                HStack(spacing: 8) {
                    Text(scopeDisplayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(minWidth: 220, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.whyControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.whyPanelBorder.opacity(0.65), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.whyChromeBackground)
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? coordinator.localized("Recent Files", "最近文件")
                         : coordinator.localized("Files", "文件"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.horizontal, 14)

                    if service.results.isEmpty && service.isSearching {
                        Text(coordinator.localized("Searching...", "搜索中..."))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else if service.results.isEmpty {
                        Text(coordinator.localized("No files found", "未找到文件"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(service.results) { result in
                            FileSearchRow(
                                result: result,
                                selected: result.id == selectedResult?.id,
                                onSelect: {
                                    selectedResultID = result.id
                                },
                                onOpen: {
                                    selectedResultID = result.id
                                    service.open(result)
                                }
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let result = selectedResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(coordinator.localized("Preview", "预览"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.fileName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .lineLimit(2)
                                Text(result.parentPath)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.whyCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(spacing: 0) {
                            let items = metadataRows(for: result)
                            ForEach(Array(items.enumerated()), id: \.offset) { index, pair in
                                HStack {
                                    Text(pair.0)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(pair.1)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                if index < items.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(Color.whyCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(16)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(coordinator.localized("No Selection", "未选择文件"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(coordinator.localized("Select a file from the left list", "请在左侧选择一个文件"))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Label(coordinator.localized("Search Files", "搜索文件"), systemImage: "magnifyingglass.circle.fill")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(coordinator.localized("Open", "打开")) {
                openSelection()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))

            Text("↩")
                .foregroundStyle(.secondary)

            Button(coordinator.localized("Reveal", "定位")) {
                revealSelection()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))

            Text("⌘↩")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(coordinator.localized("Actions", "操作"))
                .foregroundStyle(.secondary)
            Text("⌘K")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.whyChromeBackground)
    }

    private func runSearch() {
        service.update(scope: activeScope, queryText: query)
    }

    private func syncSelection() {
        if let selectedResult, service.results.contains(where: { $0.id == selectedResult.id }) {
            selectedResultID = selectedResult.id
            return
        }
        selectedResultID = service.results.first?.id
    }

    private func moveSelection(_ delta: Int) {
        guard !service.results.isEmpty else { return }
        guard
            let selectedResult,
            let index = service.results.firstIndex(where: { $0.id == selectedResult.id })
        else {
            selectedResultID = service.results.first?.id
            return
        }

        let next = (index + delta + service.results.count) % service.results.count
        selectedResultID = service.results[next].id
    }

    private func openSelection() {
        guard let selectedResult else { return }
        service.open(selectedResult)
    }

    private func revealSelection() {
        guard let selectedResult else { return }
        service.reveal(selectedResult)
    }

    private func metadataRows(for result: FileSearchResult) -> [(String, String)] {
        let typeDescription = fileTypeDescription(for: result.url)
        return [
            (coordinator.localized("Name", "名称"), result.fileName),
            (coordinator.localized("Where", "位置"), collapseHome(result.parentPath)),
            (coordinator.localized("Type", "类型"), typeDescription),
            (coordinator.localized("Size", "大小"), formatSize(result.fileSize)),
            (coordinator.localized("Created", "创建时间"), formatDate(result.createdAt)),
            (coordinator.localized("Modified", "修改时间"), formatDate(result.modifiedAt))
        ]
    }

    private func fileTypeDescription(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey])
        return values?.localizedTypeDescription ?? coordinator.localized("File", "文件")
    }

    private func collapseHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }

    private func formatSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "-" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 125:
                if !flags.contains(.command) {
                    moveSelection(1)
                    return nil
                }
            case 126:
                if !flags.contains(.command) {
                    moveSelection(-1)
                    return nil
                }
            case 36, 76:
                if flags.contains(.command) {
                    revealSelection()
                } else {
                    openSelection()
                }
                return nil
            case 53:
                coordinator.backToLauncher()
                return nil
            default:
                break
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct FileSearchRow: View {
    let result: FileSearchResult
    let selected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var hovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        if selected {
            return colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
        }
        if hovering {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
        return .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.fileName)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Text(result.parentPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .highPriorityGesture(TapGesture(count: 2).onEnded {
            onOpen()
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            onSelect()
        })
    }
}
