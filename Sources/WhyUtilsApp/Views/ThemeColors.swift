import AppKit
import SwiftUI

extension Color {
    static let whyPanelBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 0.98)
        }
        return NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 0.98)
    })

    static let whyPanelBorder = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.08)
        }
        return NSColor.black.withAlphaComponent(0.10)
    })

    static let whyChromeBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 0.98)
        }
        return NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 0.98)
    })

    static let whyControlBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.10)
        }
        return NSColor.black.withAlphaComponent(0.06)
    })

    static let whyCardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.21, alpha: 0.96)
        }
        return NSColor(calibratedRed: 0.89, green: 0.91, blue: 0.94, alpha: 0.96)
    })

    static let whySidebarBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.98)
        }
        return NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.97, alpha: 0.98)
    })
}
