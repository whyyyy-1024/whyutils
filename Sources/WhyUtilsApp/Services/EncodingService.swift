import Foundation

enum EncodingServiceError: LocalizedError {
    case emptyInput
    case invalidBase64
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .emptyInput: return L10n.text("Input is empty", "输入为空")
        case .invalidBase64: return L10n.text("Invalid Base64 input", "Base64 输入无效")
        case .invalidUTF8: return L10n.text("Decoded result is not UTF-8 text", "解码结果不是 UTF-8 文本")
        }
    }
}

enum EncodingService {
    static func urlEncode(_ input: String, safe: String = "") -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: safe)
        return input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input
    }

    static func urlDecode(_ input: String) -> String {
        input.removingPercentEncoding ?? input
    }

    static func base64Encode(_ input: String, urlSafe: Bool, stripPadding: Bool) -> String {
        var encoded = Data(input.utf8).base64EncodedString()
        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        if stripPadding {
            encoded = encoded.replacingOccurrences(of: "=", with: "")
        }
        return encoded
    }

    static func base64Decode(_ input: String, urlSafe: Bool) throws -> String {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw EncodingServiceError.emptyInput }

        if urlSafe {
            raw = raw
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
        }

        let remainder = raw.count % 4
        if remainder != 0 {
            raw += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: raw) else {
            throw EncodingServiceError.invalidBase64
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw EncodingServiceError.invalidUTF8
        }
        return text
    }
}
