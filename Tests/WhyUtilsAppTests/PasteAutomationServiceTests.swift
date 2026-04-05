import Testing
@testable import WhyUtilsApp

struct PasteAutomationServiceTests {
    @Test
    func selectTargetBundlePrefersExternalApp() {
        let selected = PasteAutomationService.selectTargetBundleIdentifier(
            preferredBundleID: "com.whyutils.swiftui",
            frontmostBundleID: "com.tencent.xinWeChat",
            ownBundleID: "com.whyutils.swiftui"
        )
        #expect(selected == "com.tencent.xinWeChat")
    }

    @Test
    func selectTargetBundleKeepsPreferredWhenExternal() {
        let selected = PasteAutomationService.selectTargetBundleIdentifier(
            preferredBundleID: "com.tencent.xinWeChat",
            frontmostBundleID: "com.apple.Safari",
            ownBundleID: "com.whyutils.swiftui"
        )
        #expect(selected == "com.tencent.xinWeChat")
    }

    @Test
    func selectTargetBundleReturnsNilWhenNoExternalFound() {
        let selected = PasteAutomationService.selectTargetBundleIdentifier(
            preferredBundleID: "com.whyutils.swiftui",
            frontmostBundleID: "com.whyutils.swiftui",
            ownBundleID: "com.whyutils.swiftui"
        )
        #expect(selected == nil)
    }

    @Test
    func fallbackActionsDefaultDoesNotRepeatPaste() {
        let actions = PasteAutomationService.fallbackActions(includeAppleScript: true)
        #expect(actions == [.appleScript])
    }

    @Test
    func fallbackActionsWithoutAppleScriptIsSinglePaste() {
        let actions = PasteAutomationService.fallbackActions(includeAppleScript: false)
        #expect(actions == [.cgEvent])
    }

    @Test
    func commandVChannelsWithTargetPIDUsesSingleTargetChannel() {
        let channels = PasteAutomationService.commandVChannels(targetPID: 1234)
        #expect(channels == [.targetPID])
    }

    @Test
    func commandVChannelsWithoutPIDUsesSingleSessionChannel() {
        let channels = PasteAutomationService.commandVChannels(targetPID: nil)
        #expect(channels == [.session])
    }

    @Test
    func requiresFrontmostWaitIsFalseWhenTargetPIDExists() {
        let requiresWait = PasteAutomationService.requiresFrontmostWait(targetPID: 1234, targetBundleID: nil)
        #expect(requiresWait == false)
    }

    @Test
    func requiresFrontmostWaitIsFalseWhenTargetBundleExists() {
        let requiresWait = PasteAutomationService.requiresFrontmostWait(targetPID: nil, targetBundleID: "com.tencent.xinWeChat")
        #expect(requiresWait == false)
    }

    @Test
    func requiresFrontmostWaitIsTrueWhenNoTargetInfo() {
        let requiresWait = PasteAutomationService.requiresFrontmostWait(targetPID: nil, targetBundleID: nil)
        #expect(requiresWait == true)
    }
}
