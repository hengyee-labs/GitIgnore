import SwiftUI

struct BranchActionMenu: View {
    @Environment(AppState.self) private var appState
    let branch: GitBranchSummary

    @State private var confirmation: BranchConfirmation?
    @State private var inputMode: BranchInputMode?

    var body: some View {
        Menu {
            if !branch.isCurrent {
                Button("合并到当前分支", systemImage: "arrow.triangle.merge") { confirmation = .merge }
                Button("当前分支 Rebase 到这里", systemImage: "arrow.triangle.swap") { confirmation = .rebase }
                Divider()
            }
            Button("重命名", systemImage: "pencil") { inputMode = .rename }
            if branch.needsPublish {
                Button(AppLanguage.text("发布到远程", "Publish to Remote"), systemImage: "arrow.up.right") {
                    Task { await appState.publishCurrentBranch() }
                }
            }
            Button("设置上游分支", systemImage: "link") { inputMode = .upstream }
            if !branch.isCurrent {
                Divider()
                Button("安全删除", systemImage: "trash", role: .destructive) { confirmation = .delete }
                Button("强制删除…", systemImage: "trash.slash", role: .destructive) { confirmation = .forceDelete }
            }
        } label: {
            Image(systemName: "ellipsis")
                .orbitFont(.caption, weight: .bold)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("分支操作")
        .disabled(appState.isPerformingGitAction)
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )) {
            Button("取消", role: .cancel) { confirmation = nil }
            Button(confirmation?.actionTitle ?? "继续", role: confirmation?.isDestructive == true ? .destructive : nil) {
                let action = confirmation
                confirmation = nil
                Task {
                    switch action {
                    case .merge: await appState.merge(branch)
                    case .rebase: await appState.rebase(onto: branch)
                    case .delete: await appState.deleteBranch(branch, force: false)
                    case .forceDelete: await appState.deleteBranch(branch, force: true)
                    case nil: break
                    }
                }
            }
        } message: {
            Text(confirmation?.message(branch) ?? "")
        }
        .sheet(item: $inputMode) { mode in
            GitNameInputSheet(
                title: mode == .rename ? "重命名分支" : "设置上游分支",
                detail: branch.name,
                placeholder: mode == .rename ? branch.name : "origin/\(branch.name)"
            ) { value in
                inputMode = nil
                Task {
                    if mode == .rename { await appState.renameBranch(branch, to: value) }
                    else { await appState.setUpstream(for: branch, to: value) }
                }
            } cancel: { inputMode = nil }
        }
    }
}

private enum BranchInputMode: String, Identifiable {
    case rename
    case upstream
    var id: Self { self }
}

private enum BranchConfirmation {
    case merge
    case rebase
    case delete
    case forceDelete

    var title: String {
        switch self {
        case .merge: "合并这个分支？"
        case .rebase: "执行 Rebase？"
        case .delete: "删除这个分支？"
        case .forceDelete: "强制删除分支？"
        }
    }

    var actionTitle: String {
        switch self {
        case .merge: "合并"
        case .rebase: "Rebase"
        case .delete: "删除"
        case .forceDelete: "强制删除"
        }
    }

    var isDestructive: Bool { self == .delete || self == .forceDelete }

    func message(_ branch: GitBranchSummary) -> String {
        switch self {
        case .merge: "将 \(branch.name) 合并到当前分支；如有本地修改，会先临时保存在 Stash。"
        case .rebase: "将当前分支的提交重放到 \(branch.name)；如有本地修改，会先临时保存在 Stash。"
        case .delete: "只会删除已经合并的 \(branch.name)。"
        case .forceDelete: "即使尚未合并也会删除 \(branch.name)；删除后只能通过 Git Reflog 手动找回。"
        }
    }
}

struct SafeBranchSwitchSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let request: SafeBranchSwitchRequest
    @State private var isRunning = false
    @State private var strategy: SafeBranchSwitchStrategy = .restore
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                branchRoute
                changeSummary
                strategyPicker
                explanation
            }
            .padding(22)

            Divider().overlay(OrbitDesign.separator)
            footer
                .padding(.horizontal, 22)
                .frame(height: 64)
                .background(OrbitDesign.sidebar)
        }
        .frame(width: 540)
        .background(OrbitDesign.canvas)
        .interactiveDismissDisabled(isRunning)
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation,
            value: isRunning
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation,
            value: strategy
        )
        .alert("确认丢弃本地修改？", isPresented: $confirmsDiscard) {
            Button("取消", role: .cancel) {}
            Button("丢弃并切换", role: .destructive) { runSafeSwitch() }
        } message: {
            Text("GitIgnore 会先保护修改并切换分支，只有切换成功后才删除这次临时 Stash。删除后无法在 Stash 列表中恢复。")
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            OrbitIconBadge(systemName: "arrow.triangle.branch", color: OrbitDesign.violet, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text("保护本地修改后切换？")
                    .orbitFont(.title3, weight: .bold)
                Text("Git 已阻止可能覆盖文件的分支切换。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
        }
    }

    private var branchRoute: some View {
        HStack(spacing: 10) {
            branchName(request.currentBranch, caption: "当前分支", color: OrbitDesign.secondaryText)
            Image(systemName: "arrow.right")
                .orbitFont(.caption, weight: .bold)
                .foregroundStyle(OrbitDesign.violet)
                .accessibilityHidden(true)
            branchName(request.targetDisplayName, caption: "目标分支", color: OrbitDesign.violet)
        }
        .padding(13)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func branchName(_ name: String, caption: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .orbitFont(.caption2)
                .foregroundStyle(OrbitDesign.secondaryText)
            Text(name)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changeSummary: some View {
        HStack(spacing: 8) {
            metric("本地变更", value: request.changedFileCount, color: OrbitDesign.amber)
            metric("已暂存", value: request.stagedFileCount, color: OrbitDesign.accent)
            metric("未跟踪", value: request.untrackedFileCount, color: OrbitDesign.blue)
        }
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .orbitFont(.caption2, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
    }

    private var strategyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本地修改处理方式")
                .orbitFont(.caption, weight: .bold)
                .foregroundStyle(OrbitDesign.primaryText)
            Picker("本地修改处理方式", selection: $strategy) {
                Text("切换后自动还原（推荐）").tag(SafeBranchSwitchStrategy.restore)
                Text("保存在 Stash").tag(SafeBranchSwitchStrategy.keepInStash)
                Text("切换后丢弃").tag(SafeBranchSwitchStrategy.discard)
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .disabled(isRunning)
            .accessibilityHint("选择切换分支后如何处理当前本地修改")
        }
        .padding(.horizontal, 2)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(explanationTitle, systemImage: explanationIcon)
                .orbitFont(.caption, weight: .bold)
                .foregroundStyle(strategy == .discard ? OrbitDesign.coral : OrbitDesign.primaryText)
            Text(explanationText)
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(explanationColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(explanationColor.opacity(0.24), lineWidth: 1) }
    }

    private var explanationTitle: String {
        switch strategy {
        case .restore: "保护、切换并还原"
        case .keepInStash: "保护并切换"
        case .discard: "切换成功后丢弃"
        }
    }

    private var explanationIcon: String {
        switch strategy {
        case .restore: "arrow.uturn.backward.circle"
        case .keepInStash: "archivebox"
        case .discard: "trash"
        }
    }

    private var explanationColor: Color {
        strategy == .discard ? OrbitDesign.coral : OrbitDesign.amber
    }

    private var explanationText: String {
        switch strategy {
        case .restore:
            "GitIgnore 会先保护当前修改（包含未跟踪文件），切换后自动还原，并尽量保持原来的暂存状态；若发生冲突，会保留保护 Stash 并打开三栏冲突编辑器。"
        case .keepInStash:
            "GitIgnore 会保护当前修改并切换目标分支，不自动还原；稍后可从 Stash 临时保存中手动恢复。"
        case .discard:
            "GitIgnore 会先保护当前修改，确认分支切换成功后再删除这次临时 Stash。切换失败或删除失败时不会丢失保护内容。"
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isRunning {
                ProgressView().controlSize(.small).tint(OrbitDesign.violet)
                Text("正在保护修改并切换…")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            } else {
                Button("返回工作区") {
                    appState.selectSection(.changes)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isRunning)
            Button(actionTitle) {
                if strategy == .discard {
                    confirmsDiscard = true
                } else {
                    runSafeSwitch()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(strategy == .discard ? OrbitDesign.coral : OrbitDesign.violet)
            .keyboardShortcut(.defaultAction)
            .disabled(isRunning)
        }
    }

    private var actionTitle: String {
        switch strategy {
        case .restore: "保护修改并切换"
        case .keepInStash: "保存到 Stash 并切换"
        case .discard: "丢弃修改并切换"
        }
    }

    private func runSafeSwitch() {
        isRunning = true
        Task {
            _ = await appState.performSafeBranchSwitch(request, strategy: strategy)
            isRunning = false
            dismiss()
        }
    }
}
