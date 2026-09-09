import Foundation

extension AppState {
    func refreshRepositoryHealth(
        at root: URL,
        status: GitStatusSummary? = nil,
        worktrees: [GitWorktreeSummary]? = nil,
        stashes: [GitStashSummary]? = nil
    ) async {
        let liveStatus = status ?? self.status
        let liveWorktrees = worktrees ?? self.worktrees
        let liveStashes = stashes ?? self.stashes
        let operationState = try? await gitRunner.repositoryOperationState(at: root)
        guard repository?.path == root.path else { return }

        let invalidWorktreeCount = liveWorktrees.count {
            !FileManager.default.fileExists(atPath: $0.path)
        }
        let staleStashCount = liveStashes.count { stash in
            guard let date = Self.stashDateFormatter.date(from: stash.dateText) else { return false }
            return Date().timeIntervalSince(date) > 30 * 24 * 60 * 60
        }
        let largeUntrackedFiles = liveStatus.files.lazy
            .filter { $0.kind == .untracked }
            .compactMap { file -> String? in
                let url = root.appendingPathComponent(file.path)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return size >= 20 * 1_024 * 1_024 ? file.path : nil
            }
            .prefix(20)

        repositoryHealth.operationState = operationState ?? nil
        repositoryHealth.isDetachedHead = repository?.branch == "游离状态"
        repositoryHealth.invalidWorktreeCount = invalidWorktreeCount
        repositoryHealth.staleStashCount = staleStashCount
        repositoryHealth.largeUntrackedFiles = Array(largeUntrackedFiles)
    }

    private static let stashDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
