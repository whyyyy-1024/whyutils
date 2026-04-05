import Foundation

struct AIConfiguration: Codable, Equatable {
    var isEnabled: Bool = false
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
}

enum AIAgentExecutionState: Equatable {
    case idle
    case planning
    case awaitingConfirmation
    case executing
    case completed
    case failed(message: String)
}

struct AIPlanStep: Codable, Equatable, Identifiable {
    let id: UUID
    let toolName: String
    let argumentsJSON: String
    var requiresConfirmation: Bool

    init(
        id: UUID = UUID(),
        toolName: String,
        argumentsJSON: String,
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.requiresConfirmation = requiresConfirmation
    }
}

struct AIExecutionPlan: Codable, Equatable {
    let goal: String
    let steps: [AIPlanStep]

    var requiresConfirmation: Bool {
        steps.contains(where: \.requiresConfirmation)
    }

    func exceedsStepLimit(limit: Int) -> Bool {
        steps.count > limit
    }
}
