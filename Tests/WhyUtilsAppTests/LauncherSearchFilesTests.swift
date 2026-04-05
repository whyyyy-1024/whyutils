import Testing
@testable import WhyUtilsApp

@MainActor
struct LauncherSearchFilesTests {
    @Test
    func toolCatalogContainsSearchFiles() {
        #expect(ToolKind.allCases.contains(.searchFiles))
    }

    @Test
    func launcherIncludesSearchFilesItem() {
        let coordinator = AppCoordinator.shared
        coordinator.query = ""
        #expect(coordinator.launcherItems.contains(LauncherItem.tool(.searchFiles)))
    }

    @Test
    func launcherDoesNotShowRecentAppsWhenQueryIsEmpty() {
        let coordinator = AppCoordinator.shared
        coordinator.query = ""

        let hasAppItem = coordinator.launcherItems.contains { item in
            if case .app = item {
                return true
            }
            return false
        }
        #expect(hasAppItem == false)
    }

    @Test
    func launcherShouldIncludeSystemSettingForVPNQuery() {
        let coordinator = AppCoordinator.shared
        coordinator.query = "vpn"

        let hasVPNSetting = coordinator.launcherItems.contains { item in
            if case .systemSetting(let setting) = item {
                return setting.id == "vpn"
            }
            return false
        }
        #expect(hasVPNSetting == true)
    }
}
