import Foundation

extension AppState {
    func prepareSafeOperation(
        kind: SafeGitOperationKind,
        target: String,
        targetTitle: String? = nil,
        resetMode: GitResetMode? = nil,
        force: Bool = false
    ) async {
        guard let repository else { return }
        let root = URL(fileURLWithPath: repository.path, isDirectory: true)
        do {
            let liveStatus = try await gitRunner.status(at: root)
            let preview = try await gitRunner.safeOperationPreview(
                kind: kind,
                target: target,
                resetMode: resetMode,
                at: root
            )
            guard self.repository?.path == repository.path else { return }
            status = liveStatus
            workflows.safeOperationRequest = SafeGitOperationRequest(
                repositoryPath: repository.path,
                kind: kind,
                target: target,
                targetTitle: targetTitle ?? target,
                resetMode: resetMode,
                force: force,
                currentBranch: repository.branch,
                preview: preview,
                changedFileCount: liveStatus.changedFileCount,
                stagedFileCount: liveStatus.stagedFileCount,
                untrackedFileCount: liveStatus.files.filter { $0.kind == .untracked }.count
            )
        } catch {
            present(error: error, title: "无法预检 \(kind.title)")
        }
    }

    func performSafeOperation(
        _ request: SafeGitOperationRequest,
        strategy: LocalChangesStrategy
    ) async {
        guard let repository, repository.path == request.repositoryPath else {
            presentMessage("仓库已经发生变化，请重新发起操作。", title: "无法继续安全操作")
            return
        }
        let root = URL(fileURLWithPath: request.repositoryPath, isDirectory: true)
        let operationID = beginGitOperation(
            kind: request.kind == .rebase ? .rebase : .recovery,
            title: request.kind == .deleteBranch ? request.kind.title : "安全 \(request.kind.title)",
            repositoryPath: request.repositoryPath
        )
        var protection: SafePullProtection?
        var operationDidStart = false
        var operationDidSucceed = false
        var outcome = SafeOperationOutcome.notStarted
        var detail = "预检尚未完成。"

        isPerformingGitAction = true
        errorMessage = nil
        feedback = nil
        await gitOperationQueue.acquire(repositoryPath: request.repositoryPath)
        activateGitOperation(operationID)

        do {
            if request.changedFileCount > 0, request.kind != .deleteBranch {
                updateGitOperation(operationID, phase: .running, detail: "正在保护本地修改")
                protection = try await gitRunner.createSafePullProtection(
                    message: "GitIgnore · \(request.kind.title) 前的本地修改",
                    at: root
                )
            }

            updateGitOperation(operationID, phase: .running, detail: "正在执行 \(request.kind.title)")
            operationDidStart = true
            try await gitRunner.executeSafeOperation(request, at: root)
            operationDidSucceed = true

            let postOperationStatus = try await gitRunner.status(at: root)
            if postOperationStatus.files.contains(where: \.hasConflict) {
                outcome = .conflicts
                detail = "Git 操作已执行，但仓库存在冲突，需要继续处理。"
                status = postOperationStatus
            } else if let protection {
                switch strategy {
                case .restore:
                    updateGitOperation(operationID, phase: .running, detail: "正在恢复操作前的本地修改")
                    let restoreResult = try await gitRunner.restoreSafePullProtection(protection, at: root)
                    switch restoreResult {
                    case .restored:
                        outcome = .succeeded
                        detail = "Git 操作和本地修改恢复均已完成。"
                    case let .restoredWithProtection(technicalDetails):
                        outcome = .operationSucceededRestoreFailed
                        detail = "Git 操作成功，本地内容已恢复，但暂存边界需要检查。\n\(technicalDetails)"
                    case let .conflicts(files, technicalDetails):
                        outcome = .conflicts
                        detail = "Git 操作成功，恢复本地修改时产生 \(files.count) 个冲突。\n\(technicalDetails)"
                    case let .failed(technicalDetails):
                        outcome = .operationSucceededRestoreFailed
                        detail = "Git 操作成功，但本地修改自动恢复失败；保护用 Stash 仍保留。\n\(technicalDetails)"
                    }
                case .keepInStash:
                    outcome = .succeeded
                    detail = "Git 操作已完成，本地修改保存在 Stash 中。"
                case .discard:
                    try await gitRunner.discardSafePullProtection(protection, at: root)
                    outcome = .succeeded
                    detail = "Git 操作已完成，已按确认丢弃原本的本地修改。"
                }
            } else {
                outcome = .succeeded
                detail = "Git 操作已完成。"
            }
        } catch {
            let liveStatus = (try? await gitRunner.status(at: root)) ?? status
            status = liveStatus
            let technical = (error as? GitRunnerError)?.technicalDetails ?? error.localizedDescription
            if liveStatus.files.contains(where: \.hasConflict) {
                outcome = .conflicts
                detail = "Git 操作已开始并产生冲突，需要继续处理。\n\(technical)"
            } else if operationDidSucceed {
                outcome = .operationSucceededRestoreFailed
                detail = "Git 操作已成功，但后续恢复失败；保护用 Stash 仍然保留。\n\(technical)"
            } else if operationDidStart {
                outcome = .operationFailedProtectionRetained
                detail = protection == nil
                    ? "Git 操作没有成功完成。\n\(technical)"
                    : "Git 操作没有成功完成；保护用 Stash 仍然保留。\n\(technical)"
            } else {
                outcome = .notStarted
                detail = "Git 操作没有执行，当前仓库状态未被本次操作修改。\n\(technical)"
            }
        }

        await refresh(scope: .all)
        cancelPendingLiveRefresh()
        let succeeded = outcome == .succeeded
        finishGitOperation(operationID, succeeded: succeeded, detail: detail)
        await gitOperationQueue.release(repositoryPath: request.repositoryPath)
        isPerformingGitAction = false

        switch outcome {
        case .succeeded:
            feedback = AppFeedback(kind: .success, title: outcome.title, message: detail)
        case .conflicts:
            feedback = AppFeedback(kind: .warning, title: outcome.title, message: "请继续处理冲突；保护用 Stash 不会被自动删除。", technicalDetails: detail)
            if let conflict = status.files.first(where: \.hasConflict) {
                await openConflictEditor(for: conflict)
            } else {
                selectedSection = .changes
            }
        case .operationSucceededRestoreFailed, .operationFailedProtectionRetained, .notStarted:
            feedback = AppFeedback(kind: .failure, title: outcome.title, message: "请查看技术详情；如有保护用 Stash，可从 Stash 页面继续处理。", technicalDetails: detail)
        }
    }
}
