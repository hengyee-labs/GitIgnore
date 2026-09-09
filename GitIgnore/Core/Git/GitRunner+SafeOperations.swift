import Foundation

extension GitRunner {
    func safeOperationPreview(
        kind: SafeGitOperationKind,
        target: String,
        resetMode: GitResetMode?,
        at repositoryURL: URL
    ) async throws -> GitOperationPreview {
        switch kind {
        case .reset:
            return try await operationPreview(to: target, at: repositoryURL)
        case .cherryPick:
            let output = try await run(arguments: [
                "-C", repositoryURL.path, "show", "--format=", "--name-only", target, "--"
            ])
            let files = Self.nonEmptyLines(output.standardOutput)
            return GitOperationPreview(
                title: "Cherry-pick \(String(target.prefix(8)))",
                summary: "会把这条提交应用到当前分支，预计影响 \(files.count) 个文件。",
                affectedFiles: files,
                commitCount: 1
            )
        case .merge, .rebase:
            async let filesOutput = run(arguments: [
                "-C", repositoryURL.path, "diff", "--name-only", "HEAD...\(target)", "--"
            ])
            let range = kind == .merge ? "HEAD..\(target)" : "\(target)..HEAD"
            async let countOutput = run(arguments: [
                "-C", repositoryURL.path, "rev-list", "--count", range
            ])
            let files = try await Self.nonEmptyLines(filesOutput.standardOutput)
            let count = try await Int(countOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let action = kind == .merge ? "合并" : "重放"
            return GitOperationPreview(
                title: "\(kind.title) \(target)",
                summary: "将 \(action) \(count) 条提交，预计影响 \(files.count) 个文件。",
                affectedFiles: files,
                commitCount: count
            )
        case .deleteBranch:
            async let filesOutput = run(arguments: [
                "-C", repositoryURL.path, "diff", "--name-only", "HEAD...\(target)", "--"
            ])
            async let countOutput = run(arguments: [
                "-C", repositoryURL.path, "rev-list", "--count", "HEAD..\(target)"
            ])
            let files = try await Self.nonEmptyLines(filesOutput.standardOutput)
            let count = try await Int(countOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return GitOperationPreview(
                title: "删除分支 \(target)",
                summary: count > 0
                    ? "该分支还有 \(count) 条当前分支没有的提交；删除后只能通过 Git Reflog 手动找回。"
                    : "该分支没有独占提交；确认后将直接删除。",
                affectedFiles: files,
                commitCount: count
            )
        }
    }

    func executeSafeOperation(_ request: SafeGitOperationRequest, at repositoryURL: URL) async throws {
        switch request.kind {
        case .merge:
            try await merge(branch: request.target, at: repositoryURL)
        case .rebase:
            try await rebase(onto: request.target, at: repositoryURL)
        case .cherryPick:
            try await cherryPick(request.target, at: repositoryURL)
        case .reset:
            try await reset(to: request.target, mode: request.resetMode ?? .mixed, at: repositoryURL)
        case .deleteBranch:
            try await deleteBranch(request.target, force: request.force, at: repositoryURL)
        }
    }

    private static func nonEmptyLines(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
    }
}
