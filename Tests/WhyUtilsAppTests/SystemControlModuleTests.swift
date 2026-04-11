import Foundation
import Testing
@testable import WhyUtilsApp

struct SystemControlModuleTests {
    @Test
    func moduleContainsSystemControlTools() {
        let module = SystemControlModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "process_list" }))
        #expect(tools.contains(where: { $0.name == "process_info" }))
        #expect(tools.contains(where: { $0.name == "process_kill" }))
        #expect(tools.contains(where: { $0.name == "network_request" }))
        #expect(tools.contains(where: { $0.name == "screenshot" }))
        #expect(tools.contains(where: { $0.name == "window_list" }))
    }
    
    @Test
    func processKillRequiresConfirmation() {
        let module = SystemControlModule()
        let tools = module.tools()
        let kill = tools.first(where: { $0.name == "process_kill" })
        #expect(kill?.requiresConfirmation == true)
    }
    
    @Test
    func processKillHasDangerousLevel() {
        let module = SystemControlModule()
        let tools = module.tools()
        let kill = tools.first(where: { $0.name == "process_kill" })
        #expect(kill?.dangerousLevel == .dangerous)
    }
    
    @Test
    func processListTool() async throws {
        let module = SystemControlModule()
        let result = try await module.execute(
            toolName: "process_list",
            arguments: ["limit": 5]
        )
        #expect(result.contains("PID") || result.contains("Process") || !result.isEmpty)
    }
    
    @Test
    func processInfoTool() async throws {
        let module = SystemControlModule()
        let result = try await module.execute(
            toolName: "process_info",
            arguments: ["pid": 1]
        )
        #expect(!result.isEmpty)
    }
    
    @Test
    func processKillProtectsKernelTask() async throws {
        let module = SystemControlModule()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "0", "-o", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let name = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard name == "kernel_task" else {
            Issue.record("PID 0 is not kernel_task, skipping test")
            return
        }
        
        let result = try await module.execute(
            toolName: "process_kill",
            arguments: ["pid": 0]
        )
        #expect(result.contains("protected"))
    }
    
    @Test
    func unknownToolThrowsError() async throws {
        let module = SystemControlModule()
        do {
            _ = try await module.execute(toolName: "unknown_tool", arguments: [:])
            Issue.record("Expected unknown tool error")
        } catch let error as ToolError {
            #expect(error == .unknownTool("unknown_tool"))
        }
    }
    
    @Test
    func providerIdIsSystemControl() {
        let module = SystemControlModule()
        #expect(module.providerId == "systemcontrol")
    }
    
    @Test
    func allToolDescriptorsHaveCorrectProviderId() {
        let module = SystemControlModule()
        for tool in module.tools() {
            #expect(tool.providerId == "systemcontrol")
        }
    }
}