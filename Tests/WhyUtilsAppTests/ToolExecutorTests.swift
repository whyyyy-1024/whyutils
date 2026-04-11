import Testing
@testable import WhyUtilsApp

struct ToolExecutorTests {
    @Test
    func executorRoutesToCorrectProvider() async throws {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        let executor = ToolExecutor(registry: registry, providers: [provider])
        
        let result = try await executor.execute(toolName: "mock_tool", arguments: [:])
        #expect(result.toolName == "mock_tool")
        #expect(result.success == true)
        #expect(result.output == "executed mock_tool")
    }
    
    @Test
    func executorThrowsForUnknownTool() async {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        let executor = ToolExecutor(registry: registry, providers: [provider])
        
        await #expect(throws: ToolError.unknownTool("nope")) {
            try await executor.execute(toolName: "nope", arguments: [:])
        }
    }
    
    @Test
    func executorThrowsForProviderNotFound() async throws {
        let provider = MockToolProvider()
        let registry = ToolRegistry(providers: [provider])
        let executor = ToolExecutor(registry: registry, providers: [])
        
        await #expect(throws: ToolError.providerNotFound("mock")) {
            try await executor.execute(toolName: "mock_tool", arguments: [:])
        }
    }
}

private struct MockToolProvider: ToolProvider {
    let providerId = "mock"
    
    func tools() -> [ToolDescriptor] {
        [ToolDescriptor(
            name: "mock_tool",
            description: "Mock tool",
            providerId: "mock",
            dangerousLevel: .safe
        )]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        "executed \(toolName)"
    }
}