import Foundation

extension GitRunner {
    private static var mergeEditorByteLimit: Int { 1_500_000 }

    func mergeConflictDocument(path: String, at repositoryURL: URL) async throws -> GitMergeConflictDocument {
        let fileURL = try validatedMergeFileURL(path: path, repositoryURL: repositoryURL)
        async let baseTask = conflictBlob(stage: 1, path: path, repositoryURL: repositoryURL)
        async let currentTask = conflictBlob(stage: 2, path: path, repositoryURL: repositoryURL)
        async let incomingTask = conflictBlob(stage: 3, path: path, repositoryURL: repositoryURL)

        let workingFileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let workingText = try workingFileExists ? textFile(at: fileURL, displayPath: path) : nil
        let base = try await baseTask
        let current = try await currentTask
        let incoming = try await incomingTask

        return GitMergeConflictDocument(
            path: path,
            baseText: base,
            currentText: current,
            incomingText: incoming,
            resultText: workingText ?? current ?? incoming ?? "",
            workingFileExists: workingFileExists
        )
    }

    func saveMergeResult(
        _ text: String,
        path: String,
        deleteResult: Bool,
        at repositoryURL: URL
    ) async throws {
        guard !MergeConflictParser.hasConflictMarkers(in: text) else {
            throw MergeEditorError.unresolvedMarkers
        }
        let fileURL = try validatedMergeFileURL(path: path, repositoryURL: repositoryURL)
        if deleteResult {
            _ = try await run(arguments: ["-C", repositoryURL.path, "rm", "--", path])
            return
        }

        let data = Data(text.utf8)
        guard data.count <= Self.mergeEditorByteLimit else {
            throw MergeEditorError.fileTooLarge(path: path, bytes: data.count)
        }
        try data.write(to: fileURL, options: .atomic)
        _ = try await run(arguments: ["-C", repositoryURL.path, "add", "--", path])
    }

    func inProgressBranchOperation(at repositoryURL: URL) async -> GitBranchOperation? {
        guard let gitDirectory = try? await gitDirectory(at: repositoryURL) else {
            return nil
        }
        if FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("rebase-merge").path)
            || FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("rebase-apply").path) {
            return .rebase
        }
        return FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("MERGE_HEAD").path)
            ? .merge
            : nil
    }

    func continueBranchOperation(_ operation: GitBranchOperation, at repositoryURL: URL) async throws {
        _ = try await run(arguments: [
            "-C", repositoryURL.path,
            "-c", "core.editor=true",
            operation.rawValue, "--continue"
        ])
    }

    func abortBranchOperation(_ operation: GitBranchOperation, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, operation.rawValue, "--abort"])
    }

    private func conflictBlob(stage: Int, path: String, repositoryURL: URL) async throws -> String? {
        let object = ":\(stage):\(path)"
        let sizeOutput = try await run(
            arguments: ["-C", repositoryURL.path, "cat-file", "-s", object],
            acceptedStatuses: [0, 1, 128]
        )
        guard sizeOutput.terminationStatus == 0 else { return nil }
        let byteCount = Int(sizeOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard byteCount <= Self.mergeEditorByteLimit else {
            throw MergeEditorError.fileTooLarge(path: path, bytes: byteCount)
        }
        let output = try await run(arguments: ["-C", repositoryURL.path, "show", object])
        guard !output.standardOutput.utf8.contains(0) else {
            throw MergeEditorError.binaryFile(path: path)
        }
        return output.standardOutput
    }


    private func textFile(at url: URL, displayPath: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount <= Self.mergeEditorByteLimit else {
            throw MergeEditorError.fileTooLarge(path: displayPath, bytes: byteCount)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw MergeEditorError.binaryFile(path: displayPath)
        }
        return text
    }

    private func validatedMergeFileURL(path: String, repositoryURL: URL) throws -> URL {
        let root = repositoryURL.standardizedFileURL
        let fileURL = root.appendingPathComponent(path).standardizedFileURL
        guard fileURL.path.hasPrefix(root.path + "/") else { throw MergeEditorError.invalidPath }
        return fileURL
    }
}
