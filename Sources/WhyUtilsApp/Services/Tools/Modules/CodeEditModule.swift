import Foundation

struct CodeEditModule: ToolProvider {
    let providerId = "codeedit"
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "code_read_range", description: "Read specific line range from a file", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_edit_line", description: "Edit a single line in a file", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "code_edit_range", description: "Edit multiple lines in a file", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "code_search_symbols", description: "Search for function/class/variable definitions", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_find_references", description: "Find references to a symbol", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_list_imports", description: "List imports/dependencies in a file", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_outline", description: "Get file structure outline", providerId: providerId, dangerousLevel: .safe),
            .init(name: "code_analyze", description: "Static analysis for syntax issues", providerId: providerId, dangerousLevel: .safe)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "code_read_range":
            let path = try requiredArg(named: "path", in: arguments)
            let lineStart = intArg(named: "lineStart", in: arguments) ?? 1
            let lineEnd = intArg(named: "lineEnd", in: arguments)
            return try readRange(path: path, lineStart: lineStart, lineEnd: lineEnd)
        case "code_edit_line":
            let path = try requiredArg(named: "path", in: arguments)
            let line = try requiredIntArg(named: "line", in: arguments)
            let content = try requiredArg(named: "content", in: arguments)
            let operation = stringArg(named: "operation", in: arguments) ?? "replace"
            return try editLine(path: path, line: line, content: content, operation: operation)
        case "code_edit_range":
            let path = try requiredArg(named: "path", in: arguments)
            let lineStart = try requiredIntArg(named: "lineStart", in: arguments)
            let lineEnd = try requiredIntArg(named: "lineEnd", in: arguments)
            let content = try requiredArg(named: "content", in: arguments)
            return try editRange(path: path, lineStart: lineStart, lineEnd: lineEnd, content: content)
        case "code_search_symbols":
            let path = try requiredArg(named: "path", in: arguments)
            let symbol = try requiredArg(named: "symbol", in: arguments)
            return try searchSymbols(path: path, symbol: symbol)
        case "code_find_references":
            let path = try requiredArg(named: "path", in: arguments)
            let symbol = try requiredArg(named: "symbol", in: arguments)
            return try findReferences(path: path, symbol: symbol)
        case "code_list_imports":
            let path = try requiredArg(named: "path", in: arguments)
            return try listImports(path: path)
        case "code_outline":
            let path = try requiredArg(named: "path", in: arguments)
            return try outline(path: path)
        case "code_analyze":
            let path = try requiredArg(named: "path", in: arguments)
            return try analyze(path: path)
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
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return v
    }
    private func requiredIntArg(named name: String, in arguments: [String: Any]) throws -> Int {
        guard let v = intArg(named: name, in: arguments) else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return v
    }
    
    private func readRange(path: String, lineStart: Int, lineEnd: Int?) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let start = max(1, lineStart) - 1
        let end = min(lineEnd ?? lines.count, lines.count) - 1
        guard start < lines.count else { return "File has fewer than \(lineStart) lines" }
        let selected = lines[start...min(end, lines.count - 1)]
        return selected.enumerated().map { i, line in "\(start + i + 1): \(line)" }.joined(separator: "\n")
    }
    
    private func editLine(path: String, line: Int, content: String, operation: String) throws -> String {
        var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)
        let idx = line - 1
        guard idx >= 0 && idx < lines.count else { return "Line \(line) out of range" }
        switch operation {
        case "replace": lines[idx] = content
        case "insert_before": lines.insert(content, at: idx)
        case "insert_after": lines.insert(content, at: idx + 1)
        case "delete": lines.remove(at: idx)
        default: return "Unknown operation: \(operation)"
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return "Edited line \(line) in \(path)"
    }
    
    private func editRange(path: String, lineStart: Int, lineEnd: Int, content: String) throws -> String {
        var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)
        let start = max(0, lineStart - 1)
        let end = min(lineEnd - 1, lines.count - 1)
        guard start <= end else { return "Invalid line range" }
        lines.removeSubrange(start...end)
        lines.insert(content, at: start)
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return "Edited lines \(lineStart)-\(lineEnd) in \(path)"
    }
    
    private func searchSymbols(path: String, symbol: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let matches = lines.enumerated().compactMap { i, line in
            line.range(of: symbol, options: .regularExpression) != nil ? "\(i + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
        }
        guard !matches.isEmpty else { return "No symbols found matching '\(symbol)'" }
        return matches.joined(separator: "\n")
    }
    
    private func findReferences(path: String, symbol: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let refs = lines.enumerated().compactMap { i, line in
            line.contains(symbol) ? "\(i + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
        }
        guard !refs.isEmpty else { return "No references found for '\(symbol)'" }
        return refs.joined(separator: "\n")
    }
    
    private func listImports(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let importPatterns = ["^import\\s+", "^#include\\s+", "^from\\s+.*\\s+import\\s+"]
        let imports = lines.enumerated().compactMap { i, line in
            importPatterns.contains { line.range(of: $0, options: .regularExpression) != nil } ? "\(i + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
        }
        guard !imports.isEmpty else { return "No imports found" }
        return imports.joined(separator: "\n")
    }
    
    private func outline(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let patterns = [
            ("func", #"^\s*(?:func|def|function)\s+(\w+)"#),
            ("struct", #"^\s*(?:struct|class|type)\s+(\w+)"#),
            ("var", #"^\s*(?:var|let|const)\s+(\w+)"#)
        ]
        let outline = lines.enumerated().compactMap { i, line in
            for (_, pattern) in patterns {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let matched = String(line[match])
                    return "\(i + 1): \(matched)"
                }
            }
            return nil
        }
        guard !outline.isEmpty else { return "No symbols found" }
        return outline.joined(separator: "\n")
    }
    
    private func analyze(path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var issues: [String] = []
        for (i, line) in lines.enumerated() {
            if line.hasSuffix(" ") { issues.append("\(i + 1): Trailing whitespace") }
            if line.count > 120 { issues.append("\(i + 1): Line too long (\(line.count) chars)") }
        }
        guard !issues.isEmpty else { return "No issues found" }
        return issues.joined(separator: "\n")
    }
}