import Foundation

enum LauncherItem: Identifiable, Equatable {
    case aiPrompt(query: String)
    case googleSearch(query: String)
    case systemSetting(SystemSettingItem)
    case app(AppSearchItem)
    case tool(ToolKind)

    var id: String {
        switch self {
        case .aiPrompt(let query):
            return "ai:\(query)"
        case .googleSearch(let query):
            return "google:\(query)"
        case .systemSetting(let setting):
            return "setting:\(setting.id)"
        case .app(let app):
            return "app:\(app.id)"
        case .tool(let tool):
            return "tool:\(tool.rawValue)"
        }
    }

    var symbol: String {
        switch self {
        case .aiPrompt:
            return "sparkles"
        case .googleSearch:
            return "magnifyingglass.circle.fill"
        case .systemSetting(let setting):
            return setting.symbol
        case .app:
            return "app.fill"
        case .tool(let tool):
            return tool.symbol
        }
    }

    var isGoogleSearch: Bool {
        if case .googleSearch = self {
            return true
        }
        return false
    }

    var isApplication: Bool {
        if case .app = self {
            return true
        }
        return false
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .aiPrompt:
            return L10n.text("Ask AI Assistant", "交给 AI 助手", language: language)
        case .googleSearch:
            return L10n.text("Search Google", "搜索 Google", language: language)
        case .systemSetting(let setting):
            return setting.title(in: language)
        case .app(let app):
            return app.name
        case .tool(let tool):
            return tool.title(in: language)
        }
    }

    func subtitle(in language: AppLanguage) -> String {
        switch self {
        case .aiPrompt(let query):
            return query
        case .googleSearch(let query):
            return query
        case .systemSetting(let setting):
            return setting.subtitle(in: language)
        case .app(let app):
            let detail = app.bundleIdentifier ?? app.url.path
            if app.isRunning {
                return L10n.text("Running · \(detail)", "运行中 · \(detail)", language: language)
            }
            return detail
        case .tool(let tool):
            return tool.subtitle(in: language)
        }
    }
}
