import AppKit
import Darwin
import Foundation

// Usage: swift Tools/app-performance-sample.swift PID SECONDS OUTPUT.json PHASE
let arguments = CommandLine.arguments
guard arguments.count == 5, let pid = Int32(arguments[1]), let seconds = Double(arguments[2]),
      seconds >= 1, seconds <= 600,
      let application = NSRunningApplication(processIdentifier: pid),
      ["com.hengyee.Orbit", "com.hengyee.GitIgnore.Regression"].contains(application.bundleIdentifier ?? "") else {
    fatalError("Expected a running GitIgnore PID, duration 1...600, output JSON path and phase label")
}
struct Sample: Codable {
    let elapsedSeconds: Double
    let residentBytes: UInt64
    let cpuPercent: Double
}
let start = ProcessInfo.processInfo.systemUptime
var samples: [Sample] = []
var previousCPU: UInt64?
var previousWall = start
while ProcessInfo.processInfo.systemUptime - start < seconds {
    guard !application.isTerminated else { break }
    var info = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { break }
    let now = ProcessInfo.processInfo.systemUptime
    let total = info.pti_total_user + info.pti_total_system
    if let previousCPU, total >= previousCPU, now > previousWall {
        samples.append(Sample(elapsedSeconds: now - start, residentBytes: info.pti_resident_size,
                              cpuPercent: Double(total - previousCPU) / 1_000_000_000 / (now - previousWall) * 100))
    }
    previousCPU = total
    previousWall = now
    Thread.sleep(forTimeInterval: 0.5)
}
struct Report: Codable {
    let phase: String
    let pid: Int32
    let uiActionsAutomated = false
    let samples: [Sample]
    let meanCPUPercent: Double
    let peakResidentBytes: UInt64
    let finalResidentBytes: UInt64
    let memoryGrowthBytes: Int64
}
let report = Report(phase: arguments[4], pid: pid, samples: samples,
                    meanCPUPercent: samples.reduce(0) { $0 + $1.cpuPercent } / Double(max(1, samples.count)),
                    peakResidentBytes: samples.map(\.residentBytes).max() ?? 0,
                    finalResidentBytes: samples.last?.residentBytes ?? 0,
                    memoryGrowthBytes: Int64(samples.last?.residentBytes ?? 0) - Int64(samples.first?.residentBytes ?? 0))
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(report).write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
print("\(report.phase): \(samples.count) samples, mean CPU \(String(format: "%.2f", report.meanCPUPercent))%, peak RSS \(report.peakResidentBytes / 1_048_576) MiB, final RSS \(report.finalResidentBytes / 1_048_576) MiB")
