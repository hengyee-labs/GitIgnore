import AppKit
import SwiftUI

struct RepositoryToolsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = RepositoryToolKind.history
    @State private var report = RepositoryToolReport()
    @State private var isReportLoading = false
    @State private var isHealthCheckRunning = false
    @State private var isSparseUpdating = false
    @State private var healthResult: String?
    @State private var historyQuery = ""
    @State private var authorQuery = ""
    @State private var pathQuery = ""
    @State private var pathMatchedCommitIDs: Set<String>?
    @State private var pathFilterError: String?
    @State private var isFilteringPaths = false
    @State private var openingCommitID: String?

    private var normalizedPathQuery: String {
        pathQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCommits: [GitCommitSummary] {
        appState.commits.filter { commit in
            let q = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let author = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = normalizedPathQuery
            return (q.isEmpty || commit.subject.localizedCaseInsensitiveContains(q) || commit.hash.hasPrefix(q))
                && (author.isEmpty || commit.author.localizedCaseInsensitiveContains(author))
                && (path.isEmpty || pathMatchedCommitIDs == nil || pathMatchedCommitIDs?.contains(commit.hash) == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                OrbitIconBadge(systemName: "slider.horizontal.3", color: OrbitDesign.violet, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("专业工具").orbitFont(.title3, weight: .semibold)
                    Text("按需运行，结果会限制在当前仓库和当前窗口内。")
                        .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                if isReportLoading {
                    ProgressView()
                        .controlSize(.small)
                        .help("正在读取仓库工具状态")
                }
                Button { dismiss() } label: {
                    Text(verbatim: AppLanguage.isEnglish ? "Close" : "关闭")
                }
                .keyboardShortcut(.cancelAction)
            }.padding(20).frame(height: 68)
            Divider().overlay(OrbitDesign.separator)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(RepositoryToolKind.allCases) { item in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                tab = item
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: item.symbol)
                                    .frame(width: 17)
                                Text(item.title)
                                Spacer(minLength: 4)
                                if tab == item {
                                    Circle()
                                        .fill(OrbitDesign.accent)
                                        .frame(width: 5, height: 5)
                                }
                            }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).frame(height: 36)
                                .background(tab == item ? OrbitDesign.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(OrbitInteractiveButtonStyle())
                        .foregroundStyle(tab == item ? OrbitDesign.primaryText : OrbitDesign.secondaryText)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                    }
                    Spacer()
                }.padding(12).frame(width: 176).background(OrbitDesign.sidebar)
                Divider().overlay(OrbitDesign.separator)
                Group {
                    switch tab {
                    case .history: historyTab
                    case .extensions: extensionsTab
                    case .automation: automationTab
                    case .health: healthTab
                    }
                }
                .id(tab)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 600)
        .background(OrbitDesign.canvas)
        .task { await loadReport() }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolTitle("历史过滤与比较", subtitle: "输入后即时筛选；点击提交会前往提交历史并打开完整详情。")
            HStack(spacing: 8) {
                TextField("提交说明或哈希", text: $historyQuery)
                TextField("作者", text: $authorQuery).frame(width: 150)
                TextField("路径关键词", text: $pathQuery).frame(width: 150)
                if isFilteringPaths {
                    ProgressView()
                        .controlSize(.small)
                        .help("正在匹配提交涉及的文件路径")
                }
                Button {
                    historyQuery = ""
                    authorQuery = ""
                    pathQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                .buttonStyle(.plain)
                .help("清除全部过滤条件")
                .disabled(historyQuery.isEmpty && authorQuery.isEmpty && pathQuery.isEmpty)
            }

            HStack(spacing: 8) {
                Text("匹配 \(filteredCommits.count) / \(appState.commits.count) 条已加载提交")
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                if !normalizedPathQuery.isEmpty {
                    Text("·")
                        .foregroundStyle(OrbitDesign.secondaryText)
                    if let pathFilterError {
                        Label(pathFilterError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(OrbitDesign.coral)
                            .lineLimit(1)
                    } else if isFilteringPaths {
                        Text("正在读取文件路径…")
                            .foregroundStyle(OrbitDesign.violet)
                    } else {
                        Label("已按真实文件路径筛选", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(OrbitDesign.accent)
                    }
                }
                Spacer()
                Text("点击一条提交查看详情")
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .orbitFont(.caption2)

            Group {
                if filteredCommits.isEmpty && !isFilteringPaths {
                    VStack(spacing: 9) {
                        OrbitIconBadge(systemName: "line.3.horizontal.decrease.circle", color: OrbitDesign.violet, size: 42)
                        Text("没有匹配的提交")
                            .orbitFont(.callout, weight: .semibold)
                        Text("尝试缩短关键词，或清除部分过滤条件。")
                            .orbitFont(.caption)
                            .foregroundStyle(OrbitDesign.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredCommits) { commit in
                                Button {
                                    Task { await openCommit(commit) }
                                } label: {
                                    HStack(spacing: 9) {
                                        Text(commit.shortHash)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(OrbitDesign.violet)
                                            .frame(width: 68, alignment: .leading)
                                        Text(commit.subject)
                                            .orbitFont(.caption, weight: .medium)
                                            .foregroundStyle(OrbitDesign.primaryText)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(commit.author)
                                            .orbitFont(.caption2)
                                            .foregroundStyle(OrbitDesign.secondaryText)
                                            .lineLimit(1)
                                        if openingCommitID == commit.id {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(OrbitDesign.secondaryText)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(
                                        openingCommitID == commit.id ? OrbitDesign.accent.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(OrbitInteractiveButtonStyle())
                                .disabled(openingCommitID != nil)
                                .help("打开 \(commit.shortHash) 的提交详情")
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
        }
        .padding(20)
        .task(id: normalizedPathQuery) {
            await updatePathFilter()
        }
    }

    private var extensionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolTitle("LFS、子模块与稀疏检出", subtitle: "读取和修改仓库扩展配置，不会自动下载或上传对象。")
            reportRow("Git LFS", report.lfs, icon: "externaldrive")
            reportRow("Submodule", report.submodules, icon: "shippingbox")
            HStack {
                reportRow("稀疏检出", report.sparseCheckout, icon: "square.dashed", compact: true)
                Spacer()
                Button {
                    Task { await toggleSparse() }
                } label: {
                    HStack(spacing: 7) {
                        if isSparseUpdating { ProgressView().controlSize(.small) }
                        Text(isSparseUpdating ? "正在更新…" : "切换稀疏检出")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSparseUpdating || isReportLoading)
            }
            Text("需要进一步配置目录时，使用 Git 的 sparse-checkout 命令可以避免把大型仓库全部载入工作区。")
                .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }.padding(20)
    }

    private var automationTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolTitle("签名提交与 Hooks", subtitle: "保留系统 Git 配置，GitIgnore 只展示当前仓库的有效设置。")
            reportRow("Hooks 路径", report.hooks, icon: "wand.and.stars")
            HStack {
                Text("当前身份").orbitFont(.caption, weight: .semibold)
                Text(appState.gitIdentity.name.isEmpty ? "未设置" : "\(appState.gitIdentity.name) <\(appState.gitIdentity.email)>")
                    .font(.caption.monospaced()).foregroundStyle(OrbitDesign.secondaryText)
            }
            Button("刷新 Hooks 列表") { Task { await loadReport() } }
                .buttonStyle(.bordered)
                .disabled(isReportLoading)
            if let remote = appState.remoteInfo?.webURL {
                Button("在浏览器打开远程入口") { NSWorkspace.shared.open(remote) }.buttonStyle(.bordered)
            }
            Text("签名、凭据、Hooks 和 OAuth 仍由系统 Git 与远程平台负责；这里不保存令牌。")
                .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }.padding(20)
    }

    private var healthTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolTitle("仓库健康检查", subtitle: "只读检查对象数据库、变更规模和当前操作队列。")
            HStack(spacing: 10) {
                metric("变更文件", "\(appState.status.changedFileCount)")
                metric("提交缓存", "\(appState.commits.count)")
                metric("对象数量", report.objectCount.map(String.init) ?? "—")
            }
            Button {
                Task {
                    guard let root = appState.repositoryRootURL else { return }
                    isHealthCheckRunning = true
                    defer { isHealthCheckRunning = false }
                    do {
                        healthResult = try await appState.gitRunner.runRepositoryHealthCheck(at: root)
                    } catch is CancellationError {
                        return
                    } catch {
                        healthResult = "检查未完成：\(error.localizedDescription)"
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isHealthCheckRunning { ProgressView().controlSize(.small) }
                    Label(isHealthCheckRunning ? "检查中…" : "运行只读 fsck 检查", systemImage: "stethoscope")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OrbitDesign.accent)
            .disabled(isHealthCheckRunning)
            if let healthResult {
                Text(healthResult).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("大型仓库检查可能需要几秒；Git 输出有 16 MB 上限，超过上限会提前停止并提示。")
                .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            Spacer()
        }.padding(20)
    }

    private func toolTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).orbitFont(.title3, weight: .semibold)
            Text(subtitle).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
        }
    }
    private func reportRow(_ title: String, _ value: String, icon: String, compact: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(OrbitDesign.violet).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).orbitFont(.caption, weight: .semibold)
                Text(value).font(.caption2.monospaced()).foregroundStyle(OrbitDesign.secondaryText).lineLimit(compact ? 2 : 4)
            }
            Spacer()
        }.padding(11).background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText); Text(value).font(.title3.monospacedDigit().weight(.semibold)) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(11).background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
    }
    private func loadReport() async {
        guard let root = appState.repositoryRootURL else { return }
        isReportLoading = true
        defer { isReportLoading = false }
        do {
            report = try await appState.gitRunner.repositoryToolReport(at: root)
        } catch is CancellationError {
            return
        } catch {
            appState.present(error: error, title: "无法读取专业工具状态")
        }
    }
    private func toggleSparse() async {
        guard let root = appState.repositoryRootURL else { return }
        let enabled = report.sparseCheckout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || report.sparseCheckout == "未启用稀疏检出"
        isSparseUpdating = true
        defer { isSparseUpdating = false }
        do {
            try await appState.gitRunner.setSparseCheckout(enabled, at: root)
            await loadReport()
            appState.feedback = AppFeedback(
                kind: .success,
                title: enabled ? "已启用稀疏检出" : "已关闭稀疏检出",
                message: "仓库扩展状态已经刷新。"
            )
        } catch {
            appState.present(error: error, title: "稀疏检出设置失败")
        }
    }

    private func updatePathFilter() async {
        let query = normalizedPathQuery
        guard !query.isEmpty else {
            pathMatchedCommitIDs = nil
            pathFilterError = nil
            isFilteringPaths = false
            return
        }

        isFilteringPaths = true
        pathMatchedCommitIDs = nil
        pathFilterError = nil
        do {
            try await Task.sleep(for: .milliseconds(260))
            try Task.checkCancellation()
            guard let root = appState.repositoryRootURL else {
                isFilteringPaths = false
                return
            }
            let matches = try await appState.gitRunner.commitHashes(
                matchingPathKeyword: query,
                limit: max(appState.commits.count, 200),
                at: root
            )
            try Task.checkCancellation()
            guard normalizedPathQuery == query else { return }
            pathMatchedCommitIDs = matches
            isFilteringPaths = false
        } catch is CancellationError {
            return
        } catch {
            guard normalizedPathQuery == query else { return }
            pathMatchedCommitIDs = []
            pathFilterError = error.localizedDescription
            isFilteringPaths = false
        }
    }

    private func openCommit(_ commit: GitCommitSummary) async {
        guard openingCommitID == nil else { return }
        openingCommitID = commit.id
        appState.selectSection(.history)
        await appState.selectCommit(commit)
        guard !Task.isCancelled else { return }
        openingCommitID = nil
        dismiss()
    }
}
