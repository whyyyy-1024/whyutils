import Foundation

struct ProcessItem: Identifiable, Equatable {
    let id: Int32
    let pid: Int32
    let name: String
    let cpu: Double
    let memory: Double
    let user: String
}