import Foundation

struct AIChatWorkspacePersistence: Sendable {
    let load: @Sendable () -> Data?
    let save: @Sendable (Data?) -> Void

    static let inMemory = AIChatWorkspacePersistence(
        load: { nil },
        save: { _ in }
    )

    static func userDefaults(key: String) -> AIChatWorkspacePersistence {
        AIChatWorkspacePersistence(
            load: { UserDefaults.standard.data(forKey: key) },
            save: { data in
                if let data {
                    UserDefaults.standard.set(data, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        )
    }
}

@MainActor
final class AIChatWorkspaceStore: ObservableObject {
    @Published private(set) var threads: [AIThread] = []
    @Published var activeThreadID: UUID?
    @Published var activeChatID: UUID?

    private let persistence: AIChatWorkspacePersistence
    private let now: @Sendable () -> Date

    init(
        persistence: AIChatWorkspacePersistence = .userDefaults(key: "whyutils.ai.chat.threads"),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.now = now
        bootstrap()
    }

    var activeThread: AIThread? {
        guard let activeThreadID else { return threads.first }
        return threads.first(where: { $0.id == activeThreadID }) ?? threads.first
    }

    var activeChat: AIChatSession? {
        guard let thread = activeThread else { return nil }
        guard let activeChatID else { return thread.chats.first }
        return thread.chats.first(where: { $0.id == activeChatID }) ?? thread.chats.first
    }

    func createNewThread(directory: String, select: Bool = true) {
        let firstChat = AIChatSession.empty(now: now())
        var thread = AIThread.create(workingDirectory: directory, now: now())
        thread.chats = [firstChat]
        threads.insert(thread, at: 0)
        if select {
            activeThreadID = thread.id
            activeChatID = firstChat.id
        }
        persist()
    }

    func createNewChat(in threadID: UUID, select: Bool = true) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let newChat = AIChatSession.empty(now: now())
        threads[threadIndex].chats.insert(newChat, at: 0)
        threads[threadIndex].updatedAt = now()
        if select {
            activeThreadID = threadID
            activeChatID = newChat.id
        }
        sortThreads()
        persist()
    }

    func selectThread(id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        activeThreadID = id
        if let thread = threads.first(where: { $0.id == id }) {
            activeChatID = thread.chats.first?.id
        }
    }

    func selectChat(threadID: UUID, chatID: UUID) {
        guard let thread = threads.first(where: { $0.id == threadID }),
              thread.chats.contains(where: { $0.id == chatID }) else { return }
        activeThreadID = threadID
        activeChatID = chatID
    }

    func deleteThread(id: UUID) {
        let fallbackThread = threads.first(where: { $0.id != id })
        threads.removeAll { $0.id == id }
        if threads.isEmpty {
            createNewThread(directory: "")
        } else if activeThreadID == id {
            activeThreadID = fallbackThread?.id ?? threads.first?.id
            activeChatID = threads.first(where: { $0.id == activeThreadID })?.chats.first?.id
        }
        sortThreads()
        persist()
    }

    func deleteChat(threadID: UUID, chatID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let fallbackChat = threads[threadIndex].chats.first(where: { $0.id != chatID })
        threads[threadIndex].chats.removeAll { $0.id == chatID }
        threads[threadIndex].updatedAt = now()
        
        if threads[threadIndex].chats.isEmpty {
            let newChat = AIChatSession.empty(now: now())
            threads[threadIndex].chats = [newChat]
            if activeThreadID == threadID {
                activeChatID = newChat.id
            }
        } else if activeChatID == chatID {
            activeChatID = fallbackChat?.id ?? threads[threadIndex].chats.first?.id
        }
        sortThreads()
        persist()
    }

    func renameThread(id: UUID, title: String) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[threadIndex].title = title
        threads[threadIndex].updatedAt = now()
        sortThreads()
        persist()
    }

    func renameChat(threadID: UUID, chatID: UUID, title: String) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
              let chatIndex = threads[threadIndex].chats.firstIndex(where: { $0.id == chatID }) else { return }
        threads[threadIndex].chats[chatIndex] = threads[threadIndex].chats[chatIndex].renamed(to: title)
        threads[threadIndex].chats[chatIndex].updatedAt = now()
        threads[threadIndex].updatedAt = now()
        sortThreads()
        persist()
    }

    @discardableResult
    func appendMessage(
        role: AIChatMessageRole,
        text: String,
        imageAttachments: [AIChatImageAttachment] = [],
        toolTraces: [AIToolExecutionTrace] = [],
        confirmationRequest: AIConfirmationRequest? = nil,
        isStreaming: Bool = false,
        threadID: UUID? = nil,
        chatID: UUID? = nil
    ) -> UUID {
        let (targetThreadID, targetChatID) = ensureActiveChat(threadID: threadID, chatID: chatID)
        let message = AIChatMessageRecord(
            role: role,
            text: text,
            createdAt: now(),
            imageAttachments: imageAttachments,
            toolTraces: toolTraces,
            confirmationRequest: confirmationRequest,
            isStreaming: isStreaming
        )
        updateChat(threadID: targetThreadID, chatID: targetChatID) { chat in
            chat.messages.append(message)
            if role == .user {
                chat = chat.applyingAutoTitle(from: text)
            }
            chat.updatedAt = now()
        }
        updateThread(threadID: targetThreadID) { thread in
            // Don't auto-update thread title - it should remain as directory name or user-set title
            thread.updatedAt = now()
        }
        persist()
        return message.id
    }

    func updateMessage(
        threadID: UUID? = nil,
        chatID: UUID? = nil,
        messageID: UUID,
        text: String? = nil,
        imageAttachments: [AIChatImageAttachment]? = nil,
        toolTraces: [AIToolExecutionTrace]? = nil,
        confirmationRequest: AIConfirmationRequest?? = nil,
        isStreaming: Bool? = nil
    ) {
        let (targetThreadID, targetChatID) = ensureActiveChat(threadID: threadID, chatID: chatID)
        updateChat(threadID: targetThreadID, chatID: targetChatID) { chat in
            guard let index = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
            if let text { chat.messages[index].text = text }
            if let imageAttachments { chat.messages[index].imageAttachments = imageAttachments }
            if let toolTraces { chat.messages[index].toolTraces = toolTraces }
            if let confirmationRequest { chat.messages[index].confirmationRequest = confirmationRequest }
            if let isStreaming { chat.messages[index].isStreaming = isStreaming }
            chat.updatedAt = now()
        }
        updateThread(threadID: targetThreadID) { thread in
            thread.updatedAt = now()
        }
        persist()
    }

    func removeConfirmation(threadID: UUID? = nil, chatID: UUID? = nil, messageID: UUID) {
        updateMessage(threadID: threadID, chatID: chatID, messageID: messageID, confirmationRequest: .some(nil))
    }

    func updateFileChangeSummary(threadID: UUID? = nil, chatID: UUID? = nil, summary: FileChangeSummary) {
        let (targetThreadID, targetChatID) = ensureActiveChat(threadID: threadID, chatID: chatID)
        updateChat(threadID: targetThreadID, chatID: targetChatID) { chat in
            chat.fileChangeSummary = summary
            chat.updatedAt = now()
        }
        updateThread(threadID: targetThreadID) { thread in
            thread.updatedAt = now()
        }
        persist()
    }

    private func bootstrap() {
        if let data = persistence.load(),
           let decoded = try? JSONDecoder().decode([AIThread].self, from: data),
           decoded.isEmpty == false {
            // Filter out threads with empty workingDirectory (legacy bug)
            threads = decoded
                .filter { $0.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
                .map { thread in
                    var normalizedThread = thread
                    normalizedThread.chats = thread.chats.map { $0.normalizedForPersistence() }
                    return normalizedThread
                }
            sortThreads()
            activeThreadID = threads.first?.id
            activeChatID = threads.first?.chats.first?.id
            syncSessions()
            persist()
            return
        }

        if migrateFromLegacySessions() {
            syncSessions()
            return
        }

        // No existing data - don't auto-create thread, wait for user to select directory
        threads = []
        activeThreadID = nil
        activeChatID = nil
        syncSessions()
    }

    private func migrateFromLegacySessions() -> Bool {
        guard let legacyData = UserDefaults.standard.data(forKey: "whyutils.ai.chat.sessions"),
              let legacySessions = try? JSONDecoder().decode([AIChatSession].self, from: legacyData),
              legacySessions.isEmpty == false else {
            return false
        }

        let nowDate = now()
        var legacyThread = AIThread.create(workingDirectory: "", now: nowDate)
        legacyThread.title = "Legacy Session"
        legacyThread.chats = legacySessions.map { $0.normalizedForPersistence() }
        legacyThread.updatedAt = legacySessions.map { $0.updatedAt }.max() ?? nowDate

        threads = [legacyThread]
        sortThreads()
        activeThreadID = legacyThread.id
        activeChatID = legacyThread.chats.first?.id

        UserDefaults.standard.removeObject(forKey: "whyutils.ai.chat.sessions")
        persist()
        return true
    }

    private func persist() {
        let normalized = threads.map { thread -> AIThread in
            var normalizedThread = thread
            normalizedThread.chats = thread.chats.map { $0.normalizedForPersistence() }
            return normalizedThread
        }
        let data = try? JSONEncoder().encode(normalized)
        persistence.save(data)
    }

    private func ensureActiveChat(threadID: UUID?, chatID: UUID?) -> (UUID, UUID) {
        if let threadID, let chatID { return (threadID, chatID) }
        
        if let activeThreadID, let activeChatID {
            if threads.contains(where: { $0.id == activeThreadID }),
               let thread = threads.first(where: { $0.id == activeThreadID }),
               thread.chats.contains(where: { $0.id == activeChatID }) {
                return (activeThreadID, activeChatID)
            }
        }
        
        if let existingThread = threads.first {
            activeThreadID = existingThread.id
            if let existingChat = existingThread.chats.first {
                activeChatID = existingChat.id
                return (existingThread.id, existingChat.id)
            }
            let newChat = AIChatSession.empty(now: now())
            var thread = existingThread
            thread.chats = [newChat]
            threads[0] = thread
            activeChatID = newChat.id
            return (existingThread.id, newChat.id)
        }
        
        // No threads exist - return placeholder IDs (user needs to create thread first)
        return (UUID(), UUID())
    }

    private func updateThread(threadID: UUID, mutate: (inout AIThread) -> Void) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        var thread = threads[index]
        mutate(&thread)
        threads[index] = thread
        sortThreads()
    }

    private func updateChat(threadID: UUID, chatID: UUID, mutate: (inout AIChatSession) -> Void) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }
        guard let chatIndex = threads[threadIndex].chats.firstIndex(where: { $0.id == chatID }) else { return }
        var chat = threads[threadIndex].chats[chatIndex]
        mutate(&chat)
        threads[threadIndex].chats[chatIndex] = chat
        sortThreads()
    }

    private func sortThreads() {
        threads.sort { $0.updatedAt > $1.updatedAt }
    }
    
    @Published private(set) var sessions: [AIChatSession] = []
    @Published var activeSessionID: UUID?
    
    var activeSession: AIChatSession? {
        activeChat
    }
    
    func createNewSession(select: Bool = true) {
        if let threadID = activeThreadID {
            createNewChat(in: threadID, select: select)
        } else {
            createNewThread(directory: "", select: select)
        }
        syncSessions()
    }
    
    func selectSession(id: UUID) {
        for thread in threads {
            if let chat = thread.chats.first(where: { $0.id == id }) {
                selectChat(threadID: thread.id, chatID: chat.id)
                syncSessions()
                return
            }
        }
    }
    
    func deleteSession(id: UUID) {
        for thread in threads {
            if thread.chats.contains(where: { $0.id == id }) {
                deleteChat(threadID: thread.id, chatID: id)
                syncSessions()
                return
            }
        }
    }
    
    func renameSession(id: UUID, title: String) {
        for thread in threads {
            if thread.chats.contains(where: { $0.id == id }) {
                renameChat(threadID: thread.id, chatID: id, title: title)
                syncSessions()
                return
            }
        }
    }
    
    @discardableResult
    func appendMessage(
        role: AIChatMessageRole,
        text: String,
        imageAttachments: [AIChatImageAttachment] = [],
        toolTraces: [AIToolExecutionTrace] = [],
        confirmationRequest: AIConfirmationRequest? = nil,
        isStreaming: Bool = false,
        sessionID: UUID? = nil
    ) -> UUID {
        let result = appendMessage(
            role: role,
            text: text,
            imageAttachments: imageAttachments,
            toolTraces: toolTraces,
            confirmationRequest: confirmationRequest,
            isStreaming: isStreaming,
            threadID: nil,
            chatID: sessionID
        )
        syncSessions()
        return result
    }
    
    func updateMessage(
        sessionID: UUID? = nil,
        messageID: UUID,
        text: String? = nil,
        imageAttachments: [AIChatImageAttachment]? = nil,
        toolTraces: [AIToolExecutionTrace]? = nil,
        confirmationRequest: AIConfirmationRequest?? = nil,
        isStreaming: Bool? = nil
    ) {
        updateMessage(
            threadID: nil,
            chatID: sessionID,
            messageID: messageID,
            text: text,
            imageAttachments: imageAttachments,
            toolTraces: toolTraces,
            confirmationRequest: confirmationRequest,
            isStreaming: isStreaming
        )
        syncSessions()
    }
    
    func removeConfirmation(sessionID: UUID? = nil, messageID: UUID) {
        removeConfirmation(threadID: nil, chatID: sessionID, messageID: messageID)
        syncSessions()
    }
    
    private func syncSessions() {
        sessions = threads.flatMap { $0.chats }.sorted { $0.updatedAt > $1.updatedAt }
        activeSessionID = activeChatID
    }
}