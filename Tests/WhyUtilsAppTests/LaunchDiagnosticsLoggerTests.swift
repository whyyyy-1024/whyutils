import Foundation
import Testing
@testable import WhyUtilsApp

struct LaunchDiagnosticsLoggerTests {
    @Test
    func logFilePathUsesLibraryLogsWhyutils() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let url = LaunchDiagnosticsLogger.logFileURL(homeDirectory: home)
        #expect(url.path == "/Users/tester/Library/Logs/whyutils/launch.log")
    }

    @Test
    func formatLineContainsTimestampAndMessage() {
        let date = Date(timeIntervalSince1970: 0)
        let line = LaunchDiagnosticsLogger.formatLine(
            message: "hello",
            date: date,
            pid: 123
        )
        #expect(line.contains("1970-01-01"))
        #expect(line.contains(".000"))
        #expect(line.contains("[pid:123]"))
        #expect(line.contains("hello"))
    }
}
