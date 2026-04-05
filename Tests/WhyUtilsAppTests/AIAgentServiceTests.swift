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

    @Test
    func submitReturnsConfirmationForSideEffectfulPlan() async throws {
        let service = AIAgentService(
            registry: .live,
            transport: AITransport { _, _ in
                """
                {"goal":"Open Finder","steps":[{"toolName":"open_app","argumentsJSON":"{\\"bundleIdentifier\\":\\"com.apple.finder\\"}"}]}
                """
            },
            executor: .noOp
        )

        let result = try await service.submit(
            task: "Open Finder",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test"),
            context: .empty
        )

        switch result {
        case .awaitingConfirmation(let request):
            #expect(request.plan.goal == "Open Finder")
            #expect(request.summary == "open_app")
        case .completed:
            Issue.record("Expected confirmation gate")
        }
    }

    @Test
    func submitExecutesSafePlanAndReturnsTrace() async throws {
        let service = AIAgentService(
            registry: .live,
            transport: AITransport { _, _ in
                """
                {"goal":"Format JSON","steps":[{"toolName":"json_format","argumentsJSON":"{\\"input\\":\\"{\\\\\\"ok\\\\\\":true}\\"}"}]}
                """
            },
            executor: AIToolExecutor { step in
                #expect(step.toolName == "json_format")
                return "{\n  \"ok\" : true\n}"
            }
        )

        let result = try await service.submit(
            task: "Format JSON",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test"),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.plan.goal == "Format JSON")
            #expect(run.traces.count == 1)
            #expect(run.traces[0].toolName == "json_format")
            #expect(run.finalMessage.contains("\"ok\""))
        case .awaitingConfirmation:
            Issue.record("Expected immediate completion")
        }
    }

    @Test
    func confirmExecutesPreviouslyApprovedPlan() async throws {
        let service = AIAgentService(
            registry: .live,
            transport: .failingStub,
            executor: AIToolExecutor { step in
                #expect(step.toolName == "open_app")
                return "Opened Finder"
            }
        )
        let request = AIConfirmationRequest(
            plan: AIExecutionPlan(
                goal: "Open Finder",
                steps: [
                    AIPlanStep(
                        toolName: "open_app",
                        argumentsJSON: "{\"bundleIdentifier\":\"com.apple.finder\"}",
                        requiresConfirmation: true
                    )
                ]
            )
        )

        let run = try await service.confirm(request)
        #expect(run.traces.count == 1)
        #expect(run.finalMessage == "Opened Finder")
    }
}
