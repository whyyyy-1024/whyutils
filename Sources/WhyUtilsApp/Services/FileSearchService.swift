import AppKit
import Foundation

enum FileSearchScope: Equatable {
    case user(userName: String)
    case thisMac

    var displayTitle: String {
        switch self {
        case .user(let userName):
            return "User (\(userName))"
        case .thisMac:
            return "This Mac"
        }
    }

    var metadataScopes: [Any] {
        switch self {
        case .user:
            return [NSMetadataQueryUserHomeScope]
        case .thisMac:
            return [NSMetadataQueryLocalComputerScope]
        }
    }
}

struct FileSearchResult: Identifiable, Equatable {
    let url: URL
    let fileName: String
    let parentPath: String
    let modifiedAt: Date?
    let createdAt: Date?
    let fileSize: Int64?
    let isDirectory: Bool

    var id: String { url.path }
}

@MainActor
final class FileSearchService: NSObject, ObservableObject {
    static let shared = FileSearchService()

    @Published private(set) var results: [FileSearchResult] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var sectionTitle: String = "Recent Files"

    private let resultLimit = 200
    private let query = NSMetadataQuery()
    private var currentScope: FileSearchScope
    private var currentText: String = ""
    private var debounceItem: DispatchWorkItem?
    private var observing = false

    private let fsNameKey = "kMDItemFSName"
    private let pathKey = "kMDItemPath"
    private let modifiedDateKey = "kMDItemFSContentChangeDate"
    private let createDateKey = "kMDItemFSCreationDate"
    private let fsSizeKey = "kMDItemFSSize"
    private let contentTypeTreeKey = "kMDItemContentTypeTree"

    override init() {
        self.currentScope = .user(userName: NSUserName())
        super.init()
        query.searchScopes = currentScope.metadataScopes
        installObserversIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(scope: FileSearchScope, queryText: String) {
        currentScope = scope
        currentText = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        sectionTitle = currentText.isEmpty ? "Recent Files" : "Files"

        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.startQuery()
            }
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    func stop() {
        debounceItem?.cancel()
        if query.isStarted {
            query.stop()
        }
        isSearching = false
    }

    func open(_ result: FileSearchResult) {
        NSWorkspace.shared.open(result.url)
    }

    func reveal(_ result: FileSearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.url])
    }

    nonisolated static func shouldExcludePath(_ path: String, scope: FileSearchScope) -> Bool {
        let normalized = path.lowercased()

        if normalized.contains("/.") {
            return true
        }

        switch scope {
        case .thisMac:
            if normalized.hasPrefix("/system/")
                || normalized.hasPrefix("/private/")
                || normalized.hasPrefix("/library/")
                || normalized.hasPrefix("/dev/")
                || normalized.hasPrefix("/cores/")
                || normalized.hasPrefix("/volumes/") {
                return true
            }
            return false
        case .user:
            return false
        }
    }

    nonisolated static func sort(_ values: [FileSearchResult]) -> [FileSearchResult] {
        values.sorted { lhs, rhs in
            let leftDate = lhs.modifiedAt ?? .distantPast
            let rightDate = rhs.modifiedAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }
    }

    private func installObserversIfNeeded() {
        guard observing == false else { return }
        observing = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryUpdated),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueryUpdated),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
    }

    private func startQuery() {
        if query.isStarted {
            query.stop()
        }

        query.searchScopes = currentScope.metadataScopes
        query.predicate = buildPredicate(scope: currentScope, queryText: currentText)
        query.sortDescriptors = [
            NSSortDescriptor(key: modifiedDateKey, ascending: false)
        ]

        results = []
        isSearching = true
        query.start()
    }

    @objc
    private func handleQueryUpdated(_ notification: Notification) {
        guard let metadataItems = query.results as? [NSMetadataItem] else {
            results = []
            isSearching = false
            return
        }

        var mapped: [FileSearchResult] = []
        mapped.reserveCapacity(min(metadataItems.count, resultLimit))
        var seenPaths = Set<String>()

        for item in metadataItems {
            guard
                let path = item.value(forAttribute: pathKey) as? String,
                let name = item.value(forAttribute: fsNameKey) as? String
            else {
                continue
            }

            if Self.shouldExcludePath(path, scope: currentScope) {
                continue
            }
            if seenPaths.contains(path) {
                continue
            }
            seenPaths.insert(path)

            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
            if values?.isDirectory == true {
                continue
            }

            let parent = url.deletingLastPathComponent().path
            let modifiedAt = item.value(forAttribute: modifiedDateKey) as? Date
            let createdAt = item.value(forAttribute: createDateKey) as? Date
            let fileSize = (item.value(forAttribute: fsSizeKey) as? NSNumber)?.int64Value

            mapped.append(
                FileSearchResult(
                    url: url,
                    fileName: name,
                    parentPath: parent,
                    modifiedAt: modifiedAt,
                    createdAt: createdAt,
                    fileSize: fileSize,
                    isDirectory: false
                )
            )

            if mapped.count >= resultLimit {
                break
            }
        }

        results = Self.sort(mapped)
        isSearching = false
        query.disableUpdates()
        query.enableUpdates()
    }

    private func buildPredicate(scope: FileSearchScope, queryText: String) -> NSPredicate {
        let base = NSPredicate(format: "%K == %@", contentTypeTreeKey, "public.item")
        if queryText.isEmpty {
            return base
        }

        let q = queryText
        let content = NSPredicate(
            format: "(%K CONTAINS[cd] %@) OR (%K CONTAINS[cd] %@)",
            fsNameKey, q, pathKey, q
        )
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, content])
    }
}
