import SwiftUI

struct BranchToolsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var base = ""
    @State private var target = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitDesign.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    comparisonControls
                    if let comparison = appState.workflows.branchComparison {
                        comparisonResult(comparison)
                    }
                    cleanupSection
                }
                .padding(18)
            }
        }
        .frame(minWidth: 660, minHeight: 560)
        .background(OrbitDesign.canvas)
        .onAppear {
            let current = appState.branches.first(where: \.isCurrent)?.name ?? appState.branches.first?.name ?? ""
            base = current
            target = appState.branches.first(where: { $0.name != current })?.name ?? current
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            OrbitIconBadge(systemName: "arrow.left.arrow.right", color: OrbitDesign.blue, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("分支比较与清理").orbitFont(.title3, weight: .bold)
                Text("比较提交与文件差异，并只清理已合并的本地分支。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var comparisonControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("比较分支", systemImage: "arrow.left.arrow.right")
                .orbitFont(.headline)
            HStack(spacing: 10) {
                branchPicker(title: "基准", selection: $base)
                Image(systemName: "arrow.right")
                    .foregroundStyle(OrbitDesign.secondaryText)
                branchPicker(title: "目标", selection: $target)
                Button("开始比较") {
                    Task { await appState.compareBranches(base: base, target: target) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(base.isEmpty || target.isEmpty || base == target || appState.workflows.isLoadingPreview)
            }
            if appState.workflows.isLoadingPreview {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func branchPicker(title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 7) {
            Text(title).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            Picker(title, selection: selection) {
                ForEach(appState.branches) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .labelsHidden()
            .frame(minWidth: 150)
        }
    }

    private func comparisonResult(_ comparison: GitBranchComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                metric("目标独有", comparison.ahead, OrbitDesign.accent)
                metric("基准独有", comparison.behind, OrbitDesign.amber)
                metric("变化文件", comparison.changedFiles.count, OrbitDesign.blue)
            }
            if !comparison.commits.isEmpty {
                Text("目标分支新增提交").orbitFont(.caption, weight: .bold).foregroundStyle(OrbitDesign.secondaryText)
                ForEach(comparison.commits.prefix(20)) { commit in
                    HStack(spacing: 9) {
                        Circle().fill(OrbitDesign.violet).frame(width: 7, height: 7)
                        Text(commit.shortHash).font(.caption2.monospaced()).foregroundStyle(OrbitDesign.secondaryText)
                        Text(commit.subject).orbitFont(.caption).lineLimit(1)
                        Spacer()
                        Text(commit.author).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
                    }
                }
            }
            if !comparison.changedFiles.isEmpty {
                DisclosureGroup("查看 \(comparison.changedFiles.count) 个变化文件") {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(comparison.changedFiles, id: \.self) { path in
                            Label(path, systemImage: "doc")
                                .font(.caption.monospaced())
                                .foregroundStyle(OrbitDesign.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                }
                .orbitFont(.caption, weight: .semibold)
            }
        }
        .padding(14)
        .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.blue.opacity(0.28), lineWidth: 1) }
    }

    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(color)
            Text(title).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 7))
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已合并分支清理").orbitFont(.headline)
                    Text("自动排除当前分支、main、master、develop 和未合并分支。")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                Button("重新分析") { Task { await appState.analyzeMergedBranches() } }
                    .buttonStyle(.bordered)
            }
            if appState.workflows.mergedBranchCandidates.isEmpty {
                Text("尚未发现可安全清理的本地分支。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            } else {
                ForEach(appState.workflows.mergedBranchCandidates, id: \.self) { branch in
                    HStack {
                        Label(branch, systemImage: "checkmark.circle")
                            .orbitFont(.callout, weight: .medium)
                        Spacer()
                        Button("删除", role: .destructive) {
                            Task { await appState.deleteMergedBranch(branch) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(9)
                    .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(14)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
        .task { await appState.analyzeMergedBranches() }
    }
}
