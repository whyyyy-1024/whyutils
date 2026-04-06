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

enum OpenAIChatContentPart: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private struct ImageURLPayload: Codable, Equatable, Sendable {
        let url: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            self = .imageURL(try container.decode(ImageURLPayload.self, forKey: .imageURL).url)
        default:
            throw OpenAICompatibleClientError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let value):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: value), forKey: .imageURL)
        }
    }
}

enum OpenAIChatMessageContent: Codable, Equatable, Sendable {
    case text(String)
    case parts([OpenAIChatContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .parts(try container.decode([OpenAIChatContentPart].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .parts(let value):
            try container.encode(value)
        }
    }

    var plainText: String {
        switch self {
        case .text(let value):
            return value
        case .parts(let value):
            return value.compactMap { part in
                if case .text(let text) = part { return text }
                return nil
            }
            .joined(separator: "\n")
        }
    }
}

struct OpenAIChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: OpenAIChatMessageContent

    init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(role: String, content: OpenAIChatMessageContent) {
        self.role = role
        self.content = content
    }
}

enum OpenAICompatibleClient {
    static func buildChatRequest(
        configuration: AIConfiguration,
        messages: [OpenAIChatMessage],
        stream: Bool = false
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
            let stream: Bool
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequestBody(
                model: configuration.model,
                messages: messages,
                stream: stream
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

    static func streamChat(
        configuration: AIConfiguration,
        messages: [OpenAIChatMessage],
        session: URLSession = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildChatRequest(
                        configuration: configuration,
                        messages: messages,
                        stream: true
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(statusCode) else {
                        throw OpenAICompatibleClientError.serverError(
                            statusCode: statusCode,
                            message: "Streaming request failed"
                        )
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            break
                        }
                        if let delta = try parseChatCompletionStreamChunk(payload),
                           delta.isEmpty == false {
                            continuation.yield(delta)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static func parseChatCompletionResponse(_ data: Data) throws -> String {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: OpenAIChatMessageContent
                }

                let message: Message
            }

            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content.plainText,
              content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        return content
    }

    static func parseChatCompletionStreamChunk(_ payload: String) throws -> String? {
        struct StreamResponse: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    let content: String?
                }

                let delta: Delta
            }

            let choices: [Choice]
        }

        guard let data = payload.data(using: .utf8) else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        let response = try JSONDecoder().decode(StreamResponse.self, from: data)
        return response.choices.first?.delta.content
    }
}
