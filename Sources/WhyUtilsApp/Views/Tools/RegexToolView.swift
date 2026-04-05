import SwiftUI

struct RegexToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var pattern: String = ""
    @State private var replacement: String = ""
    @State private var inputText: String = ""
    @State private var outputText: String = ""

    @State private var ignoreCase: Bool = false
    @State private var multiLine: Bool = false
    @State private var dotMatches: Bool = false

    @State private var status: String = "Enter regex pattern and test text"
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField(t("Pattern", "模式"), text: $pattern)
                    .textFieldStyle(.roundedBorder)
                TextField(t("Replacement", "替换文本"), text: $replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 18) {
                Toggle(t("i Ignore Case", "i 忽略大小写"), isOn: $ignoreCase)
                Toggle(t("m Multiline", "m 多行"), isOn: $multiLine)
                Toggle(t("s Dot Matches Newline", "s 点号匹配换行"), isOn: $dotMatches)
            }
            .font(.system(size: 12, weight: .semibold))

            ActionButtonRow(actions: [
                .init(t("Find All", "查找全部"), action: findAll),
                .init(t("Replace Preview", "替换预览"), action: replacePreview),
                .init(t("Copy Output", "输出复制"), action: copyOutput),
                .init(t("Clear", "清空"), role: .destructive, action: clearAll)
            ])

            EditorPairView(
                leftTitle: t("Test Text", "测试文本"),
                rightTitle: t("Result", "结果"),
                leftText: $inputText,
                rightText: $outputText
            )

            StatusLine(text: status, isError: isError)
        }
    }

    private func findAll() {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            status = t("Please enter Pattern", "请输入 Pattern")
            isError = true
            return
        }

        do {
            let matches = try RegexService.findMatches(
                pattern: p,
                text: inputText,
                ignoreCase: ignoreCase,
                multiLine: multiLine,
                dotMatchesNewLine: dotMatches
            )

            var lines: [String] = ["\(t("Match count", "匹配数量")): \(matches.count)"]
            for item in matches {
                lines.append("[\(item.index)] span=(\(item.range.location), \(item.range.location + item.range.length)) text=\(item.text)")
                if !item.groups.isEmpty {
                    lines.append("groups=\(item.groups)")
                }
            }
            outputText = lines.joined(separator: "\n")
            status = t("Find finished", "查找完成")
            isError = false
        } catch {
            outputText = "\(t("Error", "错误")): \(error.localizedDescription)"
            status = "\(t("Execution failed", "执行失败")): \(error.localizedDescription)"
            isError = true
        }
    }

    private func replacePreview() {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            status = t("Please enter Pattern", "请输入 Pattern")
            isError = true
            return
        }

        do {
            outputText = try RegexService.replace(
                pattern: p,
                replacement: replacement,
                text: inputText,
                ignoreCase: ignoreCase,
                multiLine: multiLine,
                dotMatchesNewLine: dotMatches
            )
            status = t("Replace preview finished", "替换预览完成")
            isError = false
        } catch {
            outputText = "\(t("Error", "错误")): \(error.localizedDescription)"
            status = "\(t("Replace failed", "替换失败")): \(error.localizedDescription)"
            isError = true
        }
    }

    private func copyOutput() {
        copyToClipboard(outputText)
        status = outputText.isEmpty ? t("Output is empty, not copied", "输出为空，未复制") : t("Output copied", "输出内容已复制")
        isError = outputText.isEmpty
    }

    private func clearAll() {
        pattern = ""
        replacement = ""
        inputText = ""
        outputText = ""
        status = t("Cleared", "已清空")
        isError = false
    }

    private func t(_ english: String, _ chinese: String) -> String {
        coordinator.localized(english, chinese)
    }
}
