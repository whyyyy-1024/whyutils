import Foundation

enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case userPreference, projectInfo, codePattern
    case usefulSnippet, importantFile, workflow, general
}

struct MemoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var content: String
    var category: MemoryCategory
    var createdAt: Date
    var lastAccessed: Date
    var accessCount: Int
    var metadata: [String: String]
    
    init(id: UUID = UUID(), content: String, category: MemoryCategory = .general, metadata: [String: String] = [:]) {
        self.id = id
        self.content = content
        self.category = category
        self.createdAt = Date()
        self.lastAccessed = Date()
        self.accessCount = 0
        self.metadata = metadata
    }
}

struct MemoryModule: ToolProvider {
    let providerId = "memory"
    private let storagePath: String
    
    init(storagePath: String? = nil) {
        if let storagePath {
            self.storagePath = storagePath
        } else {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storagePath = supportDir.appendingPathComponent("WhyUtils/memory_store.json").path
        }
    }
    
    func tools() -> [ToolDescriptor] {
        [
            .init(name: "memory_store", description: "Store a long-term memory", providerId: providerId, dangerousLevel: .safe),
            .init(name: "memory_retrieve", description: "Retrieve memories by keyword", providerId: providerId, dangerousLevel: .safe),
            .init(name: "memory_list", description: "List all memories", providerId: providerId, dangerousLevel: .safe),
            .init(name: "memory_delete", description: "Delete a specific memory", providerId: providerId, dangerousLevel: .moderate),
            .init(name: "memory_clear", description: "Clear all memories", providerId: providerId, dangerousLevel: .dangerous)
        ]
    }
    
    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "memory_store":
            let content = try requiredArg(named: "content", in: arguments)
            let categoryRaw = stringArg(named: "category", in: arguments) ?? "general"
            let category = MemoryCategory(rawValue: categoryRaw) ?? .general
            return try storeMemory(content: content, category: category)
        case "memory_retrieve":
            let query = try requiredArg(named: "query", in: arguments)
            let category = stringArg(named: "category", in: arguments)
            return try retrieveMemories(query: query, category: category)
        case "memory_list":
            return try listMemories()
        case "memory_delete":
            let id = try requiredArg(named: "id", in: arguments)
            return try deleteMemory(id: id)
        case "memory_clear":
            return try clearMemories()
        default:
            throw ToolError.unknownTool(toolName)
        }
    }
    
    private func stringArg(named name: String, in arguments: [String: Any]) -> String? {
        arguments[name] as? String
    }
    
    private func requiredArg(named name: String, in arguments: [String: Any]) throws -> String {
        guard let v = arguments[name] as? String, !v.isEmpty else {
            throw ToolError.invalidArgument("Missing required argument: \(name)")
        }
        return v
    }
    
    private func loadMemories() throws -> [MemoryEntry] {
        let url = URL(fileURLWithPath: storagePath)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: storagePath) {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([MemoryEntry].self, from: data)
    }
    
    private func saveMemories(_ memories: [MemoryEntry]) throws {
        let data = try JSONEncoder().encode(memories)
        try data.write(to: URL(fileURLWithPath: storagePath))
    }
    
    private func storeMemory(content: String, category: MemoryCategory) throws -> String {
        var memories = try loadMemories()
        let entry = MemoryEntry(content: content, category: category)
        memories.append(entry)
        if memories.count > 500 {
            memories = Array(memories.suffix(500))
        }
        try saveMemories(memories)
        return "Memory stored: \(entry.id)"
    }
    
    private func retrieveMemories(query: String, category: String?) throws -> String {
        var memories = try loadMemories()
        memories = memories.filter { entry in
            entry.content.localizedCaseInsensitiveContains(query)
        }
        if let cat = category {
            memories = memories.filter { $0.category.rawValue == cat }
        }
        memories.sort { $0.lastAccessed > $1.lastAccessed }
        memories = Array(memories.prefix(10))
        for i in memories.indices {
            memories[i].accessCount += 1
            memories[i].lastAccessed = Date()
        }
        try saveMemories(memories)
        guard !memories.isEmpty else { return "No memories found for '\(query)'" }
        return memories.map { "[\($0.id)] \($0.content) (\($0.category.rawValue))" }.joined(separator: "\n")
    }
    
    private func listMemories() throws -> String {
        let memories = try loadMemories()
        guard !memories.isEmpty else { return "No memories stored" }
        return memories.map { "[\($0.id)] \($0.content.prefix(50))... (\($0.category.rawValue))" }.joined(separator: "\n")
    }
    
    private func deleteMemory(id: String) throws -> String {
        guard let uuid = UUID(uuidString: id) else {
            return "Invalid memory ID"
        }
        var memories = try loadMemories()
        let count = memories.count
        memories.removeAll { $0.id == uuid }
        guard memories.count < count else { return "Memory not found" }
        try saveMemories(memories)
        return "Memory deleted"
    }
    
    private func clearMemories() throws -> String {
        try saveMemories([])
        return "All memories cleared"
    }
}