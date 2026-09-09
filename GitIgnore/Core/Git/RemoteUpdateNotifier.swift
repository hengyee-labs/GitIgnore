import Foundation
import UserNotifications

enum NotificationPermissionState: Sendable {
    case notRequested
    case denied
    case allowed
    case limited

    var title: String {
        switch self {
        case .notRequested: return AppLanguage.isEnglish ? "Not Requested" : "尚未请求"
        case .denied: return AppLanguage.isEnglish ? "Denied" : "已拒绝"
        case .allowed: return AppLanguage.isEnglish ? "Allowed" : "已允许"
        case .limited: return AppLanguage.isEnglish ? "Provisional" : "临时允许"
        }
    }
}

enum RemoteUpdateNotifier {
    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func permissionState() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notRequested
        case .denied: return .denied
        case .authorized: return .allowed
        case .provisional, .ephemeral: return .limited
        @unknown default: return .notRequested
        }
    }

    static func ensureAuthorization() async -> Bool {
        switch await permissionState() {
        case .allowed, .limited:
            return true
        case .denied:
            return false
        case .notRequested:
            return (try? await requestAuthorization()) ?? false
        }
    }

    static func notify(repositoryName: String, behindCount: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(behindCount) 个提交可以拉取"
        content.body = "\(repositoryName) 的当前分支已有远程更新。GitIgnore 不会自动 Pull。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "gitignore.remote.update.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    static func notifyUnavailable(repositoryName: String, reason: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(repositoryName) 远程检测未完成"
        content.body = reason
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "gitignore.remote.failure.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    static func sendTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "GitIgnore 通知已就绪"
        content.body = "远程更新、连接失败和检测超时会通过这里提醒你。"
        content.sound = .default
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "gitignore.notification.test", content: content, trigger: nil)
        )
    }
}
