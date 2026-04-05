import Testing
@testable import WhyUtilsApp

struct AppCoordinatorPanelRecoveryTests {
    @Test
    func shouldRecoverPanelOnlyWhenMissingAndDiscoverable() {
        #expect(AppCoordinator.shouldRecoverPanel(currentPanelMissing: true, discoveredPanelCount: 1) == true)
        #expect(AppCoordinator.shouldRecoverPanel(currentPanelMissing: true, discoveredPanelCount: 0) == false)
        #expect(AppCoordinator.shouldRecoverPanel(currentPanelMissing: false, discoveredPanelCount: 2) == false)
    }
}

