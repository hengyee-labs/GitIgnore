import Foundation

extension AppState {
    @discardableResult
    func beginGitOperation(
        kind: GitOperationKind,
        title: String,
        repositoryPath: String
    ) -> UUID {
        let record = GitOperationRecord(
            id: UUID(),
            repositoryPath: repositoryPath,
            kind: kind,
            title: title,
            startedAt: Date(),
            finishedAt: nil,
            phase: .queued,
            detail: nil
        )
        workflows.recentOperations.insert(record, at: 0)
        trimOperationHistory()
        return record.id
    }

    func activateGitOperation(_ id: UUID) {
        updateGitOperation(id, phase: .running)
        workflows.activeOperation = workflows.recentOperations.first { $0.id == id }
        isPerformingGitAction = true
    }

    func updateGitOperation(_ id: UUID, phase: GitOperationPhase, detail: String? = nil) {
        guard let index = workflows.recentOperations.firstIndex(where: { $0.id == id }) else { return }
        workflows.recentOperations[index].phase = phase
        if let detail { workflows.recentOperations[index].detail = detail }
        if workflows.activeOperation?.id == id {
            workflows.activeOperation = workflows.recentOperations[index]
        }
    }

    func finishGitOperation(_ id: UUID, succeeded: Bool, detail: String?) {
        guard let index = workflows.recentOperations.firstIndex(where: { $0.id == id }) else { return }
        workflows.recentOperations[index].phase = succeeded ? .succeeded : .failed
        workflows.recentOperations[index].finishedAt = Date()
        workflows.recentOperations[index].detail = detail
        if workflows.activeOperation?.id == id {
            workflows.activeOperation = nil
            isPerformingGitAction = false
        }
        trimOperationHistory()
    }

    func clearFinishedGitOperations() {
        workflows.recentOperations.removeAll { $0.phase.isFinished }
    }

    private func trimOperationHistory() {
        if workflows.recentOperations.count > 24 {
            workflows.recentOperations.removeLast(workflows.recentOperations.count - 24)
        }
    }
}
