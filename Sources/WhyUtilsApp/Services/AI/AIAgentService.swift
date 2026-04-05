import Foundation

struct AIPlanValidationResult: Equatable {
    let isValid: Bool
    let requiresConfirmation: Bool
    let message: String?
}

struct AITransport {
    static let failingStub = AITransport()
}

struct AIToolExecutor {
    static let noOp = AIToolExecutor()
}

struct AIAgentService {
    let registry: AIToolRegistry
    let transport: AITransport
    let executor: AIToolExecutor

    func validate(plan: AIExecutionPlan) -> AIPlanValidationResult {
        if plan.exceedsStepLimit(limit: 3) {
            return AIPlanValidationResult(
                isValid: false,
                requiresConfirmation: false,
                message: "Plan exceeds step limit"
            )
        }

        for step in plan.steps {
            guard let tool = registry.tool(named: step.toolName) else {
                return AIPlanValidationResult(
                    isValid: false,
                    requiresConfirmation: false,
                    message: "Unknown tool: \(step.toolName)"
                )
            }
            if tool.requiresConfirmation {
                return AIPlanValidationResult(
                    isValid: true,
                    requiresConfirmation: true,
                    message: nil
                )
            }
        }

        return AIPlanValidationResult(
            isValid: true,
            requiresConfirmation: false,
            message: nil
        )
    }
}
