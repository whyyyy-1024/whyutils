import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct ThreadRenameDraft: Identifiable {
    let id: UUID
    var title: String
}

private struct ChatRenameDraft: Identifiable {
    let threadID: UUID
    let id: UUID
    var title: String
}

private struct DeleteChatDraft: Identifiable {
    let threadID: UUID
    let chat: AIChatSession
    var id: UUID { chat.id }
}

struct AIThreadListView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var workspace: AIChatWorkspaceStore
    @State private var expandedThreads: Set<UUID> = []
    @State private var threadBranches: [UUID: String] = [:]
    @State private var showDirectoryPicker = false
    @State private var renameThreadDraft: ThreadRenameDraft?
    @State private var renameChatDraft: ChatRenameDraft?
    @State private var deleteThread: AIThread?
    @State private var deleteChatDraft: DeleteChatDraft?
    @State private var showDeleteThreadAlert = false
    @State private var showDeleteChatAlert = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(workspace.threads) { thread in
                        threadSection(thread)
                    }
                }
                .padding(10)
            }
            Divider()
            newThreadButton
        }
        .background(Color.whySidebarBackground)
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectoryImport(result)
        }
        .sheet(item: $renameThreadDraft) { draft in
            threadRenameSheet(for: draft)
        }
        .sheet(item: $renameChatDraft) { draft in
            chatRenameSheet(for: draft)
        }
        .alert(isPresented: $showDeleteThreadAlert) {
            Alert(
                title: Text(coordinator.localized("Delete thread?", "删除 Thread？")),
                message: Text(deleteThread?.displayName ?? ""),
                primaryButton: .destructive(Text(coordinator.localized("Delete", "删除"))) {
                    if let thread = deleteThread {
                        workspace.deleteThread(id: thread.id)
                    }
                    deleteThread = nil
                },
                secondaryButton: .cancel {
                    deleteThread = nil
                }
            )
        }
        .alert(isPresented: $showDeleteChatAlert) {
            Alert(
                title: Text(coordinator.localized("Delete chat?", "删除 Chat？")),
                message: Text(deleteChatDraft?.chat.displayTitle ?? ""),
                primaryButton: .destructive(Text(coordinator.localized("Delete", "删除"))) {
                    if let item = deleteChatDraft {
                        workspace.deleteChat(threadID: item.threadID, chatID: item.chat.id)
                    }
                    deleteChatDraft = nil
                },
                secondaryButton: .cancel {
                    deleteChatDraft = nil
                }
            )
        }
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "folder.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(coordinator.localized("Threads", "Threads"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.whyChromeBackground)
    }

    private func threadSection(_ thread: AIThread) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            threadRow(thread)
            if expandedThreads.contains(thread.id) {
                chatRows(thread)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.whyControlBackground.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.whyPanelBorder.opacity(0.72), lineWidth: 1)
        )
    }

    private func threadRow(_ thread: AIThread) -> some View {
        let isSelected = thread.id == workspace.activeThreadID
        let isExpanded = expandedThreads.contains(thread.id)
        let branch = threadBranches[thread.id]
        
        return Button {
            if isExpanded {
                expandedThreads.remove(thread.id)
            } else {
                expandedThreads.insert(thread.id)
            }
            workspace.selectThread(id: thread.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                
                Text(thread.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let branch {
                    Text(branch)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.85), in: Capsule())
                }
                
                Spacer()
                
                Text(formattedTimestamp(thread.updatedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.whyControlBackground.opacity(0.78) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(coordinator.localized("Rename", "重命名")) {
                renameThreadDraft = ThreadRenameDraft(
                    id: thread.id,
                    title: thread.title.isEmpty ? thread.displayName : thread.title
                )
            }
            Button(coordinator.localized("Delete", "删除"), role: .destructive) {
                deleteThread = thread
                showDeleteThreadAlert = true
            }
        }
        .task(id: thread.id) {
            if expandedThreads.contains(thread.id), threadBranches[thread.id] == nil {
                if let branch = await GitService.detectBranch(directory: thread.workingDirectory) {
                    threadBranches[thread.id] = branch
                }
            }
        }
    }

    private func chatRows(_ thread: AIThread) -> some View {
        ForEach(thread.chats) { chat in
            chatRow(thread: thread, chat: chat)
        }
    }

    private func chatRow(thread: AIThread, chat: AIChatSession) -> some View {
        let isSelected = chat.id == workspace.activeChatID
        
        return Button {
            workspace.selectChat(threadID: thread.id, chatID: chat.id)
        } label: {
            HStack(spacing: 8) {
                Text(chat.displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if chat.fileChangeSummary.hasChanges {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .medium))
                        Text(chat.fileChangeSummary.summaryText)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.whyControlBackground.opacity(0.52), in: Capsule())
                }
                
                Spacer()
                
                Text(formattedTimestamp(chat.updatedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.teal.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(coordinator.localized("Rename", "重命名")) {
                renameChatDraft = ChatRenameDraft(
                    threadID: thread.id,
                    id: chat.id,
                    title: chat.title.isEmpty ? chat.displayTitle : chat.title
                )
            }
            Button(coordinator.localized("Delete", "删除"), role: .destructive) {
                deleteChatDraft = DeleteChatDraft(threadID: thread.id, chat: chat)
                showDeleteChatAlert = true
            }
        }
    }

    private func newChatButton(_ threadID: UUID) -> some View {
        Button {
            workspace.createNewChat(in: threadID)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(coordinator.localized("New Chat", "新建 Chat"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.teal)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newThreadButton: some View {
        Button {
            showDirectoryPicker = true
        } label: {
            Label(coordinator.localized("New Thread", "新建 Thread"), systemImage: "folder.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.whyControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func handleDirectoryImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let directory = url.path
            workspace.createNewThread(directory: directory)
        case .failure:
            break
        }
    }

    private func threadRenameSheet(for draft: ThreadRenameDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(coordinator.localized("Rename thread", "重命名 Thread"))
                .font(.system(size: 18, weight: .semibold))
            
            TextField(coordinator.localized("Thread title", "Thread 标题"), text: Binding(
                get: { renameThreadDraft?.title ?? draft.title },
                set: { renameThreadDraft = ThreadRenameDraft(id: draft.id, title: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            
            HStack {
                Spacer()
                Button(coordinator.localized("Cancel", "取消")) {
                    renameThreadDraft = nil
                }
                Button(coordinator.localized("Save", "保存")) {
                    guard let renameThreadDraft else { return }
                    workspace.renameThread(id: renameThreadDraft.id, title: renameThreadDraft.title)
                    self.renameThreadDraft = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func chatRenameSheet(for draft: ChatRenameDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(coordinator.localized("Rename chat", "重命名 Chat"))
                .font(.system(size: 18, weight: .semibold))
            
            TextField(coordinator.localized("Chat title", "Chat 标题"), text: Binding(
                get: { renameChatDraft?.title ?? draft.title },
                set: { renameChatDraft = ChatRenameDraft(threadID: draft.threadID, id: draft.id, title: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            
            HStack {
                Spacer()
                Button(coordinator.localized("Cancel", "取消")) {
                    renameChatDraft = nil
                }
                Button(coordinator.localized("Save", "保存")) {
                    guard let renameChatDraft else { return }
                    workspace.renameChat(threadID: renameChatDraft.threadID, chatID: renameChatDraft.id, title: renameChatDraft.title)
                    self.renameChatDraft = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return coordinator.localized("Yesterday", "昨天")
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }
}