import Foundation

enum RemoteCheckPreferences {
    static let notificationsKey = "orbit.remoteCheck.notifications"
    static let timeoutKey = "orbit.remoteCheck.timeoutSeconds"
    static let defaultTimeout = 15.0

    static var notificationsEnabled: Bool {
        guard UserDefaults.standard.object(forKey: notificationsKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: notificationsKey)
    }

    static var timeoutSeconds: Double {
        guard UserDefaults.standard.object(forKey: timeoutKey) != nil else { return defaultTimeout }
        return min(max(UserDefaults.standard.double(forKey: timeoutKey), 5), 120)
    }
}

struct RepositoryRefreshScope: OptionSet, Sendable {
    let rawValue: Int

    static let workingCopy = Self(rawValue: 1 << 0)
    static let history = Self(rawValue: 1 << 1)
    static let branches = Self(rawValue: 1 << 2)
    static let stashes = Self(rawValue: 1 << 3)
    static let worktrees = Self(rawValue: 1 << 4)
    static let remote = Self(rawValue: 1 << 5)
    static let identity = Self(rawValue: 1 << 6)
    static let all: Self = [.workingCopy, .history, .branches, .stashes, .worktrees, .remote, .identity]
}

enum GitPatchOperation: Sendable {
    case stage
    case unstage
    case discard
}

enum GitResetMode: String, CaseIterable, Identifiable, Sendable {
    case soft
    case mixed
    case hard

    var id: Self { self }

    var title: String {
        switch self {
        case .soft: "保留在暂存区"
        case .mixed: "保留在工作区"
        case .hard: "丢弃本地内容"
        }
    }

    var explanation: String {
        switch self {
        case .soft: "只移动提交位置，文件变更继续保持暂存。"
        case .mixed: "移动提交位置并取消暂存，文件内容仍然保留。"
        case .hard: "工作区与暂存区都会回到目标提交，未提交内容将无法恢复。"
        }
    }
}

struct GitOperationPreview: Sendable {
    let title: String
    let summary: String
    let affectedFiles: [String]
    let commitCount: Int
}

enum GitConflictKind: String, CaseIterable, Identifiable, Sendable {
    case bothModified
    case addedByBoth
    case deletedByOne
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .bothModified: "双方都修改"
        case .addedByBoth: "双方都新增"
        case .deletedByOne: "一侧已删除"
        case .other: "其他冲突"
        }
    }
}

struct SafePullRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let changedFileCount: Int
    let stagedFileCount: Int
    let untrackedFileCount: Int
    let incomingCommitCount: Int
}

enum SafePullPhase: Int, CaseIterable, Sendable {
    case protecting
    case pulling
    case restoring
}

struct SafePullProtection: Sendable {
    let reference: String
    let objectID: String
}

enum SafePullStashRestoreResult: Sendable {
    case restored
    case restoredWithProtection(technicalDetails: String)
    case conflicts(files: [GitFileStatus], technicalDetails: String)
    case failed(technicalDetails: String)
}

enum SafePullError: LocalizedError, Sendable {
    case protectionNotCreated

    var errorDescription: String? {
        switch self {
        case .protectionNotCreated:
            AppLanguage.isEnglish
                ? "The local changes changed before they could be protected. Refresh the workspace and try again."
                : "本地变更在保护前发生了变化，请刷新工作区后重试。"
        }
    }
}

extension GitFileStatus {
    var conflictKind: GitConflictKind {
        switch statusCode {
        case "UU": .bothModified
        case "AA": .addedByBoth
        case "UD", "DU", "DD": .deletedByOne
        default: .other
        }
    }
}
