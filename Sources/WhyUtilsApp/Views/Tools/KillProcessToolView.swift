import AppKit
import SwiftUI

struct KillProcessToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var processes: [ProcessItem] = []
    @State private var query: String = ""
    @State private var selectedProcessID: Int32?
    @State private var showKillConfirmation: Bool = false
    @State private var processToKill: ProcessItem?
    @State private var errorMessage: String?
    @State private var isRefreshing: Bool = false
    @State private var keyMonitor: Any?
    @FocusState private var focusSearch: Bool

    private var filteredProcesses: [ProcessItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return processes }
        return processes.filter { process in
            process.name.localizedCaseInsensitiveContains(trimmed) ||
                String(process.pid).hasPrefix(trimmed)
        }
    }

    private var selectedProcess: ProcessItem? {
        guard let selectedProcessID else {
            return filteredProcesses.first
        }
        return filteredProcesses.first(where: { $0.id == selectedProcessID }) ?? filteredProcesses.first
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            processList
            Divider()
            actionBar
        }
        .onAppear {
            focusSearch = true
            refreshProcesses()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _ in
            syncSelection()
        }
        .alert(
            killConfirmationTitle,
            isPresented: $showKillConfirmation,
            presenting: processToKill
        ) { process in
            Button(coordinator.localized("Terminate", "终止"), role: .destructive) {
                performKill(process)
            }
            Button(coordinator.localized("Cancel", "取消"), role: .cancel) {
                processToKill = nil
            }
        } message: { process in
            Text(coordinator.localized(
                "This will send SIGTERM to the process. It may not terminate immediately if unresponsive.",
                "将向进程发送 SIGTERM 信号。如果无响应可能不会立即终止。"
            ))
        }
    }

    private var killConfirmationTitle: String {
        guard let process = processToKill else {
            return coordinator.localized("Terminate process?", "终止进程？")
        }
        return coordinator.localized(
            "Terminate \"\(process.name)\" (PID \(process.pid))?",
            "终止 \"\(process.name)\" (PID \(process.pid))？"
        )
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

                TextField(coordinator.localized("Search processes...", "搜索进程..."), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .focused($focusSearch)
                    .onSubmit {
                        killSelectedProcess()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer(minLength: 10)

            Button {
                Task {
                    await refreshProcessesAsync()
                }
            } label: {
                Group {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                            .padding(8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .padding(8)
                    }
                }
                .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.whyChromeBackground)
    }

    private var processList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                Text(coordinator.localized("Processes", "进程"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .padding(.horizontal, 14)

                if filteredProcesses.isEmpty && isRefreshing {
                    Text(coordinator.localized("Loading...", "加载中..."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else if filteredProcesses.isEmpty {
                    Text(coordinator.localized("No processes found", "未找到进程"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredProcesses) { process in
                        ProcessRow(
                            process: process,
                            selected: process.id == selectedProcess?.id,
                            onSelect: {
                                selectedProcessID = process.id
                            },
                            onKill: {
                                selectedProcessID = process.id
                                processToKill = process
                                showKillConfirmation = true
                            }
                        )
                        .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .background(Color.whySidebarBackground)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Label(
                coordinator.localized("Kill Process", "终止进程"),
                systemImage: "xmark.circle.fill"
            )
            .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Button(coordinator.localized("Terminate", "终止")) {
                killSelectedProcess()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))
            .disabled(selectedProcess == nil)

            Text("↩")
                .foregroundStyle(.secondary)

            Button(coordinator.localized("Refresh", "刷新")) {
                Task {
                    await refreshProcessesAsync()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))

            Text("⌘R")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.whyChromeBackground)
    }

    private func refreshProcesses() {
        Task {
            await refreshProcessesAsync()
        }
    }

    private func refreshProcessesAsync() async {
        isRefreshing = true
        errorMessage = nil
        let newProcesses = await ProcessListService.fetchProcesses()
        processes = newProcesses
        isRefreshing = false
        syncSelection()
    }

    private func syncSelection() {
        if let selectedProcess, filteredProcesses.contains(where: { $0.id == selectedProcess.id }) {
            return
        }
        selectedProcessID = filteredProcesses.first?.id
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredProcesses.isEmpty else { return }
        guard
            let selectedProcess,
            let index = filteredProcesses.firstIndex(where: { $0.id == selectedProcess.id })
        else {
            selectedProcessID = filteredProcesses.first?.id
            return
        }

        let next = (index + delta + filteredProcesses.count) % filteredProcesses.count
        selectedProcessID = filteredProcesses[next].id
    }

    private func killSelectedProcess() {
        guard let process = selectedProcess else { return }
        processToKill = process
        showKillConfirmation = true
    }

    private func performKill(_ process: ProcessItem) {
        let result = ProcessListService.killProcess(pid: process.pid)
        switch result {
        case .success:
            errorMessage = nil
            Task {
                await refreshProcessesAsync()
            }
        case .failure(let message):
            errorMessage = message
        }
        processToKill = nil
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
                if !flags.contains(.command) {
                    killSelectedProcess()
                    return nil
                }
            case 15:
                if flags.contains(.command) {
                    Task {
                        await refreshProcessesAsync()
                    }
                    return nil
                }
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

private struct ProcessRow: View {
    let process: ProcessItem
    let selected: Bool
    let onSelect: () -> Void
    let onKill: () -> Void
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
            Image(systemName: "app.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("PID: \(process.pid)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("CPU: \(String(format: "%.1f", process.cpu))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(process.cpu > 50 ? .red : .secondary)

                    Text("MEM: \(String(format: "%.1f", process.memory))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(process.memory > 50 ? .orange : .secondary)
                }
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
            onKill()
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            onSelect()
        })
    }
}