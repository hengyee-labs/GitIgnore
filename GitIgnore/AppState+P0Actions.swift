import Foundation

extension AppState {
    func pull() async {
        guard let root = repositoryRootURL, !isPerformingGitAction else { return }
        do {
            let liveStatus = try await gitRunner.status(at: root)
            status = liveStatus
            if let conflict = liveStatus.files.first(where: \.hasConflict) {
                await openConflictEditor(for: conflict)
                feedback = AppFeedback(
                    kind: .warning,
                    title: AppLanguage.isEnglish ? "Resolve conflicts before Pull" : "请先解决现有冲突",
                    message: AppLanguage.isEnglish
                        ? "The first conflicted file is open in the three-way editor."
                        : "已为你打开第一个冲突文件的三栏编辑器。"
                )
                return
            }
            safePullRequest = SafePullRequest(
                changedFileCount: liveStatus.changedFileCount,
                stagedFileCount: liveStatus.stagedFileCount,
                untrackedFileCount: liveStatus.files.filter { $0.kind == .untracked }.count,
                incomingCommitCount: repository?.behindCount ?? incomingCommits.count
            )
        } catch {
            present(error: error, title: AppLanguage.isEnglish ? "Unable to inspect workspace" : "无法检查工作区状态")
        }
    }

    func performSafePull() async {
        guard let request = safePullRequest, let root = repositoryRootURL, !isPerformingGitAction else { return }
        let previousCommitIDs = Set(commits.map(\.id))
        if request.changedFileCount == 0 {
            safePullRequest = nil
            await performCleanPull(at: root, previousCommitIDs: previousCommitIDs)
            return
        }
        var protection: SafePullProtection?
        var pullCompleted = false
        var completed = false
        let recordID = beginGitOperation(kind: .pull, title: "安全 Pull", repositoryPath: root.path)
        await gitOperationQueue.acquire(repositoryPath: root.path)
        activateGitOperation(recordID)
        errorMessage = nil
        feedback = nil
        defer {
            safePullPhase = nil
            finishGitOperation(
                recordID,
                succeeded: completed,
                detail: completed ? "远程提交与本地修改已完成整合。" : feedback?.technicalDetails ?? feedback?.message
            )
            Task { await gitOperationQueue.release(repositoryPath: root.path) }
        }

        do {
            safePullPhase = .protecting
            updateGitOperation(recordID, phase: .running, detail: "正在保护本地修改")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            protection = try await gitRunner.createSafePullProtection(
                message: "GitIgnore 安全拉取 · \(formatter.string(from: Date()))",
                at: root
            )

            safePullPhase = .pulling
            updateGitOperation(recordID, phase: .running, detail: "正在拉取远程提交")
            try await gitRunner.pull(at: root)
            pullCompleted = true

            safePullPhase = .restoring
            updateGitOperation(recordID, phase: .refreshing, detail: "正在恢复本地修改")
            let restoreResult = try await gitRunner.restoreSafePullProtection(protection!, at: root)
            await handleSafePullRestore(
                restoreResult,
                pullSucceeded: true,
                pullError: nil,
                previousCommitIDs: previousCommitIDs
            )
            completed = status.files.allSatisfy { !$0.hasConflict }
        } catch {
            guard let protection else {
                safePullRequest = nil
                present(error: error, title: AppLanguage.isEnglish ? "Safe Pull could not start" : "安全拉取无法开始")
                return
            }

            if pullCompleted {
                safePullRequest = nil
                await refresh(scope: [.workingCopy, .stashes, .remote])
                feedback = AppFeedback(
                    kind: .failure,
                    title: AppLanguage.isEnglish ? "Local protection needs manual restore" : "本地保护需要手动恢复",
                    message: AppLanguage.isEnglish
                        ? "Pull completed, but automatic restore stopped. The protected Stash remains available."
                        : "Pull 已完成，但自动恢复没有完成；保护用 Stash 仍然保留，可在检查工作区后手动恢复。",
                    technicalDetails: (error as? GitRunnerError)?.technicalDetails ?? error.localizedDescription
                )
                return
            }

            safePullPhase = .restoring
            do {
                let restoreResult = try await gitRunner.restoreSafePullProtection(protection, at: root)
                await handleSafePullRestore(
                    restoreResult,
                    pullSucceeded: false,
                    pullError: error,
                    previousCommitIDs: previousCommitIDs
                )
            } catch let restoreError {
                safePullRequest = nil
                await refresh(scope: [.workingCopy, .stashes, .remote])
                feedback = AppFeedback(
                    kind: .failure,
                    title: AppLanguage.isEnglish ? "Pull failed; local protection remains" : "Pull 未完成，本地保护仍保留",
                    message: AppLanguage.isEnglish
                        ? "GitIgnore kept the protected Stash. Restore it manually from Stash after checking the workspace."
                        : "GitIgnore 没有删除保护用 Stash。请检查工作区后，从 Stash 临时保存中手动恢复。",
                    technicalDetails: safePullDiagnostics(pullError: error, restoreDetails: restoreError.localizedDescription)
                )
            }
        }
    }

    func cancelSafePull() {
        guard safePullPhase == nil else { return }
        safePullRequest = nil
    }

    func reviewChangesBeforePull() {
        guard safePullPhase == nil else { return }
        safePullRequest = nil
        selectedSection = .changes
    }

    private func performCleanPull(at root: URL, previousCommitIDs: Set<String>) async {
        safePullPhase = .pulling
        let succeeded = await performAction(
            successTitle: "Pull 已完成",
            successMessage: "远程提交已经合入当前分支。",
            kind: .pull,
            refreshScope: []
        ) {
            try await self.gitRunner.pull(at: root)
        }
        safePullPhase = nil
        if succeeded {
            await finishSuccessfulPull(previousCommitIDs: previousCommitIDs)
        }
    }

    private func handleSafePullRestore(
        _ result: SafePullStashRestoreResult,
        pullSucceeded: Bool,
        pullError: Error?,
        previousCommitIDs: Set<String>
    ) async {
        switch result {
        case .restored:
            safePullRequest = nil
            if pullSucceeded {
                await finishSuccessfulPull(previousCommitIDs: previousCommitIDs)
            } else if let pullError {
                await refresh(scope: [.workingCopy, .stashes, .remote])
                present(error: pullError, title: AppLanguage.isEnglish ? "Pull failed; local changes restored" : "Pull 未完成，本地修改已恢复")
            }

        case let .restoredWithProtection(technicalDetails):
            safePullRequest = nil
            await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
            feedback = AppFeedback(
                kind: .warning,
                title: AppLanguage.isEnglish ? "Local changes restored; Stash retained" : "本地修改已恢复，Stash 已保留",
                message: pullSucceeded
                    ? (AppLanguage.isEnglish
                       ? "The remote update was applied, but the original staged boundaries could not be restored safely. Review the workspace before committing."
                       : "远程更新已拉取，但原暂存边界无法安全还原；请在提交前检查工作区，保护用 Stash 暂不删除。")
                    : (AppLanguage.isEnglish
                       ? "Pull failed. Local content was restored, but the original staged boundaries need review; the protected Stash remains."
                       : "Pull 未完成；本地内容已恢复，但原暂存边界需要检查，保护用 Stash 仍然保留。"),
                technicalDetails: safePullDiagnostics(pullError: pullError, restoreDetails: technicalDetails)
            )

        case let .conflicts(files, technicalDetails):
            safePullRequest = nil
            await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
            let firstConflict = status.files.first { candidate in
                candidate.hasConflict && files.contains { $0.path == candidate.path }
            } ?? status.files.first(where: \.hasConflict) ?? files[0]
            feedback = AppFeedback(
                kind: .warning,
                title: AppLanguage.isEnglish ? "Local changes need conflict resolution" : "恢复本地修改时发现冲突",
                message: AppLanguage.isEnglish
                    ? "The protected Stash is retained. The first conflicted file is opening in the three-way editor."
                    : "保护用 Stash 已保留，正在用三栏编辑器打开第一个冲突文件。",
                technicalDetails: safePullDiagnostics(pullError: pullError, restoreDetails: technicalDetails)
            )
            await openConflictEditor(for: firstConflict)

        case let .failed(technicalDetails):
            safePullRequest = nil
            await refresh(scope: [.workingCopy, .stashes, .remote])
            feedback = AppFeedback(
                kind: .failure,
                title: AppLanguage.isEnglish ? "Local protection needs manual restore" : "本地保护需要手动恢复",
                message: AppLanguage.isEnglish
                    ? "The protected Stash was not removed. Check the workspace, then restore it from Stash."
                    : "保护用 Stash 没有被删除。请检查工作区后，从 Stash 临时保存中恢复。",
                technicalDetails: safePullDiagnostics(pullError: pullError, restoreDetails: technicalDetails)
            )
        }
    }

    private func finishSuccessfulPull(previousCommitIDs: Set<String>) async {
        await refresh(scope: [.workingCopy, .history, .branches, .remote, .stashes])
        cancelPendingLiveRefresh()
        let newCommits = commits.filter { !previousCommitIDs.contains($0.id) }
        recentlyAddedCommitIDs = Set(newCommits.map(\.id))
        if newCommits.isEmpty {
            historyUpdateMessage = AppLanguage.isEnglish ? "History is up to date" : "本地提交历史已是最新"
            feedback = AppFeedback(
                kind: .success,
                title: AppLanguage.isEnglish ? "Already up to date" : "已经是最新版本",
                message: AppLanguage.isEnglish ? "There are no new remote commits to Pull." : "远程仓库没有需要拉取的新提交。"
            )
        } else {
            historyUpdateMessage = AppLanguage.isEnglish ? "Synced \(newCommits.count) commits" : "已同步 \(newCommits.count) 个新提交"
            feedback = AppFeedback(
                kind: .success,
                title: AppLanguage.isEnglish ? "Remote updates synced" : "已同步远程更新",
                message: AppLanguage.isEnglish
                    ? "Added \(newCommits.count) commits and refreshed History."
                    : "新增 \(newCommits.count) 个提交，提交历史已自动更新。"
            )
        }
    }

    func openConflictEditor(for file: GitFileStatus) async {
        selectedSection = .changes
        selectedFile = file
        selectedFileDiff = nil
        await Task.yield()
        presentedConflictFile = file
    }

    private func safePullDiagnostics(pullError: Error?, restoreDetails: String) -> String {
        let pullDetails = pullError.map { error in
            (error as? GitRunnerError)?.technicalDetails ?? error.localizedDescription
        }
        return [pullDetails, restoreDetails]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func stageHunk(_ hunk: GitPatchHunk) async {
        guard let root = repositoryRootURL else { return }
        await performAction(successTitle: "区块已加入暂存区", successMessage: "只暂存了所选区块。", refreshScope: .workingCopy) {
            try await self.gitRunner.applyPatch(hunk.patchText, operation: .stage, at: root)
        }
    }

    func unstageHunk(_ hunk: GitPatchHunk) async {
        guard let root = repositoryRootURL else { return }
        await performAction(successTitle: "区块已移出暂存区", successMessage: "所选区块已回到工作区。", refreshScope: .workingCopy) {
            try await self.gitRunner.applyPatch(hunk.patchText, operation: .unstage, at: root)
        }
    }

    func discardHunk(_ hunk: GitPatchHunk) async {
        guard let root = repositoryRootURL else { return }
        await performAction(successTitle: "区块修改已丢弃", successMessage: "所选区块已从工作区移除。", refreshScope: .workingCopy) {
            try await self.gitRunner.applyPatch(hunk.patchText, operation: .discard, at: root)
        }
    }

    func discardFile(_ file: GitFileStatus) async {
        guard let root = repositoryRootURL else { return }
        if file.kind == .untracked {
            let fileURL = root.appendingPathComponent(file.path)
            await performAction(successTitle: "文件已移到废纸篓", successMessage: "未跟踪文件可以从 macOS 废纸篓恢复。", refreshScope: .workingCopy) {
                try await Task.detached(priority: .userInitiated) {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: &resultingURL)
                }.value
            }
            return
        }
        await performAction(successTitle: "文件修改已丢弃", successMessage: "文件已恢复到最近提交的内容。", refreshScope: .workingCopy) {
            try await self.gitRunner.discardFile(file.path, at: root)
        }
    }

    func commit(message: String, amend: Bool, signOff: Bool) async {
        guard let root = repositoryRootURL else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentMessage("请先填写提交摘要。", title: "提交信息不完整")
            return
        }
        let succeeded = await performAction(
            successTitle: amend ? "最近提交已更新" : "提交已创建",
            successMessage: amend ? "新的内容和说明已合并到最近提交。" : "暂存内容已经写入本地提交历史。",
            refreshScope: [.workingCopy, .history, .remote]
        ) {
            try await self.gitRunner.commit(message: trimmed, amend: amend, signOff: signOff, at: root)
        }
        if succeeded { rememberCommitMessage(trimmed) }
    }

    func undoLastCommit() async {
        guard let root = repositoryRootURL else { return }
        await performAction(
            successTitle: "最近提交已撤销",
            successMessage: "提交内容仍保留在暂存区，可继续修改后重新提交。",
            refreshScope: [.workingCopy, .history, .remote]
        ) {
            try await self.gitRunner.undoLastCommit(at: root)
        }
    }

    func reset(to commit: GitCommitSummary, mode: GitResetMode) async {
        await prepareSafeOperation(
            kind: .reset,
            target: commit.hash,
            targetTitle: "\(commit.shortHash) · \(commit.subject)",
            resetMode: mode
        )
    }

    func resetPreview(for commit: GitCommitSummary) async -> GitOperationPreview? {
        guard let root = repositoryRootURL else { return nil }
        do {
            return try await gitRunner.operationPreview(to: commit.hash, at: root)
        } catch {
            present(error: error, title: "无法预览重置影响")
            return nil
        }
    }

    func revertPreview(for commit: GitCommitSummary) async -> GitOperationPreview? {
        guard let root = repositoryRootURL else { return nil }
        do {
            return try await gitRunner.revertPreview(for: commit.hash, at: root)
        } catch {
            present(error: error, title: "无法预览 Revert 影响")
            return nil
        }
    }

    var repositoryRootURL: URL? {
        repository.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
    }
}
