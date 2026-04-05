import SwiftUI

struct Base64ToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var urlSafe: Bool = false
    @State private var stripPadding: Bool = false
    @State private var status: String = "Input text then encode/decode Base64"
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Toggle("URL Safe", isOn: $urlSafe)
                Toggle(t("Strip trailing =", "编码去掉 ="), isOn: $stripPadding)
            }
            .font(.system(size: 12, weight: .semibold))

            ActionButtonRow(actions: [
                .init(t("Encode", "编码"), action: encode),
                .init(t("Decode", "解码"), action: decode),
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

        outputText = EncodingService.base64Encode(trimmed, urlSafe: urlSafe, stripPadding: stripPadding)
        status = t("Base64 encode succeeded", "Base64 编码成功")
        isError = false
    }

    private func decode() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = t("Please enter text to decode", "请输入待解码文本")
            isError = true
            return
        }

        do {
            outputText = try EncodingService.base64Decode(trimmed, urlSafe: urlSafe)
            status = t("Base64 decode succeeded", "Base64 解码成功")
            isError = false
        } catch {
            outputText = "\(t("Error", "错误")): \(error.localizedDescription)"
            status = "\(t("Decode failed", "解码失败")): \(error.localizedDescription)"
            isError = true
        }
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
