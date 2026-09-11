import SwiftUI
import AppKit

struct PerformanceDiagnosticsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = PerformanceDiagnostics.snapshot()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                OrbitIconBadge(systemName: "gauge.with.dots.needle.67percent", color: OrbitDesign.blue, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLanguage.text("性能诊断", "Performance Diagnostics")).orbitFont(.headline)
                    Text(AppLanguage.text(
                        "查看缓存、后台任务和需关注的操作，不读取仓库文件内容",
                        "Inspect caches, background tasks, and operations that need attention without reading repository contents"
                    ))
                        .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                Button { exportReport() } label: {
                    Label(AppLanguage.text("导出", "Export"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(AppLanguage.text("关闭", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider().overlay(OrbitDesign.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        metric(AppLanguage.text("活动 Git 任务", "Active Git Tasks"), snapshot.activeGitTasks, OrbitDesign.blue)
                        metric(AppLanguage.text("仓库后台任务", "Repository Tasks"), snapshot.activeRepositoryTasks, OrbitDesign.accent)
                        metric(AppLanguage.text("累计命令", "Total Commands"), snapshot.totalGitCommands, OrbitDesign.violet)
                        metric(AppLanguage.text("已取消", "Cancelled"), snapshot.cancelledGitCommands, OrbitDesign.amber)
                    }
                    HStack(spacing: 10) {
                        metricText(AppLanguage.text("当前内存", "Memory"), ByteCountFormatter.string(fromByteCount: Int64(snapshot.currentMemoryBytes), countStyle: .memory), OrbitDesign.coral)
                        metricText(AppLanguage.text("峰值内存", "Peak Memory"), ByteCountFormatter.string(fromByteCount: Int64(snapshot.peakMemoryBytes), countStyle: .memory), OrbitDesign.amber)
                        metricText(AppLanguage.text("当前 CPU", "CPU"), String(format: "%.1f%%", snapshot.cpuPercent), OrbitDesign.blue)
                    }
                    cacheSection
                    phaseSection
                    slowOperations
                }
                .padding(18)
            }
        }
        .frame(width: 720, height: 560)
        .background(OrbitDesign.canvas)
        .task {
            while !Task.isCancelled {
                snapshot = PerformanceDiagnostics.snapshot()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(color)
            Text(title).orbitFont(.caption2, weight: .semibold).foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func metricText(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(color)
            Text(title).orbitFont(.caption2, weight: .semibold).foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(AppLanguage.text("内存缓存", "Memory Caches")).orbitFont(.headline)
            diagnosticRow(
                AppLanguage.text("提交详情", "Commit Details"),
                AppLanguage.text("\(appState.commitDetailCache.count) / 24 项", "\(appState.commitDetailCache.count) / 24 items"),
                bytes: appState.commitDetailCacheBytes.values.reduce(0, +)
            )
            diagnosticRow(
                AppLanguage.text("文件 Diff", "File Diffs"),
                AppLanguage.text("\(appState.commitFileDiffCache.count) / 6 项", "\(appState.commitFileDiffCache.count) / 6 items"),
                bytes: appState.commitFileDiffCacheBytes.values.reduce(0, +)
            )
            diagnosticRow(
                AppLanguage.text("待刷新路径", "Pending Refresh Paths"),
                AppLanguage.text("\(appState.pendingLiveRefreshPaths.count) / 128 项", "\(appState.pendingLiveRefreshPaths.count) / 128 items"),
                bytes: nil
            )
        }
    }

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(AppLanguage.text("阶段耗时", "Phase Durations")).orbitFont(.headline)
                Spacer()
                Text(AppLanguage.text("累计", "Total")).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            }
            if snapshot.phaseDurations.isEmpty {
                Text(AppLanguage.text("完成几次刷新或 Git 操作后会显示阶段耗时。", "Phase timings appear after refreshes or Git operations complete."))
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            } else {
                ForEach(snapshot.phaseDurations) { phase in
                    diagnosticRow(phase.name, "", bytes: nil, trailing: String(format: "%.0f ms", phase.total * 1_000))
                }
            }
        }
    }

    @ViewBuilder
    private var slowOperations: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(AppLanguage.text("最近需关注的操作", "Recent Operations to Review")).orbitFont(.headline)
                Spacer()
                Text(AppLanguage.text("慢操作 ≥ 150ms，同时保留取消记录", "Slow ≥ 150ms; cancellations retained"))
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            if snapshot.recentSlowOperations.isEmpty {
                Text(AppLanguage.text("暂时没有需要关注的操作。", "No operations need attention."))
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(snapshot.recentSlowOperations) { event in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(event.wasCancelled ? OrbitDesign.secondaryText : (event.duration >= 1 ? OrbitDesign.coral : OrbitDesign.amber))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.name).font(.caption.monospaced()).lineLimit(1)
                                Text(event.category).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
                            }
                            Spacer()
                            if event.wasCancelled {
                                Text(AppLanguage.text("已取消", "Cancelled"))
                                    .foregroundStyle(OrbitDesign.secondaryText)
                            }
                            if event.bytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(event.bytes), countStyle: .file))
                            }
                            Text(String(format: "%.0f ms", event.duration * 1_000))
                                .foregroundStyle(event.wasCancelled ? OrbitDesign.secondaryText : (event.duration >= 1 ? OrbitDesign.coral : OrbitDesign.amber))
                        }
                        .orbitFont(.caption2, weight: .semibold)
                        .padding(.vertical, 8)
                        Divider().overlay(OrbitDesign.separator.opacity(0.7))
                    }
                }
            }
        }
    }

    private func diagnosticRow(_ title: String, _ count: String, bytes: Int?, trailing: String? = nil) -> some View {
        HStack {
            Text(title).orbitFont(.callout)
            Spacer()
            Text(count).font(.caption.monospacedDigit()).foregroundStyle(OrbitDesign.secondaryText)
            if let bytes {
                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))
                    .font(.caption.monospacedDigit()).frame(width: 76, alignment: .trailing)
            }
            if let trailing {
                Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .padding(10)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GitIgnore-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = [
            "GitIgnore Performance Diagnostics",
            "Generated: \(Date())",
            "Memory: \(snapshot.currentMemoryBytes) bytes (peak \(snapshot.peakMemoryBytes))",
            "CPU: \(snapshot.cpuPercent)%",
            "Active Git tasks: \(snapshot.activeGitTasks)",
            "Active repository tasks: \(snapshot.activeRepositoryTasks)",
            "Total commands: \(snapshot.totalGitCommands)",
            "Cancelled commands: \(snapshot.cancelledGitCommands)",
            "",
            "Phase durations:",
            snapshot.phaseDurations.map { "- \($0.name): \(Int($0.total * 1000)) ms" }.joined(separator: "\n")
        ].joined(separator: "\n")
        try? lines.write(to: url, atomically: true, encoding: .utf8)
    }
}
