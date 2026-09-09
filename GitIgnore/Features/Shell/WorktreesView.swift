import AppKit
import SwiftUI

struct WorktreesView: View {
    @Environment(AppState.self) private var appState
    @State private var isAdding = false
    @State private var path = ""
    @State private var branch = ""
    @State private var worktreeToDelete: GitWorktreeSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OrbitPageHeader(
                title: AppLanguage.text("并行工作区", "Worktrees"),
                subtitle: AppLanguage.text("在同一个仓库中并行检出多个工作目录。", "Check out multiple working directories from one repository."),
                systemName: "point.3.connected.trianglepath.dotted",
                tint: OrbitDesign.blue
            ) {
                Button { isAdding = true } label: {
                    Label(AppLanguage.text("添加工作区", "Add Worktree"), systemImage: "plus")
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.repository == nil)
            }

            if appState.worktrees.isEmpty {
                OrbitEmptyState(
                    title: AppLanguage.text("还没有并行工作区", "No Additional Worktrees"),
                    message: AppLanguage.text("为不同分支创建独立工作目录，同时处理多个任务。", "Create a separate working directory for each branch and task."),
                    systemName: "point.3.connected.trianglepath.dotted",
                    tint: OrbitDesign.blue
                ) {
                    Button(AppLanguage.text("添加第一个工作区", "Add First Worktree")) { isAdding = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.repository == nil)
                }
            } else if let mainWorktree = onlyMainWorktree {
                mainWorktreeState(mainWorktree)
            } else {
                List(appState.worktrees) { worktree in
                    let state = worktreeStatus(worktree)
                    HStack(spacing: 12) {
                        OrbitIconBadge(systemName: worktree.isMain ? "house" : "point.3.connected.trianglepath.dotted", color: worktree.isMain ? OrbitDesign.accent : OrbitDesign.blue, size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(worktree.branch ?? "游离状态").orbitFont(.subheadline, weight: .semibold)
                            Text(worktree.path).font(.caption2.monospaced()).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
                            if let state {
                                HStack(spacing: 7) {
                                    if state.isClean {
                                        Label("干净", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(OrbitDesign.accent)
                                    } else {
                                        Text("变更 \(state.changedCount)")
                                        if state.stagedCount > 0 { Text("Stage \(state.stagedCount)") }
                                        if state.conflictCount > 0 {
                                            Label("冲突 \(state.conflictCount)", systemImage: "exclamationmark.triangle.fill")
                                                .foregroundStyle(OrbitDesign.coral)
                                        }
                                    }
                                }
                                .orbitFont(.caption2, weight: .semibold)
                                .foregroundStyle(OrbitDesign.amber)
                            } else {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        Spacer()
                        Text(String(worktree.head.prefix(7))).font(.caption2.monospaced()).foregroundStyle(OrbitDesign.secondaryText)
                        if worktree.isMain { Text("主工作区").orbitFont(.caption2, weight: .semibold).foregroundStyle(OrbitDesign.accent) }
                        Menu {
                            Button("切换到此工作区", systemImage: "arrow.right.circle") {
                                Task { await appState.switchToWorktree(worktree) }
                            }
                            Button("在 Finder 中打开", systemImage: "folder") {
                                appState.openWorktree(worktree)
                            }
                            Button("在终端中打开", systemImage: "terminal") {
                                appState.openWorktreeInTerminal(worktree)
                            }
                            if !worktree.isMain {
                                Divider()
                                Button("删除工作区", systemImage: "trash", role: .destructive) {
                                    worktreeToDelete = worktree
                                }
                                .disabled(state?.isClean != true)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(OrbitDesign.secondaryText)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(.vertical, 5)
                    .help(state?.isClean == false ? "工作区存在未提交内容，清理后才能删除" : "")
                }
                .listStyle(.inset)
            }
        }
        .background(OrbitDesign.canvas)
        .navigationTitle("并行工作区")
        .orbitPageReveal()
        .task(id: appState.worktrees.map(\.id)) {
            await appState.loadWorktreeStates()
        }
        .alert("删除并行工作区？", isPresented: Binding(
            get: { worktreeToDelete != nil },
            set: { if !$0 { worktreeToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { worktreeToDelete = nil }
            Button("删除", role: .destructive) {
                guard let target = worktreeToDelete else { return }
                worktreeToDelete = nil
                Task { await appState.removeWorktree(target) }
            }
        } message: {
            Text("该工作区已确认干净：\(worktreeToDelete?.path ?? "")")
        }
        .sheet(isPresented: $isAdding) {
            VStack(alignment: .leading, spacing: 14) {
                Text("添加并行工作区").orbitFont(.title3, weight: .bold)
                HStack {
                    TextField("工作目录路径", text: $path).textFieldStyle(.roundedBorder)
                    Button("选择…") { choosePath() }
                }
                TextField("分支名称", text: $branch).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("取消") { isAdding = false }
                    Button("添加") {
                        isAdding = false
                        Task { await appState.addWorktree(path: path, branch: branch) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(22)
            .frame(width: 470)
        }
    }

    private func worktreeStatus(_ worktree: GitWorktreeSummary) -> GitWorktreeState? {
        appState.workflows.worktreeStates[worktree.path]
    }

    private var onlyMainWorktree: GitWorktreeSummary? {
        guard appState.worktrees.count == 1, let worktree = appState.worktrees.first, worktree.isMain else {
            return nil
        }
        return worktree
    }

    private func mainWorktreeState(_ worktree: GitWorktreeSummary) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                OrbitIconBadge(systemName: "house", color: OrbitDesign.accent, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(worktree.branch ?? AppLanguage.text("游离状态", "Detached HEAD"))
                            .orbitFont(.headline)
                        Text(AppLanguage.text("主工作区", "Main Worktree"))
                            .orbitFont(.caption2, weight: .semibold)
                            .foregroundStyle(OrbitDesign.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(OrbitDesign.accent.opacity(0.10), in: Capsule())
                    }
                    Text(worktree.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .textSelection(.enabled)
                    if let state = worktreeStatus(worktree) {
                        Text(state.isClean
                             ? AppLanguage.text("工作目录干净，可以安全创建并行工作区。", "The working directory is clean and ready for a parallel worktree.")
                             : AppLanguage.text("当前有 \(state.changedCount) 个变更；创建并行工作区不会移动这些内容。", "There are \(state.changedCount) changes; creating a worktree will not move them."))
                            .orbitFont(.caption)
                            .foregroundStyle(state.isClean ? OrbitDesign.accent : OrbitDesign.amber)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(AppLanguage.text("Finder", "Finder"), systemImage: "folder") {
                        appState.openWorktree(worktree)
                    }
                    Button(AppLanguage.text("终端", "Terminal"), systemImage: "terminal") {
                        appState.openWorktreeInTerminal(worktree)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider().overlay(OrbitDesign.separator)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLanguage.text("并行处理另一个任务", "Work on Another Task in Parallel"))
                    .orbitFont(.title3, weight: .semibold)
                Text(AppLanguage.text(
                    "为修复或功能分支创建独立目录，不影响当前工作区，也不需要来回 Stash。",
                    "Create a separate directory for a fix or feature branch without affecting this worktree or repeatedly using Stash."
                ))
                .orbitFont(.subheadline)
                .foregroundStyle(OrbitDesign.secondaryText)
                .frame(maxWidth: 560, alignment: .leading)

                Button { isAdding = true } label: {
                    Label(AppLanguage.text("添加并行工作区", "Add Parallel Worktree"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: 900, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}
