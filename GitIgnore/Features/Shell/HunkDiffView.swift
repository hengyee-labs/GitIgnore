import SwiftUI

struct HunkDiffView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let diff: GitFileDiff
    let file: GitFileStatus

    @State private var discardTarget: GitPatchHunk?
    @State private var lineSelections: [String: Set<Int>] = [:]
    @State private var discardLineTarget: GitPatchHunk?
    @State private var confirmsFileDiscard = false
    @State private var lineSelectionHunkIDs: Set<String> = []

    var body: some View {
        let plan = diff.interactivePreviewPlan
        let visibleHunks = Array(diff.document.hunks.prefix(plan.renderedHunkLimit))
        LazyVStack(alignment: .leading, spacing: 12) {
            summary
            if plan.isBudgeted {
                performanceGuard(plan: plan, visibleHunkCount: visibleHunks.count)
            }
            if !diff.supportsInlinePreview {
                EmptyView()
            } else if diff.document.hunks.isEmpty {
                OrbitDiffViewer(diff: diff)
            } else {
                hunkOperationIntro(plan: plan, visibleHunkCount: visibleHunks.count)
                ForEach(Array(visibleHunks.enumerated()), id: \.element.id) { index, hunk in
                    hunkCard(hunk, index: index, plan: plan)
                }
            }
        }
        .onChange(of: diff.path) { _, _ in
            lineSelectionHunkIDs.removeAll()
            lineSelections.removeAll()
        }
        .alert("丢弃这个区块的修改？", isPresented: Binding(
            get: { discardTarget != nil },
            set: { if !$0 { discardTarget = nil } }
        )) {
            Button("取消", role: .cancel) { discardTarget = nil }
            Button("丢弃区块", role: .destructive) {
                guard let target = discardTarget else { return }
                discardTarget = nil
                Task { await appState.discardHunk(target) }
            }
        } message: {
            Text("所选区块将永久从工作区移除，此操作无法撤销。")
        }
        .alert(file.kind == .untracked ? "把未跟踪文件移到废纸篓？" : "丢弃这个文件的未暂存修改？", isPresented: $confirmsFileDiscard) {
            Button("取消", role: .cancel) {}
            Button(file.kind == .untracked ? "移到废纸篓" : "丢弃文件修改", role: .destructive) {
                Task { await appState.discardFile(file) }
            }
        } message: {
            Text(file.kind == .untracked
                 ? "未跟踪文件会移到 macOS 废纸篓。"
                 : "未暂存修改将永久丢弃，此操作无法撤销。")
        }
        .alert("丢弃所选代码行？", isPresented: Binding(
            get: { discardLineTarget != nil },
            set: { if !$0 { discardLineTarget = nil } }
        )) {
            Button("取消", role: .cancel) { discardLineTarget = nil }
            Button("丢弃所选行", role: .destructive) {
                guard let hunk = discardLineTarget else { return }
                let selection = lineSelections[hunk.id, default: []]
                discardLineTarget = nil
                Task {
                    await appState.applySelectedLines(in: hunk, selectedIndices: selection, operation: .discard)
                    lineSelections[hunk.id] = []
                }
            }
        } message: {
            Text("只丢弃已勾选的新增或删除行；丢弃后无法撤销。")
        }
    }

    private var summary: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(OrbitDesign.violet)
            Text("\(diff.document.hunks.count) 个修改区块")
                .orbitFont(.caption, weight: .bold)
            Text("+\(diff.document.addedLineCount)")
                .foregroundStyle(OrbitDesign.accent)
            Text("−\(diff.document.removedLineCount)")
                .foregroundStyle(OrbitDesign.coral)
            Spacer()
            if !diff.isStaged {
                Button(file.kind == .untracked ? "移到废纸篓" : "丢弃文件修改", role: .destructive) {
                    confirmsFileDiscard = true
                }
                    .buttonStyle(.plain)
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.coral)
                    .disabled(appState.isPerformingGitAction)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 2)
    }

    private func hunkCard(_ hunk: GitPatchHunk, index: Int, plan: GitDiffInteractivePreviewPlan) -> some View {
        let selectedCount = lineSelections[hunk.id, default: []].count
        let isSelectingLines = lineSelectionHunkIDs.contains(hunk.id)
        let lineLimit = min(plan.renderedLineLimitPerHunk ?? 120, 120)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    toggleLineSelection(hunk.id)
                } label: {
                    Image(systemName: isSelectingLines ? "checklist.checked" : "cursorarrow.rays")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelectingLines ? OrbitDesign.accent : OrbitDesign.secondaryText)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isSelectingLines ? "退出逐行选择" : "逐行选择")

                Text("区块 \(index + 1)")
                    .orbitFont(.caption, weight: .bold)
                Text("+\(hunk.addedLineCount)  −\(hunk.removedLineCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OrbitDesign.secondaryText)
                Spacer()
                if selectedCount > 0 {
                    Text("已选 \(selectedCount) 行")
                        .foregroundStyle(OrbitDesign.accent)
                        .contentTransition(.numericText())
                    if !diff.isStaged && file.kind != .untracked {
                        Button("丢弃所选") { discardLineTarget = hunk }
                            .foregroundStyle(OrbitDesign.coral)
                    }
                    Button(diff.isStaged ? "取消 Stage 所选" : "Stage 所选") {
                        let operation: GitPatchOperation = diff.isStaged ? .unstage : .stage
                        let selection = lineSelections[hunk.id, default: []]
                        Task {
                            await appState.applySelectedLines(in: hunk, selectedIndices: selection, operation: operation)
                            lineSelections[hunk.id] = []
                        }
                    }
                    .foregroundStyle(diff.isStaged ? OrbitDesign.secondaryText : OrbitDesign.accent)
                }
                Button(isSelectingLines ? "完成选择" : "逐行选择") {
                    toggleLineSelection(hunk.id)
                }
                .foregroundStyle(isSelectingLines ? OrbitDesign.secondaryText : OrbitDesign.violet)
                if !diff.isStaged && file.kind != .untracked {
                    Button("丢弃区块") { discardTarget = hunk }
                        .foregroundStyle(OrbitDesign.coral)
                }
                Button(diff.isStaged ? "取消 Stage 区块" : "Stage 区块") {
                    Task {
                        if diff.isStaged { await appState.unstageHunk(hunk) }
                        else { await appState.stageHunk(hunk) }
                    }
                }
                .foregroundStyle(diff.isStaged ? OrbitDesign.secondaryText : OrbitDesign.accent)
            }
            .buttonStyle(.plain)
            .orbitFont(.caption, weight: .semibold)
            .padding(.horizontal, 11)
            .frame(minHeight: 38)
            .background(OrbitDesign.surface)

            if isSelectingLines {
                SelectablePatchView(
                    hunk: hunk,
                    selection: Binding(
                        get: { lineSelections[hunk.id, default: []] },
                        set: { lineSelections[hunk.id] = $0 }
                    ),
                    maxVisibleLines: lineLimit,
                    allowsTextSelection: false
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            } else {
                LightweightPatchPreview(hunk: hunk, maxVisibleLines: lineLimit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
        .disabled(appState.isPerformingGitAction)
    }

    private func performanceGuard(plan: GitDiffInteractivePreviewPlan, visibleHunkCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "speedometer")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(OrbitDesign.amber)
                    .frame(width: 28, height: 28)
                    .background(OrbitDesign.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguage.text("已启用轻量预览", "Lightweight Preview Enabled"))
                        .orbitFont(.caption, weight: .bold)
                        .foregroundStyle(OrbitDesign.primaryText)
                    Text(plan.reason)
                        .orbitFont(.caption2)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Label(AppLanguage.text("显示 \(visibleHunkCount)/\(diff.document.hunks.count) 个区块", "Showing \(visibleHunkCount)/\(diff.document.hunks.count) hunks"), systemImage: "square.stack.3d.up")
                Label(ByteCountFormatter.string(fromByteCount: Int64(diff.byteCount), countStyle: .file), systemImage: "doc.text")
            }
            .orbitFont(.caption2, weight: .semibold)
            .foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(12)
        .background(OrbitDesign.amber.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.amber.opacity(0.18), lineWidth: 1) }
    }

    private func hunkOperationIntro(plan: GitDiffInteractivePreviewPlan, visibleHunkCount: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OrbitDesign.violet)
            Text(AppLanguage.text("区块默认轻量展开，区块级 Stage 可直接操作，需要逐行 Stage 时再开启逐行选择", "Hunks are open in a lightweight view. Use hunk actions directly, or enable line selection only when needed."))
                .orbitFont(.caption2, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if visibleHunkCount < diff.document.hunks.count {
                Text("\(visibleHunkCount)/\(diff.document.hunks.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(OrbitDesign.amber)
            }
            if !appState.isDiffFocusPresented {
                Button {
                    appState.presentDiffFocus()
                } label: {
                    Label(AppLanguage.text("完整阅读", "Full Reader"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .orbitFont(.caption2, weight: .bold)
                .foregroundStyle(OrbitDesign.violet)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(OrbitDesign.elevatedSurface, in: Capsule())
                .overlay { Capsule().stroke(OrbitDesign.separator, lineWidth: 1) }
                .help(AppLanguage.text("在专注模式中阅读完整 Diff", "Read the full Diff in focus mode"))
                .accessibilityHint(AppLanguage.text("保留当前文件选择并铺满内容区域", "Keep the current file selected and fill the content area"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func toggleLineSelection(_ id: String) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.16)) {
            if lineSelectionHunkIDs.contains(id) {
                lineSelectionHunkIDs.remove(id)
            } else {
                lineSelectionHunkIDs.insert(id)
            }
        }
    }
}
