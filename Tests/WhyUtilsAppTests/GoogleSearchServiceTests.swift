import Testing
@testable import WhyUtilsApp

struct GoogleSearchServiceTests {
    @Test
    func buildSearchURLEncodesQuery() throws {
        let url = try #require(GoogleSearchService.buildSearchURL(query: "swift ui 工具"))
        #expect(url.absoluteString == "https://www.google.com/search?q=swift%20ui%20%E5%B7%A5%E5%85%B7")
    }

    @Test
    func buildSearchURLReturnsNilForEmptyQuery() {
        #expect(GoogleSearchService.buildSearchURL(query: "   ") == nil)
    }
}
