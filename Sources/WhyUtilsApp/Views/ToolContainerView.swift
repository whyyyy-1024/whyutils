import AppKit
import SwiftUI

struct ToolContainerView: View {
    let tool: ToolKind
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var keyMonitor: Any?

    var body: some View {
        Group {
            if tool == .clipboard {
                ClipboardHistoryToolView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if tool == .searchFiles {
                FileSearchToolView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if tool == .aiAssistant {
                AIAssistantToolView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
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

                        Spacer()

                        VStack(spacing: 2) {
                            Text(tool.title(in: coordinator.language))
                                .font(.system(size: 17, weight: .semibold))
                            Text(tool.subtitle(in: coordinator.language))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Text(coordinator.localized("Back", "返回"))
                                .foregroundStyle(.secondary)
                            Text("Esc")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(14)
                    .background(Color.whyChromeBackground)

                    Divider()

                    Group {
                        switch tool {
                        case .aiAssistant:
                            EmptyView()
                        case .clipboard:
                            EmptyView()
                        case .searchFiles:
                            EmptyView()
                        case .json:
                            JSONToolView()
                        case .killProcess:
                            KillProcessToolView()
                        case .time:
                            TimeToolView()
                        case .url:
                            URLToolView()
                        case .base64:
                            Base64ToolView()
                        case .hash:
                            HashToolView()
                        case .regex:
                            RegexToolView()
                        }
                    }
                    .padding(14)

                    Divider()

                    HStack(spacing: 14) {
                        Text(coordinator.localized("⌘K Actions", "⌘K 操作"))
                        Text(coordinator.localized("Esc Launcher", "Esc 启动器"))
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.whyChromeBackground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onExitCommand {
            coordinator.backToLauncher()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if AppCoordinator.shouldHandleEscape(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags
            ) {
                coordinator.backToLauncher()
                return nil
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
