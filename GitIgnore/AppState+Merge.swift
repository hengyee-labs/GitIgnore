import AppKit
import Foundation

extension AppState {
    func currentBranchOperation() async -> GitBranchOperation? {
        guard let repositoryRootURL else { return nil }
        return await gitRunner.inProgressBranchOperation(at: repositoryRootURL)
    }

    func continueBranchOperation(_ operation: GitBranchOperation) async -> Bool {
        guard let repositoryRootURL else { return false }
        return await performAction(
            successTitle: "\(operation.title) 已继续",
            successMessage: "分支操作已完成，工作区和提交历史已经更新。",
            warnOnConflicts: true,
            refreshScope: [.workingCopy, .history, .branches, .remote]
        ) {
            try await self.gitRunner.continueBranchOperation(operation, at: repositoryRootURL)
        }
    }

    func abortBranchOperation(_ operation: GitBranchOperation) async -> Bool {
        guard let repositoryRootURL else { return false }
        return await performAction(
            successTitle: "\(operation.title) 已中止",
            successMessage: "分支已经恢复到操作开始前的状态。",
            refreshScope: [.workingCopy, .history, .branches, .remote]
        ) {
            try await self.gitRunner.abortBranchOperation(operation, at: repositoryRootURL)
        }
    }

    func loadMergeConflictDocument(for file: GitFileStatus) async throws -> GitMergeConflictDocument {
        guard let repository else { throw MergeEditorError.repositoryUnavailable }
        return try await gitRunner.mergeConflictDocument(
            path: file.path,
            at: URL(fileURLWithPath: repository.path, isDirectory: true)
        )
    }

    func completeMergeResolution(
        for file: GitFileStatus,
        result: String,
        deleteResult: Bool
    ) async -> Bool {
        guard let repository else { return false }
        guard !MergeConflictParser.hasConflictMarkers(in: result) else {
            present(error: MergeEditorError.unresolvedMarkers, title: "仍有冲突未解决")
            return false
        }
        return await performAction(
            successTitle: "冲突已解决",
            successMessage: "已保存并暂存 \(file.path)",
            refreshScope: .workingCopy
        ) {
            try await self.gitRunner.saveMergeResult(
                result,
                path: file.path,
                deleteResult: deleteResult,
                at: URL(fileURLWithPath: repository.path, isDirectory: true)
            )
        }
    }

    func openConflictFileExternally(_ file: GitFileStatus) {
        guard let repository else { return }
        let root = URL(fileURLWithPath: repository.path, isDirectory: true)
        NSWorkspace.shared.open(root.appendingPathComponent(file.path))
    }
}
