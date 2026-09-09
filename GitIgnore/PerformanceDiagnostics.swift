import Foundation
import OSLog
import Darwin

struct PerformanceEvent: Identifiable, Sendable {
    let id: UUID
    let category: String
    let name: String
    let duration: TimeInterval
    let bytes: Int
    let finishedAt: Date
    let wasCancelled: Bool
}

struct PerformancePhaseMetric: Identifiable, Sendable {
    let name: String
    let total: TimeInterval
    var id: String { name }
}

struct PerformanceDiagnosticsSnapshot: Sendable {
    let activeGitTasks: Int
    let activeRepositoryTasks: Int
    let totalGitCommands: Int
    let cancelledGitCommands: Int
    let recentSlowOperations: [PerformanceEvent]
    let currentMemoryBytes: Int
    let peakMemoryBytes: Int
    let cpuPercent: Double
    let phaseDurations: [PerformancePhaseMetric]
}

enum PerformanceDiagnostics {
    private static let log = OSLog(subsystem: "com.hengyee.GitIgnore", category: .pointsOfInterest)
    private static let state = LockedPerformanceState()

    struct Token: Sendable {
        let id: UUID
        let signpostID: OSSignpostID
        let category: String
        let name: String
        let startedAt: ContinuousClock.Instant
    }

    static func begin(category: String, name: String) -> Token {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "GitIgnoreOperation", signpostID: signpostID, "%{public}s / %{public}s", category, name)
        let token = Token(id: UUID(), signpostID: signpostID, category: category, name: name, startedAt: .now)
        state.begin(token.id, category: category)
        return token
    }

    static func end(_ token: Token, bytes: Int = 0, cancelled: Bool = false) {
        let duration = token.startedAt.duration(to: .now)
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        os_signpost(.end, log: log, name: "GitIgnoreOperation", signpostID: token.signpostID, "%.3f s / %d bytes", seconds, bytes)
        state.end(PerformanceEvent(
            id: token.id,
            category: token.category,
            name: token.name,
            duration: seconds,
            bytes: bytes,
            finishedAt: Date(),
            wasCancelled: cancelled
        ))
    }

    static func snapshot() -> PerformanceDiagnosticsSnapshot { state.snapshot() }
}

private final class LockedPerformanceState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeIDs: [UUID: String] = [:]
    private var recentEvents: [PerformanceEvent] = []
    private var total = 0
    private var cancelled = 0
    private var phaseTotals: [String: TimeInterval] = [:]
    private var peakMemoryBytes = 0
    private var lastCPUTime: Double = 0
    private var lastSampleDate = Date()
    private var cpuPercent = 0.0

    func begin(_ id: UUID, category: String) {
        lock.withLock { activeIDs[id] = category }
    }

    func end(_ event: PerformanceEvent) {
        lock.withLock {
            activeIDs.removeValue(forKey: event.id)
            total += 1
            if event.wasCancelled { cancelled += 1 }
            phaseTotals["\(event.category) / \(event.name)", default: 0] += event.duration
            if event.duration >= 0.15 || event.wasCancelled {
                recentEvents.insert(event, at: 0)
                if recentEvents.count > 80 { recentEvents.removeLast(recentEvents.count - 80) }
            }
        }
    }

    func snapshot() -> PerformanceDiagnosticsSnapshot {
        lock.withLock {
            let memory = Self.currentMemoryBytes()
            peakMemoryBytes = max(peakMemoryBytes, memory)
            let now = Date()
            let cpuTime = Self.currentCPUTime()
            let wall = now.timeIntervalSince(lastSampleDate)
            if wall > 0, lastCPUTime > 0 {
                cpuPercent = min(999, max(0, (cpuTime - lastCPUTime) / wall * 100))
            }
            lastCPUTime = cpuTime
            lastSampleDate = now
            return PerformanceDiagnosticsSnapshot(
                activeGitTasks: activeIDs.values.filter { $0 == "Git" }.count,
                activeRepositoryTasks: activeIDs.values.filter { $0 != "Git" }.count,
                totalGitCommands: total,
                cancelledGitCommands: cancelled,
                recentSlowOperations: recentEvents,
                currentMemoryBytes: memory,
                peakMemoryBytes: peakMemoryBytes,
                cpuPercent: cpuPercent,
                phaseDurations: phaseTotals
                    .map { PerformancePhaseMetric(name: $0.key, total: $0.value) }
                    .sorted { $0.total > $1.total }
                    .prefix(8)
                    .map { $0 }
            )
        }
    }

    private static func currentMemoryBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    private static func currentCPUTime() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    }
}
