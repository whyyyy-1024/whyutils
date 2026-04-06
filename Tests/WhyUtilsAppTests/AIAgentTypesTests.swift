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
        #expect(config.accessMode == .standard)
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

    @Test
    func confirmationRequestListsOnlySideEffectfulTools() {
        let plan = AIExecutionPlan(
            goal: "Open Finder",
            steps: [
                AIPlanStep(toolName: "json_format", argumentsJSON: "{}"),
                AIPlanStep(toolName: "open_app", argumentsJSON: "{\"bundleIdentifier\":\"com.apple.finder\"}", requiresConfirmation: true)
            ]
        )

        let request = AIConfirmationRequest(plan: plan)
        #expect(request.summary == "open_app")
    }

    @Test
    func unrestrictedAccessModeExpandsCapabilities() {
        #expect(AIAgentAccessMode.standard.includesFullAccessTools == false)
        #expect(AIAgentAccessMode.standard.requiresConfirmationForSideEffects == true)
        #expect(AIAgentAccessMode.standard.maxPlanSteps == 3)

        #expect(AIAgentAccessMode.fullAccess.includesFullAccessTools == true)
        #expect(AIAgentAccessMode.fullAccess.requiresConfirmationForSideEffects == true)
        #expect(AIAgentAccessMode.fullAccess.maxPlanSteps == 3)

        #expect(AIAgentAccessMode.unrestricted.includesFullAccessTools == true)
        #expect(AIAgentAccessMode.unrestricted.requiresConfirmationForSideEffects == false)
        #expect(AIAgentAccessMode.unrestricted.maxPlanSteps == 8)
    }
}
