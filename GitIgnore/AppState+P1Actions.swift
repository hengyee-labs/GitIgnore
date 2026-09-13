import AppKit
import Foundation

extension AppState {
    func fetchPrune() async { await fetch() }

    func cherryPick(_ commit: GitCommitSummary) async {
        await prepareSafeOperation(
            kind: .cherryPick,
            target: commit.hash,
            targetTitle: "\(commit.shortHash) · \(commit.subject)"
        )
    }

    func revertCommit(_ commit: GitCommitSummary) async {
        guard let root = repositoryRootURL else { return }
        await performAction(successTitle: "反向提交已创建", successMessage: "已通过新提交撤销 \(commit.shortHash) 的改动。", warnOnConflicts: true, refreshScope: [.workingCopy, .history, .remote]) {
            try await self.gitRunner.revert(commit.hash, at: root)
        }
    }

    func createBranch(name: String, at commit: GitCommitSummary) async {
        guard let root = repositoryRootURL, let name = normalizedGitName(name, title: "分支名称不能为空") else { return }
        await performAction(successMessage: "已从 \(commit.shortHash) 创建分支 \(name)", refreshScope: .branches) {
            try await self.gitRunner.createBranch(name, at: commit.hash, repositoryURL: root)
        }
    }

    func createTag(name: String, at commit: GitCommitSummary) async {
        guard let root = repositoryRootURL, let name = normalizedGitName(name, title: "标签名称不能为空") else { return }
        await performAction(successMessage: "已在 \(commit.shortHash) 创建标签 \(name)", refreshScope: .history) {
            try await self.gitRunner.createTag(name, at: commit.hash, repositoryURL: root)
        }
    }

    func pushTag(_ name: String) async {
        guard let root = repositoryRootURL else { return }
        await performAction(successMessage: "标签 (name) 已推送", refreshScope: .remote) {
            try await self.gitRunner.pushTag(name, at: root)
        }
    }

    func merge(_ branch: GitBranchSummary) async {
        guard !branch.isCurrent else { return }
        await prepareSafeOperation(kind: .merge, target: branch.name)
    }

    func rebase(onto branch: GitBranchSummary) async {
        guard !branch.isCurrent else { return }
        await prepareSafeOperation(kind: .rebase, target: branch.name)
    }

    func deleteBranch(_ branch: GitBranchSummary, force: Bool) async {
        guard !branch.isCurrent else { return }
        await prepareSafeOperation(kind: .deleteBranch, target: branch.name, force: force)
    }

    func renameBranch(_ branch: GitBranchSummary, to newName: String) async {
        guard let root = repositoryRootURL, let name = normalizedGitName(newName, title: "分支名称不能为空") else { return }
        await performAction(successMessage: "分支已重命名为 \(name)", refreshScope: [.branches, .remote]) {
            try await self.gitRunner.renameBranch(branch.name, to: name, at: root)
        }
    }

    func setUpstream(for branch: GitBranchSummary, to upstream: String) async {
        guard let root = repositoryRootURL, let name = normalizedGitName(upstream, title: "请输入远程分支") else { return }
        await performAction(successMessage: "\(branch.name) 已跟踪 \(name)", refreshScope: [.branches, .remote]) {
            try await self.gitRunner.setUpstream(branch: branch.name, upstream: name, at: root)
        }
    }

    func copyHash(_ commit: GitCommitSummary) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.hash, forType: .string)
        feedback = AppFeedback(kind: .success, title: "完整哈希已复制", message: commit.hash)
    }

    func showParentComparison(_ commit: GitCommitSummary) async {
        guard let detail = selectedCommitDetail, let firstFile = detail.files.first else {
            presentMessage("这条提交没有可显示的文件差异。", title: "没有父提交对比")
            return
        }
        await selectCommitFile(firstFile, in: commit)
        feedback = AppFeedback(kind: .success, title: "正在显示父提交对比", message: "已打开 \(firstFile.path) 的提交差异。")
    }

    func branchSwitchRecoveryRequest(for error: Error) -> SafeBranchSwitchRequest? {
        guard case let GitRunnerError.commandFailed(arguments, message, _) = error,
              let repository,
              let switchIndex = arguments.firstIndex(of: "switch"),
              !arguments.contains("-c"),
              !arguments.contains("--create") else { return nil }

        let normalizedMessage = message.lowercased()
        guard normalizedMessage.contains("would be overwritten by checkout")
                || normalizedMessage.contains("would be overwritten by switch") else { return nil }

        let switchArguments = arguments.suffix(from: arguments.index(after: switchIndex))
        guard let targetReference = switchArguments.last(where: { !$0.hasPrefix("-") }) else { return nil }

        let isRemote = switchArguments.contains("--track")
        let remote: String?
        let targetBranch: String
        if isRemote, let separator = targetReference.firstIndex(of: "/") {
            remote = String(targetReference[..<separator])
            targetBranch = String(targetReference[targetReference.index(after: separator)...])
        } else {
            remote = nil
            targetBranch = targetReference
        }

        return SafeBranchSwitchRequest(
            repositoryPath: repository.path,
            currentBranch: repository.branch,
            targetBranch: targetBranch,
            remote: remote,
            changedFileCount: status.changedFileCount,
            stagedFileCount: status.stagedFileCount,
            untrackedFileCount: status.files.filter { $0.kind == .untracked }.count
        )
    }

    func performSafeBranchSwitch(
        _ request: SafeBranchSwitchRequest,
        strategy: SafeBranchSwitchStrategy
    ) async -> Bool {
        guard let repository,
              repository.path == request.repositoryPath else {
            presentMessage("当前仓库已经发生变化，请重新选择目标分支。", title: "无法继续安全切换")
            return false
        }

        let root = URL(fileURLWithPath: request.repositoryPath, isDirectory: true)
        let stashMessage = "GitIgnore · 切换到 \(request.targetDisplayName) 前的本地修改"
        let recordID = beginGitOperation(
            kind: .branch,
            title: "安全切换分支",
            repositoryPath: request.repositoryPath
        )
        var protection: SafePullProtection?
        var branchSwitched = false
        workflows.isPerformingSafeBranchSwitch = true
        defer { workflows.isPerformingSafeBranchSwitch = false }
        errorMessage = nil
        feedback = nil
        await gitOperationQueue.acquire(repositoryPath: request.repositoryPath)
        activateGitOperation(recordID)

        do {
            updateGitOperation(recordID, phase: .running, detail: "正在保护本地修改")
            protection = try await gitRunner.createSafePullProtection(
                message: stashMessage,
                at: root
            )

            updateGitOperation(recordID, phase: .running, detail: "正在切换到 \(request.targetDisplayName)")
            if let remote = request.remote {
                try await gitRunner.checkoutRemote(remote: remote, branch: request.targetBranch, at: root)
            } else {
                try await gitRunner.checkout(branch: request.targetBranch, at: root)
            }
            branchSwitched = true

            let detail: String
            switch strategy {
            case .restore:
                updateGitOperation(recordID, phase: .running, detail: "正在还原本地修改")
                let restoreResult = try await gitRunner.restoreSafePullProtection(protection!, at: root)
                detail = await handleSafeBranchSwitchRestore(
                    restoreResult,
                    targetDisplayName: request.targetDisplayName
                )

            case .keepInStash:
                updateGitOperation(recordID, phase: .refreshing, detail: "正在刷新仓库状态")
                await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
                detail = "已切换到 \(request.targetDisplayName)，本地修改保存在 Stash 中。"
                actionMessage = detail
                feedback = AppFeedback(kind: .success, title: "分支已安全切换", message: detail)

            case .discard:
                updateGitOperation(recordID, phase: .running, detail: "正在丢弃已确认的本地修改")
                try await gitRunner.discardSafePullProtection(protection!, at: root)
                updateGitOperation(recordID, phase: .refreshing, detail: "正在刷新仓库状态")
                await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
                detail = "已切换到 \(request.targetDisplayName)，并丢弃原本的本地修改。"
                actionMessage = detail
                feedback = AppFeedback(kind: .success, title: "分支已切换", message: detail)
            }

            cancelPendingLiveRefresh()
            finishGitOperation(recordID, succeeded: true, detail: detail)
            await gitOperationQueue.release(repositoryPath: request.repositoryPath)
            return true
        } catch {
            await refresh(scope: [.workingCopy, .branches, .remote, .stashes])
            let technicalDetails = (error as? GitRunnerError)?.technicalDetails ?? error.localizedDescription
            let detail: String
            if branchSwitched {
                detail = "已切换到 \(request.targetDisplayName)，但后续处理未完成；保护用 Stash 仍然保留。"
                actionMessage = detail
                feedback = AppFeedback(
                    kind: .warning,
                    title: strategy == .discard ? "已切换，修改未被丢弃" : "已切换，自动还原未完成",
                    message: detail,
                    technicalDetails: technicalDetails
                )
                finishGitOperation(recordID, succeeded: true, detail: detail)
                await gitOperationQueue.release(repositoryPath: request.repositoryPath)
                return true
            }

            if protection != nil {
                detail = "目标分支未切换，本地修改已安全保存在 Stash 中。"
                actionMessage = detail
                feedback = AppFeedback(
                    kind: .failure,
                    title: "分支未切换，修改已保护",
                    message: detail,
                    technicalDetails: technicalDetails
                )
            } else {
                detail = "无法保护当前本地修改，未执行分支切换。"
                present(error: error, title: "安全切换无法开始")
            }
            finishGitOperation(recordID, succeeded: false, detail: technicalDetails)
            await gitOperationQueue.release(repositoryPath: request.repositoryPath)
            return false
        }
    }

    private func handleSafeBranchSwitchRestore(
        _ result: SafePullStashRestoreResult,
        targetDisplayName: String
    ) async -> String {
        await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
        switch result {
        case .restored:
            let detail = "已切换到 \(targetDisplayName)，本地修改和暂存状态已恢复。"
            actionMessage = detail
            feedback = AppFeedback(kind: .success, title: "分支已安全切换", message: detail)
            return detail

        case let .restoredWithProtection(technicalDetails):
            let detail = "已切换到 \(targetDisplayName) 并恢复修改；原暂存边界需要检查，保护用 Stash 已保留。"
            actionMessage = detail
            feedback = AppFeedback(
                kind: .warning,
                title: "修改已恢复，暂存状态需要检查",
                message: detail,
                technicalDetails: technicalDetails
            )
            return detail

        case let .conflicts(files, technicalDetails):
            let detail = "已切换到 \(targetDisplayName)，但恢复修改时产生冲突；保护用 Stash 已保留。"
            actionMessage = detail
            feedback = AppFeedback(
                kind: .warning,
                title: "分支已切换，需要解决冲突",
                message: "保护用 Stash 已保留，正在打开第一个冲突文件。",
                technicalDetails: technicalDetails
            )
            let firstConflict = status.files.first { candidate in
                candidate.hasConflict && files.contains { $0.path == candidate.path }
            } ?? status.files.first(where: \.hasConflict) ?? files.first
            if let firstConflict {
                await openConflictEditor(for: firstConflict)
            } else {
                selectedSection = .changes
            }
            return detail

        case let .failed(technicalDetails):
            let detail = "已切换到 \(targetDisplayName)，但自动还原未完成；请从 Stash 临时保存中手动恢复。"
            actionMessage = detail
            feedback = AppFeedback(
                kind: .warning,
                title: "分支已切换，修改需要手动恢复",
                message: detail,
                technicalDetails: technicalDetails
            )
            return detail
        }
    }

    private func normalizedGitName(_ value: String, title: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            presentMessage("请输入有效名称。", title: title)
            return nil
        }
        return normalized
    }
}
