import Foundation
import Darwin

enum GitProcessExecutor {
    static func execute(
        executableURL: URL,
        arguments: [String],
        acceptedStatuses: [Int32],
        outputLimitBytes: Int,
        environment: [String: String],
        timeoutSeconds: Double
    ) async throws -> GitCommandOutput {
        let execution = GitProcessExecution(
            executableURL: executableURL,
            arguments: arguments,
            acceptedStatuses: acceptedStatuses,
            outputLimitBytes: outputLimitBytes,
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try execution.run()
            }.value
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class GitProcessExecution: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let acceptedStatuses: [Int32]
    private let outputLimitBytes: Int
    private let environment: [String: String]
    private let timeoutSeconds: Double
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    init(executableURL: URL, arguments: [String], acceptedStatuses: [Int32], outputLimitBytes: Int, environment: [String: String], timeoutSeconds: Double) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.acceptedStatuses = acceptedStatuses
        self.outputLimitBytes = outputLimitBytes
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }

    func run() throws -> GitCommandOutput {
        let commandName = arguments.dropFirst(arguments.first == "-C" ? min(2, arguments.count) : 0).first ?? "git"
        let diagnosticToken = PerformanceDiagnostics.begin(category: "Git", name: commandName)
        var measuredBytes = 0
        var didFinishDiagnostics = false
        defer {
            if !didFinishDiagnostics {
                PerformanceDiagnostics.end(diagnosticToken, bytes: measuredBytes, cancelled: cancelled)
            }
        }
        let directoryName = "GitIgnore-" + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        lock.lock()
        self.process = process
        let shouldCancel = cancelled
        lock.unlock()

        try process.run()
        _ = setpgid(process.processIdentifier, process.processIdentifier)
        if shouldCancel { process.terminate() }
        var exceededOutputLimit = false
        let deadline = timeoutSeconds.isFinite ? Date().addingTimeInterval(max(0.1, timeoutSeconds)) : nil
        while process.isRunning {
            if cancelled {
                terminateProcessTree(process)
                break
            }
            if let deadline, Date() >= deadline {
                lock.lock()
                timedOut = true
                lock.unlock()
                terminateProcessTree(process)
                break
            }
            measuredBytes = Self.fileSize(at: outputURL) + Self.fileSize(at: errorURL)
            if measuredBytes > outputLimitBytes {
                exceededOutputLimit = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
        process.waitUntilExit()

        lock.lock()
        self.process = nil
        let wasCancelled = cancelled
        let didTimeOut = timedOut
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if didTimeOut { throw GitRunnerError.timedOut(arguments: arguments, seconds: timeoutSeconds) }

        try outputHandle.synchronize()
        try errorHandle.synchronize()
        let outputBytes = Self.fileSize(at: outputURL)
        let errorBytes = Self.fileSize(at: errorURL)
        measuredBytes = outputBytes + errorBytes
        if exceededOutputLimit {
            PerformanceDiagnostics.end(diagnosticToken, bytes: measuredBytes)
            didFinishDiagnostics = true
            throw GitRunnerError.outputLimitExceeded(arguments: arguments, limitBytes: outputLimitBytes)
        }
        guard outputBytes + errorBytes <= outputLimitBytes else {
            PerformanceDiagnostics.end(diagnosticToken, bytes: measuredBytes)
            didFinishDiagnostics = true
            throw GitRunnerError.outputLimitExceeded(arguments: arguments, limitBytes: outputLimitBytes)
        }
        let parseToken = PerformanceDiagnostics.begin(category: "Git Parse", name: commandName)
        let result: GitCommandOutput
        do {
            defer { PerformanceDiagnostics.end(parseToken, bytes: measuredBytes) }
            let outputData = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            let errorData = try Data(contentsOf: errorURL, options: .mappedIfSafe)
            result = GitCommandOutput(
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self),
                terminationStatus: process.terminationStatus
            )
        }
        guard acceptedStatuses.contains(result.terminationStatus) else {
            PerformanceDiagnostics.end(diagnosticToken, bytes: measuredBytes)
            didFinishDiagnostics = true
            throw GitRunnerError.commandFailed(
                arguments: arguments,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines),
                status: result.terminationStatus
            )
        }
        PerformanceDiagnostics.end(diagnosticToken, bytes: measuredBytes)
        didFinishDiagnostics = true
        return result
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let runningProcess = process
        lock.unlock()
        if let runningProcess { terminateProcessTree(runningProcess) }
    }

    private func terminateProcessTree(_ process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else { process.terminate(); return }
        _ = kill(-pid, SIGTERM)
        process.terminate()
    }

    private static func fileSize(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }
}
