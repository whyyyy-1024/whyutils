import Foundation

struct SystemSettingItem: Identifiable, Equatable {
    let id: String
    let titleEN: String
    let titleZH: String
    let subtitleEN: String
    let subtitleZH: String
    let symbol: String
    let keywords: [String]
    let urlCandidates: [String]

    func title(in language: AppLanguage) -> String {
        L10n.text(titleEN, titleZH, language: language)
    }

    func subtitle(in language: AppLanguage) -> String {
        L10n.text(subtitleEN, subtitleZH, language: language)
    }
}
