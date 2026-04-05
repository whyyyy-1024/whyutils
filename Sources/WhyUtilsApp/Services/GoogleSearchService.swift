import AppKit
import Foundation

enum GoogleSearchService {
    static func buildSearchURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    @discardableResult
    static func searchInChrome(query: String) -> String {
        guard let url = buildSearchURL(query: query) else {
            return L10n.text("Please enter keywords to search", "请输入要搜索的关键词")
        }

        if let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: configuration)
            return L10n.text("Opened Google search in Chrome", "已在 Chrome 打开 Google 搜索")
        }

        NSWorkspace.shared.open(url)
        return L10n.text("Chrome not found. Opened search in default browser", "未检测到 Chrome，已使用默认浏览器搜索")
    }
}
