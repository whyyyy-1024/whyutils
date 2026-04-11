import Foundation

struct ToolRegistry: Sendable {
    private let providers: [ToolProvider]
    private let toolCache: [String: ToolDescriptor]
    
    init(providers: [ToolProvider]) {
        self.providers = providers
        var cache: [String: ToolDescriptor] = [:]
        for provider in providers {
            for tool in provider.tools() {
                cache[tool.name] = tool
            }
        }
        self.toolCache = cache
    }
    
    func tool(named name: String) -> ToolDescriptor? {
        toolCache[name]
    }
    
    func allTools() -> [ToolDescriptor] {
        Array(toolCache.values)
    }
    
    func toolsByDangerLevel() -> [DangerLevel: [ToolDescriptor]] {
        Dictionary(grouping: toolCache.values) { $0.dangerousLevel }
    }
}