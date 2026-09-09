import Foundation

extension GitRunner {
    func blame(path: String, at repositoryURL: URL) async throws -> String {
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "blame", "--line-porcelain", "--", path
        ])
        return output.standardOutput
    }

    func fileHistory(path: String, at repositoryURL: URL) async throws -> [GitCommitSummary] {
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "log", "--follow", "-40",
            "--date=short", "--format=%H%x09%h%x09%s%x09%an%x09%ad%x09%D", "--", path
        ])
        return output.standardOutput.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { return nil }
            return GitCommitSummary(
                hash: fields[0], shortHash: fields[1], subject: fields[2], author: fields[3],
                dateText: fields[4], refs: fields.count > 5 ? fields[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : [], parents: []
            )
        }
    }
}
