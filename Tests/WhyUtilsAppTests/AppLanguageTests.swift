import Foundation
import Testing
@testable import WhyUtilsApp

struct AppLanguageTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "whyutils.tests.applanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func defaultLanguageIsEnglishWhenNoPreference() {
        let defaults = makeIsolatedDefaults()
        AppLanguage.clearForTests(in: defaults)
        #expect(AppLanguage.load(from: defaults) == .english)
    }

    @Test
    func languagePersistsSelection() {
        let defaults = makeIsolatedDefaults()
        AppLanguage.clearForTests(in: defaults)
        AppLanguage.save(.chinese, to: defaults)
        #expect(AppLanguage.load(from: defaults) == .chinese)
        AppLanguage.clearForTests(in: defaults)
    }

    @Test
    func toolTitleDefaultsToEnglish() {
        #expect(ToolKind.json.title(in: .english) == "JSON Tool")
    }
}
