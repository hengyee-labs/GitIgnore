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

    var title: String {
        switch self {
        case .unknown: AppLanguage.text("尚未检测", "Not Checked")
        case .checking: AppLanguage.text("正在连接", "Checking")
        case .connected: AppLanguage.text("连接正常", "Connected")
        case .unavailable: AppLanguage.text("暂时不可用", "Unavailable")
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
