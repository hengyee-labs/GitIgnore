import Foundation

extension GitRunner {
    func repositoryToolReport(at repositoryURL: URL) async throws -> RepositoryToolReport {
        async let lfs = toolOutput(["-C", repositoryURL.path, "lfs", "status"], accepted: [0, 1, 2])
        async let submodules = toolOutput(["-C", repositoryURL.path, "submodule", "status"], accepted: [0, 1])
        async let sparse = toolOutput(["-C", repositoryURL.path, "config", "--get", "core.sparseCheckout"], accepted: [0, 1])
        async let hooks = toolOutput(["-C", repositoryURL.path, "config", "--get", "core.hooksPath"], accepted: [0, 1])
        async let objects = toolOutput(["-C", repositoryURL.path, "count-objects", "-v"], accepted: [0])
        let lfsText = await lfs
        let submoduleText = await submodules
        let sparseText = await sparse
        let hooksText = await hooks
        let objectText = await objects
        let objectCount = objectText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first(where: { $0.hasPrefix("count:" ) })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
        return RepositoryToolReport(
            lfs: lfsText.isEmpty ? "没有待处理的 LFS 对象" : lfsText,
            submodules: submoduleText.isEmpty ? "没有配置子模块" : submoduleText,
            sparseCheckout: sparseText.isEmpty ? "未启用稀疏检出" : sparseText,
            hooks: hooksText.isEmpty ? "使用默认 Hooks 路径" : hooksText,
            health: "已读取对象数据库统计",
            objectCount: objectCount,
            generatedAt: Date()
        )
    }

    func runRepositoryHealthCheck(at repositoryURL: URL) async throws -> String {
        let output = try await run(arguments: ["-C", repositoryURL.path, "fsck", "--no-progress", "--connectivity-only"])
        return output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "对象数据库完整，没有发现连通性问题。"
            : output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setSparseCheckout(_ enabled: Bool, at repositoryURL: URL) async throws {
        _ = try await run(arguments: ["-C", repositoryURL.path, "config", "core.sparseCheckout", enabled ? "true" : "false"])
        if enabled { _ = try await run(arguments: ["-C", repositoryURL.path, "sparse-checkout", "init", "--cone"]) }
    }

    func hookNames(at repositoryURL: URL) async throws -> [String] {
        let output = try await run(arguments: ["-C", repositoryURL.path, "rev-parse", "--git-path", "hooks"])
        let path = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? FileManager.default.contentsOfDirectory(atPath: path))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
    }

    func commitHashes(matchingPathKeyword keyword: String, limit: Int, at repositoryURL: URL) async throws -> Set<String> {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var escaped = ""
        for character in normalized {
            if character == "\\" || character == "*" || character == "?" || character == "[" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        let boundedLimit = min(max(limit, 1), 10_000)
        let output = try await run(arguments: [
            "-C", repositoryURL.path, "log", "--all", "--format=%H", "-n", "\(boundedLimit)", "--",
            ":(icase,glob)*\(escaped)*",
            ":(icase,glob)**/*\(escaped)*"
        ])
        return Set(
            output.standardOutput
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func toolOutput(_ arguments: [String], accepted: [Int32]) async -> String {
        guard let output = try? await run(arguments: arguments, acceptedStatuses: accepted) else { return "" }
        return [output.standardOutput, output.standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
