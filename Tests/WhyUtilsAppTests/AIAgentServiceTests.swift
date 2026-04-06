import Foundation
import Testing
@testable import WhyUtilsApp

struct AIAgentServiceTests {
    @Test
    func redactSensitiveTextMasksAPIKeys() {
        let text = """
        qwen3.5-plus
        apiKey = local-test-secret-value-12345
        """

        let redacted = AIToolExecutor.redactSensitiveText(text)
        #expect(redacted.contains("qwen3.5-plus"))
        #expect(redacted.contains("[REDACTED SECRET]"))
        #expect(redacted.contains("local-test-secret-value-12345") == false)
    }

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
                {"type":"tool_plan","goal":"Open Finder","steps":[{"toolName":"open_app","argumentsJSON":"{\\"bundleIdentifier\\":\\"com.apple.finder\\"}"}]}
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
                {"type":"tool_plan","goal":"Format JSON","steps":[{"toolName":"json_format","argumentsJSON":"{\\"input\\":\\"{\\\\\\"ok\\\\\\":true}\\"}"}]}
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
    func submitCanReturnDirectChatMessage() async throws {
        let service = AIAgentService(
            registry: .live,
            transport: AITransport { _, _ in
                """
                {"type":"message","message":"当然可以，直接和我聊天就行。"}
                """
            },
            executor: .noOp
        )

        let result = try await service.submit(
            task: "你是谁",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test"),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.traces.isEmpty)
            #expect(run.finalMessage == "当然可以，直接和我聊天就行。")
        case .awaitingConfirmation:
            Issue.record("Expected direct message")
        }
    }

    @Test
    func fullAccessCapabilityQuestionMentionsLocalFileAccess() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .fullAccess),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.fullAccess.maxPlanSteps,
            accessMode: .fullAccess
        )

        let result = try await service.submit(
            task: "你能读取到我电脑上的文件吗",
            configuration: .init(
                isEnabled: true,
                baseURL: "https://example.com/v1",
                apiKey: "secret",
                model: "gpt-test",
                accessMode: .fullAccess
            ),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.traces.isEmpty)
            #expect(run.finalMessage.contains("读取"))
            #expect(run.finalMessage.contains("文件"))
            #expect(run.finalMessage.contains("路径"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func standardCapabilityQuestionExplainsFileAccessIsUnavailable() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .standard),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.standard.maxPlanSteps,
            accessMode: .standard
        )

        let result = try await service.submit(
            task: "Can you read files on my Mac?",
            configuration: .init(
                isEnabled: true,
                baseURL: "https://example.com/v1",
                apiKey: "secret",
                model: "gpt-test",
                accessMode: .standard
            ),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.traces.isEmpty)
            #expect(run.finalMessage.localizedCaseInsensitiveContains("can't"))
            #expect(run.finalMessage.localizedCaseInsensitiveContains("full access"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func fullAccessCapabilityQuestionMentionsShellCommands() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .fullAccess),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.fullAccess.maxPlanSteps,
            accessMode: .fullAccess
        )

        let result = try await service.submit(
            task: "你能执行命令吗",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test", accessMode: .fullAccess),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.finalMessage.contains("命令"))
            #expect(run.finalMessage.contains("shell") || run.finalMessage.contains("Shell"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func standardCapabilityQuestionExplainsShellCommandsNeedHigherAccess() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .standard),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.standard.maxPlanSteps,
            accessMode: .standard
        )

        let result = try await service.submit(
            task: "Can you run shell commands?",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test", accessMode: .standard),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.finalMessage.localizedCaseInsensitiveContains("can't"))
            #expect(run.finalMessage.localizedCaseInsensitiveContains("full access"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func fullAccessCapabilityQuestionMentionsOpeningBrowser() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .fullAccess),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.fullAccess.maxPlanSteps,
            accessMode: .fullAccess
        )

        let result = try await service.submit(
            task: "你能打开浏览器吗",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test", accessMode: .fullAccess),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.finalMessage.contains("浏览器"))
            #expect(run.finalMessage.contains("URL") || run.finalMessage.contains("网址"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func fullAccessCapabilityQuestionMentionsWritingFiles() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .fullAccess),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.fullAccess.maxPlanSteps,
            accessMode: .fullAccess
        )

        let result = try await service.submit(
            task: "你能修改文件吗",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test", accessMode: .fullAccess),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.finalMessage.contains("修改"))
            #expect(run.finalMessage.contains("确认") || run.finalMessage.contains("写"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func fullAccessCapabilityQuestionMentionsDirectorySearch() async throws {
        let service = AIAgentService(
            registry: .configured(accessMode: .fullAccess),
            transport: AITransport { _, _ in
                Issue.record("Capability questions should be answered locally before hitting the model")
                return ""
            },
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.fullAccess.maxPlanSteps,
            accessMode: .fullAccess
        )

        let result = try await service.submit(
            task: "你能搜索本地目录吗",
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test", accessMode: .fullAccess),
            context: .empty
        )

        switch result {
        case .completed(let run):
            #expect(run.finalMessage.contains("目录"))
            #expect(run.finalMessage.contains("路径"))
        case .awaitingConfirmation:
            Issue.record("Expected direct capability answer")
        }
    }

    @Test
    func unrestrictedModeAllowsLongerPlansWithoutConfirmation() {
        let service = AIAgentService(
            registry: .configured(accessMode: .unrestricted),
            transport: .failingStub,
            executor: .noOp,
            maxPlanSteps: AIAgentAccessMode.unrestricted.maxPlanSteps,
            accessMode: .unrestricted
        )

        let plan = AIExecutionPlan(
            goal: "Run a local workflow",
            steps: [
                AIPlanStep(toolName: "list_directory", argumentsJSON: "{}"),
                AIPlanStep(toolName: "read_file", argumentsJSON: "{\"path\":\"/tmp/a.txt\"}"),
                AIPlanStep(toolName: "run_shell_command", argumentsJSON: "{\"command\":\"pwd\"}"),
                AIPlanStep(toolName: "write_file", argumentsJSON: "{\"path\":\"/tmp/b.txt\",\"content\":\"ok\"}"),
                AIPlanStep(toolName: "open_app", argumentsJSON: "{\"query\":\"Finder\"}")
            ]
        )

        let validation = service.validate(plan: plan)
        #expect(validation.isValid == true)
        #expect(validation.requiresConfirmation == false)
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

        let run = try await service.confirm(
            request,
            configuration: .init(isEnabled: true, baseURL: "https://example.com/v1", apiKey: "secret", model: "gpt-test")
        )
        #expect(run.traces.count == 1)
        #expect(run.finalMessage == "Opened Finder")
    }

}
