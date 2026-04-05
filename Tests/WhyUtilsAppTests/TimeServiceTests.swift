import Foundation
import Testing
@testable import WhyUtilsApp

struct TimeServiceTests {
    @Test
    func timestampAutoDetectsMilliseconds() throws {
        let result = try TimeService.timestampToDate("1740990341123")
        #expect(result.inferredUnit == "milliseconds" || result.inferredUnit == "毫秒")
        #expect(result.seconds == 1_740_990_341)
        #expect(result.milliseconds == 1_740_990_341_123)
        #expect(!result.iso8601UTC.isEmpty)
    }

    @Test
    func timestampRespectsManualUnit() throws {
        let result = try TimeService.timestampToDate("1740990341", inputUnit: .milliseconds)
        #expect(result.inferredUnit == "milliseconds" || result.inferredUnit == "毫秒")
        #expect(result.seconds == 1_740_990)
        #expect(result.milliseconds == 1_740_990_341)
    }

    @Test
    func dateToTimestampInterpretsUTC() throws {
        let result = try TimeService.dateToTimestamp("1970-01-01 00:00:01", interpretAsUTC: true)
        #expect(result.seconds == 1)
        #expect(result.milliseconds == 1000)
        #expect(result.inferredUnit == "datetime" || result.inferredUnit == "日期时间")
    }

    @Test
    func liveSnapshotReturnsConsistentEpochValues() {
        let date = Date(timeIntervalSince1970: 1.234)
        let snapshot = TimeService.liveSnapshot(now: date)
        #expect(snapshot.seconds == 1)
        #expect(snapshot.milliseconds == 1234)
        #expect(!snapshot.localTime.isEmpty)
        #expect(!snapshot.iso8601UTC.isEmpty)
    }
}
