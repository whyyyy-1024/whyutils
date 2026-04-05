import Foundation

enum TimeConversionError: LocalizedError {
    case invalidTimestamp
    case invalidDate
    case outOfRange

    var errorDescription: String? {
        switch self {
        case .invalidTimestamp: return L10n.text("Invalid timestamp format", "时间戳格式错误")
        case .invalidDate: return L10n.text("Unsupported date format. Try YYYY-MM-DD HH:mm:ss or ISO8601", "日期格式不支持，试试 YYYY-MM-DD HH:mm:ss 或 ISO8601")
        case .outOfRange: return L10n.text("Time is out of supported range", "时间超出可处理范围")
        }
    }
}

enum TimestampInputUnit: String, CaseIterable, Identifiable {
    case auto
    case seconds
    case milliseconds
    case microseconds
    case nanoseconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return L10n.text("Auto", "自动")
        case .seconds: return L10n.text("Seconds", "秒")
        case .milliseconds: return L10n.text("Milliseconds", "毫秒")
        case .microseconds: return L10n.text("Microseconds", "微秒")
        case .nanoseconds: return L10n.text("Nanoseconds", "纳秒")
        }
    }
}

struct TimeConversionResult {
    let inferredUnit: String
    let seconds: Int
    let milliseconds: Int
    let localTime: String
    let utcTime: String
    let localDateTime: String
    let iso8601UTC: String
}

struct LiveTimeSnapshot {
    let localTime: String
    let localDateTime: String
    let utcTime: String
    let iso8601UTC: String
    let seconds: Int
    let milliseconds: Int
}

enum TimeService {
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

    static func timestampToDate(_ input: String, inputUnit: TimestampInputUnit = .auto) throws -> TimeConversionResult {
        let (secondsValue, unit) = try parseTimestamp(input, inputUnit: inputUnit)
        let date = Date(timeIntervalSince1970: secondsValue)

        if !date.timeIntervalSince1970.isFinite {
            throw TimeConversionError.outOfRange
        }

        let seconds = Int(secondsValue.rounded(.towardZero))
        let milliseconds = Int((secondsValue * 1000.0).rounded())

        return TimeConversionResult(
            inferredUnit: unit,
            seconds: seconds,
            milliseconds: milliseconds,
            localTime: formatDate(date, timezone: .current),
            utcTime: formatDate(date, timezone: utcTimeZone),
            localDateTime: formatDateTimePlain(date, timezone: .current),
            iso8601UTC: formatISO8601UTC(date)
        )
    }

    static func dateToTimestamp(_ input: String, interpretAsUTC: Bool) throws -> TimeConversionResult {
        let date = try parseDate(input, interpretAsUTC: interpretAsUTC)

        let secondsValue = date.timeIntervalSince1970
        let seconds = Int(secondsValue.rounded(.towardZero))
        let milliseconds = Int((secondsValue * 1000.0).rounded())

        return TimeConversionResult(
            inferredUnit: L10n.text("datetime", "日期时间"),
            seconds: seconds,
            milliseconds: milliseconds,
            localTime: formatDate(date, timezone: .current),
            utcTime: formatDate(date, timezone: utcTimeZone),
            localDateTime: formatDateTimePlain(date, timezone: .current),
            iso8601UTC: formatISO8601UTC(date)
        )
    }

    static func liveSnapshot(now: Date = Date()) -> LiveTimeSnapshot {
        let secondsValue = now.timeIntervalSince1970
        let seconds = Int(secondsValue.rounded(.towardZero))
        let milliseconds = Int((secondsValue * 1000.0).rounded())
        return LiveTimeSnapshot(
            localTime: formatDate(now, timezone: .current),
            localDateTime: formatDateTimePlain(now, timezone: .current),
            utcTime: formatDate(now, timezone: utcTimeZone),
            iso8601UTC: formatISO8601UTC(now),
            seconds: seconds,
            milliseconds: milliseconds
        )
    }

    private static func parseTimestamp(_ input: String, inputUnit: TimestampInputUnit) throws -> (Double, String) {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw TimeConversionError.invalidTimestamp }

        guard let numericValue = Double(raw) else {
            throw TimeConversionError.invalidTimestamp
        }

        if inputUnit != .auto {
            return (secondsValue(from: numericValue, unit: inputUnit), inputUnit.rawValue)
        }

        if raw.contains(".") {
            return (numericValue, L10n.text("seconds", "秒"))
        }

        let digits = raw.replacingOccurrences(of: "-", with: "").count
        switch digits {
        case 0...10:
            return (numericValue, L10n.text("seconds", "秒"))
        case 13:
            return (numericValue / 1_000.0, L10n.text("milliseconds", "毫秒"))
        case 16:
            return (numericValue / 1_000_000.0, L10n.text("microseconds", "微秒"))
        case 19:
            return (numericValue / 1_000_000_000.0, L10n.text("nanoseconds", "纳秒"))
        default:
            throw TimeConversionError.invalidTimestamp
        }
    }

    private static func parseDate(_ input: String, interpretAsUTC: Bool) throws -> Date {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw TimeConversionError.invalidDate }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }

        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        if let date = isoBasic.date(from: raw) { return date }

        let timezone = interpretAsUTC ? utcTimeZone : .current
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timezone
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }

        throw TimeConversionError.invalidDate
    }

    private static func formatDate(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }

    private static func formatDateTimePlain(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func formatISO8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utcTimeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func secondsValue(from raw: Double, unit: TimestampInputUnit) -> Double {
        switch unit {
        case .auto, .seconds:
            return raw
        case .milliseconds:
            return raw / 1_000.0
        case .microseconds:
            return raw / 1_000_000.0
        case .nanoseconds:
            return raw / 1_000_000_000.0
        }
    }
}
