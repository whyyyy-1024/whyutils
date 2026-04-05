import Foundation
import Testing
@testable import WhyUtilsApp

struct FileSearchServiceTests {
    @Test
    func scopeUserHasExpectedDisplayName() {
        let scope = FileSearchScope.user(userName: "wanghaoyu")
        #expect(scope.displayTitle == "User (wanghaoyu)")
    }

    @Test
    func scopeThisMacHasExpectedDisplayName() {
        #expect(FileSearchScope.thisMac.displayTitle == "This Mac")
    }

    @Test
    func shouldExcludeSystemAndHiddenPathsForThisMac() {
        #expect(FileSearchService.shouldExcludePath("/System/Library/CoreServices/Finder.app", scope: .thisMac))
        #expect(FileSearchService.shouldExcludePath("/private/var/tmp/file.txt", scope: .thisMac))
        #expect(FileSearchService.shouldExcludePath("/Users/wanghaoyu/.git/config", scope: .thisMac))
        #expect(!FileSearchService.shouldExcludePath("/Users/wanghaoyu/Documents/report.txt", scope: .thisMac))
    }

    @Test
    func shouldNotExcludeRegularUserFilesForUserScope() {
        #expect(!FileSearchService.shouldExcludePath("/Users/wanghaoyu/Documents/demo.txt", scope: .user(userName: "wanghaoyu")))
    }

    @Test
    func sortResultsByModifiedDateDescending() {
        let old = FileSearchResult(
            url: URL(fileURLWithPath: "/tmp/old.txt"),
            fileName: "old.txt",
            parentPath: "/tmp",
            modifiedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 50),
            fileSize: 10,
            isDirectory: false
        )
        let new = FileSearchResult(
            url: URL(fileURLWithPath: "/tmp/new.txt"),
            fileName: "new.txt",
            parentPath: "/tmp",
            modifiedAt: Date(timeIntervalSince1970: 300),
            createdAt: Date(timeIntervalSince1970: 150),
            fileSize: 20,
            isDirectory: false
        )
        let sorted = FileSearchService.sort([old, new])
        #expect(sorted.map(\.fileName) == ["new.txt", "old.txt"])
    }
}
