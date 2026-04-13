import Foundation

@MainActor
final class FileChangeTracker: ObservableObject {
    static let shared = FileChangeTracker()
    @Published var currentSummary: FileChangeSummary = FileChangeSummary()
    
    private init() {}
    
    func recordCreated(path: String, content: String = "") {
        currentSummary.createdFiles.append(path)
        if !content.isEmpty {
            currentSummary.totalLinesAdded += content.components(separatedBy: .newlines).count
        }
    }
    
    func recordModified(path: String, linesAdded: Int, linesRemoved: Int) {
        let record = FileChangeRecord(path: path, linesAdded: linesAdded, linesRemoved: linesRemoved)
        currentSummary.modifiedFiles.append(record)
        currentSummary.totalLinesAdded += linesAdded
        currentSummary.totalLinesRemoved += linesRemoved
    }
    
    func recordDeleted(path: String) {
        currentSummary.deletedFiles.append(path)
    }
    
    func reset() {
        currentSummary = FileChangeSummary()
    }
}