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
    @Published private(set) var sessions: [AIChatSession] = []
    @Published var activeSessionID: UUID?

    private let persistence: AIChatWorkspacePersistence
    private let now: @Sendable () -> Date

    init(
        persistence: AIChatWorkspacePersistence = .userDefaults(key: "whyutils.ai.chat.sessions"),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.now = now
        bootstrap()
    }

    var activeSession: AIChatSession? {
        guard let activeSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == activeSessionID }) ?? sessions.first
    }

    func createNewSession(select: Bool = true) {
        let session = AIChatSession.empty(now: now())
        sessions.insert(session, at: 0)
        if select {
            activeSessionID = session.id
        }
        persist()
    }

    func selectSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    func renameSession(id: UUID, title: String) {
        updateSession(id: id) { session in
            session = session.renamed(to: title)
            session.updatedAt = now()
        }
        persist()
    }

    func deleteSession(id: UUID) {
        let fallback = sessions.first(where: { $0.id != id })?.id
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let session = AIChatSession.empty(now: now())
            sessions = [session]
            activeSessionID = session.id
        } else if activeSessionID == id {
            activeSessionID = fallback ?? sessions.first?.id
        }
        sortSessions()
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
        sessionID: UUID? = nil
    ) -> UUID {
        let targetID = ensureActiveSession(id: sessionID)
        let message = AIChatMessageRecord(
            role: role,
            text: text,
            createdAt: now(),
            imageAttachments: imageAttachments,
            toolTraces: toolTraces,
            confirmationRequest: confirmationRequest,
            isStreaming: isStreaming
        )
        updateSession(id: targetID) { session in
            session.messages.append(message)
            if role == .user {
                session = session.applyingAutoTitle(from: text)
            }
            session.updatedAt = now()
        }
        persist()
        return message.id
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
        let targetID = ensureActiveSession(id: sessionID)
        updateSession(id: targetID) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
            if let text { session.messages[index].text = text }
            if let imageAttachments { session.messages[index].imageAttachments = imageAttachments }
            if let toolTraces { session.messages[index].toolTraces = toolTraces }
            if let confirmationRequest { session.messages[index].confirmationRequest = confirmationRequest }
            if let isStreaming { session.messages[index].isStreaming = isStreaming }
            session.updatedAt = now()
        }
        persist()
    }

    func removeConfirmation(sessionID: UUID? = nil, messageID: UUID) {
        updateMessage(sessionID: sessionID, messageID: messageID, confirmationRequest: .some(nil))
    }

    private func bootstrap() {
        guard
            let data = persistence.load(),
            let decoded = try? JSONDecoder().decode([AIChatSession].self, from: data),
            decoded.isEmpty == false
        else {
            let session = AIChatSession.empty(now: now())
            sessions = [session]
            activeSessionID = session.id
            persist()
            return
        }

        sessions = decoded.map { $0.normalizedForPersistence() }
        sortSessions()
        activeSessionID = sessions.first?.id
        persist()
    }

    private func persist() {
        let normalized = sessions.map { $0.normalizedForPersistence() }
        let data = try? JSONEncoder().encode(normalized)
        persistence.save(data)
    }

    private func ensureActiveSession(id: UUID?) -> UUID {
        if let id { return id }
        if let activeSessionID { return activeSessionID }
        if let existing = sessions.first?.id {
            activeSessionID = existing
            return existing
        }
        let session = AIChatSession.empty(now: now())
        sessions = [session]
        activeSessionID = session.id
        return session.id
    }

    private func updateSession(id: UUID, mutate: (inout AIChatSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        mutate(&session)
        sessions[index] = session
        sortSessions()
    }

    private func sortSessions() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }
}
