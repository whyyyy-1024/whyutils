import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: WhyUtilsPanelController?
    private var launchBootstrapAttempts = 0
    private var pendingLaunchBootstrap: DispatchWorkItem?
    private var startupWatchdogAttempts = 0
    private var pendingStartupWatchdog: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchDiagnosticsLogger.log("applicationDidFinishLaunching begin")
        DispatchQueue.main.async { [weak self] in
            self?.beginStartupPresentationWatchdog()
        }
        LaunchDiagnosticsLogger.log("applicationDidFinishLaunching build root view")

        let rootView = AnyView(
            RootView()
                .environmentObject(AppCoordinator.shared)
                .frame(width: WhyUtilsPanelController.panelSize.width, height: WhyUtilsPanelController.panelSize.height)
        )
        panelController = WhyUtilsPanelController(rootView: rootView)
        LaunchDiagnosticsLogger.log(
            "panelController created panelExists=\(panelController?.panel != nil) hideOnDeactivate=\(WhyUtilsPanelController.hideOnDeactivate)"
        )

        if let panel = panelController?.panel {
            AppCoordinator.shared.attachPanel(panel)
            LaunchDiagnosticsLogger.log(
                "panel attached visible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)"
            )
            LaunchDiagnosticsLogger.log("applicationDidFinishLaunching -> schedule presentLauncherAfterAppStart")
            DispatchQueue.main.async { [weak self] in
                self?.presentLauncherAfterAppStart()
            }
        } else {
            LaunchDiagnosticsLogger.log("panel attach skipped: panelController.panel is nil")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LaunchDiagnosticsLogger.log("applicationShouldHandleReopen hasVisibleWindows=\(flag)")
        AppCoordinator.shared.showLauncher(resetState: false)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LaunchDiagnosticsLogger.log("applicationDidBecomeActive appActive=\(NSApp.isActive)")
        Task { @MainActor in
            guard let panel = panelController?.panel else { return }
            guard Self.shouldPresentOnActivation(isPanelVisible: panel.isVisible) else { return }
            LaunchDiagnosticsLogger.log(
                "applicationDidBecomeActive -> showLauncher panelVisible=\(panel.isVisible)"
            )
            AppCoordinator.shared.showLauncher(resetState: false)
            scheduleLaunchBootstrapIfNeeded()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        LaunchDiagnosticsLogger.log("applicationDidResignActive appActive=\(NSApp.isActive)")
    }

    nonisolated static func shouldPresentOnActivation(isPanelVisible: Bool) -> Bool {
        !isPanelVisible
    }

    nonisolated static func shouldRetryBootstrapPresentation(
        isVisible: Bool,
        isKeyWindow: Bool,
        isMainWindow: Bool
    ) -> Bool {
        !(isVisible && (isKeyWindow || isMainWindow))
    }

    @MainActor
    private func presentLauncherAfterAppStart() {
        LaunchDiagnosticsLogger.log("presentLauncherAfterAppStart")
        AppCoordinator.shared.showLauncher(resetState: true)
        launchBootstrapAttempts = 0
        scheduleLaunchBootstrapIfNeeded()
    }

    @MainActor
    private func beginStartupPresentationWatchdog() {
        pendingStartupWatchdog?.cancel()
        startupWatchdogAttempts = 0
        scheduleStartupPresentationWatchdog()
    }

    @MainActor
    private func scheduleStartupPresentationWatchdog() {
        pendingStartupWatchdog?.cancel()
        guard startupWatchdogAttempts < 14 else {
            LaunchDiagnosticsLogger.log("startupWatchdog exhausted")
            return
        }
        startupWatchdogAttempts += 1
        let attempt = startupWatchdogAttempts
        LaunchDiagnosticsLogger.log("startupWatchdog schedule attempt=\(attempt)")

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                LaunchDiagnosticsLogger.log("startupWatchdog run attempt=\(attempt)")
                AppCoordinator.shared.showLauncher(resetState: attempt == 1)

                let panel = self.panelController?.panel ?? NSApp.windows.compactMap { $0 as? WhyUtilsPanel }.first
                guard let panel else {
                    LaunchDiagnosticsLogger.log("startupWatchdog panel missing -> retry")
                    self.scheduleStartupPresentationWatchdog()
                    return
                }

                let stable = panel.isVisible && (panel.isKeyWindow || panel.isMainWindow)
                LaunchDiagnosticsLogger.log(
                    "startupWatchdog panel visible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)"
                )
                if stable {
                    LaunchDiagnosticsLogger.log("startupWatchdog stable -> stop")
                    return
                }
                self.scheduleStartupPresentationWatchdog()
            }
        }
        pendingStartupWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    @MainActor
    private func scheduleLaunchBootstrapIfNeeded() {
        pendingLaunchBootstrap?.cancel()
        guard launchBootstrapAttempts < 12 else { return }
        launchBootstrapAttempts += 1
        LaunchDiagnosticsLogger.log("scheduleLaunchBootstrapIfNeeded attempt=\(launchBootstrapAttempts)")

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard let panel = self.panelController?.panel else { return }
                LaunchDiagnosticsLogger.log(
                    "bootstrap check attempt=\(self.launchBootstrapAttempts) visible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)"
                )

                if Self.shouldRetryBootstrapPresentation(
                    isVisible: panel.isVisible,
                    isKeyWindow: panel.isKeyWindow,
                    isMainWindow: panel.isMainWindow
                ) == false {
                    LaunchDiagnosticsLogger.log("bootstrap stable -> stop retry")
                    return
                }

                LaunchDiagnosticsLogger.log("bootstrap retry showLauncher")
                AppCoordinator.shared.showLauncher(resetState: false)
                self.scheduleLaunchBootstrapIfNeeded()
            }
        }
        pendingLaunchBootstrap = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: item)
    }

}

@main
struct WhyUtilsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
