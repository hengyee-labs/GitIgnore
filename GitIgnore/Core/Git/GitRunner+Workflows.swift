import Foundation

extension GitRunner {
    func stashPreview(_ reference: String, at repositoryURL: URL) async throws -> GitStashPreview {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else {
            throw GitRunnerError.commandFailed(arguments: ["stash", "show"], message: "Stash 引用为空。", status: 128)
        }

        // `stash show` is affected by user-level diff settings. Comparing the
        // stash commit with its first parent gives a deterministic preview and
        // also handles stashes created with an index or untracked files.
        let filesOutput = try await run(arguments: [
            "-C", repositoryURL.path, "diff", "--name-status", "--find-renames", "--no-ext-diff",
            "\(normalizedReference)^1", normalizedReference, "--"
        ])
        let fileLines = filesOutput.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
        let files = fileLines.compactMap { line -> GitCommitFileChange? in
            let fields = line.split(separator: "\t").map(String.init)
            guard let code = fields.first?.first, let path = fields.last else { return nil }
            let kind: GitFileChangeKind
            switch code {
            case "A": kind = .added
            case "D": kind = .deleted
            case "R": kind = .renamed
            default: kind = .modified
            }
            return GitCommitFileChange(path: path, kind: kind)
        }
        return GitStashPreview(
            reference: normalizedReference,
            files: files
        )
    }

    func stashFileDiff(_ reference: String, path: String, at repositoryURL: URL) async throws -> GitFileDiff {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty, !normalizedPath.isEmpty else {
            throw GitRunnerError.commandFailed(arguments: ["stash", "diff"], message: "Stash 引用或文件路径为空。", status: 128)
        }
        return try await pagedDiff(arguments: [
            "-C", repositoryURL.path, "diff", "--patch", "--binary", "--find-renames", "--no-ext-diff",
            "--unified=3", "\(normalizedReference)^1", normalizedReference, "--", normalizedPath
        ], path: normalizedPath, isStaged: false)
    }

    func stashPush(message: String?, paths: [String], at repositoryURL: URL) async throws {
        var arguments = ["-C", repositoryURL.path, "stash", "push"]
        if let message, !message.isEmpty { arguments += ["-m", message] }
        if !paths.isEmpty { arguments += ["--"] + paths }
        _ = try await run(arguments: arguments)
    }

    func rebaseTodo(base: String, at repositoryURL: URL) async throws -> [RebaseTodoItem] {
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "log", "--reverse", "--pretty=format:%H%x1f%h%x1f%s%x1e", "\(base)..HEAD"
        ])
        return output.standardOutput
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 3 else { return nil }
                return RebaseTodoItem(
                    hash: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    shortHash: fields[1],
                    subject: fields[2],
                    action: .pick,
                    editedSubject: fields[2]
                )
            }
    }

    func interactiveRebase(
        base: String,
        items: [RebaseTodoItem],
        at repositoryURL: URL
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitIgnore-rebase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let planURL = directory.appendingPathComponent("plan")
        let editorURL = directory.appendingPathComponent("sequence-editor.sh")

        let plan = items.flatMap { item -> [String] in
            switch item.action {
            case .reword:
                return [
                    "pick \(item.hash) \(item.subject)",
                    "exec git commit --amend -m \(shellQuote(item.editedSubject))"
                ]
            default:
                return ["\(item.action.rawValue) \(item.hash) \(item.subject)"]
            }
        }.joined(separator: "\n") + "\n"
        try Data(plan.utf8).write(to: planURL, options: .atomic)
        let script = "#!/bin/sh\ncp \(shellQuote(planURL.path)) \"$1\"\n"
        try Data(script.utf8).write(to: editorURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: editorURL.path)

        _ = try await run(arguments: [
            "-C", repositoryURL.path,
            "-c", "sequence.editor=\(editorURL.path)",
            "-c", "core.editor=true",
            "rebase", "-i", base
        ])
    }

    func branchComparison(base: String, target: String, at repositoryURL: URL) async throws -> GitBranchComparison {
        async let countOutput = run(arguments: [
            "-C", repositoryURL.path, "rev-list", "--left-right", "--count", "\(base)...\(target)"
        ])
        async let commitsOutput = run(arguments: [
            "-C", repositoryURL.path, "log", "--date=format:%Y-%m-%d %H:%M",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1f%D%x1f%P%x1e", "-n", "200", "\(base)..\(target)"
        ])
        async let filesOutput = run(arguments: [
            "-C", repositoryURL.path, "diff", "--name-only", "\(base)...\(target)", "--"
        ])
        let counts = try await countOutput.standardOutput.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        let commits = try await parseWorkflowCommits(commitsOutput.standardOutput)
        let files = try await filesOutput.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" }).prefix(500).map(String.init)
        return GitBranchComparison(
            base: base,
            target: target,
            ahead: counts.count > 1 ? counts[1] : 0,
            behind: counts.first ?? 0,
            commits: commits,
            changedFiles: files
        )
    }

    func mergedBranches(into branch: String, at repositoryURL: URL) async throws -> [String] {
        let output = try await run(arguments: ["-C", repositoryURL.path, "branch", "--merged", branch, "--format=%(refname:short)"])
        return output.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != branch }
    }

    func worktreeState(path: String) async throws -> GitWorktreeState {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let summary = try await status(at: root)
        return GitWorktreeState(
            path: path,
            changedCount: summary.changedFileCount,
            stagedCount: summary.stagedFileCount,
            untrackedCount: summary.files.count { $0.kind == .untracked },
            conflictCount: summary.files.count { $0.hasConflict }
        )
    }

    private func parseWorkflowCommits(_ text: String) -> [GitCommitSummary] {
        text.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 7 else { return nil }
            return GitCommitSummary(
                hash: fields[0], shortHash: fields[1], subject: fields[4], author: fields[2], dateText: fields[3],
                refs: fields[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                parents: fields[6].split(separator: " ").map(String.init)
            )
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
