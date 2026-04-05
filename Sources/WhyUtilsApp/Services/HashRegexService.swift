import CryptoKit
import Foundation

enum HashAlgorithm: String, CaseIterable, Identifiable {
    case md5
    case sha1
    case sha256
    case sha384
    case sha512

    var id: String { rawValue }
}

enum HashService {
    static func digest(_ text: String, algorithm: HashAlgorithm) -> String {
        let data = Data(text.utf8)
        switch algorithm {
        case .md5:
            let hash = Insecure.MD5.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        case .sha1:
            let hash = Insecure.SHA1.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        case .sha256:
            let hash = SHA256.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        case .sha384:
            let hash = SHA384.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        case .sha512:
            let hash = SHA512.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        }
    }
}

struct RegexMatchItem: Identifiable {
    let id = UUID()
    let index: Int
    let range: NSRange
    let text: String
    let groups: [String]
}

enum RegexServiceError: LocalizedError {
    case invalidPattern(String)

    var errorDescription: String? {
        switch self {
        case .invalidPattern(let message): return message
        }
    }
}

enum RegexService {
    static func findMatches(
        pattern: String,
        text: String,
        ignoreCase: Bool,
        multiLine: Bool,
        dotMatchesNewLine: Bool
    ) throws -> [RegexMatchItem] {
        let regex = try compile(
            pattern: pattern,
            ignoreCase: ignoreCase,
            multiLine: multiLine,
            dotMatchesNewLine: dotMatchesNewLine
        )

        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.enumerated().map { idx, match in
            var groups: [String] = []
            if match.numberOfRanges > 1 {
                for groupIndex in 1..<match.numberOfRanges {
                    let r = match.range(at: groupIndex)
                    if r.location != NSNotFound {
                        groups.append(source.substring(with: r))
                    } else {
                        groups.append("")
                    }
                }
            }
            return RegexMatchItem(
                index: idx + 1,
                range: match.range,
                text: source.substring(with: match.range),
                groups: groups
            )
        }
    }

    static func replace(
        pattern: String,
        replacement: String,
        text: String,
        ignoreCase: Bool,
        multiLine: Bool,
        dotMatchesNewLine: Bool
    ) throws -> String {
        let regex = try compile(
            pattern: pattern,
            ignoreCase: ignoreCase,
            multiLine: multiLine,
            dotMatchesNewLine: dotMatchesNewLine
        )
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func compile(
        pattern: String,
        ignoreCase: Bool,
        multiLine: Bool,
        dotMatchesNewLine: Bool
    ) throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if ignoreCase { options.insert(.caseInsensitive) }
        if multiLine { options.insert(.anchorsMatchLines) }
        if dotMatchesNewLine { options.insert(.dotMatchesLineSeparators) }

        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw RegexServiceError.invalidPattern(error.localizedDescription)
        }
    }
}
