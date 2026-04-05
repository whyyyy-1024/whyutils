import AppKit
import Testing
@testable import WhyUtilsApp

struct KeyboardNavigationTests {
    @Test
    func shouldHandleEscapeWithoutModifiers() {
        let handled = AppCoordinator.shouldHandleEscape(
            keyCode: 53,
            modifiers: []
        )
        #expect(handled == true)
    }

    @Test
    func shouldIgnoreEscapeWithCommandModifier() {
        let handled = AppCoordinator.shouldHandleEscape(
            keyCode: 53,
            modifiers: NSEvent.ModifierFlags.command
        )
        #expect(handled == false)
    }

    @Test
    func shouldIgnoreNonEscapeKeys() {
        let handled = AppCoordinator.shouldHandleEscape(
            keyCode: 36,
            modifiers: []
        )
        #expect(handled == false)
    }

    @Test
    func launcherEscShouldCloseSettingsWhenPresented() {
        let action = AppCoordinator.launcherKeyAction(
            keyCode: 53,
            modifiers: [],
            isSettingsPresented: true
        )
        #expect(action == .closeSettings)
    }

    @Test
    func launcherEnterShouldPassThroughWhenSettingsPresented() {
        let action = AppCoordinator.launcherKeyAction(
            keyCode: 36,
            modifiers: [],
            isSettingsPresented: true
        )
        #expect(action == .passThrough)
    }
}
