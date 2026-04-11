import Foundation

struct FileSystemModule: ToolProvider {
    let providerId = "filesystem"
    
    private static let forbiddenPathPrefixes = [
        "/System", "/Library", "/usr", "/bin", "/etc",
        "~/.ssh", "~/.gnupg"
    ]
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "fs_create_directory", description: "Create a directory (creates intermediate directories)", providerId: providerId, dangerousLevel: .safe),
            .init(name: "fs_delete", description: "Delete a file or directory (recursive)", requiresConfirmation: true, providerId: providerId, dangerousLevel: .dangerous),
            .init(name: "fs_copy", description: "Copy a file or directory", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "fs_move", description: "Move or rename a file or directory", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "fs_find", description: "Recursively search for files by name pattern", providerId: providerId, dangerousLevel: .safe),
            .init(name: "fs_compress", description: "Compress files or directory to zip", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "fs_decompress", description: "Decompress a zip file", providerId: providerId, dangerousLevel: .safe),
            .init(name: "fs_get_info", description: "Get file/directory information", providerId: providerId, dangerousLevel: .safe)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "fs_create_directory":
            let path = try requiredArg(named: "path", in: arguments)
            return try createDirectory(path: path)
        case "fs_delete":
            let path = try requiredArg(named: "path", in: arguments)
            return try deletePath(path: path)
        case "fs_copy":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try copyPath(source: source, destination: destination)
        case "fs_move":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try movePath(source: source, destination: destination)
        case "fs_find":
            let path = stringArg(named: "path", in: arguments) ?? FileManager.default.homeDirectoryForCurrentUser.path
            let pattern = try requiredArg(named: "pattern", in: arguments)
            return try findFiles(path: path, pattern: pattern)
        case "fs_compress":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try compress(source: source, destination: destination)
        case "fs_decompress":
            let source = try requiredArg(named: "source", in: arguments)
            let destination = try requiredArg(named: "destination", in: arguments)
            return try decompress(source: source, destination: destination)
        case "fs_get_info":
            let path = try requiredArg(named: "path", in: arguments)
            return try getInfo(path: path)
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] as? String, !value.isEmpty else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return value
    }
    
    private func isPathAllowed(_ path: String) -> Bool {
        let expandedPath = path.hasPrefix("~") ? path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path) : path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        
        for forbidden in Self.forbiddenPathPrefixes {
            let expandedForbidden = forbidden.hasPrefix("~") ? forbidden.replacingOccurrences(of: "~", with: homePath) : forbidden
            if expandedPath.hasPrefix(expandedForbidden) {
                return false
            }
        }
        return true
    }
    
    private func validatePath(_ path: String) throws {
        guard isPathAllowed(path) else {
            throw ToolError.executionFailed("fs_operation", "Path not allowed: \(path)")
        }
    }
    
    private func createDirectory(path: String) throws -> String {
        try validatePath(path)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return "Created directory: \(path)"
    }
    
    private func deletePath(path: String) throws -> String {
        try validatePath(path)
        try FileManager.default.removeItem(atPath: path)
        return "Deleted: \(path)"
    }
    
    private func copyPath(source: String, destination: String) throws -> String {
        try validatePath(source)
        try validatePath(destination)
        try FileManager.default.copyItem(atPath: source, toPath: destination)
        return "Copied \(source) to \(destination)"
    }
    
    private func movePath(source: String, destination: String) throws -> String {
        try validatePath(source)
        try validatePath(destination)
        try FileManager.default.moveItem(atPath: source, toPath: destination)
        return "Moved \(source) to \(destination)"
    }
    
    private func findFiles(path: String, pattern: String) throws -> String {
        try validatePath(path)
        let enumerator = FileManager.default.enumerator(atPath: path)
        let urls = enumerator?.compactMap { item -> String? in
            let name = item as? String ?? ""
            if name.range(of: pattern, options: .regularExpression) != nil {
                return name
            }
            return nil
        } ?? []
        guard !urls.isEmpty else { return "No files found matching '\(pattern)'" }
        return urls.prefix(50).joined(separator: "\n")
    }
    
    private func compress(source: String, destination: String) throws -> String {
        try validatePath(source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destination, source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "Compressed to \(destination)" : "Failed to compress"
    }
    
    private func decompress(source: String, destination: String) throws -> String {
        try validatePath(source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", source, "-d", destination]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "Decompressed to \(destination)" : "Failed to decompress"
    }
    
    private func getInfo(path: String) throws -> String {
        try validatePath(path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = attrs[.size] as? Int64 ?? 0
        let modified = attrs[.modificationDate] as? Date ?? Date()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return [
            "Path: \(path)",
            "Type: \(exists && isDirectory.boolValue ? "Directory" : "File")",
            "Size: \(size) bytes",
            "Modified: \(ISO8601DateFormatter().string(from: modified))"
        ].joined(separator: "\n")
    }
}