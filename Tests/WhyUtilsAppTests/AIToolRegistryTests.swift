import Testing
@testable import WhyUtilsApp

struct AIToolRegistryTests {
    @Test
    func registryContainsJsonFormattingTool() {
        let registry = AIToolRegistry.live
        let tool = registry.tool(named: "json_format")
        #expect(tool != nil)
        #expect(tool?.requiresConfirmation == false)
    }

    @Test
    func registryMarksOpenAppAsSideEffectful() {
        let registry = AIToolRegistry.live
        let tool = registry.tool(named: "open_app")
        #expect(tool != nil)
        #expect(tool?.requiresConfirmation == true)
    }

    @Test
    func unknownToolReturnsNil() {
        let registry = AIToolRegistry.live
        #expect(registry.tool(named: "made_up_tool") == nil)
    }
}
