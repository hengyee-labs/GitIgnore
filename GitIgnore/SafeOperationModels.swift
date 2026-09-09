import Foundation

enum SafeGitOperationKind: String, Codable, CaseIterable, Sendable {
    case merge
    case rebase
    case cherryPick
    case reset
    case deleteBranch

    var title: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .cherryPick: "Cherry-pick"
        case .reset: "Reset"
        case .deleteBranch: "删除分支"
        }
    }

    var symbol: String {
        switch self {
        case .merge: "arrow.triangle.merge"
        case .rebase: "arrow.triangle.swap"
        case .cherryPick: "arrow.down.to.line"
        case .reset: "clock.arrow.2.circlepath"
        case .deleteBranch: "trash"
        }
    }
}

enum LocalChangesStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case restore
    case keepInStash
    case discard

    var id: Self { self }
}

enum SafeOperationOutcome: String, Codable, Sendable {
    case notStarted
    case operationFailedProtectionRetained
    case operationSucceededRestoreFailed
    case conflicts
    case succeeded

    var title: String {
        switch self {
        case .notStarted: "Git 操作没有执行"
        case .operationFailedProtectionRetained: "操作未完成"
        case .operationSucceededRestoreFailed: "操作成功，本地修改待处理"
        case .conflicts: "需要继续处理冲突"
        case .succeeded: "操作已完成"
        }
    }
}

struct SafeGitOperationRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let repositoryPath: String
    let kind: SafeGitOperationKind
    let target: String
    let targetTitle: String
    let resetMode: GitResetMode?
    let force: Bool
    let currentBranch: String
    let preview: GitOperationPreview
    let changedFileCount: Int
    let stagedFileCount: Int
    let untrackedFileCount: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
