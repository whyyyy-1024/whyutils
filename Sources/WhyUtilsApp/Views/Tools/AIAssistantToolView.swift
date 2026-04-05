import SwiftUI

struct AIAssistantToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var taskText: String = ""
    @State private var state: AIAgentExecutionState = .idle
    @State private var pendingConfirmation: AIConfirmationRequest?
    @State private var lastRun: AIAgentRunResult?
    @State private var lastPlan: AIExecutionPlan?
    @State private var status: String = "Describe a task and the assistant will plan with existing WhyUtils tools."
    @State private var isError: Bool = false

    private let service = AIAgentService.live

    private var aiConfigured: Bool {
        let config = coordinator.aiConfiguration
        return config.isEnabled
            && config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            configurationCard
            promptCard
            if let pendingConfirmation {
                confirmationCard(request: pendingConfirmation)
            }
            if let plan = lastPlan {
                planCard(plan: plan)
            }
            if let run = lastRun {
                tracesCard(run: run)
            }
            StatusLine(text: status, isError: isError)
        }
        .onAppear {
            if taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               coordinator.aiDraftTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                taskText = coordinator.aiDraftTask
            }
        }
    }

    private var configurationCard: some View {
        ToolCard(title: coordinator.localized("Assistant Status", "助手状态")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: aiConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(aiConfigured ? .teal : .orange)
                    Text(aiConfigured
                         ? coordinator.localized("AI is configured and ready", "AI 已配置完成，可直接使用")
                         : coordinator.localized("Configure Base URL, API Key, and Model in Settings first", "请先在设置中填写 Base URL、API Key 和 Model"))
                        .font(.system(size: 13, weight: .medium))
                }

                Text("Base URL: \(coordinator.aiConfiguration.baseURL.isEmpty ? "-" : coordinator.aiConfiguration.baseURL)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Model: \(coordinator.aiConfiguration.model.isEmpty ? "-" : coordinator.aiConfiguration.model)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var promptCard: some View {
        ToolCard(title: coordinator.localized("Task", "任务")) {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $taskText)
                    .font(.system(size: 13, weight: .regular))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.whyPanelBorder, lineWidth: 1)
                    )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        samplePromptButton("Format the latest clipboard JSON")
                        samplePromptButton("Summarize the latest clipboard text in 3 bullets")
                        samplePromptButton("Open Bluetooth settings")
                        samplePromptButton("Decode the latest clipboard URL")
                    }
                }

                ActionButtonRow(actions: [
                    .init(coordinator.localized("Run Plan", "执行计划"), action: submitTask),
                    .init(coordinator.localized("Use Clipboard", "使用最新剪贴板"), action: loadLatestClipboard),
                    .init(coordinator.localized("Clear", "清空"), role: .destructive, action: clearAll)
                ])
            }
        }
    }

    private func confirmationCard(request: AIConfirmationRequest) -> some View {
        ToolCard(title: coordinator.localized("Confirmation Required", "需要确认")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(coordinator.localized(
                    "The plan includes side-effect actions. Confirm before execution.",
                    "计划中包含副作用动作，确认后才会执行。"
                ))
                .font(.system(size: 13, weight: .medium))

                Text(request.summary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                ActionButtonRow(actions: [
                    .init(coordinator.localized("Confirm and Run", "确认并执行"), action: confirmPendingPlan),
                    .init(coordinator.localized("Cancel", "取消"), role: .destructive, action: cancelPendingPlan)
                ])
            }
        }
    }

    private func planCard(plan: AIExecutionPlan) -> some View {
        ToolCard(title: coordinator.localized("Plan", "计划")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(plan.goal)
                    .font(.system(size: 14, weight: .semibold))

                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(step.toolName)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                if step.requiresConfirmation {
                                    Text(coordinator.localized("confirm", "需确认"))
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.18), in: Capsule())
                                }
                            }
                            Text(step.argumentsJSON)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func tracesCard(run: AIAgentRunResult) -> some View {
        ToolCard(title: coordinator.localized("Result", "结果")) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(run.traces) { trace in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trace.toolName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text(trace.output)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack {
                    Text(run.finalMessage)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button(coordinator.localized("Copy Final Result", "复制最终结果")) {
                        copyToClipboard(run.finalMessage)
                        status = coordinator.localized("Final result copied", "最终结果已复制")
                        isError = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func samplePromptButton(_ text: String) -> some View {
        Button(text) {
            taskText = text
        }
        .buttonStyle(.bordered)
    }

    private func submitTask() {
        let trimmed = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            status = coordinator.localized("Please enter a task first", "请先输入任务")
            isError = true
            state = .failed(message: status)
            return
        }
        guard aiConfigured else {
            status = coordinator.localized("AI settings are incomplete", "AI 设置尚未完成")
            isError = true
            state = .failed(message: status)
            return
        }

        state = .planning
        pendingConfirmation = nil
        lastRun = nil
        lastPlan = nil
        status = coordinator.localized("Planning with AI...", "正在用 AI 规划...")
        isError = false

        let task = trimmed
        let configuration = coordinator.aiConfiguration
        let context = buildContext()
        Task {
            do {
                let result = try await service.submit(
                    task: task,
                    configuration: configuration,
                    context: context
                )
                await MainActor.run {
                    coordinator.aiDraftTask = task
                    switch result {
                    case .awaitingConfirmation(let request):
                        pendingConfirmation = request
                        lastPlan = request.plan
                        state = .awaitingConfirmation
                        status = coordinator.localized("Plan needs confirmation before execution", "计划需要确认后才能执行")
                    case .completed(let run):
                        lastRun = run
                        lastPlan = run.plan
                        state = .completed
                        status = coordinator.localized("Plan executed successfully", "计划执行完成")
                    }
                }
            } catch {
                await MainActor.run {
                    state = .failed(message: error.localizedDescription)
                    status = error.localizedDescription
                    isError = true
                }
            }
        }
    }

    private func confirmPendingPlan() {
        guard let pendingConfirmation else { return }
        state = .executing
        status = coordinator.localized("Executing confirmed plan...", "正在执行已确认计划...")
        isError = false

        Task {
            do {
                let run = try await service.confirm(pendingConfirmation)
                await MainActor.run {
                    self.pendingConfirmation = nil
                    lastRun = run
                    lastPlan = run.plan
                    state = .completed
                    status = coordinator.localized("Plan executed successfully", "计划执行完成")
                }
            } catch {
                await MainActor.run {
                    state = .failed(message: error.localizedDescription)
                    status = error.localizedDescription
                    isError = true
                }
            }
        }
    }

    private func cancelPendingPlan() {
        pendingConfirmation = nil
        state = .idle
        status = coordinator.localized("Pending plan canceled", "已取消待执行计划")
        isError = false
    }

    private func loadLatestClipboard() {
        if let text = coordinator.clipboardHistory.entries.first(where: { $0.kind == .text })?.text,
           text.isEmpty == false {
            taskText = text
            status = coordinator.localized("Loaded latest clipboard text into the task box", "已将最新剪贴板文本载入任务框")
            isError = false
        } else {
            status = coordinator.localized("Latest clipboard text is empty", "最新剪贴板文本为空")
            isError = true
        }
    }

    private func clearAll() {
        taskText = ""
        pendingConfirmation = nil
        lastRun = nil
        lastPlan = nil
        state = .idle
        status = coordinator.localized("Cleared", "已清空")
        isError = false
    }

    private func buildContext() -> AIAgentContext {
        let textEntries = coordinator.clipboardHistory.entries
            .filter { $0.kind == .text }
            .map(\.text)
        return AIAgentContext(
            latestClipboardText: textEntries.first,
            recentClipboardTexts: Array(textEntries.prefix(5)),
            pasteTargetAppName: coordinator.pasteTargetAppName
        )
    }
}
