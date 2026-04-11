import Testing
@testable import WhyUtilsApp

struct ToolRegistryTests {
    @Test
    func registryReturnsToolsFromProviders() {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        
        let tool = registry.tool(named: "mock_tool")
        #expect(tool != nil)
        #expect(tool?.name == "mock_tool")
        #expect(tool?.providerId == "mock")
    }
    
    @Test
    func registryReturnsNilForUnknownTool() {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        
        #expect(registry.tool(named: "unknown") == nil)
    }
    
    @Test
    func registryReturnsAllTools() {
        let provider1 = MockToolProvider(prefix: "a")
        let provider2 = MockToolProvider(prefix: "b")
        let registry = ToolRegistry(providers: [provider1, provider2])
        
        #expect(registry.allTools().count == 2)
    }
}

private struct MockToolProvider: ToolProvider {
    let providerId: String
    private let prefix: String
    
    init(prefix: String = "") {
        self.providerId = "mock"
        self.prefix = prefix
    }
    
    func tools() -> [ToolDescriptor] {
        [ToolDescriptor(
            name: "\(prefix)mock_tool",
            description: "Mock tool",
            providerId: "mock",
            dangerousLevel: .safe
        )]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        return "executed \(toolName)"
    }
}