import Foundation
import Testing
@testable import WhyUtilsApp

struct AppSearchServiceTests {
    @Test
    func shouldRefreshInstalledApplicationsIndexWhenRootsChanged() {
        let shouldRefresh = AppSearchService.shouldRefreshInstalledApplicationsIndex(
            query: "ray",
            indexedAppsEmpty: false,
            indexingInProgress: false,
            lastKnownSignature: ["applications": 1, "user-applications": 2],
            currentSignature: ["applications": 3, "user-applications": 2]
        )

        #expect(shouldRefresh == true)
    }

    @Test
    func shouldNotRefreshInstalledApplicationsIndexForEmptyQuery() {
        let shouldRefresh = AppSearchService.shouldRefreshInstalledApplicationsIndex(
            query: "   ",
            indexedAppsEmpty: false,
            indexingInProgress: false,
            lastKnownSignature: ["applications": 1],
            currentSignature: ["applications": 2]
        )

        #expect(shouldRefresh == false)
    }

    @Test
    func shouldNotRefreshInstalledApplicationsIndexWhenSignatureMatches() {
        let shouldRefresh = AppSearchService.shouldRefreshInstalledApplicationsIndex(
            query: "ray",
            indexedAppsEmpty: false,
            indexingInProgress: false,
            lastKnownSignature: ["applications": 1, "user-applications": 2],
            currentSignature: ["applications": 1, "user-applications": 2]
        )

        #expect(shouldRefresh == false)
    }

    @Test
    func matchScoreShouldPreferNamePrefix() {
        let prefix = AppSearchService.matchScore(
            itemName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            path: "/Applications/Visual Studio Code.app",
            query: "vis"
        )
        let bundleOnly = AppSearchService.matchScore(
            itemName: "Code",
            bundleIdentifier: "com.microsoft.VSCode",
            path: "/Applications/Code.app",
            query: "microsoft"
        )

        #expect(prefix != nil)
        #expect(bundleOnly != nil)
        #expect(prefix! > bundleOnly!)
    }

    @Test
    func sortShouldPreferRecentWhenQueryIsEmpty() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let older = now.addingTimeInterval(-3600)

        let items = [
            AppSearchItem(
                id: "a",
                name: "A App",
                bundleIdentifier: "com.a",
                url: URL(fileURLWithPath: "/Applications/A.app"),
                isRunning: true,
                lastOpenedAt: older
            ),
            AppSearchItem(
                id: "b",
                name: "B App",
                bundleIdentifier: "com.b",
                url: URL(fileURLWithPath: "/Applications/B.app"),
                isRunning: false,
                lastOpenedAt: now
            )
        ]

        let sorted = AppSearchService.sort(items: items, query: "", now: now)
        #expect(sorted.first?.id == "b")
    }

    @Test
    func sortShouldKeepQueryMatchesOnly() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            AppSearchItem(
                id: "finder",
                name: "Finder",
                bundleIdentifier: "com.apple.finder",
                url: URL(fileURLWithPath: "/System/Applications/Finder.app"),
                isRunning: true,
                lastOpenedAt: now
            ),
            AppSearchItem(
                id: "xcode",
                name: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                url: URL(fileURLWithPath: "/Applications/Xcode.app"),
                isRunning: false,
                lastOpenedAt: now
            )
        ]

        let sorted = AppSearchService.sort(items: items, query: "find", now: now)
        #expect(sorted.count == 1)
        #expect(sorted.first?.id == "finder")
    }
}
