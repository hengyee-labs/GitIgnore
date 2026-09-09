import SwiftUI

private struct HistoryGraphLoadID: Hashable {
    let mode: String
    let commitIDs: [String]
}

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var confirmsUndo = false
    @State private var localGraphNodes: [String: GitGraphNode] = [:]
    @State private var incomingGraphNodes: [String: GitGraphNode] = [:]
    @AppStorage("gitignore.history.graphMode") private var graphModeRawValue = HistoryGraphMode.clear.rawValue

    private var graphMode: HistoryGraphMode {
        HistoryGraphMode(rawValue: graphModeRawValue) ?? .clear
    }

    private var filteredCommits: [GitCommitSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return appState.commits }
        return appState.commits.filter {
            $0.subject.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.author.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.shortHash.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var filteredIncomingCommits: [GitCommitSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return appState.incomingCommits }
        return appState.incomingCommits.filter {
            $0.subject.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.author.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.shortHash.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

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
            } else if appState.commits.isEmpty && appState.incomingCommits.isEmpty {
                unavailableState
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
                                        guard query.isEmpty, commit.id == appState.commits.last?.id else { return }
                                        await appState.loadMoreCommits()
                                    }
                            }
                            if appState.isLoadingMoreCommits {
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
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .background(OrbitDesign.canvas)
        .navigationTitle("提交历史")
        .orbitPageReveal()
        .alert("撤销最近一次提交？", isPresented: $confirmsUndo) {
            Button("取消", role: .cancel) {}
            Button("撤销提交") { Task { await appState.undoLastCommit() } }
        } message: {
            Text("提交内容会保留在暂存区，可继续修改后重新提交。")
        }
        .task(id: HistoryGraphLoadID(mode: graphModeRawValue, commitIDs: appState.commits.map(\.id))) {
            guard graphMode == .full else {
                localGraphNodes.removeAll(keepingCapacity: false)
                return
            }
            let commits = appState.commits
            localGraphNodes = await Task.detached(priority: .utility) {
                GitGraphLayout.build(commits: commits)
            }.value
        }
        .task(id: HistoryGraphLoadID(mode: graphModeRawValue, commitIDs: appState.incomingCommits.map(\.id))) {
            guard graphMode == .full else {
                incomingGraphNodes.removeAll(keepingCapacity: false)
                return
            }
            let commits = appState.incomingCommits
            incomingGraphNodes = await Task.detached(priority: .utility) {
                GitGraphLayout.build(commits: commits)
            }.value
        }
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
                    prompt: AppLanguage.text("搜索提交、作者或哈希…", "Search commits, authors, or hashes…"),
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
            Label(AppLanguage.text("从新到旧", "Newest to oldest"), systemImage: "arrow.down")
            Rectangle()
                .fill(OrbitDesign.separator)
                .frame(width: 1, height: 16)
            if graphMode == .clear {
                Label(
                    AppLanguage.text("仅显示直接提交关系", "Direct commit relationships"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                graphLegendItem(title: AppLanguage.text("合并时显示分叉", "Branches appear for merges"), isMerge: true)
            } else {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Capsule().fill(OrbitDesign.violet).frame(width: 2, height: 14)
                        Capsule().fill(OrbitDesign.blue).frame(width: 2, height: 14)
                        Capsule().fill(OrbitDesign.accent).frame(width: 2, height: 14)
                    }
                    Text(AppLanguage.text("显示所有活跃分支路径", "All active branch paths"))
                }
            }
            Spacer(minLength: 12)
            Text(AppLanguage.text(
                "当前显示 \(filteredCommits.count + filteredIncomingCommits.count) 条",
                "Showing \(filteredCommits.count + filteredIncomingCommits.count) commits"
            ))
                .foregroundStyle(OrbitDesign.tertiaryText)
            Picker(
                AppLanguage.text("图谱显示方式", "Graph display mode"),
                selection: $graphModeRawValue
            ) {
                Text(AppLanguage.text("清晰", "Clear"))
                    .tag(HistoryGraphMode.clear.rawValue)
                Text(AppLanguage.text("完整图谱", "Full Graph"))
                    .tag(HistoryGraphMode.full.rawValue)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 154)
            .help(AppLanguage.text(
                "清晰模式适合日常阅读；完整图谱用于查看复杂分支拓扑",
                "Use Clear for everyday reading and Full Graph for complex topology"
            ))
        }
        .orbitFont(.caption2, weight: .medium)
        .foregroundStyle(OrbitDesign.secondaryText)
        .padding(.horizontal, 11)
        .frame(minHeight: 34)
        .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
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
        return HStack(spacing: 4) {
            Button {
                if isSelected {
                    appState.dismissInspector()
                } else {
                    Task { await appState.selectCommit(commit) }
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    HistoryGraphView(
                        node: (isIncoming ? incomingGraphNodes : localGraphNodes)[commit.id] ?? .fallback,
                        mode: graphMode,
                        parentCount: commit.parents.count,
                        isSelected: isSelected,
                        isLast: !isIncoming && commit.id == appState.commits.last?.id && !appState.hasMoreCommits
                    )
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
                            CommitAuthorAvatarView(author: commit.author, size: 18)
                            Text(commit.author)
                            Text("·")
                            Text(commit.dateText)
                            Text("·")
                            Text(commit.shortHash)
                                .font(.caption2.monospaced())
                        }
                        .orbitFont(.caption2)
                        .foregroundStyle(OrbitDesign.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HistoryCommitButtonStyle())
            .accessibilityLabel("\(presentation.eventTitle)：\(presentation.title)，\(commit.author)，\(commit.dateText)")
            CommitActionMenu(commit: commit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
            Text("试试提交信息、作者名或短哈希。")
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

private struct HistoryCommitPresentation {
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
