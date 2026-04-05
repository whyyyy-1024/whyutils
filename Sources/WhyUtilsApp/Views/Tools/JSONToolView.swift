import SwiftUI

struct JSONToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var status: String = "Type JSON in the left pane, then choose an action"
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActionButtonRow(actions: [
                .init(t("Validate", "合法性检查"), action: validate),
                .init(t("Format", "格式化"), action: format),
                .init(t("Minify", "压缩"), action: minify),
                .init(t("Escape as String", "转义为字符串"), action: escape),
                .init(t("Unescape String", "字符串反转义"), action: unescape),
                .init(t("Copy Output", "输出复制"), action: copyOutput),
                .init(t("Output to Input", "输出回填输入"), action: swapOutputToInput),
                .init(t("Clear", "清空"), role: .destructive, action: clearAll)
            ])

            EditorPairView(
                leftTitle: t("Input", "输入"),
                rightTitle: t("Output", "输出"),
                leftText: $inputText,
                rightText: $outputText
            )

            StatusLine(text: status, isError: isError)
        }
    }

    private func run(_ name: String, transform: (String) throws -> String) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = t("Please input content first", "请输入内容后再操作")
            isError = true
            return
        }

        do {
            let value = try transform(trimmed)
            outputText = value
            status = "\(name) \(t("succeeded", "成功"))"
            isError = false
        } catch {
            outputText = "\(t("Error", "错误")): \(error.localizedDescription)"
            status = "\(name) \(t("failed", "失败")): \(error.localizedDescription)"
            isError = true
        }
    }

    private func validate() {
        run(t("Validate", "合法性检查"), transform: JSONService.validate)
    }

    private func format() {
        run(t("Format", "格式化"), transform: JSONService.format)
    }

    private func minify() {
        run(t("Minify", "压缩"), transform: JSONService.minify)
    }

    private func escape() {
        run(t("Escape", "转义"), transform: JSONService.escapeJSONString)
    }

    private func unescape() {
        run(t("Unescape", "反转义"), transform: JSONService.unescapeJSONString)
    }

    private func copyOutput() {
        copyToClipboard(outputText)
        status = outputText.isEmpty ? t("Output is empty, not copied", "输出为空，未复制") : t("Output copied", "输出内容已复制")
        isError = outputText.isEmpty
    }

    private func swapOutputToInput() {
        inputText = outputText
        status = t("Output moved back to input", "已将输出内容放回输入框")
        isError = false
    }

    private func clearAll() {
        inputText = ""
        outputText = ""
        status = t("Cleared", "已清空")
        isError = false
    }

    private func t(_ english: String, _ chinese: String) -> String {
        coordinator.localized(english, chinese)
    }
}
