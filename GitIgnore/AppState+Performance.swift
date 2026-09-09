import Foundation

extension AppState {
    func refresh(scope: RepositoryRefreshScope, refreshSelectedDiff: Bool = true) async {
        pendingRefreshScope.formUnion(scope)
        pendingRefreshSelectedDiff = pendingRefreshSelectedDiff || refreshSelectedDiff
        guard !isRefreshCoordinatorRunning else { return }

        isRefreshCoordinatorRunning = true
        let sessionGeneration = repositorySessionGeneration
        let token = PerformanceDiagnostics.begin(category: "Refresh", name: "total")
        defer {
            isRefreshCoordinatorRunning = false
            PerformanceDiagnostics.end(token)
        }

        while !pendingRefreshScope.isEmpty, !Task.isCancelled {
            guard sessionGeneration == repositorySessionGeneration else { return }
            let nextScope = pendingRefreshScope
            let shouldRefreshSelectedDiff = pendingRefreshSelectedDiff
            pendingRefreshScope = []
            pendingRefreshSelectedDiff = false
            await performRefreshPass(scope: nextScope, refreshSelectedDiff: shouldRefreshSelectedDiff)
        }
    }

    private func performRefreshPass(scope: RepositoryRefreshScope, refreshSelectedDiff: Bool) async {
        guard let repository else { return }
        let sessionGeneration = repositorySessionGeneration
        let root = URL(fileURLWithPath: repository.path, isDirectory: true)

        if scope.contains(.workingCopy), let latestStatus = try? await gitRunner.status(at: root) {
            guard self.repository?.path == repository.path,
                  repositorySessionGeneration == sessionGeneration else { return }
            let applyToken = PerformanceDiagnostics.begin(category: "Refresh", name: "working-copy-apply")
            status = latestStatus
            self.repository = RepositorySummary(
                name: repository.name,
                path: repository.path,
                branch: repository.branch,
                changedFileCount: latestStatus.changedFileCount,
                stagedFileCount: latestStatus.stagedFileCount,
                aheadCount: repository.aheadCount,
                behindCount: repository.behindCount,
                needsPublish: repository.needsPublish
            )
            PerformanceDiagnostics.end(applyToken)
            await refreshSelectedFile(using: latestStatus, at: root, reloadDiff: refreshSelectedDiff)
        }

        if scope.contains(.history) {
            do {
                let loaded = try await gitRunner.commits(at: root, limit: 60)
                guard self.repository?.path == repository.path,
                      repositorySessionGeneration == sessionGeneration else { return }
                let selectedID = selectedCommit?.id
                commits = loaded
                hasMoreCommits = loaded.count == 60
                selectedCommit = (incomingCommits + loaded).first { $0.id == selectedID }
                if selectedCommit == nil {
                    selectedCommitDetail = nil
                    selectedCommitFilePath = nil
                    selectedCommitFileDiff = nil
                }
            } catch is CancellationError {
                return
            } catch {
                // A transient Git read failure must not replace valid history with an empty state.
                if commits.isEmpty {
                    present(error: error, title: "无法读取提交历史")
                } else {
                    feedback = AppFeedback(
                        kind: .warning,
                        title: "提交历史刷新未完成",
                        message: "已保留当前提交列表，稍后会继续自动刷新。"
                    )
                }
            }
        }

        if scope.contains(.branches) {
            async let localTask = gitRunner.branches(at: root)
            async let remoteTask = gitRunner.remoteBranches(at: root)
            let loadedBranches = (try? await localTask) ?? branches
            let loadedRemoteBranches = (try? await remoteTask) ?? remoteBranches
            guard self.repository?.path == repository.path,
                  repositorySessionGeneration == sessionGeneration else { return }
            branches = loadedBranches
            remoteBranches = loadedRemoteBranches
            if let current = self.repository {
                self.repository = RepositorySummary(
                    name: current.name,
                    path: current.path,
                    branch: current.branch,
                    changedFileCount: current.changedFileCount,
                    stagedFileCount: current.stagedFileCount,
                    aheadCount: current.aheadCount,
                    behindCount: current.behindCount,
                    needsPublish: loadedBranches.first(where: \.isCurrent)?.needsPublish ?? current.needsPublish
                )
            }
        }

        if scope.contains(.stashes) {
            let loaded = (try? await gitRunner.stashList(at: root)) ?? stashes
            guard self.repository?.path == repository.path,
                  repositorySessionGeneration == sessionGeneration else { return }
            stashes = loaded
        }
        if scope.contains(.worktrees) {
            let loaded = (try? await gitRunner.worktrees(at: root)) ?? worktrees
            guard self.repository?.path == repository.path,
                  repositorySessionGeneration == sessionGeneration else { return }
            worktrees = loaded
        }
        if scope.contains(.identity) {
            let loaded = (try? await gitRunner.identity(at: root)) ?? gitIdentity
            guard self.repository?.path == repository.path,
                  repositorySessionGeneration == sessionGeneration else { return }
            gitIdentity = loaded
        }
        if scope.contains(.remote) {
            async let branchTask = gitRunner.currentBranch(at: root)
            async let trackingTask = gitRunner.aheadBehind(at: root)
            async let remoteInfoTask = gitRunner.remoteInfo(at: root)
            async let incomingTask = gitRunner.incomingCommits(at: root)
            let branch = (try? await branchTask) ?? repository.branch
            let tracking = try? await trackingTask
            remoteInfo = (try? await remoteInfoTask) ?? remoteInfo
            if let tracking {
                incomingCommits = tracking.behind > 0 ? ((try? await incomingTask) ?? incomingCommits) : []
            }
            guard self.repository?.path == repository.path,
                  repositorySessionGeneration == sessionGeneration else { return }
            let current = self.repository ?? repository
            self.repository = RepositorySummary(
                name: current.name,
                path: current.path,
                branch: branch,
                changedFileCount: current.changedFileCount,
                stagedFileCount: current.stagedFileCount,
                aheadCount: tracking?.ahead ?? current.aheadCount,
                behindCount: tracking?.behind ?? current.behindCount,
                needsPublish: branches.first(where: \.isCurrent)?.needsPublish ?? current.needsPublish
            )
        }

        if !scope.isDisjoint(with: [.workingCopy, .branches, .stashes, .worktrees, .remote]) {
            await refreshRepositoryHealth(at: root)
        }
    }

    func loadMoreCommits() async {
        guard let repository, hasMoreCommits, !isLoadingMoreCommits else { return }
        isLoadingMoreCommits = true
        defer { isLoadingMoreCommits = false }
        let root = URL(fileURLWithPath: repository.path, isDirectory: true)
        do {
            let page = try await gitRunner.commits(at: root, limit: 60, skip: commits.count)
            let existingIDs = Set(commits.map(\.id))
            commits.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
            hasMoreCommits = page.count == 60
        } catch is CancellationError {
            return
        } catch {
            present(error: error, title: "无法继续读取提交历史")
        }
    }

    func selectCommitFile(_ file: GitCommitFileChange, in commit: GitCommitSummary) async {
        guard let repository else { return }
        commitFileLoadGeneration &+= 1
        let loadGeneration = commitFileLoadGeneration
        commitFileLoadTask?.cancel()
        selectedCommitFilePath = file.path
        selectedCommitFileDiff = nil
        isLoadingCommitFileDiff = false
        let cacheKey = "\(commit.hash):\(file.path)"
        if let cached = commitFileDiffCache[cacheKey] {
            selectedCommitFileDiff = cached
            touchCommitFileCache(cacheKey)
            return
        }

        isLoadingCommitFileDiff = true
        let root = URL(fileURLWithPath: repository.path, isDirectory: true)
        let task = Task { try await gitRunner.commitFileDiff(hash: commit.hash, path: file.path, at: root) }
        commitFileLoadTask = task
        do {
            let diff = try await task.value
            guard commitFileLoadGeneration == loadGeneration,
                  selectedCommit?.id == commit.id,
                  selectedCommitFilePath == file.path else { return }
            selectedCommitFileDiff = diff
            isLoadingCommitFileDiff = false
            if diff.byteCount <= 2_000_000 {
                commitFileDiffCache[cacheKey] = diff
                commitFileDiffCacheBytes[cacheKey] = diff.byteCount
                touchCommitFileCache(cacheKey)
            }
        } catch is CancellationError {
            if commitFileLoadGeneration == loadGeneration,
               selectedCommit?.id == commit.id,
               selectedCommitFilePath == file.path {
                isLoadingCommitFileDiff = false
            }
            return
        } catch {
            guard commitFileLoadGeneration == loadGeneration,
                  selectedCommit?.id == commit.id,
                  selectedCommitFilePath == file.path else { return }
            isLoadingCommitFileDiff = false
            present(error: error, title: "无法读取文件提交内容")
        }
    }

    func rememberCommitMessage(_ message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        recentCommitMessages.removeAll { $0 == normalized }
        recentCommitMessages.insert(normalized, at: 0)
        if recentCommitMessages.count > 8 { recentCommitMessages.removeLast(recentCommitMessages.count - 8) }
        UserDefaults.standard.set(recentCommitMessages, forKey: "orbit.recentCommitMessages")
    }

    private func refreshSelectedFile(
        using latestStatus: GitStatusSummary,
        at root: URL,
        reloadDiff: Bool
    ) async {
        guard let selectedPath = selectedFile?.path else { return }
        selectedFile = latestStatus.files.first { $0.path == selectedPath }
        guard let selectedFile else {
            diffLoadGeneration &+= 1
            diffLoadTask?.cancel()
            selectedFileDiff = nil
            selectedFileDiffError = nil
            isLoadingDiff = false
            return
        }
        guard reloadDiff else { return }

        let previousDiff = selectedFileDiff
        let staged = selectedFileDiffIsStaged
        diffLoadGeneration &+= 1
        let loadGeneration = diffLoadGeneration
        diffLoadTask?.cancel()
        if previousDiff == nil {
            isLoadingDiff = true
        }
        defer {
            if diffLoadGeneration == loadGeneration,
               self.selectedFile?.path == selectedFile.path {
                isLoadingDiff = false
            }
        }
        let task = Task { try await gitRunner.diff(for: selectedFile, staged: staged, at: root) }
        diffLoadTask = task
        do {
            let refreshedDiff = try await task.value
            guard diffLoadGeneration == loadGeneration,
                  self.selectedFile?.path == selectedFile.path else { return }
            selectedFileDiff = refreshedDiff
            selectedFileDiffError = nil
        } catch is CancellationError {
            return
        } catch {
            guard diffLoadGeneration == loadGeneration,
                  self.selectedFile?.path == selectedFile.path else { return }
            selectedFileDiff = previousDiff
            if previousDiff == nil {
                selectedFileDiffError = error.localizedDescription
            }
        }
    }

    private func touchCommitFileCache(_ key: String) {
        commitFileDiffCacheOrder.removeAll { $0 == key }
        commitFileDiffCacheOrder.append(key)
        while commitFileDiffCacheOrder.count > 6 || commitFileDiffCacheBytes.values.reduce(0, +) > 8 * 1_024 * 1_024 {
            let evicted = commitFileDiffCacheOrder.removeFirst()
            commitFileDiffCache.removeValue(forKey: evicted)
            commitFileDiffCacheBytes.removeValue(forKey: evicted)
        }
    }

    func touchCommitDetailCache(_ key: String) {
        if let detail = commitDetailCache[key] {
            commitDetailCacheBytes[key] = detail.message.utf8.count + detail.files.reduce(0) { $0 + $1.path.utf8.count + 64 }
        }
        commitDetailCacheOrder.removeAll { $0 == key }
        commitDetailCacheOrder.append(key)
        while commitDetailCacheOrder.count > 24 || commitDetailCacheBytes.values.reduce(0, +) > 4 * 1_024 * 1_024 {
            let evicted = commitDetailCacheOrder.removeFirst()
            commitDetailCache.removeValue(forKey: evicted)
            commitDetailCacheBytes.removeValue(forKey: evicted)
        }
    }
}
