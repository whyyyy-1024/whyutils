import Foundation

struct AppSearchItem: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let url: URL
    let isRunning: Bool
    let lastOpenedAt: Date?
}
