import SwiftUI

struct TimeToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    enum InputSource {
        case timestamp
        case datetime
    }

    @State private var timestampInput: String = ""
    @State private var dateInput: String = ""
    @State private var interpretAsUTC: Bool = false
    @State private var timestampUnit: TimestampInputUnit = .auto

    @State private var lastResult: TimeConversionResult?
    @State private var lastSource: InputSource = .timestamp
    @State private var now: Date = Date()

    @State private var status: String = "Type to convert. Live timestamp is always updating."
    @State private var isError: Bool = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var live: LiveTimeSnapshot {
        TimeService.liveSnapshot(now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            liveCard
            conversionWorkspace
            resultCard
            footerBar
        }
        .onReceive(ticker) { value in
            now = value
        }
        .onChange(of: timestampInput) { _ in
            guard !timestampInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            convertTimestampInput()
        }
        .onChange(of: timestampUnit) { _ in
            guard !timestampInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            convertTimestampInput()
        }
        .onChange(of: dateInput) { _ in
            guard !dateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            convertDateInput()
        }
        .onChange(of: interpretAsUTC) { _ in
            guard !dateInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            convertDateInput()
        }
    }

    private var liveCard: some View {
        ToolCard(title: t("Live Timestamp", "实时时间戳")) {
            VStack(alignment: .leading, spacing: 8) {
                copyableRow(t("Local Time", "当前本地时间"), live.localTime)
                copyableRow(t("Seconds Timestamp", "当前秒级时间戳"), String(live.seconds))
                copyableRow(t("Milliseconds Timestamp", "当前毫秒时间戳"), String(live.milliseconds))
            }
        }
    }

    private var conversionWorkspace: some View {
        HStack(spacing: 12) {
            ToolCard(title: t("Timestamp -> Date", "时间戳 -> 日期")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField(t("Enter timestamp", "输入时间戳"), text: $timestampInput)
                            .textFieldStyle(.roundedBorder)
                        Picker(t("Unit", "单位"), selection: $timestampUnit) {
                            ForEach(TimestampInputUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 96)
                    }

                    HStack(spacing: 8) {
                        Button(t("Use current seconds", "填入当前秒级")) {
                            timestampInput = String(live.seconds)
                            timestampUnit = .seconds
                            convertTimestampInput()
                        }
                        .buttonStyle(.bordered)

                        Button(t("Use current milliseconds", "填入当前毫秒")) {
                            timestampInput = String(live.milliseconds)
                            timestampUnit = .milliseconds
                            convertTimestampInput()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            ToolCard(title: t("Date -> Timestamp", "日期 -> 时间戳")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(t("YYYY-MM-DD HH:mm:ss or ISO8601", "YYYY-MM-DD HH:mm:ss 或 ISO8601"), text: $dateInput)
                        .textFieldStyle(.roundedBorder)
                    Toggle(t("Interpret timezone-less date as UTC", "按 UTC 解释无时区日期"), isOn: $interpretAsUTC)
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 8) {
                        Button(t("Use current datetime", "填入当前时间")) {
                            dateInput = live.localDateTime
                            convertDateInput()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var resultCard: some View {
        ToolCard(title: t("Conversion Result", "转换结果")) {
            VStack(alignment: .leading, spacing: 8) {
                if let result = lastResult {
                    let sourceLabel = lastSource == .timestamp ? t("Timestamp Input", "时间戳输入") : t("Date Input", "日期输入")
                    resultInfoRow(t("Source", "来源"), sourceLabel)
                    resultInfoRow(t("Detected Unit", "识别单位"), result.inferredUnit)
                    copyableRow(t("Seconds Timestamp", "秒级时间戳"), String(result.seconds))
                    copyableRow(t("Milliseconds Timestamp", "毫秒时间戳"), String(result.milliseconds))
                    copyableRow(t("Local Time", "本地时间"), result.localTime)
                    copyableRow(t("UTC Time", "UTC 时间"), result.utcTime)
                    copyableRow("ISO8601(UTC)", result.iso8601UTC)
                } else {
                    Text(t("After input on either side, conversion results will appear here automatically", "在左侧或右侧输入后，这里会自动展示转换结果"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Button(t("Clear", "清空"), role: .destructive) {
                clearAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Spacer()

            StatusLine(text: status, isError: isError)
                .frame(maxWidth: 460, alignment: .trailing)
        }
    }

    private func convertTimestampInput() {
        let trimmed = timestampInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let result = try TimeService.timestampToDate(trimmed, inputUnit: timestampUnit)
            lastResult = result
            lastSource = .timestamp
            status = t("Timestamp converted", "时间戳已自动转换")
            isError = false
        } catch {
            status = "\(t("Timestamp parse failed", "时间戳解析失败")): \(error.localizedDescription)"
            isError = true
        }
    }

    private func convertDateInput() {
        let trimmed = dateInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let result = try TimeService.dateToTimestamp(trimmed, interpretAsUTC: interpretAsUTC)
            lastResult = result
            lastSource = .datetime
            status = t("Date converted", "日期已自动转换")
            isError = false
        } catch {
            status = "\(t("Date parse failed", "日期解析失败")): \(error.localizedDescription)"
            isError = true
        }
    }

    private func clearAll() {
        timestampInput = ""
        dateInput = ""
        interpretAsUTC = false
        timestampUnit = .auto
        lastResult = nil
        status = t("Cleared inputs and results", "已清空输入与结果")
        isError = false
    }

    @ViewBuilder
    private func copyableRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(t("Copy", "复制")) {
                copyToClipboard(value)
                status = "\(t("Copied", "已复制")) \(title)"
                isError = false
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
        }
    }

    @ViewBuilder
    private func resultInfoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        coordinator.localized(english, chinese)
    }
}
