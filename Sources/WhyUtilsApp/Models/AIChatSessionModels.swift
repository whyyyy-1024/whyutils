import Foundation

enum AIChatMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

struct AIChatImageAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let pngData: Data
    let width: Int
    let height: Int
    let fileName: String?

    init(
        id: UUID = UUID(),
        pngData: Data,
        width: Int,
        height: Int,
        fileName: String? = nil
    ) {
        self.id = id
        self.pngData = pngData
        self.width = width
        self.height = height
        self.fileName = fileName
    }

    var dataURL: String {
        "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}

struct AIChatMessageRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: AIChatMessageRole
    var text: String
    let createdAt: Date
    var imageAttachments: [AIChatImageAttachment]
    var toolTraces: [AIToolExecutionTrace]
    var confirmationRequest: AIConfirmationRequest?
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: AIChatMessageRole,
        text: String,
        createdAt: Date = Date(),
        imageAttachments: [AIChatImageAttachment] = [],
        toolTraces: [AIToolExecutionTrace] = [],
        confirmationRequest: AIConfirmationRequest? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.imageAttachments = imageAttachments
        self.toolTraces = toolTraces
        self.confirmationRequest = confirmationRequest
        self.isStreaming = isStreaming
    }
}

struct AIChatSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var isUserRenamed: Bool
    let createdAt: Date
    var updatedAt: Date
    var messages: [AIChatMessageRecord]

    init(
        id: UUID = UUID(),
        title: String,
        isUserRenamed: Bool,
        createdAt: Date,
        updatedAt: Date,
        messages: [AIChatMessageRecord]
    ) {
        self.id = id
        self.title = title
        self.isUserRenamed = isUserRenamed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    static func empty(id: UUID = UUID(), now: Date = Date()) -> AIChatSession {
        AIChatSession(
            id: id,
            title: "",
            isUserRenamed: false,
            createdAt: now,
            updatedAt: now,
            messages: []
        )
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New chat" : trimmed
    }

    func applyingAutoTitle(from source: String) -> AIChatSession {
        guard isUserRenamed == false else { return self }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return self }

        var next = self
        next.title = String(trimmed.prefix(36))
        return next
    }

    func renamed(to newTitle: String) -> AIChatSession {
        var next = self
        next.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        next.isUserRenamed = true
        return next
    }

    func normalizedForPersistence() -> AIChatSession {
        var next = self
        next.messages = next.messages.map { message in
            var normalized = message
            normalized.isStreaming = false
            return normalized
        }
        return next
    }
}

extension AIChatMessageRecord {
    var openAIMessage: OpenAIChatMessage? {
        switch role {
        case .user:
            if imageAttachments.isEmpty {
                return OpenAIChatMessage(role: "user", content: .text(text))
            }

            var parts: [OpenAIChatContentPart] = []
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                parts.append(.text(trimmed))
            }
            parts.append(contentsOf: imageAttachments.map { .imageURL($0.dataURL) })
            return OpenAIChatMessage(role: "user", content: .parts(parts))
        case .assistant:
            return OpenAIChatMessage(role: "assistant", content: .text(text))
        case .system:
            return nil
        }
    }
}
