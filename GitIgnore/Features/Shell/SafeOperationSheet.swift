import SwiftUI

struct SafeOperationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let request: SafeGitOperationRequest
    @State private var strategy = LocalChangesStrategy.restore
    @State private var isRunning = false
    @State private var confirmsDiscard = false

    private var hasLocalChanges: Bool { request.changedFileCount > 0 && request.kind != .deleteBranch }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    route
                    impactSummary
                    if hasLocalChanges { strategySection }
                    affectedFiles
                    protectionNote
                }
                .padding(22)
            }
            Divider().overlay(OrbitDesign.separator)
            footer.padding(.horizontal, 22).frame(height: 64).background(OrbitDesign.sidebar)
        }
        .frame(width: 620, height: 610)
        .background(OrbitDesign.canvas)
        .interactiveDismissDisabled(isRunning)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation, value: strategy)
        .alert("确认丢弃操作前的本地修改？", isPresented: $confirmsDiscard) {
            Button("取消", role: .cancel) {}
            Button("丢弃并执行", role: .destructive) { run() }
        } message: {
            Text("本地修改会先临时保存到 Stash；只有 Git 操作成功后才会按你的选择删除。")
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            OrbitIconBadge(systemName: request.kind.symbol, color: OrbitDesign.violet, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.kind == .deleteBranch ? "执行 \(request.kind.title)？" : "执行安全 \(request.kind.title)？").orbitFont(.title3, weight: .bold)
                Text("先确认影响范围和本地修改处理方式。")
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
        }
    }

    private var route: some View {
        HStack(spacing: 10) {
            routeNode("当前分支", request.currentBranch, color: OrbitDesign.secondaryText)
            Image(systemName: "arrow.right").orbitFont(.caption, weight: .bold).foregroundStyle(OrbitDesign.violet)
            routeNode("操作目标", request.targetTitle, color: OrbitDesign.violet)
        }
        .padding(13)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func routeNode(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            Text(value).font(.caption.monospaced().weight(.semibold)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var impactSummary: some View {
        HStack(spacing: 8) {
            metric("影响文件", request.preview.affectedFiles.count, OrbitDesign.blue)
            metric("相关提交", request.preview.commitCount, OrbitDesign.violet)
            metric("本地变更", request.changedFileCount, request.changedFileCount > 0 ? OrbitDesign.amber : OrbitDesign.accent)
        }
    }

    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(color)
            Text(title).orbitFont(.caption2, weight: .semibold).foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
    }

    private var strategySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("操作完成后如何处理本地修改").orbitFont(.caption, weight: .bold)
            Picker("本地修改策略", selection: $strategy) {
                Text("自动恢复（推荐）").tag(LocalChangesStrategy.restore)
                Text("保存在 Stash").tag(LocalChangesStrategy.keepInStash)
                Text("操作成功后丢弃").tag(LocalChangesStrategy.discard)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(isRunning)
        }
    }

    private var affectedFiles: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(request.preview.summary).orbitFont(.callout, weight: .semibold)
            if request.preview.affectedFiles.isEmpty {
                Text("预检没有发现会改变内容的文件。")
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(request.preview.affectedFiles, id: \.self) { path in
                            Text(path).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 135)
                .padding(10)
                .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
            }
        }
    }

    private var protectionNote: some View {
        Label("有本地修改时会先临时保存到 Stash；冲突会直接打开内置冲突编辑器。", systemImage: "tray.and.arrow.down")
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitDesign.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack {
            if isRunning { ProgressView().controlSize(.small); Text("正在执行…").orbitFont(.caption) }
            Spacer()
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isRunning)
            Button(hasLocalChanges ? "暂存本地修改并执行" : "确认执行", role: strategy == .discard ? .destructive : nil) {
                if strategy == .discard { confirmsDiscard = true } else { run() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isRunning)
        }
    }

    private func run() {
        isRunning = true
        let selectedStrategy = hasLocalChanges ? strategy : .restore
        dismiss()
        Task { await appState.performSafeOperation(request, strategy: selectedStrategy) }
    }
}
