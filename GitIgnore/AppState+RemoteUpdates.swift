import Foundation

private enum RemoteUpdateCheckError: LocalizedError {
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case let .timedOut(seconds): "连接远程仓库超过 \(seconds) 秒，检测已自动停止。"
        }
    }
}

extension AppState {
    func scheduleRemoteUpdateCheck(for root: URL) {
        remoteCheckTask?.cancel()
        remoteCheckTask = Task { [weak self] in
            guard let self else { return }
            let notificationsEnabled = RemoteCheckPreferences.notificationsEnabled
            let timeoutSeconds = RemoteCheckPreferences.timeoutSeconds
            let authorizationTask = Task {
                guard notificationsEnabled else { return false }
                return await RemoteUpdateNotifier.ensureAuthorization()
            }
            defer { authorizationTask.cancel() }
            guard !Task.isCancelled else { return }
            self.isCheckingRemoteUpdates = true
            self.repositoryHealth.remoteConnection = .checking
            defer {
                self.isCheckingRemoteUpdates = false
                self.scheduleDeferredLiveRefreshIfNeeded()
            }

            do {
                try await self.fetchRemoteUpdates(at: root, timeoutSeconds: timeoutSeconds)
                guard !Task.isCancelled, self.repository?.path == root.path else { return }
                let tracking = try await self.gitRunner.aheadBehind(at: root)
                let incoming = tracking.behind > 0
                    ? ((try? await self.gitRunner.incomingCommits(at: root)) ?? [])
                    : []
                guard !Task.isCancelled, let current = self.repository, current.path == root.path else { return }
                self.repositoryHealth.remoteConnection = .connected
                self.repositoryHealth.lastFetchAt = Date()
                self.incomingCommits = incoming
                self.repository = RepositorySummary(
                    name: current.name,
                    path: current.path,
                    branch: current.branch,
                    changedFileCount: current.changedFileCount,
                    stagedFileCount: current.stagedFileCount,
                    aheadCount: tracking.ahead,
                    behindCount: tracking.behind,
                    needsPublish: self.branches.first(where: \.isCurrent)?.needsPublish ?? current.needsPublish
                )
                await self.refresh(scope: .branches)
                guard tracking.behind > 0 else { return }
                self.feedback = AppFeedback(
                    kind: .warning,
                    title: "发现可拉取的远程更新",
                    message: "\(current.name) 当前分支落后 \(tracking.behind) 个提交。"
                )
                if await authorizationTask.value {
                    do {
                        try await RemoteUpdateNotifier.notify(
                            repositoryName: current.name,
                            behindCount: tracking.behind
                        )
                    } catch {
                        self.feedback = AppFeedback(
                            kind: .warning,
                            title: "发现可拉取的远程更新",
                            message: "\(current.name) 落后 \(tracking.behind) 个提交，但系统通知发送失败。请在设置中检查通知权限。",
                            technicalDetails: error.localizedDescription
                        )
                    }
                } else if notificationsEnabled {
                    self.feedback = AppFeedback(
                        kind: .warning,
                        title: "发现可拉取的远程更新",
                        message: "\(current.name) 落后 \(tracking.behind) 个提交；系统通知尚未获准，请在设置中开启。"
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let current = self.repository, current.path == root.path else { return }
                let isTimeout = error is RemoteUpdateCheckError
                let rawMessage = error.localizedDescription
                let isUnauthorized = rawMessage.localizedCaseInsensitiveContains("authentication") || rawMessage.localizedCaseInsensitiveContains("permission denied")
                let isNotFound = rawMessage.localizedCaseInsensitiveContains("repository not found") || rawMessage.localizedCaseInsensitiveContains("does not appear to be a git repository")
                let message = isTimeout
                    ? error.localizedDescription
                    : "无法连接远程仓库，可以稍后手动 Fetch。"
                self.repositoryHealth.remoteConnection = isTimeout ? .timedOut(message) : (isUnauthorized ? .unauthorized(rawMessage) : (isNotFound ? .notFound(rawMessage) : .unavailable(message)))
                self.repositoryHealth.lastFetchAt = Date()
                self.feedback = AppFeedback(
                    kind: .warning,
                    title: isTimeout ? "远程检测已超时" : "暂时无法检查远程更新",
                    message: message
                )
                if await authorizationTask.value {
                    do {
                        try await RemoteUpdateNotifier.notifyUnavailable(
                            repositoryName: current.name,
                            reason: message
                        )
                    } catch {
                        self.feedback = AppFeedback(
                            kind: .warning,
                            title: isTimeout ? "远程检测已超时" : "暂时无法检查远程更新",
                            message: "\(message) 系统通知发送失败，请在设置中检查通知权限。",
                            technicalDetails: error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    private func fetchRemoteUpdates(at root: URL, timeoutSeconds: Double) async throws {
        let runner = gitRunner
        let seconds = Int(timeoutSeconds.rounded())
        let didFetch = try await withThrowingTaskGroup(of: Bool.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                try await runner.fetch(at: root)
                return true
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                return false
            }
            return try await group.next() ?? false
        }
        guard didFetch else { throw RemoteUpdateCheckError.timedOut(seconds: seconds) }
    }
}
