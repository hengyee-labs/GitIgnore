import Foundation

extension AppState {
    func openCommitStudio() async {
        guard let root = repositoryRootURL else { return }
        isCommitStudioPresented = true
        commitStudio.isLoading = true
        defer { commitStudio.isLoading = false }
        do {
            let units = try await gitRunner.commitStudioUnits(at: root)
            commitStudio.units = units
            let validIDs = Set(units.map(\.id))
            commitStudio.drafts = commitStudio.drafts.map { draft in
                var copy = draft
                copy.unitIDs.formIntersection(validIDs)
                return copy
            }
            if commitStudio.drafts.isEmpty { commitStudio.drafts = [CommitStudioDraft()] }
        } catch {
            present(error: error, title: "无法准备提交编排台")
        }
    }

    func executeCommitStudio() async {
        guard let root = repositoryRootURL, !commitStudio.isCommitting else { return }
        guard commitStudio.unassignedUnits.isEmpty else {
            presentMessage("仍有 \(commitStudio.unassignedUnits.count) 个变更区块没有分配。", title: "请先完成内容分配")
            return
        }
        commitStudio.isCommitting = true
        await gitOperationQueue.acquire(repositoryPath: root.path)
        defer {
            commitStudio.isCommitting = false
            Task { await gitOperationQueue.release(repositoryPath: root.path) }
        }
        do {
            let result = try await gitRunner.executeCommitStudio(
                drafts: commitStudio.drafts, units: commitStudio.units, at: root
            )
            isCommitStudioPresented = false
            commitStudio = CommitStudioState()
            await refresh(scope: [.workingCopy, .history, .remote])
            feedback = AppFeedback(
                kind: .success,
                title: "提交序列已创建",
                message: "已按顺序创建 \(result.commitIDs.count) 个提交；未分配内容仍留在工作区。"
            )
        } catch {
            present(error: error, title: "提交编排未完成")
        }
    }
}
