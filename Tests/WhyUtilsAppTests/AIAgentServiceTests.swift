import Testing
@testable import WhyUtilsApp

struct AIAgentServiceTests {
    @Test
    func planningRejectsUnknownTool() {
        let service = AIAgentService(
            registry: .live,
            transport: .failingStub,
            executor: .noOp
        )

        let plan = AIExecutionPlan(
            goal: "Unknown tool",
            steps: [AIPlanStep(toolName: "nope", argumentsJSON: "{}")]
        )

        #expect(service.validate(plan: plan).isValid == false)
    }

    @Test
    func sideEffectfulPlanRequiresConfirmation() {
        let service = AIAgentService(
            registry: .live,
            transport: .failingStub,
            executor: .noOp
        )

        let plan = AIExecutionPlan(
            goal: "Open app",
            steps: [
                AIPlanStep(
                    toolName: "open_app",
                    argumentsJSON: "{\"bundleIdentifier\":\"com.apple.finder\"}",
                    requiresConfirmation: true
                )
            ]
        )

        let result = service.validate(plan: plan)
        #expect(result.isValid == true)
        #expect(result.requiresConfirmation == true)
    }
}
