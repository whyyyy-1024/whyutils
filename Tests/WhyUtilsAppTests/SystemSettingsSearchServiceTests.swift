import Testing
@testable import WhyUtilsApp

struct SystemSettingsSearchServiceTests {
    @Test
    func shouldFindVPNByEnglishKeyword() {
        let results = SystemSettingsSearchService.search(query: "vpn", limit: 5)
        #expect(results.contains(where: { $0.id == "vpn" }))
    }

    @Test
    func shouldFindBluetoothByChineseKeyword() {
        let results = SystemSettingsSearchService.search(query: "蓝牙", limit: 5)
        #expect(results.contains(where: { $0.id == "bluetooth" }))
    }

    @Test
    func shouldReturnNoResultForUnknownKeyword() {
        let results = SystemSettingsSearchService.search(query: "zzzz_non_existing_setting")
        #expect(results.isEmpty)
    }

    @Test
    func shouldUseLegacyVPNAutomationOnOldMacOS() {
        #expect(SystemSettingsSearchService.shouldUseLegacyVPNAutomation(for: 12) == true)
        #expect(SystemSettingsSearchService.shouldUseLegacyVPNAutomation(for: 13) == false)
    }
}
