import SwiftUI

private struct HistoryGraphLoadID: Hashable {
    let mode: String
    let commitIDs: [String]
}

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.orbitFontPalette) private var fontPalette
    @State private var query = ""
    @State private var confirmsUndo = false
    @State private var localGraphNodes: [String: GitGraphNode] = [:]
    @State private var incomingGraphNodes: [String: GitGraphNode] = [:]
    @State private var author = ""
    @State private var branchFilter = ""
    @State private var days = 0
    @State private var kind = "all"
    @State private var historyResults: [GitCommitSummary] = []
    @State private var isLoadingHistory = false
    @State private var hasMoreHistory = true
    @State private var historyError: String?
    @State private var historyGeneration = UUID()
    @State private var retryID = UUID()
    @State private var historyLimitReached = false
    @AppStorage("gitignore.history.graphMode") private var graphModeRawValue = HistoryGraphMode.clear.rawValue
    @AppStorage("gitignore.history.scope") private var historyScopeRawValue = HistoryScope.all.rawValue

    private var graphMode: HistoryGraphMode {
        HistoryGraphMode(rawValue: graphModeRawValue) ?? .clear
    }

    private var historyScope: HistoryScope {
        HistoryScope(rawValue: historyScopeRawValue) ?? .all
    }

    private var filteredCommits: [GitCommitSummary] {
        historyScope == .incoming && branchFilter.isEmpty ? [] : historyResults
    }

    private var filteredIncomingCommits: [GitCommitSummary] {
        historyScope == .incoming && branchFilter.isEmpty ? historyResults : []
    }

    private var historyQuery: GitHistoryQuery {
        GitHistoryQuery(scope: historyScopeRawValue, branch: branchFilter,
                        author: author.trimmingCharacters(in: .whitespacesAndNewlines),
                        text: query.trimmingCharacters(in: .whitespacesAndNewlines), days: days, kind: kind)
    }

    private var requestID: String {
        "\(appState.repository?.path ?? "")|\(appState.repository?.branch ?? "")|\(appState.commits.first?.hash ?? "")|\(appState.incomingCommits.first?.hash ?? "")|\(historyQuery)|\(retryID)"
    }

    var body: some View {
        GeometryReader { viewport in
        VStack(spacing: 0) {
            header
            filterBar(width: viewport.size.width)
            if (appState.repository?.behindCount ?? 0) > 0, historyScope != .incoming {
                HStack {
                    Label(AppLanguage.text("\(appState.repository?.behindCount ?? 0) 个远程提交待 Pull", "\(appState.repository?.behindCount ?? 0) incoming commits"), systemImage: "arrow.down.to.line")
                    Spacer()
                    Button(AppLanguage.text("预览远程更新", "Preview Incoming")) {
                        branchFilter = ""
                        historyScopeRawValue = HistoryScope.incoming.rawValue
                    }
                }
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.amber)
                .padding(.horizontal, 24).padding(.vertical, 8)
            }

            if let historyError {
                HStack {
                    Label(historyError, systemImage: "exclamationmark.circle")
                        .lineLimit(3)
                    Spacer()
                    Button(AppLanguage.text("重试", "Retry")) { retryID = UUID() }
                }
                .orbitFont(.caption)
                .padding(12)
                .foregroundStyle(OrbitDesign.coral)
            }

            if let updateMessage = appState.historyUpdateMessage {
                historyUpdateBanner(updateMessage)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: updateMessage) {
                        try? await Task.sleep(for: .seconds(4.5))
                        appState.clearHistoryUpdate()
                    }
            }

            if appState.repository == nil {
                emptyState
            } else if isLoadingHistory && historyResults.isEmpty {
                ProgressView(AppLanguage.text("正在筛选提交…", "Filtering commits…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCommits.isEmpty && filteredIncomingCommits.isEmpty {
                noResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            historyGuide
                            if !filteredIncomingCommits.isEmpty {
                                incomingUpdatesHeader
                                    .id("incoming-updates")
                                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                                ForEach(filteredIncomingCommits) { commit in
                                    commitRow(commit, isIncoming: true)
                                        .id("incoming-\(commit.id)")
                                }
                                localHistoryLabel
                            }
                            ForEach(filteredCommits) { commit in
                                commitRow(commit)
                                    .id(commit.id)
                                    .task {
                                        guard commit.id == historyResults.last?.id else { return }
                                        await loadHistoryPage()
                                    }
                            }
                            if hasMoreHistory {
                                Button(AppLanguage.text("加载更多提交", "Load More Commits")) {
                                    Task { await loadHistoryPage() }
                                }
                                .disabled(isLoadingHistory)
                            }
                            if historyLimitReached {
                                Text(AppLanguage.text("已达本次阅读上限，请缩小时间、分支或作者范围。", "Reading limit reached. Narrow the date, branch, or author filters."))
                                    .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                            }
                            if isLoadingHistory {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("正在读取更早的提交…")
                                }
                                .orbitFont(.caption)
                                .foregroundStyle(OrbitDesign.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .transition(.opacity)
                            }
                        }
                        .frame(width: max(0, viewport.size.width - 48), alignment: .leading)
                        .padding(24)
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: appState.recentlyAddedCommitIDs) { _, newIDs in
                        guard let firstCommit = appState.commits.first(where: { newIDs.contains($0.id) }) else { return }
                        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.42, dampingFraction: 0.84)) {
                            proxy.scrollTo(firstCommit.id, anchor: .top)
                        }
                    }
                    .onChange(of: appState.incomingCommits.map(\.id)) { oldIDs, newIDs in
                        guard oldIDs.isEmpty, !newIDs.isEmpty, query.isEmpty else { return }
                        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.24)) {
                            proxy.scrollTo("incoming-updates", anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }
        .background(OrbitDesign.canvas)
        .navigationTitle("提交历史")
        .orbitPageReveal()
        .alert("撤销最近一次提交？", isPresented: $confirmsUndo) {
            Button("取消", role: .cancel) {}
            Button("撤销提交") { Task { await appState.undoLastCommit() } }
        } message: {
            Text("提交内容会保留在暂存区，可继续修改后重新提交。")
        }
        .task(id: HistoryGraphLoadID(mode: graphModeRawValue, commitIDs: filteredCommits.map(\.id))) {
            guard graphMode == .full else {
                localGraphNodes.removeAll(keepingCapacity: false)
                return
            }
            let commits = filteredCommits
            let nodes = await Task.detached(priority: .utility) {
                GitGraphLayout.build(commits: commits)
            }.value
            guard !Task.isCancelled else { return }
            localGraphNodes = nodes
        }
        .task(id: HistoryGraphLoadID(mode: graphModeRawValue, commitIDs: filteredIncomingCommits.map(\.id))) {
            guard graphMode == .full else {
                incomingGraphNodes.removeAll(keepingCapacity: false)
                return
            }
            let commits = filteredIncomingCommits
            let nodes = await Task.detached(priority: .utility) {
                GitGraphLayout.build(commits: commits)
            }.value
            guard !Task.isCancelled else { return }
            incomingGraphNodes = nodes
        }
        .task(id: requestID) {
            historyGeneration = UUID()
            let canReuseRepositoryHistory = historyScope == .all
                && branchFilter.isEmpty
                && author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && days == 0
                && kind == "all"
            historyResults = canReuseRepositoryHistory ? appState.commits : []
            hasMoreHistory = true
            historyLimitReached = false
            isLoadingHistory = false
            historyError = nil
            if canReuseRepositoryHistory {
                hasMoreHistory = appState.hasMoreCommits
                return
            }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            await loadHistoryPage()
        }
        .onDisappear { historyGeneration = UUID() }
        .onChange(of: appState.repository?.path) { _, _ in branchFilter = "" }
    }

    private func loadHistoryPage() async {
        guard !isLoadingHistory, hasMoreHistory, let repository = appState.repository else { return }
        let canUseRepositoryPagination = historyScope == .all
            && branchFilter.isEmpty
            && author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && days == 0
            && kind == "all"
        if canUseRepositoryPagination {
            await appState.loadMoreCommits()
            historyResults = appState.commits
            hasMoreHistory = appState.hasMoreCommits
            return
        }
        let generation = historyGeneration
        let request = requestID
        let filter = historyQuery
        let offset = historyResults.count
        isLoadingHistory = true
        defer { if generation == historyGeneration { isLoadingHistory = false } }
        do {
            let page = try await appState.gitRunner.historyPage(
                at: URL(fileURLWithPath: repository.path), query: filter, skip: offset)
            try Task.checkCancellation()
            guard generation == historyGeneration, request == requestID else { return }
            let existing = Set(historyResults.map(\.id))
            historyResults.append(contentsOf: page.filter { !existing.contains($0.id) })
            let bytes = historyResults.reduce(0) { $0 + $1.subject.utf8.count + $1.author.utf8.count + 256 }
            historyLimitReached = historyResults.count >= 10_000 || bytes >= 8 * 1_024 * 1_024
            hasMoreHistory = page.count == 100 && !historyLimitReached
            historyError = nil
        } catch is CancellationError {
        } catch {
            guard generation == historyGeneration, request == requestID else { return }
            historyError = error.localizedDescription
        }
    }

    private func filterBar(width: CGFloat) -> some View {
        let layout = width >= 1000
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            HStack(spacing: 12) { scopeFilters }
            HStack(spacing: 12) { detailFilters }
        }
        .controlSize(.small)
        .orbitFont(.caption)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(OrbitDesign.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var scopeFilters: some View {
        Picker(AppLanguage.text("范围", "Scope"), selection: $historyScopeRawValue) {
            ForEach(HistoryScope.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
        .onChange(of: historyScopeRawValue) { _, _ in branchFilter = "" }
        Picker(AppLanguage.text("分支", "Branch"), selection: $branchFilter) {
            Text(AppLanguage.text("跟随范围", "Use Scope")).tag("")
            ForEach(appState.branches) { Text($0.name).tag("refs/heads/\($0.name)") }
            ForEach(appState.remoteBranches) { Text($0.id).tag("refs/remotes/\($0.id)") }
        }
        .frame(maxWidth: 260)
    }

    @ViewBuilder private var detailFilters: some View {
        TextField(AppLanguage.text("作者或邮箱", "Author or email"), text: $author)
            .textFieldStyle(.roundedBorder).frame(minWidth: 100, maxWidth: 180)
            .accessibilityLabel(AppLanguage.text("筛选作者", "Filter by Author"))
        Picker(AppLanguage.text("时间", "Date"), selection: $days) {
            Text(AppLanguage.text("全部", "Any Time")).tag(0)
            Text(AppLanguage.text("最近 7 天", "Last 7 Days")).tag(7)
            Text(AppLanguage.text("最近 30 天", "Last 30 Days")).tag(30)
            Text(AppLanguage.text("最近 90 天", "Last 90 Days")).tag(90)
        }
        Picker(AppLanguage.text("类型", "Type"), selection: $kind) {
            Text(AppLanguage.text("全部", "All")).tag("all")
            Text(AppLanguage.text("合并提交", "Merges")).tag("merge")
            Text(AppLanguage.text("普通提交", "Non-Merges")).tag("commit")
        }
        Button {
            query = ""; author = ""; branchFilter = ""; days = 0; kind = "all"
            historyScopeRawValue = HistoryScope.all.rawValue
        } label: { Image(systemName: "arrow.counterclockwise") }
        .help(AppLanguage.text("重置筛选", "Reset Filters"))
        .accessibilityLabel(AppLanguage.text("重置筛选", "Reset Filters"))
    }

    private func historyUpdateBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(OrbitDesign.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).orbitFont(.caption, weight: .bold)
                Text(appState.recentlyAddedCommitIDs.isEmpty
                     ? "提交列表无需调整"
                     : "新提交已置于时间线顶部，并为你短暂高亮")
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            Button("知道了") { appState.clearHistoryUpdate() }
                .buttonStyle(.plain)
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.accent)
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 48)
        .background(OrbitDesign.accent.opacity(0.09))
        .overlay(alignment: .bottom) { Rectangle().fill(OrbitDesign.accent.opacity(0.22)).frame(height: 1) }
    }

    private var header: some View {
        OrbitPageHeader(
            title: AppLanguage.text("提交历史", "Commit History"),
            subtitle: AppLanguage.text("沿着时间线查看仓库的每一次变化。", "Explore every change along the repository timeline."),
            systemName: "clock.arrow.circlepath"
        ) {
            HStack(spacing: 8) {
                if appState.isLoadingRepository || appState.isPerformingGitAction {
                    ProgressView().controlSize(.small).tint(OrbitDesign.accent)
                }
                WorkspaceActionButton(title: AppLanguage.text("撤销最近提交", "Undo Last Commit"), systemName: "arrow.uturn.backward", tint: OrbitDesign.secondaryText) {
                    confirmsUndo = true
                }
                .disabled(appState.commits.isEmpty || appState.isPerformingGitAction)
            }
        } accessory: {
            HStack(spacing: 8) {
                OrbitSearchField(
                    prompt: AppLanguage.text("搜索提交说明…", "Search commit messages…"),
                    text: $query
                )
                Text("⌘F")
                    .font(.caption2.monospaced())
                    .foregroundStyle(OrbitDesign.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
    }

    private var incomingUpdatesHeader: some View {
        HStack(spacing: 12) {
            OrbitIconBadge(systemName: "arrow.down.to.line", color: OrbitDesign.amber, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.isEnglish
                     ? "\(appState.repository?.behindCount ?? appState.incomingCommits.count) remote commits ready to Pull"
                     : "\(appState.repository?.behindCount ?? appState.incomingCommits.count) 个远程提交等待 Pull")
                    .orbitFont(.callout, weight: .bold)
                Text(AppLanguage.isEnglish
                     ? "Fetched for preview only. Your local branch has not changed."
                     : "自动检测已读取提交信息，但尚未改变本地分支。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer(minLength: 12)
            WorkspaceActionButton(
                title: "Pull \(appState.repository?.behindCount ?? appState.incomingCommits.count)",
                systemName: "arrow.down.to.line",
                tint: OrbitDesign.amber
            ) {
                Task { await appState.pull() }
            }
            .disabled(appState.isPerformingGitAction)
        }
        .padding(13)
        .background(OrbitDesign.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(OrbitDesign.amber.opacity(0.32), lineWidth: 1)
        }
    }

    private var localHistoryLabel: some View {
        HStack(spacing: 8) {
            Label(
                AppLanguage.text("本地提交", "Local Commits"),
                systemImage: "laptopcomputer"
            )
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
            Text(AppLanguage.text("\(filteredCommits.count) 条", "\(filteredCommits.count) commits"))
                .orbitFont(.caption2)
                .foregroundStyle(OrbitDesign.tertiaryText)
            Rectangle().fill(OrbitDesign.separator).frame(height: 1)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var historyGuide: some View {
        HStack(spacing: 14) {
            Text(AppLanguage.text(
                "当前显示 \(filteredCommits.count + filteredIncomingCommits.count) 条",
                "Showing \(filteredCommits.count + filteredIncomingCommits.count) commits"
            ))
                .foregroundStyle(OrbitDesign.tertiaryText)
            Spacer(minLength: 8)
            Text(AppLanguage.text("按时间排列 · 分支与合并关系显示在标签中", "Chronological order · branch and merge context shown in labels"))
                .orbitFont(.caption2)
                .foregroundStyle(OrbitDesign.tertiaryText)
                .lineLimit(1)
        }
        .orbitFont(.caption2, weight: .medium)
        .foregroundStyle(OrbitDesign.secondaryText)
        .padding(.horizontal, 11)
        .frame(minHeight: 34)
        .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func graphLegendItem(title: String, isMerge: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(OrbitDesign.canvas)
                    .overlay { Circle().stroke(OrbitDesign.violet, lineWidth: 2) }
                    .frame(width: 10, height: 10)
                if isMerge {
                    Circle()
                        .stroke(OrbitDesign.violet.opacity(0.4), lineWidth: 1)
                        .frame(width: 15, height: 15)
                }
            }
            .frame(width: 16, height: 16)
            Text(title)
        }
    }

    private func commitRow(_ commit: GitCommitSummary, isIncoming: Bool = false) -> some View {
        let isSelected = appState.selectedCommit?.id == commit.id
        let isNew = appState.recentlyAddedCommitIDs.contains(commit.id)
        let presentation = commitPresentation(commit)
        let currentBranch = appState.repository?.branch ?? ""
        let branchLabel = commitBranchLabel(commit, fallback: currentBranch)
        let isHead = commit.refs.contains { ref in
            let normalized = ref.replacingOccurrences(of: "HEAD -> ", with: "")
            return normalized == currentBranch || normalized.hasSuffix("/\(currentBranch)")
        }
        return HStack(spacing: 4) {
            HistoryCommitRow(
                commit: commit,
                presentation: presentation,
                graphMode: graphMode,
                graphNode: (isIncoming ? incomingGraphNodes : localGraphNodes)[commit.id] ?? .fallback,
                isSelected: isSelected,
                isNew: isNew,
                isIncoming: isIncoming,
                isHead: isHead,
                branchLabel: branchLabel,
                isLast: !isIncoming && commit.id == appState.commits.last?.id && !appState.hasMoreCommits,
                reduceMotion: reduceMotion
            ) {
                if isSelected {
                    appState.dismissInspector()
                } else {
                    Task { await appState.selectCommit(commit) }
                }
            }
            .equatable()
            CommitActionMenu(commit: commit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: max(88, fontPalette.baseSize * 4 + 36))
        .background(isSelected
                    ? OrbitDesign.selectionFill
                    : (isIncoming
                       ? OrbitDesign.amber.opacity(0.07)
                       : (isNew ? OrbitDesign.accent.opacity(0.10) : OrbitDesign.surface)),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected
                        ? OrbitDesign.violet.opacity(0.24)
                        : (isIncoming
                           ? OrbitDesign.amber.opacity(0.30)
                           : (isNew ? OrbitDesign.accent.opacity(0.4) : OrbitDesign.separator)),
                        lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(OrbitDesign.violet)
                    .frame(width: 3, height: 34)
                    .padding(.leading, 4)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.3), value: isNew)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18), value: isSelected)
    }

    private func commitBranchLabel(_ commit: GitCommitSummary, fallback: String) -> String {
        let ref = commit.refs.first { !$0.contains("origin/") && !$0.contains("upstream/") }
        return ref?.replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "tag: ", with: "") ?? fallback
    }

    private func referenceBadge(_ reference: String) -> some View {
        let tint = referenceTint(reference)
        return HStack(spacing: 4) {
            Image(systemName: referenceSymbol(reference))
                .font(.system(size: 9, weight: .semibold))
            Text(displayReference(reference))
                .lineLimit(1)
        }
        .orbitFont(.caption2, weight: .semibold)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay { Capsule().stroke(tint.opacity(0.24), lineWidth: 1) }
    }

    private func referenceSymbol(_ reference: String) -> String {
        if reference.contains("tag:") { return "tag" }
        if reference.contains("origin/") || reference.contains("upstream/") { return "icloud" }
        return "arrow.triangle.branch"
    }

    private func commitPresentation(_ commit: GitCommitSummary) -> HistoryCommitPresentation {
        let subject = commit.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit.parents.count > 1 {
            return HistoryCommitPresentation(
                eventTitle: AppLanguage.text("合并", "Merge"),
                symbol: "arrow.triangle.branch",
                tint: OrbitDesign.violet,
                title: localizedMergeSubject(subject),
                scope: nil
            )
        }

        guard let colon = subject.firstIndex(of: ":") else {
            return .regular(title: subject)
        }
        let rawPrefix = String(subject[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedType = rawPrefix
            .split(separator: "(", maxSplits: 1)
            .first
            .map(String.init)?
            .replacingOccurrences(of: "!", with: "")
            .lowercased() ?? ""
        let title = String(subject[subject.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scope: String?
        if let open = rawPrefix.firstIndex(of: "("),
           let close = rawPrefix.lastIndex(of: ")"),
           open < close {
            let value = String(rawPrefix[rawPrefix.index(after: open)..<close])
            scope = value.isEmpty ? nil : value
        } else {
            scope = nil
        }

        switch normalizedType {
        case "feat":
            return .init(eventTitle: AppLanguage.text("功能", "Feature"), symbol: "sparkles", tint: OrbitDesign.accent, title: title, scope: scope)
        case "fix":
            return .init(eventTitle: AppLanguage.text("修复", "Fix"), symbol: "wrench.and.screwdriver", tint: OrbitDesign.coral, title: title, scope: scope)
        case "docs":
            return .init(eventTitle: AppLanguage.text("文档", "Docs"), symbol: "doc.text", tint: OrbitDesign.blue, title: title, scope: scope)
        case "refactor":
            return .init(eventTitle: AppLanguage.text("重构", "Refactor"), symbol: "arrow.triangle.2.circlepath", tint: OrbitDesign.violet, title: title, scope: scope)
        case "test":
            return .init(eventTitle: AppLanguage.text("测试", "Test"), symbol: "checkmark.seal", tint: OrbitDesign.amber, title: title, scope: scope)
        case "chore", "build", "ci":
            return .init(eventTitle: AppLanguage.text("维护", "Maintenance"), symbol: "gearshape", tint: OrbitDesign.secondaryText, title: title, scope: scope)
        default:
            return .regular(title: subject)
        }
    }

    private func localizedMergeSubject(_ subject: String) -> String {
        guard !AppLanguage.isEnglish else { return subject }
        let quotedParts = subject.components(separatedBy: "'")
        if quotedParts.count >= 3 {
            let source = quotedParts[1]
            let remainder = quotedParts[2]
            if let intoRange = remainder.range(of: " into ", options: .caseInsensitive) {
                let target = remainder[intoRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !source.isEmpty, !target.isEmpty {
                    return "\(source) → \(target)"
                }
            }
        }
        if subject.lowercased().hasPrefix("merge pull request") {
            return subject.replacingOccurrences(of: "Merge pull request", with: "合并 Pull Request", options: .caseInsensitive)
        }
        return subject
    }

    private func displayReference(_ reference: String) -> String {
        reference
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "tag: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func referenceTint(_ reference: String) -> Color {
        if reference.contains("HEAD") || reference.contains("develop") || reference.contains("main") {
            return OrbitDesign.violet
        }
        if reference.contains("origin/") || reference.contains("upstream/") {
            return OrbitDesign.blue
        }
        if reference.contains("tag:") {
            return OrbitDesign.amber
        }
        return OrbitDesign.accent
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            OrbitIconBadge(systemName: "clock.arrow.circlepath", color: OrbitDesign.violet, size: 56)
            Text("先打开一个 Git 仓库").orbitFont(.title3, weight: .bold)
            Text("打开仓库后，GitIgnore 会读取最近的提交历史。")
                .orbitFont(.subheadline)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(OrbitDesign.secondaryText)
            Text("没有匹配的提交").orbitFont(.headline)
            Text(AppLanguage.text("可清空关键词或调整作者、时间和分支条件。", "Clear the search or adjust the author, date, and branch filters."))
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            OrbitIconBadge(systemName: "clock.badge.exclamationmark", color: OrbitDesign.amber, size: 52)
            Text("没有读取到提交历史").orbitFont(.headline)
            Text("仓库可能还没有提交，或上次读取被中断。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
            Button("重新读取提交历史") {
                Task { await appState.refresh(scope: .history) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct HistoryCommitRow: View, Equatable {
    let commit: GitCommitSummary
    let presentation: HistoryCommitPresentation
    let graphMode: HistoryGraphMode
    let graphNode: GitGraphNode
    let isSelected: Bool
    let isNew: Bool
    let isIncoming: Bool
    let isHead: Bool
    let branchLabel: String
    let isLast: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    nonisolated static func == (lhs: HistoryCommitRow, rhs: HistoryCommitRow) -> Bool {
        lhs.commit == rhs.commit
            && lhs.presentation == rhs.presentation
            && lhs.graphMode == rhs.graphMode
            && lhs.graphNode == rhs.graphNode
            && lhs.isSelected == rhs.isSelected
            && lhs.isNew == rhs.isNew
            && lhs.isIncoming == rhs.isIncoming
            && lhs.isHead == rhs.isHead
            && lhs.branchLabel == rhs.branchLabel
            && lhs.isLast == rhs.isLast
            && lhs.reduceMotion == rhs.reduceMotion
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                CommitAuthorAvatarView(author: commit.author, size: 34)
                    .overlay(Circle().stroke(isSelected ? OrbitDesign.violet : OrbitDesign.separator, lineWidth: 2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Label(presentation.eventTitle, systemImage: presentation.symbol)
                            .orbitFont(.caption2, weight: .bold)
                            .foregroundStyle(presentation.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(presentation.tint.opacity(0.10), in: Capsule())

                        if let scope = presentation.scope {
                            Text(scope)
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(OrbitDesign.secondaryText)
                        }

                        if !branchLabel.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                Text(branchLabel).lineLimit(1)
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(OrbitDesign.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(OrbitDesign.blue.opacity(0.10), in: Capsule())
                        }

                        ForEach(Array(commit.refs.prefix(2)), id: \.self) { ref in
                            referenceBadge(ref)
                        }
                        if commit.refs.count > 2 {
                            Text("+\(commit.refs.count - 2)")
                                .orbitFont(.caption2, weight: .semibold)
                                .foregroundStyle(OrbitDesign.tertiaryText)
                        }

                        Spacer(minLength: 6)
                        if isIncoming {
                            Label(AppLanguage.text("待 Pull", "Ready to Pull"), systemImage: "arrow.down.circle.fill")
                                .orbitFont(.caption2, weight: .bold)
                                .foregroundStyle(OrbitDesign.amber)
                        }
                    }

                    Text(presentation.title)
                        .orbitFont(.callout, weight: .semibold)
                        .foregroundStyle(OrbitDesign.primaryText)
                        .lineLimit(1)
                        .layoutPriority(1)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(commit.author)
                                .orbitFont(.caption2, weight: .semibold)
                            Text(AppLanguage.text("提交作者", "Author"))
                                .font(.system(size: 9))
                                .foregroundStyle(OrbitDesign.tertiaryText)
                        }
                        Text("·")
                        Text(commit.dateText)
                        Text("·")
                        Text(commit.shortHash)
                            .font(.caption2.monospaced())
                        if isHead {
                            Text(AppLanguage.text("当前", "HEAD"))
                                .orbitFont(.caption2, weight: .bold)
                                .foregroundStyle(OrbitDesign.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(OrbitDesign.accent.opacity(0.10), in: Capsule())
                        }
                    }
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .lineLimit(1)

                    if commit.parents.count > 1 {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(AppLanguage.text(
                                "合并 (commit.parents.count) 个父提交 · 点击查看父提交差异",
                                "Merged (commit.parents.count) parent commits · click to compare parents"
                            ))
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(OrbitDesign.violet)
                        .padding(.top, 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(HistoryCommitButtonStyle())
        .accessibilityLabel("\(presentation.eventTitle)：\(presentation.title)，\(commit.author)，\(commit.dateText)")
    }

    private func referenceBadge(_ reference: String) -> some View {
        let tint = referenceTint(reference)
        return HStack(spacing: 4) {
            Image(systemName: referenceSymbol(reference))
                .font(.system(size: 9, weight: .semibold))
            Text(displayReference(reference))
                .lineLimit(1)
        }
        .orbitFont(.caption2, weight: .semibold)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay { Capsule().stroke(tint.opacity(0.24), lineWidth: 1) }
    }

    private func referenceSymbol(_ reference: String) -> String {
        if reference.contains("tag:") { return "tag" }
        if reference.contains("origin/") || reference.contains("upstream/") { return "icloud" }
        return "arrow.triangle.branch"
    }

    private func displayReference(_ reference: String) -> String {
        reference
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "tag: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func referenceTint(_ reference: String) -> Color {
        if reference.contains("HEAD") || reference.contains("develop") || reference.contains("main") {
            return OrbitDesign.violet
        }
        if reference.contains("origin/") || reference.contains("upstream/") {
            return OrbitDesign.blue
        }
        if reference.contains("tag:") {
            return OrbitDesign.amber
        }
        return OrbitDesign.accent
    }
}

private struct CompactHistoryGraphMark: View {
    let parentCount: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            if parentCount > 1 {
                Capsule()
                    .fill(OrbitDesign.violet.opacity(0.45))
                    .frame(width: 28, height: 2)
                Circle().fill(OrbitDesign.canvas).frame(width: 8, height: 8)
                    .overlay { Circle().stroke(OrbitDesign.blue, lineWidth: 1.8) }
                    .offset(x: -14, y: -7)
                Circle().fill(OrbitDesign.canvas).frame(width: 8, height: 8)
                    .overlay { Circle().stroke(OrbitDesign.accent, lineWidth: 1.8) }
                    .offset(x: -14, y: 7)
            }
            Circle()
                .fill(isSelected ? OrbitDesign.accent : OrbitDesign.canvas)
                .frame(width: parentCount > 1 ? 15 : 13, height: parentCount > 1 ? 15 : 13)
                .overlay { Circle().stroke(parentCount > 1 ? OrbitDesign.violet : OrbitDesign.accent, lineWidth: 2) }
        }
        .frame(width: 34, height: 40)
        .accessibilityHidden(true)
    }
}

private struct HistoryCommitPresentation: Equatable {
    let eventTitle: String
    let symbol: String
    let tint: Color
    let title: String
    let scope: String?

    static func regular(title: String) -> HistoryCommitPresentation {
        HistoryCommitPresentation(
            eventTitle: AppLanguage.text("提交", "Commit"),
            symbol: "circle",
            tint: OrbitDesign.secondaryText,
            title: title,
            scope: nil
        )
    }
}

private struct HistoryCommitButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.06) : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
