import Foundation
import Testing
@testable import WhyUtilsApp

struct ClipboardHistoryServiceTests {
    @Test
    func insertingSkipsImmediateDuplicate() {
        let now = Date()
        let original = [
            ClipboardHistoryEntry(text: "hello", copiedAt: now),
            ClipboardHistoryEntry(text: "world", copiedAt: now.addingTimeInterval(-1))
        ]

        let result = ClipboardHistoryService.inserting("hello", into: original, copiedAt: now, maxItems: 20)
        #expect(result.map(\.text) == ["hello", "world"])
    }

    @Test
    func insertingMovesExistingItemToFront() {
        let now = Date()
        let original = [
            ClipboardHistoryEntry(text: "first", copiedAt: now.addingTimeInterval(-2)),
            ClipboardHistoryEntry(text: "second", copiedAt: now.addingTimeInterval(-1))
        ]

        let result = ClipboardHistoryService.inserting("second", into: original, copiedAt: now, maxItems: 20)
        #expect(result.map(\.text) == ["second", "first"])
    }

    @Test
    func insertingRespectsMaxItems() {
        let now = Date()
        let original = [
            ClipboardHistoryEntry(text: "a", copiedAt: now.addingTimeInterval(-3)),
            ClipboardHistoryEntry(text: "b", copiedAt: now.addingTimeInterval(-2)),
            ClipboardHistoryEntry(text: "c", copiedAt: now.addingTimeInterval(-1))
        ]

        let result = ClipboardHistoryService.inserting("d", into: original, copiedAt: now, maxItems: 3)
        #expect(result.map(\.text) == ["d", "a", "b"])
    }
}
