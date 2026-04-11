import Foundation

struct ToolExecutor: Sendable {
    private let registry: ToolRegistry
    private let providers: [String: ToolProvider]
    
    init(registry: ToolRegistry, providers: [ToolProvider]) {
        self.registry = registry
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.providerId, $0) })
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let tool = registry.tool(named: toolName) else {
            throw ToolError.unknownTool(toolName)
        }
        guard let provider = providers[tool.providerId] else {
            throw ToolError.providerNotFound(tool.providerId)
        }
        
        let start = Date()
        let output = try await provider.execute(toolName: toolName, arguments: arguments)
        let duration = Int(Date().timeIntervalSince(start) * 1000)
        
        return ToolResult(
            toolName: toolName,
            output: output,
            durationMs: duration,
            success: true
        )
    }
}