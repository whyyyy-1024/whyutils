import Testing
@testable import WhyUtilsApp

struct ToolTypesTests {
    @Test
    func dangerLevelOrdering() {
        #expect(DangerLevel.safe.rawValue < DangerLevel.moderate.rawValue)
        #expect(DangerLevel.moderate.rawValue < DangerLevel.dangerous.rawValue)
    }
    
    @Test
    func toolDescriptorContainsRequiredFields() {
        let tool = ToolDescriptor(
            name: "test_tool",
            description: "A test tool",
            parameters: [],
            requiresConfirmation: true,
            providerId: "basic",
            dangerousLevel: .moderate
        )
        #expect(tool.name == "test_tool")
        #expect(tool.requiresConfirmation == true)
        #expect(tool.dangerousLevel == .moderate)
        #expect(tool.providerId == "basic")
    }
}