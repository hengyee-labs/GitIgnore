import Foundation

enum GitTemporaryFileCleanup {
    /// 只清理 GitIgnore 自己创建的过期 Diff 目录。
    ///
    /// Diff 阅读器通常会在 `deinit` 中删除目录，但强制退出或崩溃可能
    /// 中断清理。这里跳过近期目录，避免影响仍在使用中的阅读器。
    static func removeStaleDiffDirectories(
        olderThan ageLimit: TimeInterval = 60 * 60,
        now: Date = Date()
    ) {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries where entry.lastPathComponent.hasPrefix("GitIgnore-Diff-") {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true,
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > ageLimit else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}

struct GitCommandOutput: Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32
}

enum GitRunnerError: LocalizedError, Sendable {
    case commandFailed(arguments: [String], message: String, status: Int32)
    case notARepository(URL)
    case outputLimitExceeded(arguments: [String], limitBytes: Int)
    case timedOut(arguments: [String], seconds: Double)
    case indexLocked(path: String, activeOwner: String?)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, message, _):
            return Self.friendlyDescription(arguments: arguments, message: message)
        case let .notARepository(url):
            return "“\(url.lastPathComponent)”不是有效的 Git 仓库。"
        case let .outputLimitExceeded(_, limitBytes):
            return "Git 返回的数据超过 \(ByteCountFormatter.string(fromByteCount: Int64(limitBytes), countStyle: .file))，已停止读取以保护内存。"
        case let .timedOut(_, seconds):
            return "Git 操作超过 \(Int(seconds.rounded())) 秒仍未完成，已安全停止。"
        case let .indexLocked(_, activeOwner):
            return activeOwner == nil
                ? "检测到刚生成的仓库锁，请稍候一秒后重试。"
                : "仓库正在被另一个 Git 进程写入，已阻止并发操作。"
        }
    }

    var technicalDetails: String? {
        switch self {
        case let .commandFailed(arguments, message, status):
            let detail = message.isEmpty ? "没有更多输出" : message
            return "退出状态：\(status)\n执行参数：\(arguments.joined(separator: " "))\n\(detail)"
        case .notARepository:
            return nil
        case let .outputLimitExceeded(arguments, limitBytes):
            return "执行参数：\(arguments.joined(separator: " "))\n输出上限：\(limitBytes) bytes"
        case let .timedOut(arguments, seconds):
            return "执行参数：\(arguments.joined(separator: " "))\n超时时间：\(seconds) 秒"
        case let .indexLocked(path, activeOwner):
            return "锁文件：\(path)\n占用进程：\(activeOwner ?? "未发现；锁文件过新，为避免误删暂未处理")"
        }
    }

    private static func friendlyDescription(arguments: [String], message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("couldn't connect") || normalized.contains("unable to access") || normalized.contains("failed to connect") {
            return "无法连接远程仓库。请检查网络、仓库地址或内网连接后重试。"
        }
        if normalized.contains("authentication failed") || normalized.contains("permission denied") || normalized.contains("could not read username") {
            return "远程仓库身份验证失败。请检查账号凭据或访问权限。"
        }
        if normalized.contains("non-fast-forward") || normalized.contains("fetch first") {
            return "远程仓库包含更新，当前内容暂时不能直接上传。请先拉取并处理差异。"
        }
        if normalized.contains("no tracking information") || normalized.contains("no upstream") {
            return "当前分支还没有关联远程分支，请先设置跟踪分支。"
        }
        if normalized.contains("would be overwritten") || normalized.contains("local changes") {
            return "本地尚有未处理的变更，本次操作可能覆盖内容，已为你停止。"
        }
        if normalized.contains("conflict") {
            return "操作产生了内容冲突，请前往工作区变更处理冲突文件。"
        }
        if normalized.contains("nothing to commit") {
            return "没有可以提交的新内容。"
        }

        if arguments.contains("pull") { return "拉取远程更新失败，请检查分支状态后重试。" }
        if arguments.contains("push") { return "上传本地提交失败，请检查远程权限和分支状态。" }
        if arguments.contains("fetch") { return "检查远程更新失败，请检查网络和仓库地址。" }
        if arguments.contains("commit") { return "创建提交失败，请检查提交身份和暂存内容。" }
        return "操作未完成。请检查仓库状态后重试。"
    }
}

actor GitRunner {
    private let executableURL = URL(fileURLWithPath: "/usr/bin/git")
    private var gitDirectoryCache: [String: URL] = [:]
    private let readLimiter = AsyncSemaphore(value: 4)
    private let writeLimiter = AsyncSemaphore(value: 1)

    func gitDirectory(at repositoryURL: URL) async throws -> URL {
        let repositoryPath = repositoryURL.standardizedFileURL.path
        if let cachedDirectory = gitDirectoryCache[repositoryPath] {
            return cachedDirectory
        }

        let output = try await run(arguments: [
            "-C", repositoryPath, "rev-parse", "--absolute-git-dir"
        ])
        let path = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw GitRunnerError.notARepository(repositoryURL) }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        gitDirectoryCache[repositoryPath] = directory
        return directory
    }

    func version() async throws -> String {
        let output = try await run(arguments: ["--version"])
        return output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func repositoryRoot(at url: URL) async throws -> URL {
        do {
            let output = try await run(arguments: ["-C", url.path, "rev-parse", "--show-toplevel"])
            let path = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw GitRunnerError.notARepository(url) }
            return URL(fileURLWithPath: path, isDirectory: true)
        } catch {
            throw GitRunnerError.notARepository(url)
        }
    }

    func currentBranch(at repositoryURL: URL) async throws -> String {
        let output = try await run(arguments: ["-C", repositoryURL.path, "branch", "--show-current"])
        let branch = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? "游离状态" : branch
    }

    func identity(at repositoryURL: URL) async throws -> GitIdentity {
        async let nameOutput = run(
            arguments: ["-C", repositoryURL.path, "config", "--get", "user.name"],
            acceptedStatuses: [0, 1]
        )
        async let emailOutput = run(
            arguments: ["-C", repositoryURL.path, "config", "--get", "user.email"],
            acceptedStatuses: [0, 1]
        )
        let name = try await nameOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = try await emailOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitIdentity(name: name, email: email)
    }

    func status(at repositoryURL: URL) async throws -> GitStatusSummary {
        let output = try await run(arguments: ["-C", repositoryURL.path, "status", "--porcelain=v1", "-z"])
        let fields = output.standardOutput.split(separator: "\0", omittingEmptySubsequences: true)
        var files: [GitFileStatus] = []
        var index = 0

        while index < fields.count {
            let raw = String(fields[index])
            guard raw.count >= 3 else {
                index += 1
                continue
            }

            let codes = Array(raw.prefix(2))
            guard codes.count == 2 else {
                index += 1
                continue
            }

            var path = String(raw.dropFirst(3))
            let indexCode = codes[0]
            let worktreeCode = codes[1]
            let isRename = indexCode == "R" || worktreeCode == "R" || indexCode == "C" || worktreeCode == "C"
            if isRename, index + 1 < fields.count {
                path = String(fields[index + 1])
                index += 1
            }

            let isConflict = indexCode == "U" || worktreeCode == "U"
                || (indexCode == worktreeCode && (indexCode == "A" || indexCode == "D"))
            let kindCode: Character = [indexCode, worktreeCode].first { $0 != " " && $0 != "?" } ?? "?"
            let kind = isConflict ? GitFileChangeKind.conflicted
                : (GitFileChangeKind(rawValue: String(kindCode)) ?? .modified)
            files.append(GitFileStatus(
                id: "\(path)-\(index)",
                path: path,
                indexCode: indexCode,
                worktreeCode: worktreeCode,
                kind: kind
            ))
            index += 1
        }

        return GitStatusSummary(files: files)
    }

    func commits(at repositoryURL: URL, limit: Int = 60, skip: Int = 0) async throws -> [GitCommitSummary] {
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "log", "--all", "--topo-order",
            "--date=format:%Y-%m-%d %H:%M", "--pretty=format:\(Self.commitLogFormat)",
            "--skip=\(skip)", "-n", "\(limit)"
        ])
        return parseCommitSummaries(output.standardOutput)
    }

    func incomingCommits(at repositoryURL: URL, limit: Int = 200) async throws -> [GitCommitSummary] {
        let output = try await run(
            arguments: [
                "-C", repositoryURL.path, "log", "--topo-order", "--date=format:%Y-%m-%d %H:%M",
                "--pretty=format:\(Self.commitLogFormat)", "-n", "\(limit)", "HEAD..@{upstream}"
            ],
            acceptedStatuses: [0, 128]
        )
        guard output.terminationStatus == 0 else { return [] }
        return parseCommitSummaries(output.standardOutput)
    }

    private static let commitLogFormat = "%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1f%D%x1f%P%x1e"

    private func parseCommitSummaries(_ text: String) -> [GitCommitSummary] {
        text
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record
                    .split(separator: "\u{1f}", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard fields.count >= 7 else { return nil }
                let refs = fields[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return GitCommitSummary(
                    hash: fields[0],
                    shortHash: fields[1],
                    subject: fields[4],
                    author: fields[2],
                    dateText: fields[3],
                    refs: refs,
                    parents: fields[6].split(separator: " ").map(String.init)
                )
            }
    }

    func commitDetail(hash: String, at repositoryURL: URL) async throws -> GitCommitDetail {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        async let messageOutput = run(arguments: [
            "-C", repositoryURL.path, "show", "-s", "--format=%B", normalizedHash, "--"
        ])
        async let filesOutput = run(arguments: [
            "-C", repositoryURL.path, "show", "--format=", "--name-status", "--find-renames", normalizedHash, "--"
        ])
        let message = try await messageOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileLines = try await filesOutput.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)

        let files = fileLines.compactMap { line -> GitCommitFileChange? in
            let fields = line.split(separator: "\t").map(String.init)
            guard let status = fields.first, let path = fields.last, !path.isEmpty else { return nil }
            let kind: GitFileChangeKind
            switch status.first {
            case "A": kind = .added
            case "D": kind = .deleted
            case "R": kind = .renamed
            case "U": kind = .conflicted
            default: kind = .modified
            }
            return GitCommitFileChange(path: path, kind: kind)
        }
        return GitCommitDetail(
            message: message,
            files: files
        )
    }

    func branches(at repositoryURL: URL) async throws -> [GitBranchSummary] {
        let format = "%(HEAD)%09%(refname:short)%09%(upstream:short)"
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "for-each-ref", "--format=\(format)", "refs/heads"
        ])

        return output.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .compactMap { record in
                let fields = record.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 3, !fields[1].isEmpty else { return nil }
                return GitBranchSummary(
                    name: fields[1],
                    isCurrent: fields[0] == "*",
                    upstream: fields[2].isEmpty ? nil : fields[2]
                )
            }
    }

    func remoteBranches(at repositoryURL: URL) async throws -> [GitRemoteBranchSummary] {
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "for-each-ref", "--format=%(refname:short)%09%(upstream:short)", "refs/remotes"
        ])
        return output.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .compactMap { record in
                let fields = record.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let fullName = fields.first, fullName.contains("/") else { return nil }
                let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[1] != "HEAD" else { return nil }
                return GitRemoteBranchSummary(
                    name: parts[1],
                    remote: parts[0],
                    trackingBranch: fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
                )
            }
    }

    func aheadBehind(at repositoryURL: URL) async throws -> (ahead: Int, behind: Int) {
        let output = try await run(
            arguments: ["-C", repositoryURL.path, "rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            acceptedStatuses: [0, 128]
        )
        guard output.terminationStatus == 0 else { return (0, 0) }
        let values = output.standardOutput.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard values.count >= 2 else { return (0, 0) }
        return (values[0], values[1])
    }

    func remoteInfo(at repositoryURL: URL) async throws -> GitRemoteInfo? {
        let remotesOutput = try await run(
            arguments: ["-C", repositoryURL.path, "remote"],
            acceptedStatuses: [0]
        )
        let remoteNames = remotesOutput.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
        let remoteName = remoteNames.first(where: { $0 == "origin" }) ?? remoteNames.first
        guard let remoteName else { return nil }
        let output = try await run(
            arguments: ["-C", repositoryURL.path, "remote", "get-url", remoteName],
            acceptedStatuses: [0, 2]
        )
        let raw = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized: String
        if raw.hasPrefix("git@"), let colon = raw.firstIndex(of: ":") {
            let hostStart = raw.index(raw.startIndex, offsetBy: 4)
            normalized = "https://\(raw[hostStart..<colon])/\(raw[raw.index(after: colon)...])"
        } else if raw.hasPrefix("ssh://") {
            normalized = raw.replacingOccurrences(of: "ssh://git@", with: "https://")
        } else {
            normalized = raw
        }
        let clean = normalized.hasSuffix(".git") ? String(normalized.dropLast(4)) : normalized
        let host = URL(string: clean)?.host?.lowercased() ?? ""
        let provider: String
        if host.contains("github") { provider = "GitHub" }
        else if host.contains("gitlab") { provider = "GitLab" }
        else if host.contains("gitee") { provider = "Gitee" }
        else { provider = "远程仓库" }
        return GitRemoteInfo(name: remoteName, url: raw, webURL: URL(string: clean), provider: provider)
    }

    func stashList(at repositoryURL: URL) async throws -> [GitStashSummary] {
        let format = "%gd%x1f%gs%x1f%ci%x1e"
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "stash", "list", "--pretty=format:\(format)"
        ])
        return output.standardOutput
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 3 else { return nil }
                let subject = fields[1]
                let branch: String
                if let range = subject.range(of: "On ") {
                    branch = String(subject[range.upperBound...].split(separator: ":", maxSplits: 1).first ?? "")
                } else if let range = subject.range(of: "WIP on ") {
                    branch = String(subject[range.upperBound...].split(separator: ":", maxSplits: 1).first ?? "")
                } else { branch = "当前分支" }
                return GitStashSummary(reference: fields[0], branch: branch, message: subject, dateText: String(fields[2].prefix(16)))
            }
    }

    func stashApply(_ reference: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "stash", "apply", reference])
    }

    func stashPop(_ reference: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "stash", "pop", reference])
    }

    func stashDrop(_ reference: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "stash", "drop", reference])
    }

    func worktrees(at repositoryURL: URL) async throws -> [GitWorktreeSummary] {
        let output = try await run(arguments: ["-C", repositoryURL.path, "worktree", "list", "--porcelain"])
        let blocks = output.standardOutput.components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.split(separator: "\n").map(String.init)
            guard let pathLine = lines.first(where: { $0.hasPrefix("worktree ") }) else { return nil }
            let path = String(pathLine.dropFirst("worktree ".count))
            let head = lines.first(where: { $0.hasPrefix("HEAD ") }).map { String($0.dropFirst(5)) } ?? ""
            let branch = lines.first(where: { $0.hasPrefix("branch ") }).map { String($0.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
            return GitWorktreeSummary(path: path, branch: branch, head: head, isMain: path == repositoryURL.path)
        }
    }

    func worktreeAdd(path: String, branch: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "worktree", "add", path, branch])
    }

    func worktreeRemove(path: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "worktree", "remove", path])
    }

    func stage(_ paths: [String], at repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(arguments: ["-C", repositoryURL.path, "add", "--"] + paths)
    }

    func stageAll(at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "add", "-A"])
    }

    func unstage(_ paths: [String], at repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(arguments: ["-C", repositoryURL.path, "restore", "--staged", "--"] + paths)
    }

    func commit(message: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "commit", "-m", message])
    }

    func createBranch(_ name: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "switch", "-c", name])
    }

    func checkout(branch: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "switch", branch])
    }

    func checkoutRemote(_ branch: GitRemoteBranchSummary, at repositoryURL: URL) async throws {
        try await checkoutRemote(remote: branch.remote, branch: branch.name, at: repositoryURL)
    }

    func checkoutRemote(remote: String, branch: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "switch", "--track", "\(remote)/\(branch)"])
    }

    func fetch(at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "fetch", "--all", "--prune"])
    }

    func pull(at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "pull", "--ff-only"])
    }

    func push(at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "push"])
    }

    func stashPush(message: String?, includeUntracked: Bool = false, at repositoryURL: URL) async throws {
        var arguments = ["-C", repositoryURL.path, "stash", "push"]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        if let message, !message.isEmpty {
            arguments += ["-m", message]
        }
        _ = try await run(arguments: arguments)
    }

    func diff(for file: GitFileStatus, staged: Bool, at repositoryURL: URL) async throws -> GitFileDiff {
        var arguments: [String]
        if file.kind == .untracked {
            arguments = ["-C", repositoryURL.path, "diff", "--no-index", "--", "/dev/null", file.path]
        } else {
            arguments = ["-C", repositoryURL.path, "diff", "--no-ext-diff", "--unified=3"]
            if staged { arguments.append("--cached") }
            arguments += ["--", file.path]
        }
        return try await pagedDiff(
            arguments: arguments,
            acceptedStatuses: file.kind == .untracked ? [0, 1] : [0],
            path: file.path,
            isStaged: staged
        )
    }

    func pagedDiff(
        arguments: [String],
        acceptedStatuses: [Int32] = [0],
        path: String,
        isStaged: Bool
    ) async throws -> GitFileDiff {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GitIgnore-Diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("diff.patch")
        var pagedArguments = arguments
        let insertionIndex = pagedArguments.firstIndex(of: "--") ?? pagedArguments.endIndex
        pagedArguments.insert("--output=\(outputURL.path)", at: insertionIndex)
        do {
            _ = try await run(arguments: pagedArguments, acceptedStatuses: acceptedStatuses)
            let token = PerformanceDiagnostics.begin(category: "Diff", name: "index-and-parse")
            let reader = try GitDiffPagedReader(fileURL: outputURL)
            let diff = GitFileDiff(path: path, reader: reader, isStaged: isStaged)
            PerformanceDiagnostics.end(token, bytes: reader.byteCount)
            return diff
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func resolveUsingOurs(_ path: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "checkout", "--ours", "--", path])
        _ = try await run(arguments: ["-C", repositoryURL.path, "add", "--", path])
    }

    func resolveUsingTheirs(_ path: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "checkout", "--theirs", "--", path])
        _ = try await run(arguments: ["-C", repositoryURL.path, "add", "--", path])
    }

    func markResolved(_ path: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "add", "--", path])
    }

    func run(
        arguments: [String],
        acceptedStatuses: [Int32] = [0],
        environment: [String: String] = [:]
    ) async throws -> GitCommandOutput {
        let isWrite = Self.isWriteCommand(arguments)
        let limiter = isWrite ? writeLimiter : readLimiter
        try await limiter.acquire()
        defer { Task { await limiter.release() } }
        if isWrite, let repositoryURL = Self.repositoryURL(from: arguments) {
            try await preflightIndexLock(at: repositoryURL)
        }
        var executionEnvironment = environment
        if !isWrite { executionEnvironment["GIT_OPTIONAL_LOCKS"] = "0" }
        return try await GitProcessExecutor.execute(
            executableURL: executableURL,
            arguments: arguments,
            acceptedStatuses: acceptedStatuses,
            outputLimitBytes: 16 * 1_024 * 1_024,
            environment: executionEnvironment,
            timeoutSeconds: Self.timeoutSeconds(for: arguments, isWrite: isWrite)
        )
    }

    private static func isWriteCommand(_ arguments: [String]) -> Bool {
        guard let verb = commandVerb(in: arguments) else { return false }
        switch verb {
        case "add", "restore", "commit", "switch", "checkout", "fetch", "pull", "push", "merge", "rebase", "cherry-pick", "reset", "update-ref", "apply":
            return true
        case "stash":
            return arguments.contains(where: { ["push", "apply", "pop", "drop", "clear"].contains($0) })
        case "worktree":
            return arguments.contains(where: { ["add", "remove", "move", "prune", "repair", "lock", "unlock"].contains($0) })
        case "branch":
            return arguments.contains(where: { ["-d", "-D", "-m", "-M", "-c", "-C"].contains($0) })
        default:
            return false
        }
    }

    private static func commandVerb(in arguments: [String]) -> String? {
        if arguments.first == "-C", arguments.count > 2 { return arguments[2] }
        return arguments.first
    }

    private static func repositoryURL(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "-C"), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    private func preflightIndexLock(at repositoryURL: URL) async throws {
        let gitDirectory = try await gitDirectory(at: repositoryURL)
        let lockURL = gitDirectory.appendingPathComponent("index.lock", isDirectory: false)
        guard FileManager.default.fileExists(atPath: lockURL.path) else { return }

        var lastOwner: String?
        for attempt in 0..<4 {
            guard FileManager.default.fileExists(atPath: lockURL.path) else { return }
            lastOwner = Self.openFileOwner(for: lockURL.path)
            if lastOwner == nil { break }
            if attempt < 3 { try await Task.sleep(for: .milliseconds(250)) }
        }
        if let lastOwner {
            throw GitRunnerError.indexLocked(path: lockURL.path, activeOwner: lastOwner)
        }

        let values = try? lockURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values?.isRegularFile == true else {
            throw GitRunnerError.indexLocked(path: lockURL.path, activeOwner: nil)
        }
        let age = Date().timeIntervalSince(values?.contentModificationDate ?? Date())
        if age < 2 {
            try await Task.sleep(for: .seconds(max(0.1, 2.05 - age)))
            guard FileManager.default.fileExists(atPath: lockURL.path) else { return }
            if let owner = Self.openFileOwner(for: lockURL.path) {
                throw GitRunnerError.indexLocked(path: lockURL.path, activeOwner: owner)
            }
            let refreshedAge = Date().timeIntervalSince((try? lockURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())
            guard refreshedAge >= 2 else {
                throw GitRunnerError.indexLocked(path: lockURL.path, activeOwner: nil)
            }
        }

        // No process owns the regular file and it survived the grace period:
        // this is the crash residue Git itself asks users to remove manually.
        try FileManager.default.removeItem(at: lockURL)
    }

    private nonisolated static func openFileOwner(for path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-Fpc", "--", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let pid = lines.first(where: { $0.hasPrefix("p") }).map { String($0.dropFirst()) }
            let command = lines.first(where: { $0.hasPrefix("c") }).map { String($0.dropFirst()) }
            return [command, pid.map { "PID \($0)" }].compactMap { $0 }.joined(separator: " · ")
        } catch {
            return nil
        }
    }

    private static func timeoutSeconds(for arguments: [String], isWrite: Bool) -> Double {
        let networkVerbs = Set(["fetch", "pull", "push", "clone"])
        if arguments.contains(where: { networkVerbs.contains($0) }) {
            return RemoteCheckPreferences.timeoutSeconds
        }
        return isWrite ? 120 : 30
    }
}

actor AsyncSemaphore {
    private var permits: Int
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }
    private var waiters: [Waiter] = []

    init(value: Int) { permits = max(1, value) }

    func acquire() async throws {
        try Task.checkCancellation()
        if permits > 0 {
            permits -= 1
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume()
        } else {
            permits += 1
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume()
    }
}

/// Disk-backed diff source. Git writes directly to a temporary file and this
/// reader keeps only a small preview plus sparse line checkpoints in memory.
final class GitDiffPagedReader: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var checkpoints: [UInt64] = [0]
    let byteCount: Int
    let totalLineCount: Int
    let previewText: String
    private let checkpointStride = 256

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        byteCount = values.fileSize ?? 0
        var offsets: [UInt64] = [0]
        var lineCount = 0
        let handle = try FileHandle(forReadingFrom: fileURL)
        var offset: UInt64 = 0
        var lastByte: UInt8?
        var preview = Data()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            lastByte = chunk.last
            if preview.count < 512 * 1_024 {
                preview.append(chunk.prefix(512 * 1_024 - preview.count))
            }
            for byte in chunk {
                offset += 1
                if byte == 10 {
                    lineCount += 1
                    if lineCount % checkpointStride == 0 { offsets.append(offset) }
                }
            }
        }
        try? handle.close()
        if byteCount > 0, lastByte != 10 { lineCount += 1 }
        checkpoints = offsets
        totalLineCount = lineCount
        previewText = String(decoding: preview, as: UTF8.self)
    }

    deinit { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    func readLines(start: Int, count: Int) -> [String] {
        guard count > 0, start < totalLineCount else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let block = min(start / checkpointStride, checkpoints.count - 1)
        let lineAtBlock = block * checkpointStride
        let handle = try? FileHandle(forReadingFrom: fileURL)
        guard let handle else { return [] }
        defer { try? handle.close() }
        try? handle.seek(toOffset: checkpoints[block])
        var line = lineAtBlock
        var result: [String] = []
        var pending = Data()
        while line < start + count,
              let chunk = try? handle.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let bytes = pending.prefix(upTo: newline)
                if line >= start { result.append(String(decoding: bytes, as: UTF8.self)) }
                pending.removeSubrange(...newline)
                line += 1
                if line >= start + count { return result }
            }
            if pending.count > 256 * 1_024 {
                if line >= start { result.append(String(decoding: pending.prefix(256 * 1_024), as: UTF8.self) + " …") }
                pending.removeAll(keepingCapacity: true)
                line += 1
            }
        }
        if line >= start, !pending.isEmpty { result.append(String(decoding: pending, as: UTF8.self)) }
        return result
    }

    func readAllText(maxBytes: Int = 8 * 1_024 * 1_024) -> String {
        guard byteCount <= maxBytes, let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return previewText }
        return String(decoding: data, as: UTF8.self)
    }
}
