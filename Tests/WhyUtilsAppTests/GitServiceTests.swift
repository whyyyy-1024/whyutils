import Foundation
import Testing
@testable import WhyUtilsApp

struct GitServiceTests {
    @Test
    func detectBranchInGitRepo() async throws {
        let currentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("VsCodeProjects/whyutils-swift")
            .path
        let branch = await GitService.detectBranch(directory: currentDir)
        #expect(branch != nil)
        #expect(branch?.isEmpty == false)
    }
    
    @Test
    func detectBranchInNonGitRepo() async {
        let tempDir = NSTemporaryDirectory() + "non_git_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        
        let branch = await GitService.detectBranch(directory: tempDir)
        #expect(branch == nil)
    }
    
    @Test
    func isGitRepositoryReturnsTrueForGitDir() {
        let currentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("VsCodeProjects/whyutils-swift")
            .path
        #expect(GitService.isGitRepository(directory: currentDir) == true)
    }
    
    @Test
    func isGitRepositoryReturnsFalseForNonGitDir() {
        let tempDir = NSTemporaryDirectory()
        #expect(GitService.isGitRepository(directory: tempDir) == false)
    }
}