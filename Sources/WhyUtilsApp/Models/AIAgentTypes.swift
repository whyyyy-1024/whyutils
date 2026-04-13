import Foundation

enum AIAgentAccessMode: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case standard
    case fullAccess

    var id: String { rawValue }

    var includesFullAccessTools: Bool {
        self == .fullAccess
    }

    var requiresConfirmationForSideEffects: Bool {
        self == .standard
    }

    var maxPlanSteps: Int {
        switch self {
        case .standard:
            return 3
        case .fullAccess:
            return 8
        }
    }
}

struct AIConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool = false
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
    var accessMode: AIAgentAccessMode = .standard

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case baseURL
        case apiKey
        case model
        case accessMode
        case fullAccessEnabled
        case skipConfirmationForSideEffects
    }

    init(
        isEnabled: Bool = false,
        baseURL: String = "",
        apiKey: String = "",
        model: String = "",
        accessMode: AIAgentAccessMode = .standard
    ) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.accessMode = accessMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        if let accessMode = try container.decodeIfPresent(AIAgentAccessMode.self, forKey: .accessMode) {
            self.accessMode = accessMode
        } else {
            let fullAccessEnabled = try container.decodeIfPresent(Bool.self, forKey: .fullAccessEnabled) ?? false
            self.accessMode = fullAccessEnabled ? .fullAccess : .standard
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(model, forKey: .model)
        try container.encode(accessMode, forKey: .accessMode)
    }
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
    let storedMemories: [String]

    static let empty = AIAgentContext(
        latestClipboardText: nil,
        recentClipboardTexts: [],
        pasteTargetAppName: "Current App",
        storedMemories: []
    )
}

struct AIConfirmationRequest: Codable, Equatable, Sendable {
    let plan: AIExecutionPlan

    var summary: String {
        plan.steps
            .filter(\.requiresConfirmation)
            .map(\.toolName)
            .joined(separator: ", ")
    }
}

struct AIToolExecutionTrace: Codable, Equatable, Identifiable, Sendable {
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
