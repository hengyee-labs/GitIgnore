import AppKit
import Foundation

extension GitRunner {
    func imageDiffPreview(path: String, at repositoryURL: URL) async throws -> GitImageDiffPreview {
        async let beforeData = gitObjectData("HEAD:\(path)", at: repositoryURL)
        async let afterData = localImageData(path: path, at: repositoryURL)
        return await GitImageDiffPreview(
            before: Self.imageVersion(from: try? beforeData),
            after: Self.imageVersion(from: try? afterData)
        )
    }

    private func gitObjectData(_ revisionPath: String, at repositoryURL: URL) async throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryURL.path, "show", revisionPath]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        guard data.count <= 20 * 1_024 * 1_024 else {
            throw GitRunnerError.outputLimitExceeded(arguments: process.arguments ?? [], limitBytes: 20 * 1_024 * 1_024)
        }
        return data
    }

    private func localImageData(path: String, at repositoryURL: URL) async throws -> Data {
        let url = repositoryURL.appendingPathComponent(path)
        let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 20 * 1_024 * 1_024 else {
            throw GitRunnerError.outputLimitExceeded(arguments: ["read-image", path], limitBytes: 20 * 1_024 * 1_024)
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    nonisolated private static func imageVersion(from data: Data?) -> GitImageVersion? {
        guard let data, let representation = NSBitmapImageRep(data: data) else { return nil }
        return GitImageVersion(
            data: data,
            pixelWidth: representation.pixelsWide,
            pixelHeight: representation.pixelsHigh,
            hasAlpha: representation.hasAlpha
        )
    }
}
