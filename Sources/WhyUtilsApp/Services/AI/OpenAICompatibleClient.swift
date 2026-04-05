import Foundation

enum OpenAICompatibleClientError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case missingModel

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid base URL"
        case .missingAPIKey:
            return "Missing API key"
        case .missingModel:
            return "Missing model"
        }
    }
}

struct OpenAIChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

enum OpenAICompatibleClient {
    static func buildChatRequest(
        configuration: AIConfiguration,
        messages: [OpenAIChatMessage]
    ) throws -> URLRequest {
        let base = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, var components = URLComponents(string: base) else {
            throw OpenAICompatibleClientError.invalidBaseURL
        }
        guard !configuration.apiKey.isEmpty else {
            throw OpenAICompatibleClientError.missingAPIKey
        }
        guard !configuration.model.isEmpty else {
            throw OpenAICompatibleClientError.missingModel
        }

        let normalizedPath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = normalizedPath + "/chat/completions"

        guard let url = components.url else {
            throw OpenAICompatibleClientError.invalidBaseURL
        }

        struct ChatRequestBody: Codable {
            let model: String
            let messages: [OpenAIChatMessage]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequestBody(
                model: configuration.model,
                messages: messages
            )
        )
        return request
    }
}
