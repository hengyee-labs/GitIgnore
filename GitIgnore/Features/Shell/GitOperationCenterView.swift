import AppKit
import SwiftUI

struct GitOperationCenterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()

    private var records: [GitOperationRecord] {
        appState.workflows.recentOperations
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitDesign.separator)
            if records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(records) { record in
                            operationRow(record)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 410)
        .background(OrbitDesign.canvas)
        .task(id: appState.workflows.activeOperation?.id) {
            guard appState.workflows.activeOperation != nil else { return }
            while !Task.isCancelled, appState.workflows.activeOperation != nil {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            OrbitIconBadge(systemName: "waveform.path.ecg", color: OrbitDesign.violet, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Git 操作中心").orbitFont(.headline)
                Text(appState.workflows.activeOperation == nil ? "当前没有运行中的操作" : "同一仓库的写操作正在串行执行")
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            if records.contains(where: { $0.phase.isFinished }) {
                Button("清除记录") { appState.clearFinishedGitOperations() }
                    .buttonStyle(.plain)
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .padding(14)
    }

    private func operationRow(_ record: GitOperationRecord) -> some View {
        HStack(alignment: .top, spacing: 11) {
            phaseIcon(record)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(record.title)
                        .orbitFont(.callout, weight: .semibold)
                        .lineLimit(1)
                    Text(phaseTitle(record.phase))
                        .orbitFont(.caption2, weight: .bold)
                        .foregroundStyle(phaseColor(record.phase))
                }
                Text(URL(fileURLWithPath: record.repositoryPath).lastPathComponent)
                    .font(.caption2.monospaced())
                    .foregroundStyle(OrbitDesign.secondaryText)
                if let detail = record.detail, !detail.isEmpty {
                    Text(detail)
                        .orbitFont(.caption2)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(duration(record.elapsed))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OrbitDesign.secondaryText)
                if record.phase == .failed, let detail = record.detail {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(detail, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .help("复制失败诊断")
                }
            }
        }
        .padding(10)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(phaseColor(record.phase).opacity(record.phase.isFinished ? 0.18 : 0.34), lineWidth: 1)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func phaseIcon(_ record: GitOperationRecord) -> some View {
        if record.phase == .running || record.phase == .refreshing {
            ProgressView().controlSize(.small).tint(phaseColor(record.phase))
        } else {
            Image(systemName: record.phase == .succeeded ? "checkmark.circle.fill" :
                    (record.phase == .failed ? "xmark.circle.fill" : record.kind.symbol))
                .foregroundStyle(phaseColor(record.phase))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OrbitDesign.accent)
            Text("操作记录会显示在这里").orbitFont(.callout, weight: .semibold)
            Text("可查看排队、执行、刷新和失败诊断。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func phaseTitle(_ phase: GitOperationPhase) -> String {
        switch phase {
        case .queued: "等待中"
        case .running: "执行中"
        case .refreshing: "正在刷新"
        case .succeeded: "已完成"
        case .failed: "未完成"
        }
    }

    private func phaseColor(_ phase: GitOperationPhase) -> Color {
        switch phase {
        case .queued: OrbitDesign.secondaryText
        case .running, .refreshing: OrbitDesign.violet
        case .succeeded: OrbitDesign.accent
        case .failed: OrbitDesign.coral
        }
    }

    private func duration(_ interval: TimeInterval) -> String {
        interval < 60 ? String(format: "%.1fs", interval) : String(format: "%.1fm", interval / 60)
    }
}
