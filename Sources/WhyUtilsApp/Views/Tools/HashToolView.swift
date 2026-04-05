import SwiftUI

struct HashToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var algorithm: HashAlgorithm = .sha256
    @State private var status: String = "Enter text to generate hash"
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(t("Algorithm", "算法"), selection: $algorithm) {
                ForEach(HashAlgorithm.allCases) { algo in
                    Text(algo.rawValue).tag(algo)
                }
            }
            .pickerStyle(.segmented)

            ActionButtonRow(actions: [
                .init(t("Generate Hash", "计算哈希"), action: hash),
                .init(t("Copy Output", "输出复制"), action: copyOutput),
                .init(t("Clear", "清空"), role: .destructive, action: clearAll)
            ])

            EditorPairView(
                leftTitle: t("Input Text", "输入文本"),
                rightTitle: t("Hash Output", "哈希输出"),
                leftText: $inputText,
                rightText: $outputText
            )

            StatusLine(text: status, isError: isError)
        }
    }

    private func hash() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = t("Please enter text to hash", "请输入待计算文本")
            isError = true
            return
        }

        outputText = HashService.digest(trimmed, algorithm: algorithm)
        status = "\(t("Hash generated", "哈希计算成功")) (\(algorithm.rawValue))"
        isError = false
    }

    private func copyOutput() {
        copyToClipboard(outputText)
        status = outputText.isEmpty ? t("Output is empty, not copied", "输出为空，未复制") : t("Output copied", "输出内容已复制")
        isError = outputText.isEmpty
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
