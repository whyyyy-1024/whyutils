import Foundation
import Testing
@testable import WhyUtilsApp

private final class DataBox: @unchecked Sendable {
    var data: Data?
}

@MainActor
struct AIChatWorkspaceStoreTests {
    @Test
    func bootstrapCreatesBlankSessionWhenStorageIsEmpty() {
        let savedData = DataBox()
        let store = AIChatWorkspaceStore(
            persistence: .init(
                load: { nil },
                save: { savedData.data = $0 }
            ),
            now: { Date(timeIntervalSince1970: 100) }
        )

        #expect(store.sessions.count == 1)
        #expect(store.activeSession?.displayTitle == "New chat")
        #expect(savedData.data != nil)
    }

    @Test
    func createSessionSelectsItAndKeepsMostRecentFirst() {
        let store = AIChatWorkspaceStore(
            persistence: .inMemory,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let firstID = try! #require(store.activeSession?.id)

        store.createNewSession()

        #expect(store.sessions.count == 2)
        #expect(store.activeSession?.id != firstID)
        #expect(store.sessions.first?.id == store.activeSession?.id)
    }

    @Test
    func renameMarksSessionAsUserRenamed() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        let sessionID = try! #require(store.activeSession?.id)

        store.renameSession(id: sessionID, title: "部署问题排查")

        #expect(store.activeSession?.title == "部署问题排查")
        #expect(store.activeSession?.isUserRenamed == true)
    }

    @Test
    func deletingSelectedSessionFallsBackToAnotherSession() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        let firstID = try! #require(store.activeSession?.id)
        store.createNewSession()
        let secondID = try! #require(store.activeSession?.id)

        store.deleteSession(id: secondID)

        #expect(store.sessions.count == 1)
        #expect(store.activeSession?.id == firstID)
    }

    @Test
    func persistedSessionsRestoreAndNormalizeStreamingMessages() throws {
        let persisted = [
            AIChatSession(
                id: UUID(),
                title: "恢复会话",
                isUserRenamed: false,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20),
                messages: [
                    AIChatMessageRecord(
                        role: .assistant,
                        text: "还在输出",
                        createdAt: Date(timeIntervalSince1970: 15),
                        isStreaming: true
                    )
                ]
            )
        ]
        let data = try JSONEncoder().encode(persisted)
        let store = AIChatWorkspaceStore(
            persistence: .init(
                load: { data },
                save: { _ in }
            )
        )

        #expect(store.sessions.count == 1)
        #expect(store.activeSession?.title == "恢复会话")
        #expect(store.activeSession?.messages.first?.isStreaming == false)
    }

    @Test
    func appendingUserMessageAutoTitlesTheSession() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)

        _ = store.appendMessage(role: .user, text: "帮我找一下今天改过的配置文件")

        #expect(store.activeSession?.title == "帮我找一下今天改过的配置文件")
        #expect(store.activeSession?.messages.count == 1)
    }

    @Test
    func updatingMessageChangesTextAndStreamingState() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        let messageID = store.appendMessage(role: .assistant, text: "", isStreaming: true)

        store.updateMessage(messageID: messageID, text: "第一段回复", isStreaming: false)

        #expect(store.activeSession?.messages.first?.text == "第一段回复")
        #expect(store.activeSession?.messages.first?.isStreaming == false)
    }
}
