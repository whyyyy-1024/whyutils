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

    @Test
    func fullAccessRegistryContainsShellTool() {
        let registry = AIToolRegistry.configured(
            accessMode: .fullAccess
        )
        let tool = registry.tool(named: "run_shell_command")
        #expect(tool != nil)
        #expect(tool?.requiresConfirmation == false)
    }

    @Test
    func fullAccessRegistrySkipsConfirmationForSideEffects() {
        let registry = AIToolRegistry.configured(accessMode: .fullAccess)
        let shellTool = registry.tool(named: "run_shell_command")
        let writeTool = registry.tool(named: "write_file")
        let openApp = registry.tool(named: "open_app")
        #expect(shellTool?.requiresConfirmation == false)
        #expect(writeTool?.requiresConfirmation == false)
        #expect(openApp?.requiresConfirmation == false)
    }
}
