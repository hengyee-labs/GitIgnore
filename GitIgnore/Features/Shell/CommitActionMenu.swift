import SwiftUI

struct CommitActionMenu: View {
    @Environment(AppState.self) private var appState
    let commit: GitCommitSummary

    @State private var confirmation: CommitConfirmation?
    @State private var inputMode: CommitInputMode?

    var body: some View {
        Menu {
            Button("复制完整哈希", systemImage: "doc.on.doc") { appState.copyHash(commit) }
            Button("与父提交对比", systemImage: "arrow.left.arrow.right") {
                Task { await appState.showParentComparison(commit) }
            }
            Divider()
            Button("Cherry-pick 到当前分支", systemImage: "arrow.down.to.line") { confirmation = .cherryPick }
            Button("Revert 这条提交", systemImage: "arrow.uturn.backward") { inputMode = .revert }
            Divider()
            Button("从这里创建分支", systemImage: "arrow.triangle.branch") { inputMode = .branch }
            Button("在这里创建标签", systemImage: "tag") { inputMode = .tag }
            Divider()
            Button("Reset 到这里…", systemImage: "clock.arrow.2.circlepath") { inputMode = .reset }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("提交操作")
        .disabled(appState.isPerformingGitAction)
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )) {
            Button("取消", role: .cancel) { confirmation = nil }
            Button(confirmation?.actionTitle ?? "继续") {
                let action = confirmation
                confirmation = nil
                Task {
                    if action == .cherryPick { await appState.cherryPick(commit) }
                }
            }
        } message: {
            Text(confirmation?.message(commit) ?? "")
        }
        .sheet(item: $inputMode) { mode in
            switch mode {
            case .branch:
                GitNameInputSheet(title: "从提交创建分支", detail: commit.shortHash, placeholder: "feature/new-work") { name in
                    inputMode = nil
                    Task { await appState.createBranch(name: name, at: commit) }
                } cancel: { inputMode = nil }
            case .tag:
                GitNameInputSheet(title: "创建标签", detail: commit.shortHash, placeholder: "v1.0.0") { name in
                    inputMode = nil
                    Task { await appState.createTag(name: name, at: commit) }
                } cancel: { inputMode = nil }
            case .reset:
                ResetPreviewSheet(commit: commit) { inputMode = nil }
            case .revert:
                RevertPreviewSheet(commit: commit) { inputMode = nil }
            }
        }
    }
}

private enum CommitConfirmation {
    case cherryPick

    var title: String { "应用这条提交？" }
    var actionTitle: String { "Cherry-pick" }

    func message(_ commit: GitCommitSummary) -> String {
        "将 \(commit.shortHash) 的改动应用到当前分支；如有冲突，将进入冲突处理流程。"
    }
}

private enum CommitInputMode: String, Identifiable {
    case branch
    case tag
    case reset
    case revert
    var id: Self { self }
}

struct GitNameInputSheet: View {
    let title: String
    let detail: String
    let placeholder: String
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).orbitFont(.headline)
            Text("基于 \(detail)").orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            TextField(placeholder, text: $value).textFieldStyle(.roundedBorder).onSubmit { submit(value) }
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("创建") { submit(value) }
                    .buttonStyle(.borderedProminent)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct ResetPreviewSheet: View {
    @Environment(AppState.self) private var appState
    let commit: GitCommitSummary
    let dismiss: () -> Void
    @State private var mode: GitResetMode = .mixed
    @State private var preview: GitOperationPreview?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                OrbitIconBadge(systemName: "clock.arrow.2.circlepath", color: OrbitDesign.coral, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset 预览").orbitFont(.headline)
                    Text("目标提交 \(commit.shortHash)").orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                }
            }
            Picker("处理文件变更", selection: $mode) {
                ForEach(GitResetMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            Text(mode.explanation).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)

            if isLoading {
                HStack { ProgressView().controlSize(.small); Text("正在计算影响范围…") }
                    .orbitFont(.caption)
            } else if let preview {
                Text(preview.summary).orbitFont(.callout, weight: .semibold)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(preview.affectedFiles, id: \.self) { path in
                            Text(path).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 170)
                .padding(10)
                .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Label(mode == .hard ? "未提交内容将无法恢复" : "本地内容会按所选模式保留", systemImage: mode == .hard ? "exclamationmark.triangle" : "checkmark.circle")
                    .orbitFont(.caption).foregroundStyle(mode == .hard ? OrbitDesign.coral : OrbitDesign.accent)
                Spacer()
                Button("取消", action: dismiss).keyboardShortcut(.cancelAction)
                Button("执行 Reset", role: mode == .hard ? .destructive : nil) {
                    dismiss()
                    Task { await appState.reset(to: commit, mode: mode) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || preview == nil)
            }
        }
        .padding(20)
        .frame(width: 540, height: 390)
        .task {
            preview = await appState.resetPreview(for: commit)
            isLoading = false
        }
    }
}

private struct RevertPreviewSheet: View {
    @Environment(AppState.self) private var appState
    let commit: GitCommitSummary
    let dismiss: () -> Void
    @State private var preview: GitOperationPreview?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                OrbitIconBadge(systemName: "arrow.uturn.backward", color: OrbitDesign.coral, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revert 预览").orbitFont(.headline)
                    Text("提交 \(commit.shortHash) · \(commit.subject)")
                        .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
                }
            }
            if isLoading {
                HStack { ProgressView().controlSize(.small); Text("正在读取影响文件…") }.orbitFont(.caption)
            } else if let preview {
                Text(preview.summary).orbitFont(.callout, weight: .semibold)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(preview.affectedFiles, id: \.self) { path in
                            Text(path).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Label("通过新提交撤销，不改写原提交", systemImage: "arrow.uturn.backward.circle")
                    .orbitFont(.caption).foregroundStyle(OrbitDesign.accent)
                Spacer()
                Button("取消", action: dismiss).keyboardShortcut(.cancelAction)
                Button("创建反向提交", role: .destructive) {
                    dismiss()
                    Task { await appState.revertCommit(commit) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || preview == nil)
            }
        }
        .padding(20)
        .frame(width: 540, height: 360)
        .task {
            preview = await appState.revertPreview(for: commit)
            isLoading = false
        }
    }
}
