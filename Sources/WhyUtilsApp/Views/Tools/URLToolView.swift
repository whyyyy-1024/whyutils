import SwiftUI

struct URLToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var safeChars: String = ""
    @State private var status: String = "Enter text and choose URL encode/decode"
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Keep chars unescaped (safe)", "编码保留字符 (safe)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(t("e.g. /:?=&", "例如 /:?=&"), text: $safeChars)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }

            ActionButtonRow(actions: [
                .init(t("URL Encode", "URL 编码"), action: encode),
                .init(t("URL Decode", "URL 解码"), action: decode),
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

    private func encode() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = t("Please enter text to encode", "请输入待编码文本")
            isError = true
            return
        }
        outputText = EncodingService.urlEncode(trimmed, safe: safeChars)
        status = t("URL encode succeeded", "URL 编码成功")
        isError = false
    }

    private func decode() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = t("Please enter text to decode", "请输入待解码文本")
            isError = true
            return
        }
        outputText = EncodingService.urlDecode(trimmed)
        status = t("URL decode succeeded", "URL 解码成功")
        isError = false
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
