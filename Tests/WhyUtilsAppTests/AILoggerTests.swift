import Foundation
import Testing
@testable import WhyUtilsApp

struct AILoggerTests {
    @Test
    func logFilePathUsesLibraryLogsWhyutils() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let url = AILogger.logFileURL(homeDirectory: home)
        #expect(url.path == "/Users/tester/Library/Logs/whyutils/ai.log")
    }

    @Test
    func formattedEntryIncludesStatusHeadersBodyAndError() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.com/v1/chat/completions")!,
                statusCode: 502,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "X-Request-ID": "req_123"
                ]
            )
        )

        let entry = AILogger.formatEntry(
            kind: "complete",
            url: response.url,
            statusCode: response.statusCode,
            usageSummary: "prompt_tokens=12, completion_tokens=34, total_tokens=46",
            headers: response.allHeaderFields,
            body: "{\"error\":\"bad gateway\"}",
            error: OpenAICompatibleClientError.serverError(statusCode: 502, message: "bad gateway"),
            date: Date(timeIntervalSince1970: 0),
            pid: 42
        )

        #expect(entry.contains("AI COMPLETE"))
        #expect(entry.contains("https://example.com/v1/chat/completions"))
        #expect(entry.contains("Status: 502"))
        #expect(entry.contains("Usage: prompt_tokens=12, completion_tokens=34, total_tokens=46"))
        #expect(entry.contains("Content-Type: application/json"))
        #expect(entry.contains("X-Request-ID: req_123"))
        #expect(entry.contains("{\"error\":\"bad gateway\"}"))
        #expect(entry.contains("Request failed (502): bad gateway"))
        #expect(entry.contains("[pid:42]"))
    }
}
