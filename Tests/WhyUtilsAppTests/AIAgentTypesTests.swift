import Testing
@testable import WhyUtilsApp

struct AIAgentTypesTests {
    @Test
    func aiConfigurationDefaultsToDisabledAndEmptyFields() {
        let config = AIConfiguration()
        #expect(config.isEnabled == false)
        #expect(config.baseURL == "")
        #expect(config.apiKey == "")
        #expect(config.model == "")
    }

    @Test
    func planRejectsMoreThanThreeSteps() {
        let plan = AIExecutionPlan(
            goal: "Too many steps",
            steps: [
                AIPlanStep(toolName: "a", argumentsJSON: "{}"),
                AIPlanStep(toolName: "b", argumentsJSON: "{}"),
                AIPlanStep(toolName: "c", argumentsJSON: "{}"),
                AIPlanStep(toolName: "d", argumentsJSON: "{}")
            ]
        )

        #expect(plan.exceedsStepLimit(limit: 3) == true)
    }

    @Test
    func sideEffectDetectionUsesStepFlags() {
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

        #expect(plan.requiresConfirmation == true)
    }
}
