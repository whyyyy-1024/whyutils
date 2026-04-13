import Foundation
import Testing
@testable import WhyUtilsApp

private final class DataBox: @unchecked Sendable {
    var data: Data?
}

@MainActor
struct AIChatWorkspaceStoreTests {
    @Test
    func bootstrapCreatesBlankThreadWithFirstChatWhenStorageIsEmpty() {
        let savedData = DataBox()
        let store = AIChatWorkspaceStore(
            persistence: .init(
                load: { nil },
                save: { savedData.data = $0 }
            ),
            now: { Date(timeIntervalSince1970: 100) }
        )

        #expect(store.threads.count == 1)
        #expect(store.threads.first?.chats.count == 1)
        #expect(store.activeChat?.displayTitle == "New chat")
        #expect(savedData.data != nil)
    }

    @Test
    func createNewThreadAddsThreadWithFirstChat() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        
        store.createNewThread(directory: "/test/project")
        
        #expect(store.threads.count == 2)
        #expect(store.threads.first?.chats.count == 1)
        #expect(store.activeThreadID != nil)
        #expect(store.activeChatID != nil)
        #expect(store.threads.first?.workingDirectory == "/test/project")
    }

    @Test
    func createNewChatAddsChatToActiveThread() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/test/project")
        let threadID = try! #require(store.activeThreadID)
        
        store.createNewChat(in: threadID)
        
        #expect(store.threads.first?.chats.count == 2)
    }

    @Test
    func selectChatUpdatesActiveIDs() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/test/project")
        let threadID = try! #require(store.activeThreadID)
        store.createNewChat(in: threadID)
        let firstChatID = store.threads.first?.chats.last?.id
        
        store.selectChat(threadID: threadID, chatID: firstChatID!)
        
        #expect(store.activeChatID == firstChatID)
    }

    @Test
    func selectThreadUpdatesActiveThreadAndChat() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/first")
        let firstThreadID = try! #require(store.activeThreadID)
        store.createNewThread(directory: "/second")
        
        store.selectThread(id: firstThreadID)
        
        #expect(store.activeThreadID == firstThreadID)
        #expect(store.activeChatID == store.threads.first(where: { $0.id == firstThreadID })?.chats.first?.id)
    }

    @Test
    func deleteThreadFallsBackToAnotherThread() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/first")
        let firstThreadID = try! #require(store.activeThreadID)
        store.createNewThread(directory: "/second")
        let secondThreadID = try! #require(store.activeThreadID)
        
        store.deleteThread(id: secondThreadID)
        
        #expect(store.threads.count == 2)
        #expect(store.activeThreadID == firstThreadID)
    }

    @Test
    func deleteChatFallsBackToAnotherChat() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/test")
        let threadID = try! #require(store.activeThreadID)
        store.createNewChat(in: threadID)
        let firstChatID = store.threads.first?.chats.last?.id
        store.selectChat(threadID: threadID, chatID: firstChatID!)
        let secondChatID = try! #require(store.activeChatID)
        
        store.deleteChat(threadID: threadID, chatID: secondChatID)
        
        #expect(store.threads.first?.chats.count == 1)
        #expect(store.activeChatID != secondChatID)
    }

    @Test
    func renameThreadUpdatesThreadTitle() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/test")
        let threadID = try! #require(store.activeThreadID)
        
        store.renameThread(id: threadID, title: "My Project")
        
        #expect(store.threads.first?.title == "My Project")
    }

    @Test
    func renameChatUpdatesChatTitle() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/test")
        let threadID = try! #require(store.activeThreadID)
        let chatID = try! #require(store.activeChatID)
        
        store.renameChat(threadID: threadID, chatID: chatID, title: "部署问题排查")
        
        #expect(store.activeChat?.title == "部署问题排查")
        #expect(store.activeChat?.isUserRenamed == true)
    }

    @Test
    func persistedThreadsRestoreAndNormalizeStreamingMessages() throws {
        let persisted = [
            AIThread(
                id: UUID(),
                title: "项目",
                workingDirectory: "/test",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20),
                chats: [
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
            )
        ]
        let data = try JSONEncoder().encode(persisted)
        let store = AIChatWorkspaceStore(
            persistence: .init(
                load: { data },
                save: { _ in }
            )
        )

        #expect(store.threads.count == 1)
        #expect(store.activeThread?.title == "项目")
        #expect(store.activeChat?.title == "恢复会话")
        #expect(store.activeChat?.messages.first?.isStreaming == false)
    }

    @Test
    func appendingUserMessageAutoTitlesChatAndThread() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)

        _ = store.appendMessage(role: .user, text: "帮我找一下今天改过的配置文件")

        #expect(store.activeChat?.title == "帮我找一下今天改过的配置文件")
        #expect(store.activeThread?.title == "帮我找一下今天改过的配置文件")
        #expect(store.activeChat?.messages.count == 1)
    }

    @Test
    func updatingMessageChangesTextAndStreamingState() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        let messageID = store.appendMessage(role: .assistant, text: "", isStreaming: true)

        store.updateMessage(messageID: messageID, text: "第一段回复", isStreaming: false)

        #expect(store.activeChat?.messages.first?.text == "第一段回复")
        #expect(store.activeChat?.messages.first?.isStreaming == false)
    }

    @Test
    func updateFileChangeSummaryUpdatesActiveChat() {
        let store = AIChatWorkspaceStore(persistence: .inMemory)
        store.createNewThread(directory: "/test")
        
        var summary = FileChangeSummary()
        summary.createdFiles = ["test.swift"]
        summary.totalLinesAdded = 100
        store.updateFileChangeSummary(summary: summary)
        
        #expect(store.activeChat?.fileChangeSummary.createdFiles == ["test.swift"])
        #expect(store.activeChat?.fileChangeSummary.totalLinesAdded == 100)
    }

    @Test
    func activeThreadReturnsNilWhenEmpty() {
        let store = AIChatWorkspaceStore(
            persistence: .init(
                load: { try? JSONEncoder().encode([AIThread]()) },
                save: { _ in }
            )
        )
        
        #expect(store.threads.count == 1)
        #expect(store.activeThread != nil)
    }
}