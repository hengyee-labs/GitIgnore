import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var selectedSection: SidebarSection = .overview {
        didSet {
            UserDefaults.standard.set(selectedSection.rawValue, forKey: "orbit.lastSelectedSection")
            synchronizeInspectorSelection()
        }
    }
    var repository: RepositorySummary?
    var recentRepositories: [RecentRepository] = []
    var status = GitStatusSummary(files: [])
    var commits: [GitCommitSummary] = []
    var incomingCommits: [GitCommitSummary] = []
    var branches: [GitBranchSummary] = []
    var remoteBranches: [GitRemoteBranchSummary] = []
    var stashes: [GitStashSummary] = []
    var worktrees: [GitWorktreeSummary] = []
    var remoteInfo: GitRemoteInfo?
    var gitIdentity = GitIdentity(name: "", email: "")
    var selectedCommit: GitCommitSummary?
    var selectedCommitDetail: GitCommitDetail?
    var selectedCommitFilePath: String?
    var selectedCommitFileDiff: GitFileDiff?
    var selectedFile: GitFileStatus?
    var selectedFileDiff: GitFileDiff?
    var selectedFileDiffError: String?
    var selectedFileDiffIsStaged = false
    var selectedImageDiffPreview: GitImageDiffPreview?
    var isDiffFocusPresented = false
    var isLoadingImageDiff = false
    var gitVersion = "正在检测 Git…"
    var isLoadingRepository = false
    var isLoadingDiff = false
    var isLoadingCommitDetail = false
    var isLoadingCommitFileDiff = false
    var isLoadingMoreCommits = false
    var hasMoreCommits = false
    var isCheckingRemoteUpdates = false
    var isPerformingGitAction = false
    var actionMessage: String?
    var errorMessage: String?
    var feedback: AppFeedback?
    var recentlyAddedCommitIDs: Set<String> = []
    var historyUpdateMessage: String?
    var isCommandPalettePresented = false
    var safePullRequest: SafePullRequest?
    var safePullPhase: SafePullPhase?
    var presentedConflictFile: GitFileStatus?
    var repositoryHealth = RepositoryHealthSummary.empty
    var recentCommitMessages: [String] = []
    var workflows = AdvancedWorkflowState()
    var commitStudio = CommitStudioState()
    var isCommitStudioPresented = false
    let gitRunner = GitRunner()
    let repositoryWatcher = RepositoryFileWatcher()
    @ObservationIgnored let gitOperationQueue = GitOperationQueue()
    private let recentRepositoriesKey = "orbit.recentRepositories"
    private var activeRepositoryLoadID: UUID?
    @ObservationIgnored var repositorySessionGeneration: UInt = 0
    var liveRefreshTask: Task<Void, Never>?
    @ObservationIgnored var diffLoadTask: Task<GitFileDiff, Error>?
    @ObservationIgnored var imageDiffLoadTask: Task<GitImageDiffPreview, Error>?
    @ObservationIgnored var commitDetailLoadTask: Task<GitCommitDetail, Error>?
    @ObservationIgnored var commitFileLoadTask: Task<GitFileDiff, Error>?
    @ObservationIgnored var commitDetailCache: [String: GitCommitDetail] = [:]
    @ObservationIgnored var commitDetailCacheOrder: [String] = []
    @ObservationIgnored var commitDetailCacheBytes: [String: Int] = [:]
    @ObservationIgnored var commitFileDiffCache: [String: GitFileDiff] = [:]
    @ObservationIgnored var commitFileDiffCacheOrder: [String] = []
    @ObservationIgnored var commitFileDiffCacheBytes: [String: Int] = [:]
    @ObservationIgnored var pendingLiveRefreshPaths: Set<String> = []
    @ObservationIgnored var deferredLiveRefreshPaths: Set<String> = []
    @ObservationIgnored var pendingRefreshScope: RepositoryRefreshScope = []
    @ObservationIgnored var pendingRefreshSelectedDiff = false
    @ObservationIgnored var isRefreshCoordinatorRunning = false
    @ObservationIgnored var remoteCheckTask: Task<Void, Never>?
    @ObservationIgnored var repositoryOpenTask: Task<Void, Never>?
    @ObservationIgnored var liveRefreshGeneration: UInt = 0
    @ObservationIgnored var diffLoadGeneration: UInt = 0
    @ObservationIgnored var commitDetailLoadGeneration: UInt = 0
    @ObservationIgnored var commitFileLoadGeneration: UInt = 0
    @ObservationIgnored var stashPreviewGeneration: UInt = 0
    @ObservationIgnored private var securityScopedURLs: [String: URL] = [:]
    private let repositoryBookmarksKey = "orbit.repositoryBookmarks"
    init() {
        if let rawSection = UserDefaults.standard.string(forKey: "orbit.lastSelectedSection"),
           let savedSection = SidebarSection(rawValue: rawSection) {
            selectedSection = savedSection
        }
        if let data = UserDefaults.standard.data(forKey: recentRepositoriesKey),
           let savedRepositories = try? JSONDecoder().decode([RecentRepository].self, from: data) {
            recentRepositories = savedRepositories
        }
        recentCommitMessages = UserDefaults.standard.stringArray(forKey: "orbit.recentCommitMessages") ?? []
        if let savedPath = UserDefaults.standard.string(forKey: "orbit.lastRepositoryPath") {
            repository = RepositorySummary(
                name: URL(fileURLWithPath: savedPath).lastPathComponent,
                path: savedPath,
                branch: "检测中…",
                changedFileCount: 0,
                stagedFileCount: 0,
                aheadCount: 0,
                behindCount: 0,
                needsPublish: false
            )
            if !recentRepositories.contains(where: { $0.path == savedPath }) {
                recentRepositories.append(RecentRepository(
                    name: URL(fileURLWithPath: savedPath).lastPathComponent,
                    path: savedPath,
                    lastOpened: .distantPast
                ))
                persistRecentRepositories()
            }
        }
    }

    func loadEnvironment() async {
        do {
            gitVersion = try await gitRunner.version()
        } catch {
            gitVersion = "Git 不可用"
            present(error: error, title: "无法使用版本管理工具")
        }

        if let repository {
            await openRepository(URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func openRepository(_ url: URL, selectOverview: Bool = false) async {
        let accessURL = resolveRepositoryAccessURL(url)
        let performanceToken = PerformanceDiagnostics.begin(category: "Repository", name: "open-or-switch")
        defer { PerformanceDiagnostics.end(performanceToken, cancelled: Task.isCancelled) }
        let loadID = UUID()
        repositorySessionGeneration &+= 1
        let sessionGeneration = repositorySessionGeneration
        activeRepositoryLoadID = loadID
        let requestedPath = accessURL.standardizedFileURL.path
        if repository?.path != requestedPath {
            cancelRepositoryScopedWork()
        }
        isLoadingRepository = true
        errorMessage = nil
        defer {
            if activeRepositoryLoadID == loadID {
                isLoadingRepository = false
            }
        }

        do {
            try Task.checkCancellation()
            let root = try await gitRunner.repositoryRoot(at: accessURL)
            try Task.checkCancellation()
            let shouldCheckRemote = selectOverview
                || repository?.path != root.path
                || repository?.branch == "检测中…"
            async let branchTask = gitRunner.currentBranch(at: root)
            async let statusTask = gitRunner.status(at: root)
            async let commitsTask = gitRunner.commits(at: root)
            async let incomingCommitsTask: [GitCommitSummary] = (try? await gitRunner.incomingCommits(at: root)) ?? []
            async let branchesTask: [GitBranchSummary] = (try? await gitRunner.branches(at: root)) ?? []
            async let remoteBranchesTask: [GitRemoteBranchSummary] = (try? await gitRunner.remoteBranches(at: root)) ?? []
            async let stashesTask: [GitStashSummary] = (try? await gitRunner.stashList(at: root)) ?? []
            async let worktreesTask: [GitWorktreeSummary] = (try? await gitRunner.worktrees(at: root)) ?? []
            async let remoteInfoTask: GitRemoteInfo? = try? await gitRunner.remoteInfo(at: root)
            async let trackingTask: (ahead: Int, behind: Int)? = try? await gitRunner.aheadBehind(at: root)
            async let identityTask: GitIdentity = (try? await gitRunner.identity(at: root)) ?? GitIdentity(name: "", email: "")

            let branch = try await branchTask
            let loadedStatus = try await statusTask
            let loadedCommits = try await commitsTask
            let loadedIncomingCommits = await incomingCommitsTask
            let loadedBranches = await branchesTask
            let loadedRemoteBranches = await remoteBranchesTask
            let loadedStashes = await stashesTask
            let loadedWorktrees = await worktreesTask
            let loadedRemoteInfo = await remoteInfoTask
            let tracking = await trackingTask
            let loadedIdentity = await identityTask

            guard !Task.isCancelled,
                  activeRepositoryLoadID == loadID,
                  repositorySessionGeneration == sessionGeneration else { return }

            let isSameRepository = repository?.path == root.path
            let previousSelectedCommitID = selectedCommit?.id
            let previousSelectedFilePath = selectedFile?.path

            let applyToken = PerformanceDiagnostics.begin(category: "Repository", name: "state-apply")
            status = loadedStatus
            commits = loadedCommits
            incomingCommits = loadedIncomingCommits
            branches = loadedBranches
            remoteBranches = loadedRemoteBranches
            stashes = loadedStashes
            worktrees = loadedWorktrees
            remoteInfo = loadedRemoteInfo ?? nil
            gitIdentity = loadedIdentity
            hasMoreCommits = loadedCommits.count == 60
            if isSameRepository {
                selectedCommit = (loadedIncomingCommits + loadedCommits).first { $0.id == previousSelectedCommitID }
                selectedFile = loadedStatus.files.first { $0.path == previousSelectedFilePath }
                if selectedFile == nil { selectedFileDiff = nil }
            } else {
                selectedCommit = nil
                selectedCommitDetail = nil
                selectedCommitFilePath = nil
                selectedCommitFileDiff = nil
                selectedFile = nil
                selectedFileDiff = nil
            }
            repository = RepositorySummary(
                name: root.lastPathComponent,
                path: root.path,
                branch: branch,
                changedFileCount: loadedStatus.changedFileCount,
                stagedFileCount: loadedStatus.stagedFileCount,
                aheadCount: tracking?.ahead ?? 0,
                behindCount: tracking?.behind ?? 0,
                needsPublish: loadedBranches.first(where: \.isCurrent)?.needsPublish ?? false
            )
            PerformanceDiagnostics.end(applyToken)
            await refreshRepositoryHealth(
                at: root,
                status: loadedStatus,
                worktrees: loadedWorktrees,
                stashes: loadedStashes
            )
            UserDefaults.standard.set(root.path, forKey: "orbit.lastRepositoryPath")
            rememberRepository(root)
            startWatchingRepository(at: root)
            if shouldCheckRemote { scheduleRemoteUpdateCheck(for: root) }
            if selectOverview { selectedSection = .overview }
        } catch is CancellationError {
            return
        } catch {
            if activeRepositoryLoadID == loadID {
                if case GitRunnerError.notARepository = error {
                    await requestExistingRepositoryAccess(accessURL)
                } else {
                    present(error: error, title: "无法打开仓库")
                }
            }
        }
    }

    func refreshRepository() async {
        guard let repository else { return }
        await openRepository(URL(fileURLWithPath: repository.path, isDirectory: true))
    }

    func shutdown() {
        activeRepositoryLoadID = nil
        repositoryOpenTask?.cancel()
        repositoryOpenTask = nil
        cancelRepositoryScopedWork()
    }

    func cancelRepositoryScopedWork() {
        diffLoadGeneration &+= 1
        commitDetailLoadGeneration &+= 1
        commitFileLoadGeneration &+= 1
        stashPreviewGeneration &+= 1
        diffLoadTask?.cancel()
        imageDiffLoadTask?.cancel()
        commitDetailLoadTask?.cancel()
        commitFileLoadTask?.cancel()
        liveRefreshTask?.cancel()
        remoteCheckTask?.cancel()
        repositoryWatcher.stop()
        pendingLiveRefreshPaths.removeAll(keepingCapacity: true)
        deferredLiveRefreshPaths.removeAll(keepingCapacity: true)
        pendingRefreshScope = []
        commitDetailCache.removeAll(keepingCapacity: true)
        commitDetailCacheOrder.removeAll(keepingCapacity: true)
        commitDetailCacheBytes.removeAll(keepingCapacity: true)
        commitFileDiffCache.removeAll(keepingCapacity: true)
        commitFileDiffCacheOrder.removeAll(keepingCapacity: true)
        commitFileDiffCacheBytes.removeAll(keepingCapacity: true)
        selectedFileDiff = nil
        selectedFileDiffError = nil
        selectedImageDiffPreview = nil
        selectedCommitFileDiff = nil
        workflows.stashPreview = nil
        workflows.stashFileDiff = nil
        isDiffFocusPresented = false
        isLoadingDiff = false
        isLoadingCommitDetail = false
        isLoadingCommitFileDiff = false
        isLoadingImageDiff = false
    }

    func stage(_ file: GitFileStatus) async {
        await stage([file])
    }

    func stage(_ files: [GitFileStatus]) async {
        guard let repository else { return }
        let paths = Array(Set(files.map(\.path)))
        guard !paths.isEmpty else { return }
        let message = paths.count == 1 ? "已将 \(paths[0]) 加入暂存区" : "已将 \(paths.count) 个文件加入暂存区"
        await performAction(successTitle: "内容已移入暂存区", successMessage: message, kind: .stage, refreshScope: .workingCopy) {
            try await self.gitRunner.stage(paths, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func selectFile(_ file: GitFileStatus, staged: Bool) async {
        diffLoadGeneration &+= 1
        let loadGeneration = diffLoadGeneration
        diffLoadTask?.cancel()
        imageDiffLoadTask?.cancel()
        isLoadingDiff = false
        isLoadingImageDiff = false
        selectedFile = file
        selectedFileDiffIsStaged = staged
        selectedCommit = nil
        selectedCommitDetail = nil
        selectedFileDiff = nil
        selectedFileDiffError = nil
        selectedImageDiffPreview = nil
        isDiffFocusPresented = false
        guard !file.path.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") else {
            isLoadingDiff = false
            return
        }
        guard let repository else {
            isLoadingDiff = false
            return
        }

        isLoadingDiff = true
        defer {
            if diffLoadGeneration == loadGeneration {
                isLoadingDiff = false
            }
        }
        let task = Task {
            try await gitRunner.diff(
                for: file,
                staged: staged,
                at: URL(fileURLWithPath: repository.path, isDirectory: true)
            )
        }
        diffLoadTask = task
        do {
            let diff = try await task.value
            guard diffLoadGeneration == loadGeneration, selectedFile?.path == file.path else { return }
            selectedFileDiff = diff
            selectedFileDiffError = nil
            if diff.contentKind == .image {
                isLoadingImageDiff = true
                let root = URL(fileURLWithPath: repository.path, isDirectory: true)
                let imageTask = Task { try await gitRunner.imageDiffPreview(path: file.path, at: root) }
                imageDiffLoadTask = imageTask
                selectedImageDiffPreview = try? await imageTask.value
                if diffLoadGeneration == loadGeneration, selectedFile?.path == file.path {
                    isLoadingImageDiff = false
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard diffLoadGeneration == loadGeneration, selectedFile?.path == file.path else { return }
            selectedFileDiffError = error.localizedDescription
        }
    }

    func selectCommit(_ commit: GitCommitSummary) async {
        commitDetailLoadGeneration &+= 1
        let loadGeneration = commitDetailLoadGeneration
        commitDetailLoadTask?.cancel()
        commitFileLoadTask?.cancel()
        selectedCommit = commit
        selectedCommitDetail = nil
        selectedCommitFilePath = nil
        selectedCommitFileDiff = nil
        selectedFile = nil
        selectedFileDiff = nil
        selectedImageDiffPreview = nil
        guard let repository else { return }

        if let cached = commitDetailCache[commit.id] {
            isLoadingCommitDetail = false
            selectedCommitDetail = cached
            touchCommitDetailCache(commit.id)
            return
        }
        isLoadingCommitDetail = true
        defer {
            if commitDetailLoadGeneration == loadGeneration {
                isLoadingCommitDetail = false
            }
        }
        let task = Task {
            try await gitRunner.commitDetail(
                hash: commit.hash,
                at: URL(fileURLWithPath: repository.path, isDirectory: true)
            )
        }
        commitDetailLoadTask = task
        do {
            let detail = try await task.value
            guard commitDetailLoadGeneration == loadGeneration, selectedCommit?.id == commit.id else { return }
            selectedCommitDetail = detail
            commitDetailCache[commit.id] = detail
            touchCommitDetailCache(commit.id)
        } catch is CancellationError {
            return
        } catch {
            present(error: error, title: "无法读取提交内容")
        }
    }

    func unstage(_ file: GitFileStatus) async {
        await unstage([file])
    }

    func unstage(_ files: [GitFileStatus]) async {
        guard let repository else { return }
        let paths = Array(Set(files.map(\.path)))
        guard !paths.isEmpty else { return }
        let message = paths.count == 1 ? "已将 \(paths[0]) 移回未暂存区" : "已将 \(paths.count) 个文件移回未暂存区"
        await performAction(successTitle: "内容已移出暂存区", successMessage: message, kind: .stage, refreshScope: .workingCopy) {
            try await self.gitRunner.unstage(paths, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func stageAll() async {
        guard let repository else { return }
        await performAction(successTitle: "全部内容已暂存", successMessage: "所有工作区变更已准备好提交。", kind: .stage, refreshScope: .workingCopy) {
            try await self.gitRunner.stageAll(at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func commit(message: String) async {
        guard let repository else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            presentMessage("请先填写提交摘要。", title: "提交信息不完整")
            return
        }
        await performAction(successTitle: "提交已创建", successMessage: "暂存内容已经写入本地提交历史。", kind: .commit, refreshScope: [.workingCopy, .history, .remote]) {
            try await self.gitRunner.commit(message: trimmedMessage, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func createBranch(name: String) async {
        guard let repository else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentMessage("请输入分支名称。", title: "分支名称不能为空")
            return
        }
        await performAction(successMessage: "已创建并切换到 \(trimmedName)", kind: .branch, refreshScope: [.workingCopy, .history, .branches, .remote]) {
            try await self.gitRunner.createBranch(trimmedName, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func checkout(_ branch: GitBranchSummary) async {
        guard let repository else { return }
        await performAction(successMessage: "已切换到 \(branch.name)", kind: .branch, refreshScope: [.workingCopy, .history, .branches, .remote]) {
            try await self.gitRunner.checkout(branch: branch.name, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func checkoutRemote(_ branch: GitRemoteBranchSummary) async {
        guard let repository else { return }
        await performAction(successMessage: "已检出远程分支 \(branch.remote)/\(branch.name)", kind: .branch, refreshScope: [.workingCopy, .history, .branches, .remote]) {
            try await self.gitRunner.checkoutRemote(branch, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func fetch() async {
        guard let repository else { return }
        await performAction(successTitle: "远程状态已更新", successMessage: "已检查所有远程分支的最新状态。", kind: .fetch, refreshScope: [.branches, .remote]) {
            try await self.gitRunner.fetch(at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }
    func push() async {
        guard let repository else { return }
        await performAction(successTitle: "本地提交已上传", successMessage: "远程分支已经更新。", kind: .push, refreshScope: [.branches, .remote]) {
            try await self.gitRunner.push(at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    /// Publishes the currently checked-out local branch for the first time.
    /// A branch without an upstream reports no ahead commits, so this action
    /// must be exposed independently from the regular Push button.
    func publishCurrentBranch() async {
        guard let repository else { return }
        guard let currentBranch = branches.first(where: \.isCurrent) else {
            presentMessage(
                AppLanguage.text("当前分支仍在读取中，请稍候再试。", "The current branch is still loading. Try again in a moment."),
                title: AppLanguage.text("无法发布分支", "Unable to publish branch")
            )
            return
        }
        guard currentBranch.needsPublish else {
            await push()
            return
        }
        guard let remoteInfo else {
            presentMessage(
                AppLanguage.text("请先为仓库配置远程仓库。", "Add a remote repository before publishing this branch."),
                title: AppLanguage.text("没有可用的远程仓库", "No remote repository")
            )
            return
        }

        let root = URL(fileURLWithPath: repository.path, isDirectory: true)
        let branchName = currentBranch.name
        let remoteName = remoteInfo.name
        await performAction(
            successTitle: AppLanguage.text("分支已发布", "Branch published"),
            successMessage: AppLanguage.text(
                "已将 \(branchName) 推送到 \(remoteName)/\(branchName)，并设置为跟踪分支。",
                "\(branchName) was pushed to \(remoteName)/\(branchName) and is now tracking it."
            ),
            kind: .push,
            refreshScope: [.branches, .remote]
        ) {
            try await self.gitRunner.publishCurrentBranch(
                branch: branchName,
                remote: remoteName,
                at: root
            )
        }
    }

    func stash(message: String?) async {
        guard let repository else { return }
        await performAction(successTitle: "工作内容已临时保存", successMessage: "稍后可以从临时保存列表恢复。", refreshScope: [.workingCopy, .stashes]) {
            try await self.gitRunner.stashPush(message: message, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func applyStash(_ stash: GitStashSummary) async {
        guard let repository else { return }
        await performAction(successMessage: "已恢复临时保存的内容", warnOnConflicts: true, refreshScope: [.workingCopy, .stashes]) {
            try await self.gitRunner.stashApply(stash.reference, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func popStash(_ stash: GitStashSummary) async {
        guard let repository else { return }
        await performAction(successMessage: "已恢复并移除这条临时保存", warnOnConflicts: true, refreshScope: [.workingCopy, .stashes]) {
            try await self.gitRunner.stashPop(stash.reference, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func dropStash(_ stash: GitStashSummary) async {
        guard let repository else { return }
        await performAction(successMessage: "已删除 \(stash.reference)", refreshScope: .stashes) {
            try await self.gitRunner.stashDrop(stash.reference, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func addWorktree(path: String, branch: String) async {
        guard let repository else { return }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedBranch.isEmpty else {
            presentMessage("请填写工作目录路径和分支名称。", title: "并行工作区信息不完整")
            return
        }
        await performAction(successTitle: "并行工作区已创建", successMessage: "现在可以同时处理另一条分支。", refreshScope: .worktrees) {
            try await self.gitRunner.worktreeAdd(path: trimmedPath, branch: trimmedBranch, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func openWorktree(_ worktree: GitWorktreeSummary) {
        NSWorkspace.shared.open(URL(fileURLWithPath: worktree.path, isDirectory: true))
    }

    func removeWorktree(_ worktree: GitWorktreeSummary) async {
        guard let repository, !worktree.isMain else {
            presentMessage("主工作区不能从这里删除。", title: "无法删除")
            return
        }
        await performAction(successTitle: "并行工作区已删除", successMessage: "对应工作目录已从仓库中移除。", refreshScope: .worktrees) {
            try await self.gitRunner.worktreeRemove(path: worktree.path, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func resolveUsingOurs(_ file: GitFileStatus) async {
        guard let repository else { return }
        await performAction(successMessage: "已保留当前分支中的版本：\(file.path)", refreshScope: .workingCopy) {
            try await self.gitRunner.resolveUsingOurs(file.path, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func resolveUsingTheirs(_ file: GitFileStatus) async {
        guard let repository else { return }
        await performAction(successMessage: "已采用合入分支中的版本：\(file.path)", refreshScope: .workingCopy) {
            try await self.gitRunner.resolveUsingTheirs(file.path, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }

    func markResolved(_ file: GitFileStatus) async {
        guard let repository else { return }
        await performAction(successMessage: "已标记 \(file.path) 为已解决", refreshScope: .workingCopy) {
            try await self.gitRunner.markResolved(file.path, at: URL(fileURLWithPath: repository.path, isDirectory: true))
        }
    }
    @discardableResult
    func performAction(
        successTitle: String = "操作已完成",
        successMessage: String,
        kind: GitOperationKind = .other,
        operationTitle: String? = nil,
        warnOnConflicts: Bool = false,
        refreshScope: RepositoryRefreshScope = .all,
        operation: @escaping @Sendable () async throws -> Void
    ) async -> Bool {
        guard let repository else { return false }
        let recordID = beginGitOperation(
            kind: kind,
            title: operationTitle ?? successTitle,
            repositoryPath: repository.path
        )
        errorMessage = nil
        feedback = nil
        await gitOperationQueue.acquire(repositoryPath: repository.path)
        activateGitOperation(recordID)

        do {
            try await operation()
            updateGitOperation(recordID, phase: .refreshing)
            await refresh(scope: refreshScope)
            cancelPendingLiveRefresh()
            if warnOnConflicts {
                let conflictCount = status.files.filter(\.hasConflict).count
                actionMessage = conflictCount > 0
                    ? "\(successMessage) · 检测到 \(conflictCount) 个冲突文件"
                    : successMessage
                feedback = AppFeedback(
                    kind: conflictCount > 0 ? .warning : .success,
                    title: conflictCount > 0 ? "内容已恢复，但需要处理冲突" : successTitle,
                    message: conflictCount > 0 ? "检测到 \(conflictCount) 个冲突文件，请前往工作区变更处理。" : successMessage
                )
            } else {
                actionMessage = successMessage
                feedback = AppFeedback(kind: .success, title: successTitle, message: successMessage)
            }
            finishGitOperation(recordID, succeeded: true, detail: successMessage)
            await gitOperationQueue.release(repositoryPath: repository.path)
            scheduleDeferredLiveRefreshIfNeeded()
            return true
        } catch {
            let detail = (error as? GitRunnerError)?.technicalDetails ?? error.localizedDescription
            finishGitOperation(recordID, succeeded: false, detail: detail)
            await gitOperationQueue.release(repositoryPath: repository.path)
            present(error: error, title: "操作未完成")
            scheduleDeferredLiveRefreshIfNeeded()
            return false
        }
    }
    private func rememberRepository(_ root: URL) {
        let newEntry = RecentRepository(name: root.lastPathComponent, path: root.path, lastOpened: Date())
        recentRepositories.removeAll { $0.path == root.path }
        recentRepositories.insert(newEntry, at: 0)
        persistRecentRepositories()
    }

    private func resolveRepositoryAccessURL(_ url: URL) -> URL {
        let path = url.standardizedFileURL.path
        if let existing = securityScopedURLs[path] { return existing }
        let bookmarks = UserDefaults.standard.dictionary(forKey: repositoryBookmarksKey) as? [String: Data]
        if let data = bookmarks?[path] {
            var stale = false
            do {
                let resolved = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                if resolved.startAccessingSecurityScopedResource() { securityScopedURLs[path] = resolved }
                if stale { saveRepositoryBookmark(for: resolved) }
                return resolved
            } catch {
                UserDefaults.standard.set(nil, forKey: repositoryBookmarksKey)
            }
        }
        return url
    }

    func saveRepositoryBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var bookmarks = UserDefaults.standard.dictionary(forKey: repositoryBookmarksKey) as? [String: Data] ?? [:]
        bookmarks[url.standardizedFileURL.path] = data
        UserDefaults.standard.set(bookmarks, forKey: repositoryBookmarksKey)
    }

    private func requestExistingRepositoryAccess(_ url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else {
            presentMessage("原项目路径已不存在，请从新的位置打开仓库。", title: "项目路径不可用")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "授权访问已有项目"
        panel.message = "只需授权一次，无需重新导入项目。"
        panel.prompt = "授权并打开"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        saveRepositoryBookmark(for: selectedURL)
        beginOpeningRepository(selectedURL)
    }

    func persistRecentRepositories() {
        guard let data = try? JSONEncoder().encode(recentRepositories) else { return }
        UserDefaults.standard.set(data, forKey: recentRepositoriesKey)
    }
}
