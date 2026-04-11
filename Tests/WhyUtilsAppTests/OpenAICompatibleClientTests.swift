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

    @Test
    func parsesChatCompletionResponseContent() throws {
        let data = Data(
            """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"goal\\":\\"Format clipboard\\",\\"steps\\":[]}"
                  }
                }
              ]
            }
            """.utf8
        )

        let content = try OpenAICompatibleClient.parseChatCompletionResponse(data)
        #expect(content == "{\"goal\":\"Format clipboard\",\"steps\":[]}")
    }

    @Test
    func buildChatRequestCanEnableStreaming() throws {
        let config = AIConfiguration(
            isEnabled: true,
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1"
        )
        let request = try OpenAICompatibleClient.buildChatRequest(
            configuration: config,
            messages: [.init(role: "user", content: "Hello")],
            stream: true
        )

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["stream"] as? Bool == true)
        let streamOptions = try #require(json?["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test
    func buildsChatRequestWithImageParts() throws {
        let config = AIConfiguration(
            isEnabled: true,
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1"
        )
        let request = try OpenAICompatibleClient.buildChatRequest(
            configuration: config,
            messages: [
                .init(
                    role: "user",
                    content: .parts([
                        .text("Describe this image"),
                        .imageURL("data:image/png;base64,AAA")
                    ])
                )
            ]
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let first = try #require(messages.first)
        let content = try #require(first["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content.first?["type"] as? String == "text")
        #expect((content.last?["image_url"] as? [String: Any])?["url"] as? String == "data:image/png;base64,AAA")
    }

    @Test
    func parsesStreamingDeltaChunk() throws {
        let chunk = """
        {"choices":[{"delta":{"content":"hello"}}]}
        """

        let content = try OpenAICompatibleClient.parseChatCompletionStreamChunk(chunk)
        #expect(content == "hello")
    }

    @Test
    func parsesTopLevelUsageFromChatCompletionResponse() throws {
        let data = Data(
            """
            {
              "choices": [
                {
                  "message": {
                    "content": "hello"
                  }
                }
              ],
              "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 4,
                "total_tokens": 14
              }
            }
            """.utf8
        )

        let usage = try OpenAICompatibleClient.parseChatCompletionUsage(data)
        #expect(usage?.promptTokens == 10)
        #expect(usage?.completionTokens == 4)
        #expect(usage?.totalTokens == 14)
    }

    @Test
    func parsesUsageFromStreamingChunk() throws {
        let chunk = """
        {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}
        """

        let usage = try OpenAICompatibleClient.parseChatCompletionStreamUsageChunk(chunk)
        #expect(usage?.promptTokens == 12)
        #expect(usage?.completionTokens == 8)
        #expect(usage?.totalTokens == 20)
    }
}
