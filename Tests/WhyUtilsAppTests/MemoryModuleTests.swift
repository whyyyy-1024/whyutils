import Foundation
import Testing
@testable import WhyUtilsApp

struct MemoryModuleTests {
    @Test
    func moduleContainsMemoryTools() {
        let module = MemoryModule()
        let tools = module.tools()
        
        #expect(tools.contains(where: { $0.name == "memory_store" }))
        #expect(tools.contains(where: { $0.name == "memory_retrieve" }))
        #expect(tools.contains(where: { $0.name == "memory_list" }))
        #expect(tools.contains(where: { $0.name == "memory_delete" }))
    }
    
    @Test
    func storeAndRetrieveMemory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WhyUtilsTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storagePath = tempDir.appendingPathComponent("memory_store.json").path
        
        let module = MemoryModule(storagePath: storagePath)
        try await module.execute(
            toolName: "memory_store",
            arguments: ["content": "Test memory", "category": "general"]
        )
        let result = try await module.execute(
            toolName: "memory_retrieve",
            arguments: ["query": "Test"]
        )
        #expect(result.contains("Test memory"))
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @Test
    func listMemories() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WhyUtilsTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storagePath = tempDir.appendingPathComponent("memory_store.json").path
        
        let module = MemoryModule(storagePath: storagePath)
        let result = try await module.execute(
            toolName: "memory_list",
            arguments: [:]
        )
        #expect(result.contains("Memory") || result.contains("empty") || result.contains("No memories"))
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @Test
    func providerIdIsMemory() {
        let module = MemoryModule()
        #expect(module.providerId == "memory")
    }
    
    @Test
    func memoryClearWorks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WhyUtilsTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storagePath = tempDir.appendingPathComponent("memory_store.json").path
        
        let module = MemoryModule(storagePath: storagePath)
        try await module.execute(toolName: "memory_store", arguments: ["content": "Test 1"])
        try await module.execute(toolName: "memory_store", arguments: ["content": "Test 2"])
        let clearResult = try await module.execute(toolName: "memory_clear", arguments: [:])
        #expect(clearResult.contains("cleared"))
        let listResult = try await module.execute(toolName: "memory_list", arguments: [:])
        #expect(listResult.contains("No memories"))
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @Test
    func memoryDeleteWorks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WhyUtilsTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storagePath = tempDir.appendingPathComponent("memory_store.json").path
        
        let module = MemoryModule(storagePath: storagePath)
        let storeResult = try await module.execute(toolName: "memory_store", arguments: ["content": "Delete me"])
        let idMatch = storeResult.components(separatedBy: ": ").last
        let id = idMatch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let deleteResult = try await module.execute(toolName: "memory_delete", arguments: ["id": id])
        #expect(deleteResult.contains("deleted"))
        
        try? FileManager.default.removeItem(at: tempDir)
    }
}