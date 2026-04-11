import Foundation
import Testing
@testable import WhyUtilsApp

struct CodeEditModuleTests {
    @Test
    func moduleContainsCodeEditTools() {
        let module = CodeEditModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "code_read_range" }))
        #expect(tools.contains(where: { $0.name == "code_edit_line" }))
        #expect(tools.contains(where: { $0.name == "code_edit_range" }))
        #expect(tools.contains(where: { $0.name == "code_search_symbols" }))
        #expect(tools.contains(where: { $0.name == "code_outline" }))
    }
    
    @Test
    func readRangeTool() async throws {
        let module = CodeEditModule()
        let tempFile = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString).txt"
        let content = "line1\nline2\nline3\nline4\nline5"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        
        let result = try await module.execute(
            toolName: "code_read_range",
            arguments: ["path": tempFile, "lineStart": "2", "lineEnd": "4"]
        )
        #expect(result.contains("line2"))
        #expect(result.contains("line3"))
        #expect(result.contains("line4"))
    }
    
    @Test
    func outlineTool() async throws {
        let module = CodeEditModule()
        let tempFile = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString).swift"
        let content = """
        struct Foo {
            func bar() {}
            var baz: Int
        }
        func helper() {}
        """
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        
        let result = try await module.execute(
            toolName: "code_outline",
            arguments: ["path": tempFile]
        )
        #expect(result.contains("Foo"))
        #expect(result.contains("bar"))
        #expect(result.contains("baz"))
    }
}