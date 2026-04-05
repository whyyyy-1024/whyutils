import AppKit
import Foundation

@MainActor
final class AppSearchService: ObservableObject {
    static let shared = AppSearchService()
    static let dataDidChangeNotification = Notification.Name("com.whyutils.app-search.data-did-change")

    private struct RecentAppRecord: Codable, Equatable {
        let id: String
        let name: String
        let bundleIdentifier: String?
        let path: String
        let lastOpenedAt: Date
    }

    private struct IndexedApp: Equatable {
        let id: String
        let name: String
        let bundleIdentifier: String?
        let url: URL
    }

    private struct Candidate {
        var id: String
        var name: String
        var bundleIdentifier: String?
        var url: URL
        var isRunning: Bool
        var lastOpenedAt: Date?

        var searchItem: AppSearchItem {
            AppSearchItem(
                id: id,
                name: name,
                bundleIdentifier: bundleIdentifier,
                url: url,
                isRunning: isRunning,
                lastOpenedAt: lastOpenedAt
            )
        }
    }

    private let recentsStorageKey = "whyutils.app-search.recent-apps"
    private let recentLimit = 160
    private let indexQueue = DispatchQueue(label: "com.whyutils.app-search.index", qos: .userInitiated)

    private var defaults: UserDefaults
    private var recents: [RecentAppRecord]
    private var indexedApps: [IndexedApp] = []
    private var indexedAppsSignature: [String: Int64] = [:]
    private var indexingInProgress = false
    private var activationObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recents = Self.loadRecents(defaults: defaults, key: recentsStorageKey)
        installWorkspaceObservers()
    }

    func search(query: String, limit: Int) -> [AppSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        ensureApplicationIndexLoadedIfNeeded(query: trimmed)

        let runningApps = collectRunningApplications()
        var runningMap: [String: Candidate] = [:]
        for app in runningApps {
            if let existing = runningMap[app.id] {
                runningMap[app.id] = existing.isRunning ? existing : app
            } else {
                runningMap[app.id] = app
            }
        }
        var candidates: [String: Candidate] = [:]

        for recent in recents {
            let url = URL(fileURLWithPath: recent.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let running = runningMap[recent.id]
            var candidate = Candidate(
                id: recent.id,
                name: recent.name,
                bundleIdentifier: recent.bundleIdentifier,
                url: url,
                isRunning: running?.isRunning ?? false,
                lastOpenedAt: recent.lastOpenedAt
            )
            if let running {
                candidate.url = running.url
                if candidate.bundleIdentifier == nil {
                    candidate.bundleIdentifier = running.bundleIdentifier
                }
                if candidate.name.isEmpty {
                    candidate.name = running.name
                }
            }
            candidates[recent.id] = candidate
        }

        for running in runningApps {
            merge(candidate: running, into: &candidates)
        }

        if trimmed.isEmpty == false {
            for indexed in indexedApps {
                let candidate = Candidate(
                    id: indexed.id,
                    name: indexed.name,
                    bundleIdentifier: indexed.bundleIdentifier,
                    url: indexed.url,
                    isRunning: runningMap[indexed.id]?.isRunning ?? false,
                    lastOpenedAt: candidates[indexed.id]?.lastOpenedAt
                )
                merge(candidate: candidate, into: &candidates)
            }
        }

        let allItems = candidates.values.map { $0.searchItem }
        let sorted = Self.sort(items: allItems, query: trimmed)
        return Array(sorted.prefix(max(1, limit)))
    }

    func open(_ item: AppSearchItem) -> Bool {
        if let running = runningApplication(for: item) {
            let activated = running.activate(options: [.activateIgnoringOtherApps])
            recordOpened(item)
            return activated
        }

        let opened = NSWorkspace.shared.open(item.url)
        if opened {
            recordOpened(item)
        }
        return opened
    }

    func reveal(_ item: AppSearchItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    nonisolated static func matchScore(
        itemName: String,
        bundleIdentifier: String?,
        path: String,
        query: String
    ) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return 0 }

        let q = normalized(trimmed)
        let name = normalized(itemName)
        let bundle = normalized(bundleIdentifier ?? "")
        let pathValue = normalized(path)

        if name == q { return 1200 }
        if name.hasPrefix(q) { return 1000 }
        if name.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 920 }
        if name.contains(q) { return 780 }
        if bundle.hasPrefix(q) { return 700 }
        if bundle.contains(q) { return 640 }
        if pathValue.contains(q) { return 520 }
        return nil
    }

    nonisolated static func sort(items: [AppSearchItem], query: String, now: Date = Date()) -> [AppSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return items.sorted { lhs, rhs in
                let leftDate = lhs.lastOpenedAt ?? .distantPast
                let rightDate = rhs.lastOpenedAt ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                if lhs.isRunning != rhs.isRunning {
                    return lhs.isRunning && !rhs.isRunning
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        return items
            .compactMap { item -> (AppSearchItem, Int, Double)? in
                guard let base = matchScore(
                    itemName: item.name,
                    bundleIdentifier: item.bundleIdentifier,
                    path: item.url.path,
                    query: trimmed
                ) else { return nil }

                let runningBonus = item.isRunning ? 55 : 0
                let recencyBonus = recencyBonus(lastOpenedAt: item.lastOpenedAt, now: now)
                let total = base + runningBonus + recencyBonus
                let recency = item.lastOpenedAt?.timeIntervalSinceReferenceDate ?? 0
                return (item, total, recency)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let url = running.bundleURL
            else {
                return
            }
            let name = running.localizedName ?? url.deletingPathExtension().lastPathComponent
            let bundleIdentifier = running.bundleIdentifier
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleAppEvent(name: name, bundleIdentifier: bundleIdentifier, url: url)
            }
        }

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.notifyDataDidChange()
            }
        }

        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.notifyDataDidChange()
            }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if let activationObserver {
            center.removeObserver(activationObserver)
        }
        if let launchObserver {
            center.removeObserver(launchObserver)
        }
        if let terminateObserver {
            center.removeObserver(terminateObserver)
        }
    }

    private func handleAppEvent(name: String, bundleIdentifier: String?, url: URL) {
        guard Self.shouldTrackApplication(
            bundleIdentifier: bundleIdentifier,
            path: url.path,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        ) else {
            return
        }

        let id = bundleIdentifier ?? url.path
        let item = AppSearchItem(
            id: id,
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: url,
            isRunning: true,
            lastOpenedAt: Date()
        )
        recordOpened(item)
    }

    private func recordOpened(_ item: AppSearchItem) {
        let record = RecentAppRecord(
            id: item.id,
            name: item.name,
            bundleIdentifier: item.bundleIdentifier,
            path: item.url.path,
            lastOpenedAt: Date()
        )

        recents.removeAll(where: { $0.id == record.id })
        recents.insert(record, at: 0)
        if recents.count > recentLimit {
            recents = Array(recents.prefix(recentLimit))
        }

        Self.saveRecents(recents, defaults: defaults, key: recentsStorageKey)
        notifyDataDidChange()
    }

    private func collectRunningApplications() -> [Candidate] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard
                let url = app.bundleURL,
                Self.shouldTrackApplication(
                    bundleIdentifier: app.bundleIdentifier,
                    path: url.path,
                    ownBundleIdentifier: ownBundleIdentifier
                )
            else {
                return nil
            }

            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            let id = app.bundleIdentifier ?? url.path
            let lastOpened = recents.first(where: { $0.id == id })?.lastOpenedAt
            return Candidate(
                id: id,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                url: url,
                isRunning: !app.isTerminated,
                lastOpenedAt: lastOpened
            )
        }
    }

    private func runningApplication(for item: AppSearchItem) -> NSRunningApplication? {
        if let bundleID = item.bundleIdentifier {
            if let matched = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                return matched
            }
        }
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == item.url })
    }

    private func ensureApplicationIndexLoadedIfNeeded(query: String) {
        let currentSignature = Self.applicationRootsSignature()
        guard Self.shouldRefreshInstalledApplicationsIndex(
            query: query,
            indexedAppsEmpty: indexedApps.isEmpty,
            indexingInProgress: indexingInProgress,
            lastKnownSignature: indexedAppsSignature,
            currentSignature: currentSignature
        ) else {
            return
        }

        indexingInProgress = true
        indexQueue.async { [weak self] in
            let apps = Self.scanInstalledApplications()
            DispatchQueue.main.async {
                guard let self else { return }
                self.indexedApps = apps
                self.indexedAppsSignature = currentSignature
                self.indexingInProgress = false
                self.notifyDataDidChange()
            }
        }
    }

    private func notifyDataDidChange() {
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.dataDidChangeNotification, object: nil)
    }

    private func merge(candidate: Candidate, into dict: inout [String: Candidate]) {
        guard let existing = dict[candidate.id] else {
            dict[candidate.id] = candidate
            return
        }

        let name = existing.name.count >= candidate.name.count ? existing.name : candidate.name
        let bundleID = existing.bundleIdentifier ?? candidate.bundleIdentifier
        let url = FileManager.default.fileExists(atPath: existing.url.path) ? existing.url : candidate.url
        let isRunning = existing.isRunning || candidate.isRunning
        let lastOpened: Date?
        switch (existing.lastOpenedAt, candidate.lastOpenedAt) {
        case let (left?, right?):
            lastOpened = max(left, right)
        case let (left?, nil):
            lastOpened = left
        case let (nil, right?):
            lastOpened = right
        default:
            lastOpened = nil
        }

        dict[candidate.id] = Candidate(
            id: candidate.id,
            name: name,
            bundleIdentifier: bundleID,
            url: url,
            isRunning: isRunning,
            lastOpenedAt: lastOpened
        )
    }

    nonisolated private static func shouldTrackApplication(
        bundleIdentifier: String?,
        path: String,
        ownBundleIdentifier: String?
    ) -> Bool {
        if let bundleIdentifier, bundleIdentifier == ownBundleIdentifier {
            return false
        }

        let normalizedPath = path.lowercased()
        if normalizedPath.hasPrefix("/system/library/") {
            return false
        }
        if normalizedPath.contains("/xcode.app/contents/developer/") {
            return false
        }
        if normalizedPath.contains("/library/input methods/") {
            return false
        }
        if normalizedPath.hasSuffix(".appex") {
            return false
        }
        return normalizedPath.hasSuffix(".app")
    }

    nonisolated private static func recencyBonus(lastOpenedAt: Date?, now: Date) -> Int {
        guard let lastOpenedAt else { return 0 }
        let delta = max(0, now.timeIntervalSince(lastOpenedAt))
        if delta < 30 { return 120 }
        if delta < 180 { return 95 }
        if delta < 1_800 { return 70 }
        if delta < 10_800 { return 45 }
        if delta < 86_400 { return 28 }
        if delta < 604_800 { return 14 }
        return 0
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    nonisolated private static func loadRecents(defaults: UserDefaults, key: String) -> [RecentAppRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let value = try? JSONDecoder().decode([RecentAppRecord].self, from: data) else { return [] }
        return value
    }

    nonisolated private static func saveRecents(_ value: [RecentAppRecord], defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    nonisolated static func shouldRefreshInstalledApplicationsIndex(
        query: String,
        indexedAppsEmpty: Bool,
        indexingInProgress: Bool,
        lastKnownSignature: [String: Int64],
        currentSignature: [String: Int64]
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        guard indexingInProgress == false else { return false }
        if indexedAppsEmpty { return true }
        return lastKnownSignature != currentSignature
    }

    nonisolated private static func applicationRootsSignature(fileManager: FileManager = .default) -> [String: Int64] {
        var signature: [String: Int64] = [:]
        for root in applicationSearchRoots(fileManager: fileManager) {
            let values = try? root.resourceValues(forKeys: [.contentModificationDateKey, .attributeModificationDateKey])
            let modificationDate = values?.contentModificationDate
                ?? values?.attributeModificationDate
                ?? .distantPast
            signature[root.path] = Int64(modificationDate.timeIntervalSince1970)
        }
        return signature
    }

    nonisolated private static func scanInstalledApplications(fileManager: FileManager = .default) -> [IndexedApp] {
        var seen = Set<String>()
        var items: [IndexedApp] = []

        for root in applicationSearchRoots(fileManager: fileManager) where fileManager.fileExists(atPath: root.path) {
            if let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) {
                for case let url as URL in enumerator {
                    guard url.pathExtension.lowercased() == "app" else { continue }
                    appendIndexedApp(url: url, seen: &seen, items: &items)
                }
            }
        }

        return items.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func applicationSearchRoots(fileManager: FileManager = .default) -> [URL] {
        let baseRoots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var roots: [URL] = []
        for root in baseRoots {
            roots.append(root)
            roots.append(root.appendingPathComponent("Utilities"))
        }
        return roots
    }

    nonisolated private static func appendIndexedApp(url: URL, seen: inout Set<String>, items: inout [IndexedApp]) {
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let id = bundleIdentifier ?? url.path
        guard seen.insert(id).inserted else { return }

        items.append(
            IndexedApp(
                id: id,
                name: name,
                bundleIdentifier: bundleIdentifier,
                url: url
            )
        )
    }
}
