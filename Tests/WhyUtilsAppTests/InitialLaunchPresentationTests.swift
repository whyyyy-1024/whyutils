import Testing
@testable import WhyUtilsApp

struct InitialLaunchPresentationTests {
    @Test
    func shouldPresentOnActivationWhenPanelHidden() {
        #expect(
            AppDelegate.shouldPresentOnActivation(isPanelVisible: false) == true
        )
        #expect(
            AppDelegate.shouldPresentOnActivation(isPanelVisible: true) == false
        )
    }

    @Test
    func bootstrapRetryStopsOnlyWhenPanelVisibleAndFocused() {
        #expect(
            AppDelegate.shouldRetryBootstrapPresentation(
                isVisible: false,
                isKeyWindow: false,
                isMainWindow: false
            ) == true
        )

        #expect(
            AppDelegate.shouldRetryBootstrapPresentation(
                isVisible: true,
                isKeyWindow: true,
                isMainWindow: false
            ) == false
        )

        #expect(
            AppDelegate.shouldRetryBootstrapPresentation(
                isVisible: true,
                isKeyWindow: false,
                isMainWindow: true
            ) == false
        )
    }
}
