import AppKit
import ApplicationServices
import Carbon
import Foundation

enum PasteAutomationService {
    enum FallbackAction: Equatable {
        case cgEvent
        case appleScript
    }

    enum CommandVChannel: Equatable {
        case targetPID
        case session
    }

    @MainActor
    static func pasteToApplication(
        entry: ClipboardHistoryEntry,
        targetApp: NSRunningApplication?
    ) -> String {
        guard writeToPasteboard(entry: entry) else {
            return L10n.text("Failed to write to clipboard", "写入剪贴板失败")
        }

        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        let effectiveTarget = resolveTargetApplication(preferred: targetApp)
        let targetName = effectiveTarget?.localizedName ?? L10n.text("Current App", "当前应用")
        let targetPID = effectiveTarget?.processIdentifier
        let targetBundleID = effectiveTarget?.bundleIdentifier

        activateTargetApplication(effectiveTarget)
        let performPaste: @MainActor (pid_t?, String?) -> Void = { effectivePID, effectiveBundleID in
            let resolvedPID = effectivePID ?? targetPID
            let resolvedBundleID = effectiveBundleID ?? targetBundleID

            if entry.kind == .text {
                let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if setTextByAccessibility(text: text, targetPID: resolvedPID) {
                    return
                }
            }

            let actions = fallbackActions(includeAppleScript: !trusted)
            executeFallbackActions(actions, targetPID: resolvedPID, targetBundleID: resolvedBundleID)
        }

        if requiresFrontmostWait(targetPID: targetPID, targetBundleID: targetBundleID) {
            waitForTargetToBeFrontmost(
                targetPID: targetPID,
                targetBundleID: targetBundleID,
                retries: 3,
                interval: 0.02
            ) { frontmost in
                performPaste(frontmost?.processIdentifier, frontmost?.bundleIdentifier)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                performPaste(targetPID, targetBundleID)
            }
        }

        if trusted {
            return L10n.text("Pasting to \(targetName)", "正在粘贴到 \(targetName)")
        }
        return L10n.text(
            "Pasting to \(targetName). Please confirm Accessibility and Automation permissions",
            "正在粘贴到 \(targetName)，请确认辅助功能与自动化权限"
        )
    }

    private static func writeToPasteboard(entry: ClipboardHistoryEntry) -> Bool {
        NSPasteboard.general.clearContents()
        switch entry.kind {
        case .text:
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return NSPasteboard.general.setString(trimmed, forType: .string)
        case .image:
            guard let data = entry.imagePNGData else { return false }
            if let image = NSImage(data: data), NSPasteboard.general.writeObjects([image]) {
                return true
            }
            NSPasteboard.general.setData(data, forType: .png)
            return true
        }
    }

    @discardableResult
    private static func sendCommandVByCGEvent(targetPID: pid_t?) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let key = CGKeyCode(kVK_ANSI_V)

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand

        guard let down, let up else { return false }
        let channels = commandVChannels(targetPID: targetPID)
        for channel in channels {
            switch channel {
            case .targetPID:
                guard let targetPID, targetPID > 0 else { continue }
                down.postToPid(targetPID)
                up.postToPid(targetPID)
            case .session:
                down.post(tap: .cgSessionEventTap)
                up.post(tap: .cgSessionEventTap)
            }
        }
        return true
    }

    @discardableResult
    private static func sendCommandVByAppleScript(targetBundleID: String?) -> Bool {
        let activateScript: String
        if let bundleID = targetBundleID {
            activateScript = """
            tell application id "\(bundleID)"
                activate
            end tell
            """
        } else {
            activateScript = ""
        }
        let scriptSource = """
        \(activateScript)
        delay 0.08
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    @discardableResult
    private static func setTextByAccessibility(text: String, targetPID: pid_t?) -> Bool {
        guard !text.isEmpty else { return false }
        var candidates: [AXUIElement] = []

        if let pid = targetPID, pid > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            if result == .success, let focused = axElement(from: focusedRef) {
                candidates.append(focused)
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        var systemFocusedRef: CFTypeRef?
        let systemResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &systemFocusedRef)
        if systemResult == .success, let focused = axElement(from: systemFocusedRef) {
            candidates.append(focused)
        }

        for element in candidates {
            let selectedSet = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if selectedSet == .success { return true }

            let valueSet = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
            if valueSet == .success { return true }

            let insert = AXUIElementSetAttributeValue(element, "AXInsertText" as CFString, text as CFString)
            if insert == .success { return true }
        }
        return false
    }

    private static func axElement(from ref: CFTypeRef?) -> AXUIElement? {
        guard let ref else { return nil }
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
    }

    @MainActor
    private static func activateTargetApplication(_ targetApp: NSRunningApplication?) {
        guard let targetApp else { return }
        targetApp.unhide()
        _ = targetApp.activate(options: [.activateAllWindows])
    }

    @MainActor
    private static func waitForTargetToBeFrontmost(
        targetPID: pid_t?,
        targetBundleID: String?,
        retries: Int,
        interval: TimeInterval,
        completion: @MainActor @escaping (NSRunningApplication?) -> Void
    ) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let pidMatched = targetPID != nil && frontmost?.processIdentifier == targetPID
        let bundleMatched = targetBundleID != nil && frontmost?.bundleIdentifier == targetBundleID

        if targetPID == nil && targetBundleID == nil {
            completion(frontmost)
            return
        }

        if pidMatched || bundleMatched || retries <= 0 {
            completion(frontmost)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            waitForTargetToBeFrontmost(
                targetPID: targetPID,
                targetBundleID: targetBundleID,
                retries: retries - 1,
                interval: interval,
                completion: completion
            )
        }
    }

    private static func resolveTargetApplication(preferred: NSRunningApplication?) -> NSRunningApplication? {
        let ownBundleID = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let selectedBundleID = selectTargetBundleIdentifier(
            preferredBundleID: preferred?.bundleIdentifier,
            frontmostBundleID: frontmost?.bundleIdentifier,
            ownBundleID: ownBundleID
        )

        if let selectedBundleID {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: selectedBundleID)
            if let active = running.first(where: { !$0.isTerminated }) {
                return active
            }
            if preferred?.bundleIdentifier == selectedBundleID {
                return preferred
            }
            if frontmost?.bundleIdentifier == selectedBundleID {
                return frontmost
            }
        }

        if let preferred, preferred.bundleIdentifier != ownBundleID, !preferred.isTerminated {
            return preferred
        }
        if let frontmost, frontmost.bundleIdentifier != ownBundleID, !frontmost.isTerminated {
            return frontmost
        }
        return nil
    }

    static func selectTargetBundleIdentifier(
        preferredBundleID: String?,
        frontmostBundleID: String?,
        ownBundleID: String?
    ) -> String? {
        for candidate in [preferredBundleID, frontmostBundleID] {
            guard let candidate, !candidate.isEmpty else { continue }
            if candidate != ownBundleID {
                return candidate
            }
        }
        return nil
    }

    static func fallbackActions(includeAppleScript: Bool) -> [FallbackAction] {
        if includeAppleScript {
            return [.appleScript]
        }
        return [.cgEvent]
    }

    static func commandVChannels(targetPID: pid_t?) -> [CommandVChannel] {
        if let targetPID, targetPID > 0 {
            return [.targetPID]
        }
        return [.session]
    }

    static func requiresFrontmostWait(targetPID: pid_t?, targetBundleID: String?) -> Bool {
        if let targetPID, targetPID > 0 {
            return false
        }
        if let targetBundleID, !targetBundleID.isEmpty {
            return false
        }
        return true
    }

    private static func executeFallbackActions(
        _ actions: [FallbackAction],
        targetPID: pid_t?,
        targetBundleID: String?
    ) {
        guard !actions.isEmpty else { return }
        for (idx, action) in actions.enumerated() {
            let delay = Double(idx) * 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                switch action {
                case .cgEvent:
                    _ = sendCommandVByCGEvent(targetPID: targetPID)
                case .appleScript:
                    _ = sendCommandVByAppleScript(targetBundleID: targetBundleID)
                }
            }
        }
    }
}
