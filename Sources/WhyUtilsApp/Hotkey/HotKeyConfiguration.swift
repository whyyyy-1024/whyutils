import Carbon
import Foundation

enum HotKeyKey: String, CaseIterable, Identifiable, Codable {
    case space
    case k
    case p
    case j
    case l
    case period
    case comma

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .space: return UInt32(kVK_Space)
        case .k: return UInt32(kVK_ANSI_K)
        case .p: return UInt32(kVK_ANSI_P)
        case .j: return UInt32(kVK_ANSI_J)
        case .l: return UInt32(kVK_ANSI_L)
        case .period: return UInt32(kVK_ANSI_Period)
        case .comma: return UInt32(kVK_ANSI_Comma)
        }
    }

    var title: String {
        switch self {
        case .space: return "Space"
        case .k: return "K"
        case .p: return "P"
        case .j: return "J"
        case .l: return "L"
        case .period: return "."
        case .comma: return ","
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var key: HotKeyKey
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    static let `default` = HotKeyConfiguration(
        key: .space,
        command: true,
        shift: true,
        option: false,
        control: false
    )

    var modifiers: UInt32 {
        var value: UInt32 = 0
        if command { value |= UInt32(cmdKey) }
        if shift { value |= UInt32(shiftKey) }
        if option { value |= UInt32(optionKey) }
        if control { value |= UInt32(controlKey) }
        return value
    }

    var display: String {
        var parts: [String] = []
        if command { parts.append("⌘") }
        if shift { parts.append("⇧") }
        if option { parts.append("⌥") }
        if control { parts.append("⌃") }
        parts.append(key.title)
        return parts.joined()
    }

    var normalized: HotKeyConfiguration {
        if command || shift || option || control {
            return self
        }
        var copy = self
        copy.command = true
        return copy
    }
}
