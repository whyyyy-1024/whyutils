import Testing
@testable import WhyUtilsApp

struct AppPanelBehaviorTests {
    @Test
    @MainActor
    func panelControllerShouldNotAutoHideOnDeactivate() {
        #expect(WhyUtilsPanelController.hideOnDeactivate == false)
    }

    @Test
    func shouldNotHidePanelWhenAttachedSheetIsVisible() {
        let shouldHide = WhyUtilsPanel.shouldHideOnResign(
            isVisible: true,
            hasAttachedSheet: true
        )
        #expect(shouldHide == false)
    }

    @Test
    func shouldHidePanelWhenNoAttachedSheet() {
        let shouldHide = WhyUtilsPanel.shouldHideOnResign(
            isVisible: true,
            hasAttachedSheet: false
        )
        #expect(shouldHide == true)
    }

    @Test
    func shouldNotHidePanelWhenAutoHideTemporarilySuppressed() {
        let shouldHide = WhyUtilsPanel.shouldHideOnResign(
            isVisible: true,
            hasAttachedSheet: false,
            suppressAutoHide: true
        )
        #expect(shouldHide == false)
    }
}
