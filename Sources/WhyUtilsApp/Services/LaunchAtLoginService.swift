import Foundation

enum LaunchAtLoginError: LocalizedError {
    case writeFailed(path: String, reason: String)
    case loadFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let path, let reason):
            return L10n.text(
                "Failed to write launch item at \(path): \(reason)",
                "写入启动项失败（\(path)）：\(reason)"
            )
        case .loadFailed(let path, let reason):
            return L10n.text(
                "Failed to load launch item at \(path): \(reason)",
                "加载启动项失败（\(path)）：\(reason)"
            )
        }
    }
}

enum LaunchAtLoginService {
    static let label = "com.whyutils.swiftui"

    static var primaryPlistURL: URL {
        plistURL(homeDirectory: FileManager.default.homeDirectoryForCurrentUser, usePrimaryDirectory: true)
    }

    static var fallbackPlistURL: URL {
        plistURL(homeDirectory: FileManager.default.homeDirectoryForCurrentUser, usePrimaryDirectory: false)
    }

    nonisolated static func installPlistURL(homeDirectory: URL, isLaunchAgentsWritable: Bool) -> URL {
        plistURL(homeDirectory: homeDirectory, usePrimaryDirectory: isLaunchAgentsWritable)
    }

    nonisolated private static func plistURL(homeDirectory: URL, usePrimaryDirectory: Bool) -> URL {
        if usePrimaryDirectory {
            return homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("LaunchAgents")
                .appendingPathComponent("\(label).plist")
        }

        return homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("whyutils")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: primaryPlistURL.path) ||
            FileManager.default.fileExists(atPath: fallbackPlistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            uninstall()
        }
    }

    private static func install() throws {
        let execPath = executablePath()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let writable = isLaunchAgentsDirectoryWritable(homeDirectory: home)
        let targets = installTargets(homeDirectory: home, launchAgentsWritable: writable)
        let plist = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
        <plist version=\"1.0\">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscape(execPath))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
        </dict>
        </plist>
        """
        var lastError: Error?

        for targetPlistURL in targets {
            do {
                try writePlist(plist, to: targetPlistURL)

                _ = runLaunchCtl(["unload", primaryPlistURL.path])
                _ = runLaunchCtl(["unload", fallbackPlistURL.path])

                let loadResult = runLaunchCtl(["load", targetPlistURL.path])
                if !loadResult.success {
                    throw LaunchAtLoginError.loadFailed(path: targetPlistURL.path, reason: loadResult.output)
                }
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private static func uninstall() {
        _ = runLaunchCtl(["unload", primaryPlistURL.path])
        _ = runLaunchCtl(["unload", fallbackPlistURL.path])
        try? FileManager.default.removeItem(at: primaryPlistURL)
        try? FileManager.default.removeItem(at: fallbackPlistURL)
    }

    private static func executablePath() -> String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return bundlePath + "/Contents/MacOS/whyutils-swift"
        }
        return CommandLine.arguments[0]
    }

    private static func installTargets(homeDirectory: URL, launchAgentsWritable: Bool) -> [URL] {
        if launchAgentsWritable {
            return [
                plistURL(homeDirectory: homeDirectory, usePrimaryDirectory: true),
                plistURL(homeDirectory: homeDirectory, usePrimaryDirectory: false)
            ]
        }
        return [
            plistURL(homeDirectory: homeDirectory, usePrimaryDirectory: false),
            plistURL(homeDirectory: homeDirectory, usePrimaryDirectory: true)
        ]
    }

    private static func writePlist(_ content: String, to targetPlistURL: URL) throws {
        let parent = targetPlistURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try content.write(to: targetPlistURL, atomically: true, encoding: .utf8)
        } catch {
            throw LaunchAtLoginError.writeFailed(path: targetPlistURL.path, reason: error.localizedDescription)
        }
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func isLaunchAgentsDirectoryWritable(homeDirectory: URL) -> Bool {
        let directory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir)
        if exists {
            if !isDir.boolValue {
                return false
            }
            return FileManager.default.isWritableFile(atPath: directory.path)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private struct LaunchCtlResult {
        let success: Bool
        let output: String
    }

    private static func runLaunchCtl(_ arguments: [String]) -> LaunchCtlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return LaunchCtlResult(success: process.terminationStatus == 0, output: output)
        } catch {
            return LaunchCtlResult(success: false, output: error.localizedDescription)
        }
    }
}
