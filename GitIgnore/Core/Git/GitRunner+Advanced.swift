import Foundation

extension GitRunner {
    /// Publishes a local branch for the first time and configures its upstream
    /// in the same Git transaction. This is intentionally separate from the
    /// regular `push` command because Git cannot infer a destination when a
    /// branch has no tracking ref yet.
    func publishCurrentBranch(
        branch: String,
        remote: String = "origin",
        at repositoryURL: URL
    ) async throws {
        _ = try await run(arguments: [
            "-C", repositoryURL.path, "push", "--set-upstream", remote, branch
        ])
    }

    func createSafePullProtection(message: String, at repositoryURL: URL) async throws -> SafePullProtection {
        let previousObjectID = try await stashObjectID(at: repositoryURL)
        _ = try await run(arguments: [
            "-C", repositoryURL.path, "stash", "push", "--include-untracked", "-m", message
        ])
        guard let objectID = try await stashObjectID(at: repositoryURL), objectID != previousObjectID else {
            throw SafePullError.protectionNotCreated
        }
        return SafePullProtection(reference: "stash@{0}", objectID: objectID)
    }

    func restoreSafePullProtection(
        _ protection: SafePullProtection,
        at repositoryURL: URL
    ) async throws -> SafePullStashRestoreResult {
        let reference = try await stashReference(for: protection, at: repositoryURL)
        guard let reference else {
            return .failed(technicalDetails: "Protected stash \(protection.objectID) is no longer present.")
        }

        let output = try await run(
            arguments: ["-C", repositoryURL.path, "stash", "pop", "--index", reference],
            acceptedStatuses: [0, 1]
        )
        guard output.terminationStatus != 0 else { return .restored }

        let currentStatus = try await status(at: repositoryURL)
        let conflicts = currentStatus.files.filter(\.hasConflict)
        let indexedDetails = [output.standardOutput, output.standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard conflicts.isEmpty else {
            return .conflicts(files: conflicts, technicalDetails: indexedDetails)
        }
        guard currentStatus.files.isEmpty else {
            return .failed(technicalDetails: indexedDetails)
        }

        let fallbackOutput = try await run(
            arguments: ["-C", repositoryURL.path, "stash", "apply", reference],
            acceptedStatuses: [0, 1]
        )
        let fallbackStatus = try await status(at: repositoryURL)
        let fallbackConflicts = fallbackStatus.files.filter(\.hasConflict)
        let fallbackDetails = [fallbackOutput.standardOutput, fallbackOutput.standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let details = [indexedDetails, fallbackDetails].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !fallbackConflicts.isEmpty {
            return .conflicts(files: fallbackConflicts, technicalDetails: details)
        }
        return fallbackOutput.terminationStatus == 0
            ? .restoredWithProtection(technicalDetails: details)
            : .failed(technicalDetails: details)
    }

    func discardSafePullProtection(
        _ protection: SafePullProtection,
        at repositoryURL: URL
    ) async throws {
        guard let reference = try await stashReference(for: protection, at: repositoryURL) else { return }
        _ = try await run(arguments: ["-C", repositoryURL.path, "stash", "drop", reference])
    }

    private func stashReference(
        for protection: SafePullProtection,
        at repositoryURL: URL
    ) async throws -> String? {
        let listOutput = try await run(arguments: [
            "-C", repositoryURL.path, "stash", "list", "--format=%gd%x09%H"
        ])
        return listOutput.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .compactMap { line -> (String, String)? in
                let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
                return fields.count == 2 ? (fields[0], fields[1]) : nil
            }
            .first { $0.1 == protection.objectID }?.0
    }

    func commitFileDiff(hash: String, path: String, parent selectedParent: String? = nil, at repositoryURL: URL) async throws -> GitFileDiff {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentOutput = try await run(
            arguments: ["-C", repositoryURL.path, "rev-parse", "\(normalizedHash)^"],
            acceptedStatuses: [0, 128]
        )
        let parent = selectedParent ?? (parentOutput.terminationStatus == 0
            ? parentOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            : "4b825dc642cb6eb9a060e54bf8d69288fbee4904")
        return try await pagedDiff(arguments: [
            "-C", repositoryURL.path, "diff", "--no-ext-diff", "--find-renames",
            "--unified=3", parent, normalizedHash, "--", path
        ], path: path, isStaged: false)
    }

    func applyPatch(_ patch: String, operation: GitPatchOperation, at repositoryURL: URL) async throws {
        let patchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitIgnore-patch-\(UUID().uuidString).diff")
        try Data(patch.utf8).write(to: patchURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: patchURL) }

        var arguments = ["-C", repositoryURL.path, "apply", "--recount", "--whitespace=nowarn"]
        switch operation {
        case .stage:
            arguments.append("--cached")
        case .unstage:
            arguments += ["--cached", "--reverse"]
        case .discard:
            arguments.append("--reverse")
        }
        arguments.append(patchURL.path)
        var checkArguments = arguments
        checkArguments.insert("--check", at: checkArguments.count - 1)
        _ = try await run(arguments: checkArguments)
        _ = try await run(arguments: arguments)
    }

    func discardFile(_ path: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "restore", "--worktree", "--", path])
    }

    func commit(message: String, amend: Bool, signOff: Bool, at repositoryURL: URL) async throws {
        var arguments = ["-C", repositoryURL.path, "commit", "-m", message]
        if amend { arguments.append("--amend") }
        if signOff { arguments.append("--signoff") }
        _ = try await run(arguments: arguments)
    }

    func undoLastCommit(at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "reset", "--soft", "HEAD~1"])
    }

    func reset(to revision: String, mode: GitResetMode, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "reset", "--\(mode.rawValue)", revision])
    }

    func operationPreview(to revision: String, at repositoryURL: URL) async throws -> GitOperationPreview {
        async let filesOutput = run(arguments: [
            "-C", repositoryURL.path, "diff", "--name-only", "\(revision)..HEAD", "--"
        ])
        async let countOutput = run(arguments: [
            "-C", repositoryURL.path, "rev-list", "--count", "\(revision)..HEAD"
        ])
        let files = try await filesOutput.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        let count = try await Int(countOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return GitOperationPreview(
            title: "重置到 \(String(revision.prefix(8)))",
            summary: "提交位置将回退 \(count) 步，影响 \(files.count) 个文件。",
            affectedFiles: files,
            commitCount: count
        )
    }

    func revertPreview(for revision: String, at repositoryURL: URL) async throws -> GitOperationPreview {
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "show", "--format=", "--name-only", revision, "--"
        ])
        let files = output.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
        return GitOperationPreview(
            title: "Revert \(String(revision.prefix(8)))",
            summary: "会创建一条新的反向提交，影响 \(files.count) 个文件，原历史不会被改写。",
            affectedFiles: files,
            commitCount: 1
        )
    }

    func cherryPick(_ revision: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "cherry-pick", revision])
    }

    func revert(_ revision: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "revert", "--no-edit", revision])
    }

    func createBranch(_ name: String, at revision: String, repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "branch", name, revision])
    }

    func createTag(_ name: String, at revision: String, repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "tag", name, revision])
    }

    func tags(at repositoryURL: URL) async throws -> [String] {
        let output = try await run(arguments: ["-C", repositoryURL.path, "tag", "--sort=-creatordate", "--format=%(refname:short)"])
        return output.standardOutput.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
    }

    func pushTag(_ name: String, remote: String = "origin", at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "push", remote, "refs/tags/\(name)"])
    }

    func deleteTag(_ name: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "tag", "-d", name])
    }

    func merge(branch: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "merge", "--no-edit", branch])
    }

    func rebase(onto branch: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "rebase", branch])
    }

    func deleteBranch(_ branch: String, force: Bool, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "branch", force ? "-D" : "-d", branch])
    }

    func renameBranch(_ branch: String, to newName: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "branch", "-m", branch, newName])
    }

    func setUpstream(branch: String, upstream: String, at repositoryURL: URL) async throws {
        _ = try await run(arguments: [
            "-C", repositoryURL.path, "branch", "--set-upstream-to=\(upstream)", branch
        ])
    }

    private func stashObjectID(at repositoryURL: URL) async throws -> String? {
        let output = try await run(
            arguments: ["-C", repositoryURL.path, "rev-parse", "--verify", "refs/stash"],
            acceptedStatuses: [0, 128]
        )
        guard output.terminationStatus == 0 else { return nil }
        let objectID = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return objectID.isEmpty ? nil : objectID
    }
}
