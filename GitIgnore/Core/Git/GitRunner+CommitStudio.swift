import Foundation

extension GitRunner {
    func commitStudioUnits(at repositoryURL: URL) async throws -> [CommitStudioUnit] {
        let status = try await status(at: repositoryURL)
        var result: [CommitStudioUnit] = []
        for file in status.files {
            if file.kind == .untracked {
                result.append(CommitStudioUnit(
                    id: "file:\(file.path)", path: file.path, title: "完整文件", patch: nil,
                    addedLines: 0, removedLines: 0
                ))
                continue
            }
            let output = try await run(arguments: [
                "-C", repositoryURL.path, "diff", "--binary", "--no-ext-diff", "HEAD", "--", file.path
            ])
            let document = GitPatchParser.parse(output.standardOutput)
            if document.hunks.isEmpty {
                result.append(CommitStudioUnit(
                    id: "file:\(file.path)", path: file.path, title: "完整文件", patch: nil,
                    addedLines: 0, removedLines: 0
                ))
            } else {
                for (index, hunk) in document.hunks.enumerated() {
                    result.append(CommitStudioUnit(
                        id: "hunk:\(file.path):\(index):\(hunk.header)", path: file.path,
                        title: hunk.header, patch: hunk.patchText,
                        addedLines: hunk.addedLineCount, removedLines: hunk.removedLineCount
                    ))
                }
            }
        }
        return result
    }

    func executeCommitStudio(
        drafts: [CommitStudioDraft],
        units: [CommitStudioUnit],
        at repositoryURL: URL
    ) async throws -> CommitStudioResult {
        guard !units.isEmpty else { throw CommitStudioError.noChanges }
        let byID = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0) })
        for (index, draft) in drafts.enumerated() {
            if draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unitIDs.isEmpty {
                throw CommitStudioError.emptyDraft(index)
            }
        }

        let originalHead = try await run(arguments: ["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitIgnore-CommitStudio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let indexURL = temporary.appendingPathComponent("index")
        let environment = ["GIT_INDEX_FILE": indexURL.path]
        _ = try await run(arguments: ["-C", repositoryURL.path, "read-tree", originalHead], environment: environment)

        var parent = originalHead
        var created: [String] = []
        for (position, draft) in drafts.enumerated() {
            let draftUnits = draft.unitIDs.compactMap { byID[$0] }
            let wholePaths = Set(draftUnits.filter(\.isWholeFile).map(\.path))
            if !wholePaths.isEmpty {
                _ = try await run(
                    arguments: ["-C", repositoryURL.path, "add", "--"] + wholePaths.sorted(),
                    environment: environment
                )
            }
            for unit in draftUnits where !unit.isWholeFile {
                guard let patch = unit.patch else { continue }
                let patchURL = temporary.appendingPathComponent("patch-\(position)-\(UUID().uuidString)")
                try Data(patch.utf8).write(to: patchURL, options: .atomic)
                _ = try await run(arguments: [
                    "-C", repositoryURL.path, "apply", "--cached", "--whitespace=nowarn", patchURL.path
                ], environment: environment)
            }
            let tree = try await run(arguments: ["-C", repositoryURL.path, "write-tree"], environment: environment)
                .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let messageURL = temporary.appendingPathComponent("message-\(position).txt")
            try Data(draft.message.utf8).write(to: messageURL, options: .atomic)
            let commit = try await run(arguments: [
                "-C", repositoryURL.path, "commit-tree", tree, "-p", parent, "-F", messageURL.path
            ]).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            created.append(commit)
            parent = commit
        }

        let liveHead = try await run(arguments: ["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard liveHead == originalHead else { throw CommitStudioError.headChanged }
        _ = try await run(arguments: ["-C", repositoryURL.path, "update-ref", "HEAD", parent, originalHead])
        _ = try await run(arguments: ["-C", repositoryURL.path, "reset", "--mixed", parent])
        return CommitStudioResult(commitIDs: created)
    }
}
