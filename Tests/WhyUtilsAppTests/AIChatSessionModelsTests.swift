import Foundation
import Testing
@testable import WhyUtilsApp

struct AIChatSessionModelsTests {
    @Test
    func emptySessionStartsUntitled() {
        let session = AIChatSession.empty()
        #expect(session.title == "")
        #expect(session.isUserRenamed == false)
        #expect(session.messages.isEmpty)
        #expect(session.displayTitle == "New chat")
    }

    @Test
    func autoTitleUsesFirstUserMessageSummary() {
        let session = AIChatSession.empty()
        let titled = session.applyingAutoTitle(from: "请帮我总结这个日志文件里的错误")
        #expect(titled.title == "请帮我总结这个日志文件里的错误")
        #expect(titled.isUserRenamed == false)
    }

    @Test
    func manualRenamePreventsFutureAutoTitleOverrides() {
        let session = AIChatSession.empty().renamed(to: "我的会话")
        let retitled = session.applyingAutoTitle(from: "这条消息不应该覆盖标题")
        #expect(retitled.title == "我的会话")
        #expect(retitled.isUserRenamed == true)
    }

    @Test
    func sessionPayloadRoundTripsThroughCodable() throws {
        let attachment = AIChatImageAttachment(
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            width: 32,
            height: 32,
            fileName: "sample.png"
        )
        let original = AIChatSession(
            id: UUID(),
            title: "排查 Finder 打不开",
            isUserRenamed: true,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 120),
            messages: [
                AIChatMessageRecord(
                    id: UUID(),
                    role: .assistant,
                    text: "我已经定位到 LaunchServices 签名问题。",
                    createdAt: Date(timeIntervalSince1970: 110),
                    imageAttachments: [attachment],
                    toolTraces: [
                        AIToolExecutionTrace(
                            toolName: "run_shell_command",
                            argumentsJSON: #"{"command":"codesign -dv dist/whyutils-swift.app"}"#,
                            output: "code object is not signed at all"
                        )
                    ],
                    confirmationRequest: AIConfirmationRequest(
                        plan: AIExecutionPlan(
                            goal: "Open Finder",
                            steps: [
                                AIPlanStep(
                                    toolName: "open_app",
                                    argumentsJSON: #"{"query":"Finder"}"#,
                                    requiresConfirmation: true
                                )
                            ]
                        )
                    ),
                    isStreaming: true
                )
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIChatSession.self, from: data)

        #expect(decoded == original)
        #expect(decoded.messages.first?.toolTraces.count == 1)
        #expect(decoded.messages.first?.confirmationRequest?.summary == "open_app")
        #expect(decoded.messages.first?.imageAttachments.first?.fileName == "sample.png")
    }

    @Test
    func userMessageWithImageBuildsMultimodalOpenAIMessage() {
        let attachment = AIChatImageAttachment(
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            width: 32,
            height: 32
        )
        let message = AIChatMessageRecord(
            role: .user,
            text: "看看这张图",
            imageAttachments: [attachment]
        )

        let openAIMessage = message.openAIMessage
        #expect(openAIMessage?.role == "user")
        switch openAIMessage?.content {
        case .parts(let parts):
            #expect(parts.count == 2)
        default:
            Issue.record("Expected multimodal content parts")
        }
    }
}
