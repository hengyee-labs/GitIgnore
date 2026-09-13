import SwiftUI

struct CommitInspector: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilePath: String?
    @State private var expandedDiffPaths: Set<String> = []
    let commit: GitCommitSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorEyebrow(AppLanguage.text("提交详情", "Commit Details"))
                Text(commit.subject)
                    .orbitFont(.title3, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)
                authorRow
                if !commit.parents.isEmpty {
                    Picker(AppLanguage.text("对比父提交", "Compare with Parent"), selection: Binding(
                        get: { appState.selectedCommitParent ?? commit.parents[0] },
                        set: { parent in
                            selectedFilePath = nil
                            Task { await appState.selectCommit(commit, parent: parent) }
                        }
                    )) {
                        ForEach(Array(commit.parents.enumerated()), id: \.element) { index, hash in
                            Text(AppLanguage.text("父提交 \(index + 1) · \(hash.prefix(8))", "Parent \(index + 1) · \(hash.prefix(8))")).tag(hash)
                        }
                    }
                    .controlSize(.small)
                    if commit.parents.count == 1 {
                        Button {
                            Task { await appState.showParentComparison(commit) }
                        } label: {
                            Label(AppLanguage.text("查看父提交差异", "View Parent Diff"), systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(AppLanguage.text("将这次提交与父提交进行对比", "Compare this commit with its parent"))
                    }
                }
                Divider()
                detailRow(AppLanguage.text("短哈希", "Short Hash"), value: commit.shortHash, monospaced: true)
                detailRow(AppLanguage.text("完整哈希", "Full Hash"), value: commit.hash, monospaced: true)
                HStack {
                    Text("提交操作")
                        .orbitFont(.caption, weight: .bold)
                        .foregroundStyle(OrbitDesign.secondaryText)
                    Spacer()
                    CommitActionMenu(commit: commit)
                }
                if !commit.refs.isEmpty {
                    detailRow(AppLanguage.text("引用", "References"), value: commit.refs.joined(separator: ", "))
                }
                HStack(spacing: 8) {
                    statusPill(title: AppLanguage.text("当前分支", "Current branch"), value: appState.repository?.branch ?? "-")
                    statusPill(title: AppLanguage.text("提交范围", "Scope"), value: commit.refs.isEmpty ? AppLanguage.text("本地", "Local") : AppLanguage.text("已引用", "Referenced"))
                }

                if appState.isLoadingCommitDetail {
                    loadingState
                } else if let detail = appState.selectedCommitDetail {
                    commitContent(detail)
                } else {
                    Text("没有读取到这条提交的详细内容。")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
            }
            .padding(20)
        }
    }

    private var authorRow: some View {
        HStack(spacing: 9) {
            CommitAuthorAvatarView(author: commit.author, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.author).orbitFont(.caption, weight: .semibold)
                Text(commit.dateText).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在读取提交内容…")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func commitContent(_ detail: GitCommitDetail) -> some View {
        let normalizedMessage = detail.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedMessage.isEmpty, normalizedMessage != commit.subject {
            VStack(alignment: .leading, spacing: 6) {
                Text("提交说明")
                    .orbitFont(.caption, weight: .bold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                Text(normalizedMessage)
                    .orbitFont(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if detail.files.isEmpty {
            Text("这条提交没有文件内容可显示。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
        } else {
            filePicker(detail)
        }
    }

    private func filePicker(_ detail: GitCommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("变更文件 · \(detail.files.count)")
                .orbitFont(.caption, weight: .bold)
                .foregroundStyle(OrbitDesign.secondaryText)

            LazyVStack(spacing: 8) {
                ForEach(detail.files) { file in
                    let isSelected = selectedFile(in: detail)?.path == file.path
                    VStack(spacing: 0) {
                        Button {
                            if isSelected {
                                selectedFilePath = nil
                                appState.clearSelectedCommitFilePreview()
                            } else {
                                selectedFilePath = file.path
                                Task { await appState.selectCommitFile(file, in: commit) }
                            }
                        } label: {
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(commitFileColor(file.kind))
                                    .frame(width: 4, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                        .orbitFont(.caption, weight: .semibold)
                                        .foregroundStyle(OrbitDesign.primaryText)
                                        .lineLimit(1)
                                    Text(parentPath(file.path))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(OrbitDesign.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 5)
                                if let added = file.addedLines, let removed = file.removedLines {
                                    Text("+\(added) −\(removed)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(OrbitDesign.secondaryText)
                                        .fixedSize()
                                }
                                Text(file.kind.title)
                                    .orbitFont(.caption2, weight: .semibold)
                                    .foregroundStyle(commitFileColor(file.kind))
                                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isSelected ? OrbitDesign.accent : OrbitDesign.secondaryText)
                            }
                            .padding(.horizontal, 9)
                            .frame(minHeight: 42)
                        }
                        .buttonStyle(.plain)
                        .help(isSelected ? AppLanguage.text("收起文件变更", "Collapse File Changes") : AppLanguage.text("查看文件变更", "View File Changes"))

                        if isSelected {
                            Divider().overlay(OrbitDesign.accent.opacity(0.18))
                            inlineFileDiff(file)
                                .padding(9)
                        }
                    }
                    .background(isSelected ? OrbitDesign.accent.opacity(0.09) : OrbitDesign.surface,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? OrbitDesign.accent.opacity(0.45) : OrbitDesign.separator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func inlineFileDiff(_ file: GitCommitFileChange) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(file.path)
                .font(.caption2.monospaced())
                .foregroundStyle(OrbitDesign.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if appState.isLoadingCommitFileDiff {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取这个文件的变更…")
                }
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
                .padding(.vertical, 8)
            } else if let fileDiff = appState.selectedCommitFileDiff, fileDiff.text.isEmpty {
                Text("没有可显示的文本差异，可能是二进制文件或仅发生了模式变更。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else if let fileDiff = appState.selectedCommitFileDiff {
                let plan = fileDiff.interactivePreviewPlan
                if plan.isBudgeted && !expandedDiffPaths.contains(file.path) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            AppLanguage.text("这个 Diff 较大，已暂缓渲染完整代码。", "This Diff is large, so full rendering is deferred."),
                            systemImage: "speedometer"
                        )
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        Text(AppLanguage.text(
                            "文件列表和变更统计仍可用，点击后再加载代码内容。",
                            "File metadata and change counts remain available. Load code only when needed."
                        ))
                        .orbitFont(.caption2)
                        .foregroundStyle(OrbitDesign.tertiaryText)
                        Button {
                            expandedDiffPaths.insert(file.path)
                        } label: {
                            Label(AppLanguage.text("加载完整 Diff", "Load Full Diff"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 8)
                } else {
                    HStack {
                        Spacer()
                        Button {
                            appState.presentDiffFocus()
                        } label: {
                            Label(AppLanguage.text("完整阅读", "Full Reader"), systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    OrbitDiffViewer(diff: fileDiff, title: AppLanguage.text("当前文件变更", "File Changes"))
                        .id("\(commit.id)-\(file.path)")
                        .padding(.top, 4)
                }
            }
        }
    }

    private func selectedFile(in detail: GitCommitDetail) -> GitCommitFileChange? {
        let path = appState.selectedCommitFilePath ?? selectedFilePath
        if let path,
           let selected = detail.files.first(where: { $0.path == path }) {
            return selected
        }
        return nil
    }

    private func parentPath(_ path: String) -> String {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return parent == "." || parent == "/" ? AppLanguage.text("项目根目录", "Repository Root") : parent
    }

    private func commitFileColor(_ kind: GitFileChangeKind) -> Color {
        switch kind {
        case .modified: OrbitDesign.amber
        case .added: OrbitDesign.accent
        case .deleted: OrbitDesign.coral
        case .renamed: OrbitDesign.violet
        case .untracked: OrbitDesign.blue
        case .conflicted: OrbitDesign.coral
        }
    }

    private func statusPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            Text(value).orbitFont(.caption2, weight: .semibold).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 7))
    }
}
