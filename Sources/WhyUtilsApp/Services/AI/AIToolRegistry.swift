import Foundation

struct AIToolDescriptor: Equatable {
    let name: String
    let description: String
    let requiresConfirmation: Bool
}

struct AIToolRegistry {
    let tools: [AIToolDescriptor]
    let toolRegistry: ToolRegistry
    
    static let live = AIToolRegistry(
        accessMode: .standard
    )
    
    static func configured(accessMode: AIAgentAccessMode) -> AIToolRegistry {
        AIToolRegistry(accessMode: accessMode)
    }
    
    private init(accessMode: AIAgentAccessMode) {
        let basicModule = BasicToolModule(accessMode: accessMode)
        let registry = ToolRegistry(providers: [basicModule])
        self.toolRegistry = registry
        self.tools = registry.allTools().map { desc in
            AIToolDescriptor(
                name: desc.name,
                description: desc.description,
                requiresConfirmation: desc.requiresConfirmation
            )
        }
    }
    
    func tool(named name: String) -> AIToolDescriptor? {
        tools.first(where: { $0.name == name })
    }
}