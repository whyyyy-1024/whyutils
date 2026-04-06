import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct SessionRenameDraft: Identifiable {
    let id: UUID
    var title: String
}

struct AIAssistantToolView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @StateObject private var workspace: AIChatWorkspaceStore
    @State private var composerText: String = ""
    @State private var state: AIAgentExecutionState = .idle
    @State private var expandedTraceMessageIDs = Set<UUID>()
    @State private var activeStreamTask: Task<Void, Never>?
    @State private var renameDraft: SessionRenameDraft?
    @State private var deleteSession: AIChatSession?
    @State private var composerShouldFocus: Bool = true
    @State private var composerIsFocused: Bool = false
    @State private var pendingImageAttachment: AIChatImageAttachment?
    @State private var isImageDropTargeted: Bool = false

    init() {
        _workspace = StateObject(wrappedValue: AIChatWorkspaceStore())
    }

    private var aiConfigured: Bool {
        let config = coordinator.aiConfiguration
        return config.isEnabled
            && config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var accessMode: AIAgentAccessMode {
        coordinator.aiConfiguration.accessMode
    }

    private var activeSession: AIChatSession? {
        workspace.activeSession
    }

    private var activeMessages: [AIChatMessageRecord] {
        activeSession?.messages ?? []
    }

    private var isStreaming: Bool {
        activeStreamTask != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainPane
        }
        .background(Color.whyPanelBackground)
        .sheet(item: $renameDraft) { draft in
            renameSheet(for: draft)
        }
        .alert(item: $deleteSession) { session in
            Alert(
                title: Text(coordinator.localized("Delete conversation?", "删除会话？")),
                message: Text(session.displayTitle),
                primaryButton: .destructive(Text(coordinator.localized("Delete", "删除"))) {
                    workspace.deleteSession(id: session.id)
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            consumeDraftTaskIfNeeded(forceNewSession: false)
        }
        .onChange(of: coordinator.aiDraftTask) { _ in
            consumeDraftTaskIfNeeded(forceNewSession: true)
        }
        .onDisappear {
            activeStreamTask?.cancel()
            activeStreamTask = nil
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    workspace.createNewSession()
                    composerText = ""
                    composerShouldFocus = true
                } label: {
                    Label(coordinator.localized("New chat", "新建会话"), systemImage: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(workspace.sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 204)
        .background(Color.whySidebarBackground)
    }

    private var mainPane: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            ScrollViewReader { proxy in
                Group {
                    if activeMessages.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ForEach(activeMessages) { message in
                                    messageRow(message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 24)
                        }
                    }
                }
                .onChange(of: activeSession?.id) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: activeMessages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: activeMessages.last?.text) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
            composerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeSession?.displayTitle ?? coordinator.localized("New chat", "新建会话"))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Circle()
                        .fill(aiConfigured ? accessModeColor.opacity(0.9) : Color.orange.opacity(0.95))
                        .frame(width: 6, height: 6)

                    Text(topBarSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(aiConfigured ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 8) {
                Menu {
                    ForEach(AIAgentAccessMode.allCases) { mode in
                        Button {
                            coordinator.updateAIConfiguration(accessMode: mode)
                        } label: {
                            HStack {
                                Text(accessModeLabel(for: mode))
                                if mode == accessMode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button(coordinator.localized("AI Settings", "AI 设置")) {
                        coordinator.showSettings = true
                    }
                } label: {
                    toolbarChip(
                        text: accessModeLabel,
                        systemImage: "slider.horizontal.3",
                        tint: accessModeColor
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.85))
                    Text(coordinator.aiConfiguration.model.isEmpty ? "-" : coordinator.aiConfiguration.model)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.whyControlBackground.opacity(0.42))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.whyPanelBorder.opacity(0.72), lineWidth: 1)
                )
                .frame(maxWidth: 190)

                if let session = activeSession {
                    Menu {
                        Button(coordinator.localized("AI Settings", "AI 设置")) {
                            coordinator.showSettings = true
                        }
                        Divider()
                        Button(coordinator.localized("Rename", "重命名")) {
                            renameDraft = SessionRenameDraft(id: session.id, title: session.title.isEmpty ? session.displayTitle : session.title)
                        }
                        Button(coordinator.localized("Delete", "删除"), role: .destructive) {
                            deleteSession = session
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.whyControlBackground.opacity(0.42))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.whyPanelBorder.opacity(0.72), lineWidth: 1)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.whyChromeBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.whyPanelBorder.opacity(0.75))
                .frame(height: 1)
        }
    }

    private func toolbarChip(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint.opacity(0.95))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.whyControlBackground.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.whyPanelBorder.opacity(0.72), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.teal)
            Text(coordinator.localized("How can I help?", "我可以帮你做什么？"))
                .font(.system(size: 28, weight: .semibold))
            Text(coordinator.localized(
                "Talk naturally. I can chat, call WhyUtils tools, and in higher access modes run local actions for you.",
                "直接自然地说需求。我可以聊天、调用 WhyUtils 工具，并在更高权限模式下执行本地动作。"
            ))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let pendingImageAttachment {
                pendingImageStrip(pendingImageAttachment)
            }

            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack(alignment: .leading) {
                        if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && composerIsFocused == false {
                            Text(coordinator.localized("Message WhyUtils AI", "给 WhyUtils AI 发消息"))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary.opacity(0.75))
                                .padding(.leading, 8)
                                .allowsHitTesting(false)
                        }

                        ChatInputEditor(
                            text: $composerText,
                            focusRequest: $composerShouldFocus,
                            isFocused: $composerIsFocused,
                            onPasteImage: { attachment in
                                attachImage(attachment)
                            },
                            onSubmit: {
                                if isStreaming {
                                    stopGenerating()
                                } else {
                                    submitTask()
                                }
                            }
                        )
                        .frame(height: 36)
                    }

                    Button {
                        if isStreaming {
                            stopGenerating()
                        } else {
                            submitTask()
                        }
                    } label: {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background((isStreaming ? Color.red : Color.teal), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming == false
                        && composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && pendingImageAttachment == nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.whyControlBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke((isImageDropTargeted ? Color.teal.opacity(0.9) : Color.whyPanelBorder.opacity(0.72)), lineWidth: 1)
                )
                .onDrop(
                    of: [UTType.fileURL.identifier, UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier],
                    isTargeted: $isImageDropTargeted,
                    perform: handleDroppedImageProviders
                )
            }

            if aiConfigured == false {
                Label(coordinator.localized("AI settings incomplete", "AI 设置未完成"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.whyChromeBackground)
    }

    private func pendingImageStrip(_ attachment: AIChatImageAttachment) -> some View {
        HStack(spacing: 10) {
            imageThumbnail(for: attachment, maxHeight: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName ?? coordinator.localized("Image attachment", "图片附件"))
                    .font(.system(size: 12, weight: .semibold))
                Text("\(attachment.width)×\(attachment.height)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                pendingImageAttachment = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.whyControlBackground, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.whyControlBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sessionRow(_ session: AIChatSession) -> some View {
        let isSelected = session.id == activeSession?.id
        return Button {
            workspace.selectSession(id: session.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(formattedTimestamp(session.updatedAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.whyControlBackground.opacity(0.78))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(Color.teal.opacity(0.95))
                                    .frame(width: 3)
                                    .padding(.vertical, 8)
                                    .padding(.leading, 6)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(coordinator.localized("Rename", "重命名")) {
                renameDraft = SessionRenameDraft(id: session.id, title: session.title.isEmpty ? session.displayTitle : session.title)
            }
            Button(coordinator.localized("Delete", "删除"), role: .destructive) {
                deleteSession = session
            }
        }
    }

    private func messageRow(_ message: AIChatMessageRecord) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 180) }

            VStack(alignment: .leading, spacing: 10) {
                if message.role == .assistant {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.teal)
                        Text("WhyUtils AI")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        if message.isStreaming {
                            Text(coordinator.localized("Generating", "生成中"))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.teal.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Text(message.text.isEmpty && message.isStreaming
                     ? coordinator.localized("Thinking...", "正在思考...")
                     : message.text)
                    .font(.system(size: 15, weight: message.role == .user ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: message.role == .user ? 440 : 720, alignment: .leading)

                if message.imageAttachments.isEmpty == false {
                    imageAttachmentGallery(message.imageAttachments)
                }

                if let confirmation = message.confirmationRequest {
                    confirmationCard(confirmation, messageID: message.id)
                }

                if message.toolTraces.isEmpty == false {
                    toolTraceSection(message)
                }
            }
            .padding(message.role == .user ? 12 : 0)
            .background(messageBubbleBackground(for: message.role))
            .frame(maxWidth: message.role == .user ? 476 : 760, alignment: .leading)

            if message.role != .user { Spacer(minLength: 180) }
        }
    }

    private func toolTraceSection(_ message: AIChatMessageRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleTraceExpansion(for: message.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandedTraceMessageIDs.contains(message.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(coordinator.localized("Tool calls", "工具调用"))
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(message.toolTraces.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if expandedTraceMessageIDs.contains(message.id) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(message.toolTraces) { trace in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(trace.toolName, systemImage: "hammer")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Spacer()
                            }
                            if trace.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                               trace.argumentsJSON != "{}" {
                                Text(trace.argumentsJSON)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Text(trace.output)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .background(Color.whyCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.whyPanelBorder.opacity(0.7), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func imageAttachmentGallery(_ attachments: [AIChatImageAttachment]) -> some View {
        HStack(spacing: 10) {
            ForEach(attachments) { attachment in
                imageThumbnail(for: attachment, maxHeight: 180)
            }
        }
    }

    private func imageThumbnail(for attachment: AIChatImageAttachment, maxHeight: CGFloat) -> some View {
        Group {
            if let image = NSImage(data: attachment.pngData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.whyControlBackground)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(maxHeight: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.whyPanelBorder.opacity(0.7), lineWidth: 1)
        )
    }

    private func confirmationCard(_ request: AIConfirmationRequest, messageID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                coordinator.localized(
                    "This action needs confirmation before it runs.",
                    "这个动作需要你确认后才会执行。"
                ),
                systemImage: "shield.lefthalf.filled.badge.checkmark"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.orange)

            Text(request.summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(coordinator.localized("Confirm", "确认")) {
                    confirmPendingPlan(for: messageID, request: request)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Button(coordinator.localized("Cancel", "取消"), role: .destructive) {
                    cancelPendingPlan(for: messageID)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private func renameSheet(for draft: SessionRenameDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(coordinator.localized("Rename conversation", "重命名会话"))
                .font(.system(size: 18, weight: .semibold))

            TextField(coordinator.localized("Conversation title", "会话标题"), text: Binding(
                get: { renameDraft?.title ?? draft.title },
                set: { renameDraft = SessionRenameDraft(id: draft.id, title: $0) }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(coordinator.localized("Cancel", "取消")) {
                    renameDraft = nil
                }
                Button(coordinator.localized("Save", "保存")) {
                    guard let renameDraft else { return }
                    workspace.renameSession(id: renameDraft.id, title: renameDraft.title)
                    self.renameDraft = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func submitTask() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingImageAttachment.map { [$0] } ?? []
        guard trimmed.isEmpty == false || attachments.isEmpty == false else { return }
        guard isStreaming == false else { return }

        guard aiConfigured else {
            let sessionID = activeSession?.id ?? createSessionIfNeeded()
            _ = workspace.appendMessage(role: .user, text: trimmed, imageAttachments: attachments, sessionID: sessionID)
            workspace.appendMessage(
                role: .assistant,
                text: coordinator.localized(
                    "Please finish AI configuration in Settings before sending messages.",
                    "请先在设置里完成 AI 配置，再发送消息。"
                ),
                sessionID: sessionID
            )
            composerText = ""
            return
        }

        let sessionID = activeSession?.id ?? createSessionIfNeeded()
        let task = trimmed.isEmpty
            ? coordinator.localized("Please analyze the attached image.", "请分析这张附带的图片。")
            : trimmed
        let configuration = coordinator.aiConfiguration
        let context = buildContext()

        composerText = ""
        pendingImageAttachment = nil
        state = .planning

        _ = workspace.appendMessage(role: .user, text: task, imageAttachments: attachments, sessionID: sessionID)
        let history = buildConversationHistory(sessionID: sessionID)
        let assistantMessageID = workspace.appendMessage(role: .assistant, text: "", isStreaming: true, sessionID: sessionID)
        let service = AIAgentService.live(configuration: configuration)

        let taskHandle = Task {
            do {
                let result = try await service.submit(
                    task: task,
                    configuration: configuration,
                    context: context,
                    conversation: history
                )
                await MainActor.run {
                    coordinator.aiDraftTask = ""
                }

                switch result {
                case .awaitingConfirmation(let request):
                    await streamAssistantText(
                        coordinator.localized(
                            "I have a plan and need your confirmation before running the side-effect action.",
                            "我已经生成执行方案，但其中包含副作用动作，需要你确认后我再继续。"
                        ),
                        into: assistantMessageID,
                        sessionID: sessionID
                    )
                    await MainActor.run {
                        workspace.updateMessage(
                            sessionID: sessionID,
                            messageID: assistantMessageID,
                            confirmationRequest: .some(request),
                            isStreaming: false
                        )
                        state = .awaitingConfirmation
                        activeStreamTask = nil
                    }
                case .completed(let run):
                    if run.traces.isEmpty == false {
                        await MainActor.run {
                            workspace.updateMessage(
                                sessionID: sessionID,
                                messageID: assistantMessageID,
                                toolTraces: run.traces
                            )
                        }
                        await streamAssistantResponse(
                            from: service.streamRunSummary(
                                task: task,
                                run: run,
                                configuration: configuration,
                                conversation: history
                            ),
                            fallback: run.finalMessage,
                            into: assistantMessageID,
                            sessionID: sessionID
                        )
                    } else {
                        await streamAssistantResponse(
                            from: service.streamDirectReply(
                                task: task,
                                configuration: configuration,
                                context: context,
                                conversation: history
                            ),
                            fallback: run.finalMessage,
                            into: assistantMessageID,
                            sessionID: sessionID
                        )
                    }
                    await MainActor.run {
                        state = .completed
                        activeStreamTask = nil
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    workspace.updateMessage(sessionID: sessionID, messageID: assistantMessageID, isStreaming: false)
                    state = .idle
                    activeStreamTask = nil
                }
            } catch {
                await MainActor.run {
                    workspace.updateMessage(
                        sessionID: sessionID,
                        messageID: assistantMessageID,
                        text: error.localizedDescription,
                        isStreaming: false
                    )
                    state = .failed(message: error.localizedDescription)
                    activeStreamTask = nil
                }
            }
        }

        activeStreamTask = taskHandle
    }

    private func confirmPendingPlan(for messageID: UUID, request: AIConfirmationRequest) {
        guard let sessionID = activeSession?.id else { return }
        let configuration = coordinator.aiConfiguration
        let service = AIAgentService.live(configuration: configuration)
        let history = buildConversationHistory(sessionID: sessionID)

        state = .executing
        let taskHandle = Task {
            do {
                let run = try await service.confirm(request, configuration: configuration)
                await MainActor.run {
                    workspace.removeConfirmation(sessionID: sessionID, messageID: messageID)
                    workspace.updateMessage(sessionID: sessionID, messageID: messageID, toolTraces: run.traces, isStreaming: true)
                }
                await streamAssistantResponse(
                    from: service.streamRunSummary(
                        task: request.plan.goal,
                        run: run,
                        configuration: configuration,
                        conversation: history
                    ),
                    fallback: run.finalMessage,
                    into: messageID,
                    sessionID: sessionID
                )
                await MainActor.run {
                    state = .completed
                    activeStreamTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    workspace.updateMessage(sessionID: sessionID, messageID: messageID, isStreaming: false)
                    state = .idle
                    activeStreamTask = nil
                }
            } catch {
                await MainActor.run {
                    workspace.updateMessage(
                        sessionID: sessionID,
                        messageID: messageID,
                        text: error.localizedDescription,
                        isStreaming: false
                    )
                    state = .failed(message: error.localizedDescription)
                    activeStreamTask = nil
                }
            }
        }

        activeStreamTask = taskHandle
    }

    private func cancelPendingPlan(for messageID: UUID) {
        guard let sessionID = activeSession?.id else { return }
        workspace.removeConfirmation(sessionID: sessionID, messageID: messageID)
        workspace.updateMessage(
            sessionID: sessionID,
            messageID: messageID,
            text: coordinator.localized("Execution canceled.", "已取消执行。"),
            isStreaming: false
        )
        state = .idle
    }

    private func stopGenerating() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        state = .idle
    }

    private func consumeDraftTaskIfNeeded(forceNewSession: Bool) {
        let draft = coordinator.aiDraftTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isEmpty == false else { return }
        if forceNewSession || (activeSession?.messages.isEmpty == false) || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            workspace.createNewSession()
        }
        composerText = draft
        pendingImageAttachment = nil
        composerShouldFocus = true
        coordinator.aiDraftTask = ""
    }

    private func buildContext() -> AIAgentContext {
        let textEntries = coordinator.clipboardHistory.entries
            .filter { $0.kind == .text }
            .map(\.text)
            .map(AIToolExecutor.redactSensitiveText)

        return AIAgentContext(
            latestClipboardText: textEntries.first,
            recentClipboardTexts: Array(textEntries.prefix(5)),
            pasteTargetAppName: coordinator.pasteTargetAppName
        )
    }

    private func buildConversationHistory(sessionID: UUID) -> [OpenAIChatMessage] {
        workspace.sessions
            .first(where: { $0.id == sessionID })?
            .messages
            .compactMap { message in
                guard message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || message.imageAttachments.isEmpty == false else {
                    return nil
                }
                return message.openAIMessage
            } ?? []
    }

    private func attachImage(_ attachment: AIChatImageAttachment) {
        pendingImageAttachment = attachment
        composerShouldFocus = true
    }

    private func handleDroppedImageProviders(_ providers: [NSItemProvider]) -> Bool {
        guard isStreaming == false else { return false }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            loadImageAttachment(fromFileProvider: provider)
            return true
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.png.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.tiff.identifier)
        }) {
            loadImageAttachment(fromImageProvider: provider)
            return true
        }

        return false
    }

    private func loadImageAttachment(fromFileProvider provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil),
                let attachment = AIChatImageAttachmentLoader.imageAttachment(fromFileURL: url)
            else { return }

            Task { @MainActor in
                attachImage(attachment)
            }
        }
    }

    private func loadImageAttachment(fromImageProvider provider: NSItemProvider) {
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            typeIdentifier = UTType.png.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
            typeIdentifier = UTType.jpeg.identifier
        } else {
            typeIdentifier = UTType.tiff.identifier
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data, let attachment = AIChatImageAttachmentLoader.imageAttachment(fromImageData: data, fileName: nil) else { return }
            Task { @MainActor in
                attachImage(attachment)
            }
        }
    }

    private func streamAssistantText(_ text: String, into messageID: UUID, sessionID: UUID) async {
        await MainActor.run {
            workspace.updateMessage(sessionID: sessionID, messageID: messageID, text: "", isStreaming: true)
        }

        var collected = ""
        for character in text {
            if Task.isCancelled { break }
            collected.append(character)
            await MainActor.run {
                workspace.updateMessage(sessionID: sessionID, messageID: messageID, text: collected, isStreaming: true)
            }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }

        await MainActor.run {
            workspace.updateMessage(sessionID: sessionID, messageID: messageID, text: collected, isStreaming: false)
        }
    }

    private func streamAssistantResponse(
        from stream: AsyncThrowingStream<String, Error>,
        fallback: String,
        into messageID: UUID,
        sessionID: UUID
    ) async {
        await MainActor.run {
            workspace.updateMessage(sessionID: sessionID, messageID: messageID, text: "", isStreaming: true)
        }

        var collected = ""
        do {
            for try await chunk in stream {
                if Task.isCancelled { throw CancellationError() }
                collected += chunk
                await MainActor.run {
                    workspace.updateMessage(sessionID: sessionID, messageID: messageID, text: collected, isStreaming: true)
                }
            }

            await MainActor.run {
                workspace.updateMessage(
                    sessionID: sessionID,
                    messageID: messageID,
                    text: collected.isEmpty ? fallback : collected,
                    isStreaming: false
                )
            }
        } catch is CancellationError {
            await MainActor.run {
                workspace.updateMessage(sessionID: sessionID, messageID: messageID, isStreaming: false)
            }
        } catch {
            await MainActor.run {
                workspace.updateMessage(
                    sessionID: sessionID,
                    messageID: messageID,
                    text: collected.isEmpty ? fallback : collected,
                    isStreaming: false
                )
            }
        }
    }

    private func createSessionIfNeeded() -> UUID {
        if let active = activeSession?.id { return active }
        workspace.createNewSession()
        return workspace.activeSession?.id ?? UUID()
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = activeMessages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func toggleTraceExpansion(for messageID: UUID) {
        if expandedTraceMessageIDs.contains(messageID) {
            expandedTraceMessageIDs.remove(messageID)
        } else {
            expandedTraceMessageIDs.insert(messageID)
        }
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }

    private var topBarSubtitle: String {
        if aiConfigured == false {
            return coordinator.localized("Finish Base URL, API Key, and Model in Settings", "请先在设置中完成 Base URL、API Key 和 Model")
        }
        switch state {
        case .planning:
            return coordinator.localized("Planning and responding", "正在规划并回复")
        case .awaitingConfirmation:
            return coordinator.localized("Waiting for confirmation", "等待确认")
        case .executing:
            return coordinator.localized("Executing local tools", "正在执行本地工具")
        case .failed(let message):
            return message
        case .idle, .completed:
            return coordinator.localized("Chat naturally or let the agent use local tools when needed", "直接聊天即可，需要时 agent 会调用本地工具")
        }
    }

    private var accessModeLabel: String {
        accessModeLabel(for: accessMode)
    }

    private func accessModeLabel(for mode: AIAgentAccessMode) -> String {
        switch mode {
        case .standard:
            return coordinator.localized("Standard", "标准")
        case .fullAccess:
            return "Full Access"
        case .unrestricted:
            return coordinator.localized("Unrestricted", "无限制")
        }
    }

    private var accessModeColor: Color {
        switch accessMode {
        case .standard:
            return .teal
        case .fullAccess:
            return .orange
        case .unrestricted:
            return .red
        }
    }

    @ViewBuilder
    private func messageBubbleBackground(for role: AIChatMessageRole) -> some View {
        switch role {
        case .user:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.teal.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.teal.opacity(0.10), lineWidth: 1)
                )
        case .assistant, .system:
            Color.clear
        }
    }

}

private struct ChatInputEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusRequest: Bool
    @Binding var isFocused: Bool
    let onPasteImage: (AIChatImageAttachment) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onPasteImage: onPasteImage, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.string = text
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        if focusRequest, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                focusRequest = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        let onPasteImage: (AIChatImageAttachment) -> Void
        let onSubmit: () -> Void
        weak var textView: SubmitAwareTextView?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onPasteImage: @escaping (AIChatImageAttachment) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.onPasteImage = onPasteImage
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onPasteImage: ((AIChatImageAttachment) -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && modifiers.contains(.shift) == false {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if let attachment = AIChatImageAttachmentLoader.imageAttachment(from: NSPasteboard.general) {
            onPasteImage?(attachment)
            return
        }
        super.paste(sender)
    }
}

private enum AIChatImageAttachmentLoader {
    static func imageAttachment(fromFileURL url: URL) -> AIChatImageAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return imageAttachment(fromImageData: data, fileName: url.lastPathComponent)
    }

    static func imageAttachment(fromImageData data: Data, fileName: String?) -> AIChatImageAttachment? {
        guard let image = NSImage(data: data) else { return nil }
        return imageAttachment(from: image, fileName: fileName)
    }

    static func imageAttachment(from pasteboard: NSPasteboard) -> AIChatImageAttachment? {
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        return imageAttachment(from: image, fileName: nil)
    }

    private static func imageAttachment(from image: NSImage, fileName: String?) -> AIChatImageAttachment? {
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return AIChatImageAttachment(
            pngData: pngData,
            width: rep.pixelsWide,
            height: rep.pixelsHigh,
            fileName: fileName
        )
    }
}
