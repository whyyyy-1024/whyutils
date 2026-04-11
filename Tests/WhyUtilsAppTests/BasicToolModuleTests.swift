import Testing
@testable import WhyUtilsApp

struct BasicToolModuleTests {
    @Test
    func moduleContainsClipboardTools() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "clipboard_read_latest" }))
        #expect(tools.contains(where: { $0.name == "clipboard_list_history" }))
    }
    
    @Test
    func moduleContainsJsonTools() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "json_format" }))
        #expect(tools.contains(where: { $0.name == "json_validate" }))
        #expect(tools.contains(where: { $0.name == "json_minify" }))
    }
    
    @Test
    func fullAccessIncludesShellTools() {
        let module = BasicToolModule(accessMode: .fullAccess)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "run_shell_command" }))
        #expect(tools.contains(where: { $0.name == "read_file" }))
        #expect(tools.contains(where: { $0.name == "write_file" }))
    }
    
    @Test
    func standardModeRequiresConfirmationForSideEffects() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        let openApp = tools.first(where: { $0.name == "open_app" })
        #expect(openApp?.requiresConfirmation == true)
    }
    
    @Test
    func fullAccessSkipsConfirmationForSideEffects() {
        let module = BasicToolModule(accessMode: .fullAccess)
        let tools = module.tools()
        
        let shell = tools.first(where: { $0.name == "run_shell_command" })
        #expect(shell?.requiresConfirmation == false)
    }
    
    @Test
    func executeJsonFormatTool() async throws {
        let module = BasicToolModule(accessMode: .standard)
        let result = try await module.execute(
            toolName: "json_format",
            arguments: ["input": "{\"ok\":true}"]
        )
        #expect(result.contains("\"ok\""))
    }
    
    @Test
    func unknownToolThrowsError() async throws {
        let module = BasicToolModule(accessMode: .standard)
        do {
            _ = try await module.execute(toolName: "unknown_tool", arguments: [:])
            Issue.record("Expected unknown tool error")
        } catch let error as ToolError {
            #expect(error == .unknownTool("unknown_tool"))
        }
    }
    
    @Test
    func redactSensitiveTextMasksAPIKeys() {
        let text = "apiKey = secret-value-12345"
        let redacted = BasicToolModule.redactSensitiveText(text)
        #expect(redacted.contains("[REDACTED SECRET]"))
        #expect(redacted.contains("secret-value-12345") == false)
    }
    
    @Test
    func redactSensitiveTextMasksSKPrefixes() {
        let text = "sk-test-api-key-123456789012"
        let redacted = BasicToolModule.redactSensitiveText(text)
        #expect(redacted.contains("[REDACTED SECRET]"))
    }
    
    @Test
    func standardModeDoesNotIncludeFullAccessTools() {
        let module = BasicToolModule(accessMode: .standard)
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "list_directory" }) == false)
        #expect(tools.contains(where: { $0.name == "read_file" }) == false)
        #expect(tools.contains(where: { $0.name == "open_url" }) == false)
    }
    
    @Test
    func providerIdIsBasic() {
        let module = BasicToolModule(accessMode: .standard)
        #expect(module.providerId == "basic")
    }
    
    @Test
    func allToolDescriptorsHaveCorrectProviderId() {
        let module = BasicToolModule(accessMode: .fullAccess)
        for tool in module.tools() {
            #expect(tool.providerId == "basic")
        }
    }
}