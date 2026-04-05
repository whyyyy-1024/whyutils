import AppKit
import Foundation

enum SystemSettingsSearchService {
    private static let entries: [SystemSettingItem] = [
        SystemSettingItem(
            id: "vpn",
            titleEN: "VPN",
            titleZH: "VPN",
            subtitleEN: "System Settings · Network",
            subtitleZH: "系统设置 · 网络",
            symbol: "lock.shield",
            keywords: ["vpn", "network", "代理", "网络", "虚拟专用网络"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Network-Settings.extension?VPN",
                "x-apple.systempreferences:com.apple.preference.network?VPN",
                "x-apple.systempreferences:com.apple.Network-Settings.extension"
            ]
        ),
        SystemSettingItem(
            id: "wifi",
            titleEN: "Wi-Fi",
            titleZH: "Wi-Fi",
            subtitleEN: "System Settings · Network",
            subtitleZH: "系统设置 · 网络",
            symbol: "wifi",
            keywords: ["wifi", "wi-fi", "wireless", "wlan", "无线", "网络"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Network-Settings.extension?Wi-Fi",
                "x-apple.systempreferences:com.apple.preference.network?Wi-Fi",
                "x-apple.systempreferences:com.apple.Network-Settings.extension"
            ]
        ),
        SystemSettingItem(
            id: "bluetooth",
            titleEN: "Bluetooth",
            titleZH: "蓝牙",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "dot.radiowaves.left.and.right",
            keywords: ["bluetooth", "airpods", "蓝牙", "耳机"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.BluetoothSettings",
                "x-apple.systempreferences:com.apple.preference.bluetooth"
            ]
        ),
        SystemSettingItem(
            id: "network",
            titleEN: "Network",
            titleZH: "网络",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "network",
            keywords: ["network", "internet", "代理", "网络", "网卡", "dns"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network"
            ]
        ),
        SystemSettingItem(
            id: "privacy",
            titleEN: "Privacy & Security",
            titleZH: "隐私与安全性",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "hand.raised.fill",
            keywords: ["privacy", "security", "permissions", "tcc", "隐私", "安全", "权限"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
                "x-apple.systempreferences:com.apple.preference.security"
            ]
        ),
        SystemSettingItem(
            id: "accessibility",
            titleEN: "Accessibility",
            titleZH: "辅助功能",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "accessibility",
            keywords: ["accessibility", "assistive", "voiceover", "辅助", "无障碍"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.universalaccess"
            ]
        ),
        SystemSettingItem(
            id: "display",
            titleEN: "Displays",
            titleZH: "显示器",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "display",
            keywords: ["display", "monitor", "brightness", "resolution", "显示", "屏幕", "亮度", "分辨率"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Displays-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.displays"
            ]
        ),
        SystemSettingItem(
            id: "keyboard",
            titleEN: "Keyboard",
            titleZH: "键盘",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "keyboard",
            keywords: ["keyboard", "input", "shortcut", "hotkey", "键盘", "输入法", "快捷键", "热键"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.keyboard"
            ]
        ),
        SystemSettingItem(
            id: "sound",
            titleEN: "Sound",
            titleZH: "声音",
            subtitleEN: "System Settings",
            subtitleZH: "系统设置",
            symbol: "speaker.wave.2.fill",
            keywords: ["sound", "audio", "speaker", "microphone", "声音", "音频", "麦克风", "扬声器"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Sound-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.sound"
            ]
        )
    ]

    static func search(query: String, limit: Int = 8) -> [SystemSettingItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return entries
            .compactMap { entry -> (SystemSettingItem, Int)? in
                guard let score = matchScore(item: entry, query: trimmed) else { return nil }
                return (entry, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0)
    }

    @discardableResult
    static func open(_ item: SystemSettingItem, language: AppLanguage) -> String {
        if item.id == "vpn",
           shouldUseLegacyVPNAutomation(for: ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
           openLegacyVPNPane() {
            return L10n.text(
                "Opened \(item.title(in: language)) in System Preferences",
                "已在系统偏好设置中打开 \(item.title(in: language))",
                language: language
            )
        }

        for raw in item.urlCandidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return L10n.text(
                    "Opened \(item.title(in: language)) in System Settings",
                    "已在系统设置中打开 \(item.title(in: language))",
                    language: language
                )
            }
        }

        if let settingsAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
           NSWorkspace.shared.open(settingsAppURL) {
            return L10n.text(
                "Opened System Settings (target page not available)",
                "已打开系统设置（目标页面可能不可用）",
                language: language
            )
        }

        return L10n.text(
            "Failed to open System Settings",
            "打开系统设置失败",
            language: language
        )
    }

    nonisolated static func shouldUseLegacyVPNAutomation(for majorVersion: Int) -> Bool {
        majorVersion <= 12
    }

    nonisolated static func matchScore(item: SystemSettingItem, query: String) -> Int? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }

        let fields = [
            item.id,
            item.titleEN,
            item.titleZH,
            item.subtitleEN,
            item.subtitleZH
        ] + item.keywords

        var best: Int?
        for raw in fields {
            let text = normalize(raw)
            guard !text.isEmpty else { continue }
            let score: Int?
            if text == q {
                score = 1100
            } else if text.hasPrefix(q) {
                score = 920
            } else if text.contains(q) {
                score = 760
            } else {
                score = nil
            }
            if let score {
                best = max(best ?? 0, score)
            }
        }
        return best
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func openLegacyVPNPane() -> Bool {
        let revealSucceeded = runAppleScript(lines: [
            "tell application \"System Preferences\" to activate",
            "tell application \"System Preferences\" to reveal anchor \"VPN\" of pane id \"com.apple.preference.network\""
        ])
        if revealSucceeded {
            return true
        }

        return runAppleScript(lines: [
            "tell application \"System Preferences\" to activate",
            "tell application \"System Preferences\" to set current pane to pane id \"com.apple.preference.network\""
        ])
    }

    private static func runAppleScript(lines: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] }
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
