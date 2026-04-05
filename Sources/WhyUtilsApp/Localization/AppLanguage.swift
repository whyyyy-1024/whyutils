import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case chinese = "zh-Hans"

    static let storageKey = "whyutils.app.language"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> AppLanguage {
        guard let raw = defaults.string(forKey: storageKey) else {
            return .english
        }
        return AppLanguage(rawValue: raw) ?? .english
    }

    static func save(_ language: AppLanguage, to defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: storageKey)
    }

    static func clearForTests(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

enum L10n {
    static func text(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            return english
        case .chinese:
            return chinese
        }
    }

    static func text(_ english: String, _ chinese: String) -> String {
        text(english, chinese, language: AppLanguage.load())
    }
}
