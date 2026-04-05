import Foundation
import Testing
@testable import WhyUtilsApp

struct OpenAICompatibleClientTests {
    @Test
    func buildsChatCompletionsRequest() throws {
        let config = AIConfiguration(
            isEnabled: true,
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1"
        )
        let request = try OpenAICompatibleClient.buildChatRequest(
            configuration: config,
            messages: [
                .init(role: "user", content: "Hello")
            ]
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test
    func normalizesBaseURLWithoutTrailingSlashIssues() throws {
        let config = AIConfiguration(
            isEnabled: true,
            baseURL: "https://example.com/v1/",
            apiKey: "secret",
            model: "gpt-4.1"
        )
        let request = try OpenAICompatibleClient.buildChatRequest(
            configuration: config,
            messages: [.init(role: "user", content: "Hello")]
        )

        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    }
}
