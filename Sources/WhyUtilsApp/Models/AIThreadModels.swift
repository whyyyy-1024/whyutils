import Foundation

struct AIThread: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let workingDirectory: String
    let createdAt: Date
    var updatedAt: Date
    var chats: [AIChatSession]
    
    var displayName: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        }
        return trimmedTitle
    }
    
    static func create(workingDirectory: String, now: Date) -> AIThread {
        AIThread(
            id: UUID(),
            title: "",
            workingDirectory: workingDirectory,
            createdAt: now,
            updatedAt: now,
            chats: []
        )
    }
}

struct FileChangeSummary: Codable, Equatable, Sendable {
    var modifiedFiles: [FileChangeRecord]
    var createdFiles: [String]
    var deletedFiles: [String]
    var totalLinesAdded: Int
    var totalLinesRemoved: Int
    
    init() {
        modifiedFiles = []
        createdFiles = []
        deletedFiles = []
        totalLinesAdded = 0
        totalLinesRemoved = 0
    }
    
    var hasChanges: Bool {
        !modifiedFiles.isEmpty || !createdFiles.isEmpty || !deletedFiles.isEmpty
    }
    
    var summaryText: String {
        if !hasChanges { return "" }
        return "+\(totalLinesAdded)/-\(totalLinesRemoved)"
    }
}

struct FileChangeRecord: Codable, Equatable, Sendable {
    let path: String
    let linesAdded: Int
    let linesRemoved: Int
    let modifiedAt: Date
    
    init(path: String, linesAdded: Int, linesRemoved: Int, modifiedAt: Date = Date()) {
        self.path = path
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.modifiedAt = modifiedAt
    }
}