import AppKit
import Foundation

struct SystemControlModule: ToolProvider {
    let providerId = "systemcontrol"
    
    private static let protectedProcesses = ["kernel_task", "launchd", "WindowServer", "loginwindow"]
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "process_list", description: "List running processes", providerId: providerId, dangerousLevel: .safe),
            .init(name: "process_info", description: "Get process details", providerId: providerId, dangerousLevel: .safe),
            .init(name: "process_kill", description: "Terminate a process", requiresConfirmation: true, providerId: providerId, dangerousLevel: .dangerous),
            .init(name: "network_request", description: "Send HTTP request", providerId: providerId, dangerousLevel: .safe),
            .init(name: "screenshot", description: "Take a screenshot", providerId: providerId, dangerousLevel: .safe),
            .init(name: "window_list", description: "List open windows", providerId: providerId, dangerousLevel: .safe)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "process_list":
            let sortBy = stringArg(named: "sortBy", in: arguments) ?? "name"
            let limit = intArg(named: "limit", in: arguments) ?? 20
            return try await listProcesses(sortBy: sortBy, limit: limit)
        case "process_info":
            let pid = try requiredIntArg(named: "pid", in: arguments)
            return try getProcessInfo(pid: pid)
        case "process_kill":
            let pid = try requiredIntArg(named: "pid", in: arguments)
            return try killProcess(pid: pid)
        case "network_request":
            let url = try requiredArg(named: "url", in: arguments)
            let method = stringArg(named: "method", in: arguments) ?? "GET"
            let body = stringArg(named: "body", in: arguments)
            return try await networkRequest(url: url, method: method, body: body)
        case "screenshot":
            return try await takeScreenshot()
        case "window_list":
            return try listWindows()
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    
    private func intArg(named name: String, in arguments: [String: Any]) -> Int? {
        if let v = arguments[name] as? Int { return v }
        if let v = arguments[name] as? String { return Int(v) }
        return nil
    }
    
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let v = arguments[name] as? String, !v.isEmpty else {
            throw ToolError.invalidArgument("Missing: \(name)")
        }
        return v
    }
    
    private func requiredIntArg(named name: String, in arguments: [String: Any]) throws -> Int {
        guard let v = intArg(named: name, in: arguments) else {
            throw ToolError.invalidArgument("Missing: \(name)")
        }
        return v
    }
    
    private func listProcesses(sortBy: String, limit: Int) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,pcpu,pmem,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: .newlines).dropFirst()
        let sorted: [String]
        switch sortBy {
        case "cpu":
            sorted = lines.sorted { a, b in
                let aParts = a.split(separator: " ", omittingEmptySubsequences: true)
                let bParts = b.split(separator: " ", omittingEmptySubsequences: true)
                let aCpu = aParts.count > 1 ? Double(aParts[1]) ?? 0 : 0
                let bCpu = bParts.count > 1 ? Double(bParts[1]) ?? 0 : 0
                return aCpu > bCpu
            }
        case "memory":
            sorted = lines.sorted { a, b in
                let aParts = a.split(separator: " ", omittingEmptySubsequences: true)
                let bParts = b.split(separator: " ", omittingEmptySubsequences: true)
                let aMem = aParts.count > 2 ? Double(aParts[2]) ?? 0 : 0
                let bMem = bParts.count > 2 ? Double(bParts[2]) ?? 0 : 0
                return aMem > bMem
            }
        default:
            sorted = Array(lines)
        }
        let result = sorted.prefix(limit).joined(separator: "\n")
        return result.isEmpty ? "No processes found" : result
    }
    
    private func getProcessInfo(pid: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "pid,pcpu,pmem,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .newlines).isEmpty ? "Process \(pid) not found" : output.trimmingCharacters(in: .newlines)
    }
    
    private func killProcess(pid: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let name = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !Self.protectedProcesses.contains(name) else {
            return "Cannot kill protected process: \(name)"
        }
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
        killProcess.arguments = ["-9", String(pid)]
        try killProcess.run()
        killProcess.waitUntilExit()
        return killProcess.terminationStatus == 0 ? "Killed process \(pid) (\(name))" : "Failed to kill process \(pid)"
    }
    
    private func networkRequest(url: String, method: String, body: String?) async throws -> String {
        guard let url = URL(string: url) else { return "Invalid URL" }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body { request.httpBody = body.data(using: .utf8) }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode ?? 0
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        return "Status: \(status)\n\(String(responseBody.prefix(2000)))"
    }
    
    private func takeScreenshot() async throws -> String {
        let path = NSTemporaryDirectory() + "screenshot_\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "Screenshot saved to \(path)" : "Failed to take screenshot"
    }
    
    private func listWindows() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
        tell application "System Events"
            set winList to windows of (every process whose background only is false)
            set output to ""
            repeat with w in winList
                set output to output & (name of w) & " - " & (title of w) & "\\n"
            end repeat
            return output
        end tell
        """]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .newlines).isEmpty ? "No windows found" : output.trimmingCharacters(in: .newlines)
    }
}