import Darwin
import Foundation

enum KillResult: Equatable {
    case success
    case failure(message: String)
}

enum ProcessListService {
    static func fetchProcesses() async -> [ProcessItem] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["aux", "-r"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            return []
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        return parseProcessList(output)
    }

    static func killProcess(pid: Int32) -> KillResult {
        let result = Darwin.kill(pid, SIGTERM)

        if result == 0 {
            return .success
        }

        let errorCode = errno
        switch errorCode {
        case EPERM:
            return .failure(message: "Permission denied. Try terminating processes owned by your user.")
        case ESRCH:
            return .failure(message: "Process not found. It may have already terminated.")
        default:
            return .failure(message: "Failed to terminate process (error \(errorCode)).")
        }
    }

    static func parsePsOutputLine(_ line: String) -> ProcessItem? {
        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 11 else { return nil }

        let user = String(columns[0])
        guard let pid = Int32(columns[1]) else { return nil }

        guard let cpu = Double(columns[2]),
              let memory = Double(columns[3])
        else { return nil }

        let commandPart = columns[10...]
        let fullCommand = commandPart.joined(separator: " ")
        let name = extractProcessName(from: fullCommand)

        return ProcessItem(
            id: pid,
            pid: pid,
            name: name,
            cpu: cpu,
            memory: memory,
            user: user
        )
    }

    static func filterSelfProcess(_ processes: [ProcessItem]) -> [ProcessItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return processes.filter { $0.pid != ownPID }
    }

    static func search(processes: [ProcessItem], query: String) -> [ProcessItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return processes }

        return processes.filter { item in
            item.name.lowercased().contains(q) || String(item.pid).contains(q)
        }
    }

    static func sortByCPU(_ processes: [ProcessItem]) -> [ProcessItem] {
        return processes.sorted { $0.cpu > $1.cpu }
    }

    private static func parseProcessList(_ output: String) -> [ProcessItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var items: [ProcessItem] = []

        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return [] }

        for line in lines.dropFirst() {
            guard let item = parsePsOutputLine(String(line)) else { continue }
            if item.pid == ownPID { continue }
            items.append(item)
        }

        return items
    }

    private static func extractProcessName(from command: String) -> String {
        let path = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        if name.isEmpty {
            return path
        }
        return name
    }
}