import Foundation

enum DangerLevel: Int, Codable, Sendable {
    case safe = 0
    case moderate = 1
    case dangerous = 2
}

enum ParamType: String, Codable, Sendable {
    case string
    case int
    case bool
    case object
    case array
}

struct ParamConstraints: Codable, Equatable, Sendable {
    let min: Int?
    let max: Int?
    let pattern: String?
}

struct ToolParameter: Codable, Equatable, Sendable {
    let name: String
    let type: ParamType
    let required: Bool
    let description: String
    let defaultValue: String?
    let constraints: ParamConstraints?
    
    init(name: String, type: ParamType, required: Bool, description: String, defaultValue: String? = nil, constraints: ParamConstraints? = nil) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
        self.constraints = constraints
    }
}

struct ToolDescriptor: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
    let requiresConfirmation: Bool
    let providerId: String
    let dangerousLevel: DangerLevel
    
    init(name: String, description: String, parameters: [ToolParameter] = [], requiresConfirmation: Bool = false, providerId: String, dangerousLevel: DangerLevel) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.requiresConfirmation = requiresConfirmation
        self.providerId = providerId
        self.dangerousLevel = dangerousLevel
    }
}

struct ToolResult: Codable, Equatable, Sendable {
    let toolName: String
    let output: String
    let durationMs: Int
    let success: Bool
}

enum ToolError: LocalizedError, Sendable, Equatable {
    case unknownTool(String)
    case providerNotFound(String)
    case invalidArgument(String)
    case executionFailed(String, String)
    
    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .providerNotFound(let id): return "Provider not found: \(id)"
        case .invalidArgument(let msg): return "Invalid argument: \(msg)"
        case .executionFailed(let tool, let msg): return "Execution failed for \(tool): \(msg)"
        }
    }
}