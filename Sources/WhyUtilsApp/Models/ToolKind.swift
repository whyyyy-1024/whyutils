import Foundation

enum ToolKind: String, CaseIterable, Identifiable {
    case aiAssistant
    case clipboard
    case searchFiles
    case json
    case time
    case url
    case base64
    case hash
    case regex

    var id: String { rawValue }

    var title: String { title(in: AppLanguage.load()) }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .aiAssistant: return L10n.text("AI Assistant", "AI 助手", language: language)
        case .clipboard: return L10n.text("Clipboard History", "剪贴板历史", language: language)
        case .searchFiles: return L10n.text("Search Files", "搜索文件", language: language)
        case .json: return L10n.text("JSON Tool", "JSON 工具", language: language)
        case .time: return L10n.text("Timestamp", "时间戳转换", language: language)
        case .url: return L10n.text("URL Encode/Decode", "URL 编解码", language: language)
        case .base64: return "Base64"
        case .hash: return L10n.text("Hash", "哈希", language: language)
        case .regex: return L10n.text("Regex Tester", "正则测试器", language: language)
        }
    }

    var subtitle: String { subtitle(in: AppLanguage.load()) }

    func subtitle(in language: AppLanguage) -> String {
        switch self {
        case .aiAssistant: return L10n.text("Plan and run WhyUtils tools with AI", "用 AI 规划并调用 WhyUtils 工具", language: language)
        case .clipboard: return L10n.text("Browse, search, and paste clipboard history", "查看、搜索、回贴历史复制内容", language: language)
        case .searchFiles: return L10n.text("File Search", "文件搜索", language: language)
        case .json: return L10n.text("Validate, format, minify, and escape", "合法性检查、格式化、压缩、转义", language: language)
        case .time: return L10n.text("Convert timestamps and dates", "秒/毫秒时间戳与日期互转", language: language)
        case .url: return "URL encode/decode"
        case .base64: return L10n.text("Text Base64 encode/decode", "文本 Base64 编解码", language: language)
        case .hash: return L10n.text("SHA/MD5 digest", "SHA/MD5 摘要计算", language: language)
        case .regex: return L10n.text("Match and replace preview", "匹配与替换预览", language: language)
        }
    }

    var symbol: String {
        switch self {
        case .aiAssistant: return "sparkles"
        case .clipboard: return "doc.on.clipboard"
        case .searchFiles: return "magnifyingglass.circle.fill"
        case .json: return "curlybraces.square"
        case .time: return "clock.arrow.circlepath"
        case .url: return "link"
        case .base64: return "number.square.fill"
        case .hash: return "number.square"
        case .regex: return "text.magnifyingglass"
        }
    }

    func matches(_ query: String, language: AppLanguage) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        let texts = [
            title(in: .english),
            title(in: .chinese),
            subtitle(in: .english),
            subtitle(in: .chinese),
            title(in: language),
            subtitle(in: language),
            rawValue
        ]
        return texts.joined(separator: " ").lowercased().contains(q)
    }
}
