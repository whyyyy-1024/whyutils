import Foundation
import Testing
@testable import WhyUtilsApp

struct FileSystemModuleTests {
    @Test
    func moduleContainsFileSystemTools() {
        let module = FileSystemModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "fs_create_directory" }))
        #expect(tools.contains(where: { $0.name == "fs_delete" }))
        #expect(tools.contains(where: { $0.name == "fs_copy" }))
        #expect(tools.contains(where: { $0.name == "fs_move" }))
        #expect(tools.contains(where: { $0.name == "fs_find" }))
        #expect(tools.contains(where: { $0.name == "fs_compress" }))
        #expect(tools.contains(where: { $0.name == "fs_decompress" }))
        #expect(tools.contains(where: { $0.name == "fs_get_info" }))
    }
    
    @Test
    func deleteToolRequiresConfirmation() {
        let module = FileSystemModule()
        let tools = module.tools()
        let delete = tools.first(where: { $0.name == "fs_delete" })
        #expect(delete?.requiresConfirmation == true)
    }
    
    @Test
    func createDirectoryTool() async throws {
        let module = FileSystemModule()
        let tempDir = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        
        let result = try await module.execute(
            toolName: "fs_create_directory",
            arguments: ["path": tempDir]
        )
        #expect(result.contains("Created"))
        #expect(FileManager.default.fileExists(atPath: tempDir))
    }
    
    @Test
    func getInfoTool() async throws {
        let module = FileSystemModule()
        let tempFile = NSTemporaryDirectory() + "whyutils_test_\(UUID().uuidString).txt"
        try "test content".write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        
        let result = try await module.execute(
            toolName: "fs_get_info",
            arguments: ["path": tempFile]
        )
        #expect(result.contains(tempFile))
        #expect(result.contains("12"))
    }
    
    @Test
    func forbiddenPathIsBlocked() async throws {
        let module = FileSystemModule()
        do {
            _ = try await module.execute(
                toolName: "fs_delete",
                arguments: ["path": "/System/Library"]
            )
            Issue.record("Expected executionFailed error for forbidden path")
        } catch let error as ToolError {
            if case .executionFailed = error {
                #expect(Bool(true))
            } else {
                Issue.record("Expected executionFailed error, got \(error)")
            }
        }
    }
}