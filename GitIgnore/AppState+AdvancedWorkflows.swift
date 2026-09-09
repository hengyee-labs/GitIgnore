import AppKit
import Foundation

extension AppState {
    func loadIncomingPreview() async {
        guard let root = repositoryRootURL, !incomingCommits.isEmpty else {
            workflows.incomingPreview = [:]
            return
        }
        workflows.isLoadingPreview = true
        defer { workflows.isLoadingPreview = false }
        let commitsToLoad = Array(incomingCommits.prefix(30))
        let runner = gitRunner
        let missing = commitsToLoad.filter { workflows.incomingPreview[$0.id] == nil }
        var details: [String: GitCommitDetail] = [:]
        for start in stride(from: 0, to: missing.count, by: 4) {
            let batch = Array(missing[start..<min(start + 4, missing.count)])
            let loaded = await withTaskGroup(of: (String, GitCommitDetail?).self) { group in
                for commit in batch {
                    group.addTask {
                        (commit.id, try? await runner.commitDetail(hash: commit.hash, at: root))
                    }
                }
                var values: [String: GitCommitDetail] = [:]
                for await (id, detail) in group {
                    if let detail { values[id] = detail }
                }
                return values
            }
            details.merge(loaded) { _, new in new }
        }
        workflows.incomingPreview.merge(details) { _, new in new }
        if workflows.incomingPreview.count > 30 {
            let allowed = Set(commitsToLoad.map(\.id))
            workflows.incomingPreview = workflows.incomingPreview.filter { allowed.contains($0.key) }
        }
    }

    func loadStashPreview(_ stash: GitStashSummary) async {
        guard let root = repositoryRootURL else { return }
        stashPreviewGeneration &+= 1
        let loadGeneration = stashPreviewGeneration
        workflows.isLoadingPreview = true
        workflows.stashPreview = nil
        workflows.stashFileDiff = nil
        defer {
            if stashPreviewGeneration == loadGeneration {
                workflows.isLoadingPreview = false
            }
        }
        do {
            let preview = try await gitRunner.stashPreview(stash.reference, at: root)
            guard stashPreviewGeneration == loadGeneration else { return }
            workflows.stashPreview = preview
        } catch {
            guard stashPreviewGeneration == loadGeneration else { return }
            present(error: error, title: "无法预览 Stash")
        }
    }

    func loadStashFileDiff(_ file: GitCommitFileChange, in stash: GitStashSummary) async {
        guard let root = repositoryRootURL else { return }
        stashPreviewGeneration &+= 1
        let loadGeneration = stashPreviewGeneration
        workflows.isLoadingStashFileDiff = true
        workflows.stashFileDiff = nil
        defer {
            if stashPreviewGeneration == loadGeneration {
                workflows.isLoadingStashFileDiff = false
            }
        }
        do {
            let diff = try await gitRunner.stashFileDiff(stash.reference, path: file.path, at: root)
            guard stashPreviewGeneration == loadGeneration else { return }
            workflows.stashFileDiff = diff
        } catch is CancellationError {
            return
        } catch {
            guard stashPreviewGeneration == loadGeneration else { return }
            present(error: error, title: "无法读取 Stash 文件变更")
        }
    }

    func createPartialStash(message: String?, paths: [String]) async {
        guard let root = repositoryRootURL, !paths.isEmpty else { return }
        await performAction(
            successTitle: "所选文件已保存到 Stash",
            successMessage: "已临时保存 \(paths.count) 个文件，其余工作区内容保持不变。",
            kind: .stash,
            refreshScope: [.workingCopy, .stashes]
        ) {
            try await self.gitRunner.stashPush(message: message, paths: paths, at: root)
        }
    }

    func prepareInteractiveRebase(base: String) async {
        guard let root = repositoryRootURL else { return }
        let normalized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            presentMessage("请选择 Rebase 的基准分支。", title: "缺少基准分支")
            return
        }
        workflows.isLoadingPreview = true
        defer { workflows.isLoadingPreview = false }
        do {
            workflows.rebaseItems = try await gitRunner.rebaseTodo(base: normalized, at: root)
            workflows.rebaseBase = normalized
            workflows.rebasePlannerPresented = true
        } catch {
            present(error: error, title: "无法读取 Rebase 提交")
        }
    }

    func runInteractiveRebase() async -> Bool {
        guard let root = repositoryRootURL,
              !workflows.rebaseBase.isEmpty,
              !workflows.rebaseItems.isEmpty else { return false }
        let base = workflows.rebaseBase
        let items = workflows.rebaseItems
        return await performAction(
            successTitle: "交互式 Rebase 已完成",
            successMessage: "已按计划整理 \(items.count) 个提交。",
            kind: .rebase,
            warnOnConflicts: true,
            refreshScope: [.workingCopy, .history, .branches, .remote]
        ) {
            try await self.gitRunner.interactiveRebase(base: base, items: items, at: root)
        }
    }

    func compareBranches(base: String, target: String) async {
        guard let root = repositoryRootURL else { return }
        workflows.isLoadingPreview = true
        defer { workflows.isLoadingPreview = false }
        do {
            workflows.branchComparison = try await gitRunner.branchComparison(base: base, target: target, at: root)
        } catch {
            present(error: error, title: "无法比较分支")
        }
    }

    func analyzeMergedBranches() async {
        guard let root = repositoryRootURL, let current = branches.first(where: \.isCurrent)?.name else { return }
        workflows.isLoadingPreview = true
        defer { workflows.isLoadingPreview = false }
        do {
            let merged = try await gitRunner.mergedBranches(into: current, at: root)
            let protected = Set([current, "main", "master", "develop", "dev"])
            workflows.mergedBranchCandidates = merged.filter { !protected.contains($0) }
        } catch {
            present(error: error, title: "无法分析已合并分支")
        }
    }

    func deleteMergedBranch(_ name: String) async {
        guard let root = repositoryRootURL else { return }
        let succeeded = await performAction(
            successTitle: "已删除合并分支",
            successMessage: "本地分支 \(name) 已清理。",
            kind: .branch,
            refreshScope: .branches
        ) {
            try await self.gitRunner.deleteBranch(name, force: false, at: root)
        }
        if succeeded { workflows.mergedBranchCandidates.removeAll { $0 == name } }
    }

    func loadWorktreeStates() async {
        let runner = gitRunner
        let trees = worktrees
        var states: [String: GitWorktreeState] = [:]
        for start in stride(from: 0, to: trees.count, by: 4) {
            let batch = Array(trees[start..<min(start + 4, trees.count)])
            let loaded = await withTaskGroup(of: GitWorktreeState?.self) { group in
                for tree in batch {
                    group.addTask { try? await runner.worktreeState(path: tree.path) }
                }
                var values: [String: GitWorktreeState] = [:]
                for await state in group {
                    if let state { values[state.path] = state }
                }
                return values
            }
            states.merge(loaded) { _, new in new }
        }
        workflows.worktreeStates = states
    }

    func openWorktreeInTerminal(_ worktree: GitWorktreeSummary) {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: worktree.path, isDirectory: true)],
            withApplicationAt: terminalURL,
            configuration: configuration
        )
    }

    func switchToWorktree(_ worktree: GitWorktreeSummary) async {
        await openRepository(URL(fileURLWithPath: worktree.path, isDirectory: true), selectOverview: true)
    }
}
