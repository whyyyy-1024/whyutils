import Foundation
import Testing
@testable import WhyUtilsApp

struct ProcessListServiceTests {
    @Test
    func parsePsOutputLine() {
        let line = "user  1234  12.5  3.2  123456  78901  ??  S  10:00AM  0:05.62  /Applications/Safari.app/Contents/MacOS/Safari"
        let result = ProcessListService.parsePsOutputLine(line)
        
        #expect(result != nil)
        #expect(result?.pid == 1234)
        #expect(result?.name == "Safari")
        #expect(result?.cpu == 12.5)
        #expect(result?.memory == 3.2)
        #expect(result?.user == "user")
    }

    @Test
    func parseMalformedLine() {
        let incompleteLine = "user  abc  12.5"
        let result = ProcessListService.parsePsOutputLine(incompleteLine)
        
        #expect(result == nil)
    }

    @Test
    func filterSelfProcess() {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let processes = [
            ProcessItem(id: Int32(currentPid), pid: Int32(currentPid), name: "WhyUtils", cpu: 5.0, memory: 2.0, user: "user"),
            ProcessItem(id: 9999, pid: 9999, name: "Safari", cpu: 10.0, memory: 5.0, user: "user")
        ]
        
        let filtered = ProcessListService.filterSelfProcess(processes)
        
        #expect(filtered.count == 1)
        #expect(filtered.first?.pid != Int32(currentPid))
    }

    @Test
    func searchByName() {
        let processes = [
            ProcessItem(id: 1234, pid: 1234, name: "Safari", cpu: 10.0, memory: 5.0, user: "user"),
            ProcessItem(id: 5678, pid: 5678, name: "Chrome", cpu: 20.0, memory: 10.0, user: "user"),
            ProcessItem(id: 9999, pid: 9999, name: "Finder", cpu: 5.0, memory: 2.0, user: "user")
        ]
        
        let result = ProcessListService.search(processes: processes, query: "saf")
        
        #expect(result.count == 1)
        #expect(result.first?.name == "Safari")
    }

    @Test
    func searchByPID() {
        let processes = [
            ProcessItem(id: 1234, pid: 1234, name: "Safari", cpu: 10.0, memory: 5.0, user: "user"),
            ProcessItem(id: 5678, pid: 5678, name: "Chrome", cpu: 20.0, memory: 10.0, user: "user"),
            ProcessItem(id: 9999, pid: 9999, name: "Finder", cpu: 5.0, memory: 2.0, user: "user")
        ]
        
        let result = ProcessListService.search(processes: processes, query: "5678")
        
        #expect(result.count == 1)
        #expect(result.first?.pid == 5678)
    }

    @Test
    func sortByCPU() {
        let processes = [
            ProcessItem(id: 1234, pid: 1234, name: "Safari", cpu: 10.0, memory: 5.0, user: "user"),
            ProcessItem(id: 5678, pid: 5678, name: "Chrome", cpu: 25.0, memory: 10.0, user: "user"),
            ProcessItem(id: 9999, pid: 9999, name: "Finder", cpu: 5.0, memory: 2.0, user: "user")
        ]
        
        let sorted = ProcessListService.sortByCPU(processes)
        
        #expect(sorted.map { $0.name } == ["Chrome", "Safari", "Finder"])
        #expect(sorted.first?.cpu == 25.0)
        #expect(sorted.last?.cpu == 5.0)
    }

    @Test
    func killResultSuccess() {
        let result = KillResult.success
        
        switch result {
        case .success:
            #expect(true)
        case .failure:
            Issue.record("Expected success, got failure")
        }
    }

    @Test
    func killResultFailure() {
        let result = KillResult.failure(message: "Permission denied")
        
        switch result {
        case .success:
            Issue.record("Expected failure, got success")
        case .failure(let message):
            #expect(message == "Permission denied")
        }
    }
}