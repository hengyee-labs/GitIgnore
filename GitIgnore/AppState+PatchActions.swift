import Foundation

extension AppState {
    func applySelectedLines(
        in hunk: GitPatchHunk,
        selectedIndices: Set<Int>,
        operation: GitPatchOperation
    ) async {
        guard let root = repositoryRootURL else { return }
        do {
            let patch = try hunk.patchText(selecting: selectedIndices)
            let title: String
            let message: String
            switch operation {
            case .stage:
                title = "所选行已 Stage"
                message = "只将所选代码行加入暂存区。"
            case .unstage:
                title = "所选行已取消 Stage"
                message = "只将所选代码行移回工作区。"
            case .discard:
                title = "所选行已丢弃"
                message = "所选代码行已从工作区移除。"
            }
            await performAction(
                successTitle: title,
                successMessage: message,
                kind: .stage,
                refreshScope: .workingCopy
            ) {
                try await self.gitRunner.applyPatch(patch, operation: operation, at: root)
            }
        } catch {
            present(error: error, title: "无法处理所选代码行")
        }
    }
}
