import Foundation

struct AIConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool = false
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
}

enum AIAgentExecutionState: Equatable, Sendable {
    case idle
    case planning
    case awaitingConfirmation
    case executing
    case completed
    case failed(message: String)
}

struct AIPlanStep: Codable, Equatable, Identifiable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id
        case toolName
        case argumentsJSON
        case requiresConfirmation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        toolName = try container.decode(String.self, forKey: .toolName)
        argumentsJSON = try container.decode(String.self, forKey: .argumentsJSON)
        requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
    }
}

struct AIExecutionPlan: Codable, Equatable, Sendable {
    let goal: String
    let steps: [AIPlanStep]

    var requiresConfirmation: Bool {
        steps.contains(where: \.requiresConfirmation)
    }

    func exceedsStepLimit(limit: Int) -> Bool {
        steps.count > limit
    }
}

struct AIAgentContext: Equatable, Sendable {
    let latestClipboardText: String?
    let recentClipboardTexts: [String]
    let pasteTargetAppName: String

    static let empty = AIAgentContext(
        latestClipboardText: nil,
        recentClipboardTexts: [],
        pasteTargetAppName: "Current App"
    )
}

struct AIConfirmationRequest: Equatable, Sendable {
    let plan: AIExecutionPlan

    var summary: String {
        plan.steps
            .filter(\.requiresConfirmation)
            .map(\.toolName)
            .joined(separator: ", ")
    }
}

struct AIToolExecutionTrace: Equatable, Identifiable, Sendable {
    let id: UUID
    let toolName: String
    let argumentsJSON: String
    let output: String

    init(
        id: UUID = UUID(),
        toolName: String,
        argumentsJSON: String,
        output: String
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.output = output
    }
}

struct AIAgentRunResult: Equatable, Sendable {
    let plan: AIExecutionPlan
    let traces: [AIToolExecutionTrace]
    let finalMessage: String
}

enum AIAgentSubmissionResult: Equatable, Sendable {
    case awaitingConfirmation(AIConfirmationRequest)
    case completed(AIAgentRunResult)
}
