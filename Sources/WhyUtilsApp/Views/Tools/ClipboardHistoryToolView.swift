import AppKit
import SwiftUI

struct ClipboardHistoryToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var query: String = ""
    @State private var selectedEntryID: ClipboardHistoryEntry.ID?
    @State private var status: String = "Double-click an item to paste back to the previous app"
    @State private var isError: Bool = false
    @State private var keyMonitor: Any?
    @FocusState private var focusSearch: Bool

    private var filteredEntries: [ClipboardHistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return coordinator.clipboardHistory.entries.filter { entry in
            let normalized = entry.searchableText
            return q.isEmpty || normalized.contains(q)
        }
    }

    private var selectedEntry: ClipboardHistoryEntry? {
        guard let selectedEntryID else { return filteredEntries.first }
        return filteredEntries.first { $0.id == selectedEntryID } ?? filteredEntries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftPane
                    .frame(width: 340)
                    .background(Color.whySidebarBackground)
                Divider()
                rightPane
            }
            Divider()
            actionBar
        }
        .onAppear {
            focusSearch = true
            if selectedEntry == nil {
                selectedEntryID = filteredEntries.first?.id
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _ in
            syncSelection()
        }
        .onChange(of: coordinator.clipboardHistory.entries) { _ in
            syncSelection()
        }
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    coordinator.backToLauncher()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                        .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(t("Type to filter entries...", "输入以筛选历史项..."), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .medium))
                    .focused($focusSearch)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Text(t("Today", "今天"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.horizontal, 14)

                    ForEach(filteredEntries) { entry in
                        ClipboardListRow(
                            entry: entry,
                            selected: entry.id == selectedEntry?.id,
                            emptyText: t("(empty)", "(空)"),
                            imageSummaryPrefix: t("Image", "图片"),
                            onSelect: {
                                selectedEntryID = entry.id
                            },
                            onPaste: {
                                selectedEntryID = entry.id
                                pasteSelectedEntry()
                            }
                        )
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entry = selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Group {
                            Text(t("Preview", "预览"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if entry.kind == .image, let image = nsImage(from: entry) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 300, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.whyCardBackground)
                                    )
                            } else {
                                Text(entry.text)
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.whyCardBackground)
                                    )
                            }
                        }

                        VStack(spacing: 0) {
                            let items = [
                                (t("Source", "来源"), coordinator.pasteTargetAppName),
                                (t("Content type", "内容类型"), entry.kind == .image ? t("Image", "图片") : t("Text", "文本")),
                                (t("Characters", "字符数"), "\(entry.text.count)"),
                                (t("Lines", "行数"), "\(entry.text.split(separator: "\n", omittingEmptySubsequences: false).count)"),
                                (t("Copied at", "复制时间"), formatDate(entry.copiedAt)),
                                (t("Dimensions", "尺寸"), imageDimensionText(entry)),
                                (t("Image size", "图片大小"), imageSizeText(entry))
                            ]

                            ForEach(Array(items.enumerated()), id: \.offset) { index, pair in
                                infoRow(pair.0, pair.1)
                                if index < items.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(Color.whyCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(16)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("No Entries", "暂无记录"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(t("No clipboard history available", "当前没有可展示的剪贴板记录"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                pasteSelectedEntry()
            } label: {
                Label(t("Paste to \(coordinator.pasteTargetAppName)", "粘贴到 \(coordinator.pasteTargetAppName)"), systemImage: "arrowshape.turn.up.left.fill")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))

            Text("↩")
                .foregroundStyle(.secondary)

            Text(t("Actions", "操作"))
                .foregroundStyle(.secondary)
            Text("⌘K")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Spacer()

            Button(t("Delete", "删除")) {
                guard let entry = selectedEntry else { return }
                coordinator.clipboardHistory.delete(entry)
                status = t("Deleted selected item", "已删除选中项")
                isError = false
                syncSelection()
            }
            .buttonStyle(.bordered)

            Button(t("Clear", "清空"), role: .destructive) {
                coordinator.clipboardHistory.clear()
                status = t("Clipboard history cleared", "剪贴板历史已清空")
                isError = false
                syncSelection()
            }
            .buttonStyle(.bordered)

            StatusLine(text: status, isError: isError)
                .frame(maxWidth: 360, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.whyChromeBackground)
    }

    private func pasteSelectedEntry() {
        guard let entry = selectedEntry else {
            status = t("No content to paste", "没有可粘贴的内容")
            isError = true
            return
        }
        let message = coordinator.pasteClipboardEntry(entry)
        status = message
        let lower = message.lowercased()
        isError = lower.contains("失败") || lower.contains("failed")
    }

    private func syncSelection() {
        if let current = selectedEntry, filteredEntries.contains(where: { $0.id == current.id }) {
            selectedEntryID = current.id
            return
        }
        selectedEntryID = filteredEntries.first?.id
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredEntries.isEmpty else { return }
        guard let current = selectedEntry, let index = filteredEntries.firstIndex(where: { $0.id == current.id }) else {
            selectedEntryID = filteredEntries.first?.id
            return
        }
        let next = (index + delta + filteredEntries.count) % filteredEntries.count
        selectedEntryID = filteredEntries[next].id
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
                return event
            }
            switch event.keyCode {
            case 125:
                moveSelection(1)
                return nil
            case 126:
                moveSelection(-1)
                return nil
            case 36, 76:
                pasteSelectedEntry()
                return nil
            case 53:
                coordinator.backToLauncher()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func imageDimensionText(_ entry: ClipboardHistoryEntry) -> String {
        guard entry.kind == .image else { return "-" }
        guard let width = entry.imageWidth, let height = entry.imageHeight else { return "-" }
        return "\(width)×\(height)"
    }

    private func imageSizeText(_ entry: ClipboardHistoryEntry) -> String {
        guard entry.kind == .image, let data = entry.imagePNGData else { return "-" }
        let kb = Double(data.count) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.2f MB", kb / 1024.0)
    }

    private func nsImage(from entry: ClipboardHistoryEntry) -> NSImage? {
        guard let data = entry.imagePNGData else { return nil }
        return NSImage(data: data)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        coordinator.localized(english, chinese)
    }
}

private struct ClipboardListRow: View {
    let entry: ClipboardHistoryEntry
    let selected: Bool
    let emptyText: String
    let imageSummaryPrefix: String
    let onSelect: () -> Void
    let onPaste: () -> Void
    @State private var hovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var summary: String {
        if entry.kind == .image {
            let width = entry.imageWidth ?? 0
            let height = entry.imageHeight ?? 0
            return "\(imageSummaryPrefix) (\(width)×\(height))"
        }
        let value = entry.text.replacingOccurrences(of: "\n", with: " ")
        return String(value.prefix(42))
    }

    var body: some View {
        HStack(spacing: 10) {
            if entry.kind == .image, let data = entry.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "doc")
                    .frame(width: 18)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            Text(summary.isEmpty ? emptyText : summary)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected
                    ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12))
                    : (hovering
                        ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .highPriorityGesture(TapGesture(count: 2).onEnded {
            onPaste()
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            onSelect()
        })
    }
}
