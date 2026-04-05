import AppKit
import SwiftUI

final class WhyUtilsPanel: NSPanel {
    private var suppressAutoHideUntil: Date = .distantPast

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignMain() {
        super.resignMain()
        LaunchDiagnosticsLogger.log(
            "panel resignMain visible=\(isVisible) key=\(isKeyWindow) main=\(isMainWindow)"
        )
        hideIfVisible()
    }

    override func resignKey() {
        super.resignKey()
        LaunchDiagnosticsLogger.log(
            "panel resignKey visible=\(isVisible) key=\(isKeyWindow) main=\(isMainWindow)"
        )
        hideIfVisible()
    }

    private func hideIfVisible() {
        let suppressAutoHide = Date() < suppressAutoHideUntil
        guard Self.shouldHideOnResign(
            isVisible: isVisible,
            hasAttachedSheet: attachedSheet != nil,
            suppressAutoHide: suppressAutoHide
        ) else { return }
        LaunchDiagnosticsLogger.log(
            "panel hideIfVisible -> orderOut suppressAutoHide=\(suppressAutoHide) attachedSheet=\(attachedSheet != nil)"
        )
        orderOut(nil)
    }

    func suppressAutoHide(for duration: TimeInterval = 0.45) {
        suppressAutoHideUntil = Date().addingTimeInterval(duration)
        LaunchDiagnosticsLogger.log("panel suppressAutoHide duration=\(duration)")
    }

    nonisolated static func shouldHideOnResign(
        isVisible: Bool,
        hasAttachedSheet: Bool,
        suppressAutoHide: Bool = false
    ) -> Bool {
        isVisible && !hasAttachedSheet && !suppressAutoHide
    }
}

@MainActor
final class WhyUtilsPanelController {
    static let panelSize = NSSize(width: 920, height: 640)
    static let hideOnDeactivate = false
    let panel: WhyUtilsPanel

    init(rootView: AnyView) {
        panel = WhyUtilsPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let hosting = NSHostingController(rootView: rootView)
        hosting.view.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentViewController = hosting
        panel.setContentSize(Self.panelSize)
        panel.minSize = Self.panelSize
        panel.maxSize = Self.panelSize
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = Self.hideOnDeactivate
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
