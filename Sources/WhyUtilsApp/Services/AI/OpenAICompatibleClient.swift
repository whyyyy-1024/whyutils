import Foundation

enum OpenAICompatibleClientError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case missingModel
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid base URL"
        case .missingAPIKey:
            return "Missing API key"
        case .missingModel:
            return "Missing model"
        case .invalidResponse:
            return "Invalid response payload"
        case .serverError(let statusCode, let message):
            return "Request failed (\(statusCode)): \(message)"
        }
    }
}

struct OpenAIChatMessage: Codable, Equatable, Sendable {
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

    static func completeChat(
        configuration: AIConfiguration,
        messages: [OpenAIChatMessage],
        session: URLSession = .shared
    ) async throws -> String {
        let request = try buildChatRequest(configuration: configuration, messages: messages)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAICompatibleClientError.serverError(statusCode: statusCode, message: message)
        }
        return try parseChatCompletionResponse(data)
    }

    static func parseChatCompletionResponse(_ data: Data) throws -> String {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }

                let message: Message
            }

            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content,
              content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        return content
    }
}
