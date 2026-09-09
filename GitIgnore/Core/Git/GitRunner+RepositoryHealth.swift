import Foundation

extension GitRunner {
    func repositoryOperationState(at repositoryURL: URL) async throws -> RepositoryOperationState? {
        let gitDirectory = try await gitDirectory(at: repositoryURL)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("MERGE_HEAD").path) { return .merge }
        if fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("rebase-merge").path)
            || fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("rebase-apply").path) { return .rebase }
        if fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("CHERRY_PICK_HEAD").path) { return .cherryPick }
        return nil
    }
}
