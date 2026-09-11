import Foundation

enum RepositoryOperationState: String, Sendable {
    case merge = "Merge"
    case rebase = "Rebase"
    case cherryPick = "Cherry-pick"
}

enum RemoteConnectionState: Equatable, Sendable {
    case unknown
    case checking
    case connected
    case unavailable(String)
    case timedOut(String)
    case unauthorized(String)
    case notFound(String)

    var title: String {
        switch self {
        case .unknown: AppLanguage.text("尚未检测", "Not Checked")
        case .checking: AppLanguage.text("正在连接", "Checking")
        case .connected: AppLanguage.text("连接正常", "Connected")
        case .unavailable: AppLanguage.text("网络不可用", "Network unavailable")
        case .timedOut: AppLanguage.text("连接超时", "Connection timed out")
        case .unauthorized: AppLanguage.text("远程认证失败", "Authentication failed")
        case .notFound: AppLanguage.text("远程仓库不存在", "Remote not found")
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct RepositoryHealthSummary: Sendable {
    var operationState: RepositoryOperationState?
    var isDetachedHead: Bool
    var invalidWorktreeCount: Int
    var staleStashCount: Int
    var largeUntrackedFiles: [String]
    var remoteConnection: RemoteConnectionState
    var lastFetchAt: Date?

    static let empty = RepositoryHealthSummary(
        operationState: nil,
        isDetachedHead: false,
        invalidWorktreeCount: 0,
        staleStashCount: 0,
        largeUntrackedFiles: [],
        remoteConnection: .unknown,
        lastFetchAt: nil
    )
}
