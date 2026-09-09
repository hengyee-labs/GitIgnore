import Foundation
import Observation

enum GitOperationKind: String, Sendable {
    case fetch
    case pull
    case push
    case stage
    case commit
    case branch
    case rebase
    case stash
    case worktree
    case recovery
    case other

    var symbol: String {
        switch self {
        case .fetch: "arrow.down.circle"
        case .pull: "arrow.down.to.line"
        case .push: "arrow.up.to.line"
        case .stage: "tray.and.arrow.down"
        case .commit: "checkmark.seal"
        case .branch: "arrow.triangle.branch"
        case .rebase: "arrow.triangle.swap"
        case .stash: "archivebox"
        case .worktree: "point.3.connected.trianglepath.dotted"
        case .recovery: "lifepreserver"
        case .other: "terminal"
        }
    }
}

enum GitOperationPhase: String, Sendable {
    case queued
    case running
    case refreshing
    case succeeded
    case failed

    var isFinished: Bool { self == .succeeded || self == .failed }
}

struct GitOperationRecord: Identifiable, Sendable {
    let id: UUID
    let repositoryPath: String
    let kind: GitOperationKind
    let title: String
    let startedAt: Date
    var finishedAt: Date?
    var phase: GitOperationPhase
    var detail: String?

    var elapsed: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

enum RebaseTodoAction: String, CaseIterable, Identifiable, Sendable {
    case pick
    case reword
    case squash
    case fixup
    case drop

    var id: Self { self }
    var title: String {
        switch self {
        case .pick: "保留"
        case .reword: "修改说明"
        case .squash: "合并并编辑"
        case .fixup: "合并到上一条"
        case .drop: "丢弃"
        }
    }
}

struct RebaseTodoItem: Identifiable, Hashable, Sendable {
    let hash: String
    let shortHash: String
    let subject: String
    var action: RebaseTodoAction
    var editedSubject: String
    var id: String { hash }
}

struct GitStashPreview: Sendable {
    let reference: String
    let files: [GitCommitFileChange]
}

struct GitBranchComparison: Sendable {
    let base: String
    let target: String
    let ahead: Int
    let behind: Int
    let commits: [GitCommitSummary]
    let changedFiles: [String]
}

struct GitWorktreeState: Sendable {
    let path: String
    let changedCount: Int
    let stagedCount: Int
    let untrackedCount: Int
    let conflictCount: Int

    var isClean: Bool { changedCount == 0 }
}

struct SafeBranchSwitchRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let repositoryPath: String
    let currentBranch: String
    let targetBranch: String
    let remote: String?
    let changedFileCount: Int
    let stagedFileCount: Int
    let untrackedFileCount: Int

    var targetDisplayName: String {
        remote.map { "\($0)/\(targetBranch)" } ?? targetBranch
    }
}

enum SafeBranchSwitchStrategy: String, CaseIterable, Identifiable, Sendable {
    case restore
    case keepInStash
    case discard

    var id: Self { self }
}

@MainActor
@Observable
final class AdvancedWorkflowState {
    var activeOperation: GitOperationRecord?
    var recentOperations: [GitOperationRecord] = []
    var incomingPreview: [String: GitCommitDetail] = [:]
    var stashPreview: GitStashPreview?
    var stashFileDiff: GitFileDiff?
    var branchComparison: GitBranchComparison?
    var mergedBranchCandidates: [String] = []
    var worktreeStates: [String: GitWorktreeState] = [:]
    var rebaseItems: [RebaseTodoItem] = []
    var rebaseBase = ""
    var rebasePlannerPresented = false
    var safeBranchSwitchRequest: SafeBranchSwitchRequest?
    var safeOperationRequest: SafeGitOperationRequest?
    var isPerformingSafeBranchSwitch = false
    var isLoadingPreview = false
    var isLoadingStashFileDiff = false
}

actor GitOperationQueue {
    private var lockedRepositories: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(repositoryPath: String) async {
        guard lockedRepositories.contains(repositoryPath) else {
            lockedRepositories.insert(repositoryPath)
            return
        }
        await withCheckedContinuation { continuation in
            waiters[repositoryPath, default: []].append(continuation)
        }
    }

    func release(repositoryPath: String) {
        guard var repositoryWaiters = waiters[repositoryPath], !repositoryWaiters.isEmpty else {
            lockedRepositories.remove(repositoryPath)
            waiters.removeValue(forKey: repositoryPath)
            return
        }
        let next = repositoryWaiters.removeFirst()
        waiters[repositoryPath] = repositoryWaiters.isEmpty ? nil : repositoryWaiters
        next.resume()
    }
}
