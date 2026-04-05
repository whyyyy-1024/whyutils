import Foundation

enum JSONServiceError: LocalizedError {
    case invalidJSON(String)
    case invalidJSONString

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message): return message
        case .invalidJSONString: return L10n.text("Input must be a quoted JSON string", "输入必须是带引号的 JSON 字符串")
        }
    }
}

enum JSONService {
    static func parse(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw JSONServiceError.invalidJSON(L10n.text("Failed to encode input", "输入编码失败"))
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw JSONServiceError.invalidJSON(error.localizedDescription)
        }
    }

    static func validate(_ text: String) throws -> String {
        let value = try parse(text)
        return "\(L10n.text("JSON is valid", "JSON 合法"))\n\(L10n.text("Type", "类型")): \(typeName(of: value))"
    }

    static func format(_ text: String) throws -> String {
        let value = try parse(text)
        return try serialize(value, pretty: true)
    }

    static func minify(_ text: String) throws -> String {
        let value = try parse(text)
        return try serialize(value, pretty: false)
    }

    static func escapeJSONString(_ text: String) throws -> String {
        let compact = try minify(text)
        return try encodeJSONString(compact)
    }

    static func unescapeJSONString(_ text: String) throws -> String {
        let value = try parse(text)
        guard let str = value as? String else {
            throw JSONServiceError.invalidJSONString
        }

        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return str }

        do {
            let nested = try parse(trimmed)
            return try serialize(nested, pretty: true)
        } catch {
            return str
        }
    }

    private static func typeName(of value: Any) -> String {
        if value is NSNull { return "null" }
        if value is [Any] { return "array" }
        if value is [String: Any] { return "object" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "bool"
            }
            return "number"
        }
        return "unknown"
    }

    private static func serialize(_ value: Any, pretty: Bool) throws -> String {
        if JSONSerialization.isValidJSONObject(value) {
            let data = try JSONSerialization.data(
                withJSONObject: value,
                options: pretty ? [.prettyPrinted] : []
            )
            guard let string = String(data: data, encoding: .utf8) else {
                throw JSONServiceError.invalidJSON(L10n.text("Serialization failed", "序列化失败"))
            }
            return string
        }

        if value is NSNull { return "null" }
        if let string = value as? String { return try encodeJSONString(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }

        throw JSONServiceError.invalidJSON(L10n.text("Unsupported JSON value", "不支持的 JSON 值"))
    }

    private static func encodeJSONString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode([value])
        guard var text = String(data: data, encoding: .utf8) else {
            throw JSONServiceError.invalidJSON(L10n.text("Failed to escape string", "字符串转义失败"))
        }
        text.removeFirst()
        text.removeLast()
        return text
    }
}
