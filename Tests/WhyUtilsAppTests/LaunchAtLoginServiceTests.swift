import Foundation
import Testing
@testable import WhyUtilsApp

struct LaunchAtLoginServiceTests {
    @Test
    func choosesFallbackPathWhenLaunchAgentsNotWritable() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let target = LaunchAtLoginService.installPlistURL(
            homeDirectory: home,
            isLaunchAgentsWritable: false
        )
        #expect(target.path.contains("/Library/Application Support/whyutils/LaunchAgents/"))
    }

    @Test
    func choosesLaunchAgentsPathWhenWritable() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let target = LaunchAtLoginService.installPlistURL(
            homeDirectory: home,
            isLaunchAgentsWritable: true
        )
        #expect(target.path == "/Users/tester/Library/LaunchAgents/com.whyutils.swiftui.plist")
    }
}
