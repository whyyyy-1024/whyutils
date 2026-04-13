import Foundation
import Testing
@testable import WhyUtilsApp

struct AIThreadModelsTests {
    @Test
    func threadDisplayNameUsesDirectoryWhenTitleEmpty() {
        let thread = AIThread.create(workingDirectory: "/Users/test/projects/myapp", now: Date())
        #expect(thread.displayName == "myapp")
    }
    
    @Test
    func threadDisplayNameUsesTitleWhenSet() {
        var thread = AIThread.create(workingDirectory: "/Users/test/projects/myapp", now: Date())
        thread.title = "My Custom Title"
        #expect(thread.displayName == "My Custom Title")
    }
    
    @Test
    func fileChangeSummaryHasChanges() {
        var summary = FileChangeSummary()
        summary.createdFiles.append("/test/new.swift")
        #expect(summary.hasChanges == true)
    }
    
    @Test
    func fileChangeSummaryNoChanges() {
        let summary = FileChangeSummary()
        #expect(summary.hasChanges == false)
    }
}