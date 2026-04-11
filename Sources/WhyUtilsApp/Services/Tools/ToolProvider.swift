import Foundation

protocol ToolProvider: Sendable {
    var providerId: String { get }
    func tools() -> [ToolDescriptor]
    func execute(toolName: String, arguments: [String: Any]) async throws -> String
}