import AppKit
import Combine
import Foundation

enum ClipboardEntryKind: String, Codable {
    case text
    case image
}

struct ClipboardHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: ClipboardEntryKind
    let text: String
    let imagePNGData: Data?
    let imageWidth: Int?
    let imageHeight: Int?
    let copiedAt: Date

    init(id: UUID = UUID(), text: String, copiedAt: Date) {
        self.id = id
        self.kind = .text
        self.text = text
        self.imagePNGData = nil
        self.imageWidth = nil
        self.imageHeight = nil
        self.copiedAt = copiedAt
    }

    init(id: UUID = UUID(), imagePNGData: Data, imageWidth: Int, imageHeight: Int, copiedAt: Date) {
        self.id = id
        self.kind = .image
        self.text = "Image (\(imageWidth)×\(imageHeight))"
        self.imagePNGData = imagePNGData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.copiedAt = copiedAt
    }

    var searchableText: String {
        if kind == .image {
            return text.lowercased()
        }
        return text.lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case imagePNGData
        case imageWidth
        case imageHeight
        case copiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(ClipboardEntryKind.self, forKey: .kind) ?? .text
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        imagePNGData = try container.decodeIfPresent(Data.self, forKey: .imagePNGData)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
        copiedAt = try container.decodeIfPresent(Date.self, forKey: .copiedAt) ?? Date()
    }
}

@MainActor
final class ClipboardHistoryService: ObservableObject {
    static let shared = ClipboardHistoryService()

    @Published private(set) var entries: [ClipboardHistoryEntry] = []

    private let maxItems = 200
    private let storageKey = "whyutils.clipboard.history"
    private var timer: Timer?
    private var lastChangeCount: Int

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        load()
        startMonitoring()
    }

    nonisolated static func inserting(
        _ text: String,
        into entries: [ClipboardHistoryEntry],
        copiedAt: Date,
        maxItems: Int
    ) -> [ClipboardHistoryEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }

        var updated = entries

        if let first = updated.first, first.kind == .text, first.text == trimmed {
            return updated
        }

        if let existingIndex = updated.firstIndex(where: { $0.kind == .text && $0.text == trimmed }) {
            updated.remove(at: existingIndex)
        }

        updated.insert(ClipboardHistoryEntry(text: trimmed, copiedAt: copiedAt), at: 0)

        if updated.count > maxItems {
            updated = Array(updated.prefix(maxItems))
        }

        return updated
    }

    nonisolated static func insertingImage(
        _ imagePNGData: Data,
        width: Int,
        height: Int,
        into entries: [ClipboardHistoryEntry],
        copiedAt: Date,
        maxItems: Int
    ) -> [ClipboardHistoryEntry] {
        var updated = entries

        if let first = updated.first, first.kind == .image, first.imagePNGData == imagePNGData {
            return updated
        }

        if let existingIndex = updated.firstIndex(where: { $0.kind == .image && $0.imagePNGData == imagePNGData }) {
            updated.remove(at: existingIndex)
        }

        updated.insert(
            ClipboardHistoryEntry(imagePNGData: imagePNGData, imageWidth: width, imageHeight: height, copiedAt: copiedAt),
            at: 0
        )

        if updated.count > maxItems {
            updated = Array(updated.prefix(maxItems))
        }

        return updated
    }

    func copyToPasteboard(_ entry: ClipboardHistoryEntry) {
        NSPasteboard.general.clearContents()
        switch entry.kind {
        case .text:
            NSPasteboard.general.setString(entry.text, forType: .string)
        case .image:
            guard
                let data = entry.imagePNGData,
                let image = NSImage(data: data)
            else {
                return
            }
            if NSPasteboard.general.writeObjects([image]) == false {
                NSPasteboard.general.setData(data, forType: .png)
            }
        }
    }

    func clear() {
        entries = []
        save()
    }

    func delete(_ entry: ClipboardHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        if
            let image = NSImage(pasteboard: pasteboard),
            let imageInfo = Self.convertToPNGData(image: image)
        {
            entries = Self.insertingImage(
                imageInfo.data,
                width: imageInfo.width,
                height: imageInfo.height,
                into: entries,
                copiedAt: Date(),
                maxItems: maxItems
            )
            save()
            return
        }

        guard let value = pasteboard.string(forType: .string) else { return }
        entries = Self.inserting(value, into: entries, copiedAt: Date(), maxItems: maxItems)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard let value = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: data) else { return }
        entries = value
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func convertToPNGData(image: NSImage) -> (data: Data, width: Int, height: Int)? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        guard let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return nil }
        return (pngData, rep.pixelsWide, rep.pixelsHigh)
    }
}
