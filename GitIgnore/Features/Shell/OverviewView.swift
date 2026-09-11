import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("orbit.interfaceDensity") private var interfaceDensity = OrbitDensity.comfortable.rawValue

    private var density: OrbitDensity {
        OrbitDensity(rawValue: interfaceDensity) ?? .comfortable
    }

    var body: some View {
        GeometryReader { proxy in
            let sidePadding = overviewHorizontalPadding(for: proxy.size.width)
            let contentWidth = overviewContentWidth(for: proxy.size.width)
            let innerWidth = max(contentWidth - sidePadding * 2, 0)
            ScrollView {
                VStack(alignment: .leading, spacing: overviewSpacing) {
                    header
                    if let repository = appState.repository {
                        repositoryPulse(repository)
                        primaryAction(repository)
                        contentColumns(repository, availableWidth: innerWidth)
                    } else {
                        emptyRepository
                    }
                }
                .padding(.horizontal, sidePadding)
                .padding(.vertical, density == .compact ? 24 : 32)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .background(OrbitDesign.canvas)
        .navigationTitle(AppLanguage.text("仓库概览", "Repository"))
    }

    private var overviewSpacing: CGFloat {
        density == .compact ? 16 : 22
    }

    private func overviewHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width >= 1_700 { return 46 }
        if width >= 1_320 { return 38 }
        return density == .compact ? 24 : 30
    }

    private func overviewContentWidth(for width: CGFloat) -> CGFloat {
        let sidePadding = overviewHorizontalPadding(for: width) * 2
        let available = max(width - sidePadding, 900)
        if width >= 1_700 { return min(available, 1_860) }
        if width >= 1_320 { return min(available, 1_560) }
        return available
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RepositoryIdentityMark(identity: appState.repository?.path ?? "GitIgnore", size: density == .compact ? 46 : 54)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(AppLanguage.text("仓库状态中心", "Repository Status"))
                        .orbitFont(.caption2, weight: .bold)
                        .foregroundStyle(OrbitDesign.accent)
                    Circle().fill(remoteStatusColor).frame(width: 6, height: 6)
                    Text(appState.repositoryHealth.remoteConnection.title)
                        .orbitFont(.caption2, weight: .medium)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                Text(appState.repository?.name ?? AppLanguage.text("打开一个仓库开始工作", "Open a repository to begin"))
                    .orbitFont(.title2, weight: .bold)
                    .lineLimit(1)
                if let repository = appState.repository {
                    HStack(spacing: 7) {
                        Label(repository.branch, systemImage: "arrow.triangle.branch")
                            .lineLimit(1)
                        Text("·")
                        Text(repository.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                        .font(.caption.monospaced())
                        .foregroundStyle(OrbitDesign.secondaryText)
                } else {
                    Text(AppLanguage.text("GitIgnore 会把远程同步、本地变更和仓库风险整理成明确的下一步。", "GitIgnore turns remote sync, local changes, and repository risks into a clear next step."))
                        .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                }
            }
            Spacer(minLength: 20)
            if appState.isLoadingRepository || appState.isCheckingRemoteUpdates {
                ProgressView()
                    .controlSize(.small)
                    .tint(OrbitDesign.accent)
                    .accessibilityLabel(AppLanguage.text("正在刷新仓库状态", "Refreshing repository status"))
            }
            Button { Task { await appState.refreshRepository() } } label: {
                Label(AppLanguage.text("刷新", "Refresh"), systemImage: "arrow.clockwise")
                    .orbitFont(.caption, weight: .semibold)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(OrbitDesign.surface, in: Capsule())
                    .overlay { Capsule().stroke(OrbitDesign.separator, lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(OrbitDesign.secondaryText).help(AppLanguage.text("刷新仓库状态", "Refresh repository status"))
            .disabled(appState.repository == nil || appState.isLoadingRepository)
        }
    }

    private func repositoryPulse(_ repository: RepositorySummary) -> some View {
        HStack(spacing: 0) {
            PulseMetric(title: "Pull", value: repository.behindCount, symbol: "arrow.down", color: repository.behindCount > 0 ? OrbitDesign.amber : OrbitDesign.tertiaryText) { appState.selectSection(.history) }
            pulseSeparator
            PulseMetric(title: "Push", value: repository.aheadCount, symbol: "arrow.up", color: repository.aheadCount > 0 ? OrbitDesign.blue : OrbitDesign.tertiaryText) { appState.selectSection(.branches) }
            pulseSeparator
            PulseMetric(title: AppLanguage.text("本地变更", "Changes"), value: repository.changedFileCount, symbol: "doc.badge.ellipsis", color: repository.changedFileCount > 0 ? OrbitDesign.amber : OrbitDesign.tertiaryText) { appState.selectSection(.changes) }
            pulseSeparator
            PulseMetric(title: AppLanguage.text("冲突", "Conflicts"), value: conflictCount, symbol: "exclamationmark.triangle", color: conflictCount > 0 ? OrbitDesign.coral : OrbitDesign.tertiaryText) { appState.selectSection(.changes) }
        }
        .frame(minHeight: density == .compact ? 78 : 92)
        .background { OrbitPanelBackground(cornerRadius: 12) }
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(OrbitDesign.panelBorder, lineWidth: 1) }
        .animation(reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation, value: repository.behindCount)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation, value: repository.aheadCount)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation, value: repository.changedFileCount)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation, value: conflictCount)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLanguage.text("仓库摘要", "Repository summary"))
    }

    private var pulseSeparator: some View {
        Rectangle()
            .fill(OrbitDesign.separator.opacity(0.8))
            .frame(width: 1, height: 34)
    }

    private func primaryAction(_ repository: RepositorySummary) -> some View {
        let recommendation = recommendation(for: repository)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: density == .compact ? 24 : 32) {
                recommendationContent(recommendation)
                BranchTrajectory(
                    branch: repository.branch,
                    behindCount: repository.behindCount,
                    aheadCount: repository.aheadCount,
                    accent: recommendation.color
                )
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 460, minHeight: 108, idealHeight: 118)
            }
            VStack(alignment: .leading, spacing: 16) {
                recommendationContent(recommendation)
                Divider().overlay(OrbitDesign.separator)
                HStack {
                    Label(repository.branch, systemImage: "arrow.triangle.branch")
                    Spacer()
                    Text(syncCaption(repository))
                }
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .padding(density == .compact ? 18 : 24)
        .background { OrbitPanelBackground(cornerRadius: 13, emphasis: true) }
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(OrbitDesign.panelBorder, lineWidth: 1) }
        .animation(reduceMotion ? .easeOut(duration: 0.08) : OrbitDesign.feedbackAnimation, value: recommendation.title)
    }

    private func recommendationContent(_ recommendation: OverviewRecommendation) -> some View {
        HStack(spacing: 14) {
            OrbitIconBadge(systemName: recommendation.symbol, color: recommendation.color, size: density == .compact ? 46 : 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(AppLanguage.text("建议下一步", "Next Step")).orbitFont(.caption2, weight: .bold).foregroundStyle(OrbitDesign.secondaryText)
                Text(recommendation.title).orbitFont(.title3, weight: .bold).lineLimit(2)
                Text(recommendation.detail)
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 14)
            Button(recommendation.buttonTitle) { recommendation.action() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appState.isPerformingGitAction)
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func contentColumns(_ repository: RepositorySummary, availableWidth: CGFloat) -> some View {
        let spacing = overviewSpacing
        if availableWidth >= 1_620 {
            let sideWidth = min(420, max(360, (availableWidth - spacing * 2) * 0.235))
            let statusWidth = max(620, availableWidth - sideWidth * 2 - spacing * 2)
            HStack(alignment: .top, spacing: overviewSpacing) {
                repositoryStatus(repository)
                    .frame(width: statusWidth, alignment: .top)
                repositoryRisks(repository)
                    .frame(width: sideWidth, alignment: .top)
                quickAccess(repository)
                    .frame(width: sideWidth, alignment: .top)
            }
            .frame(width: availableWidth, alignment: .leading)
        } else if availableWidth >= 1_040 {
            let sideWidth = min(430, max(360, availableWidth * 0.33))
            let statusWidth = max(560, availableWidth - sideWidth - spacing)
            HStack(alignment: .top, spacing: density.pageSpacing) {
                repositoryStatus(repository)
                    .frame(width: statusWidth, alignment: .top)
                VStack(spacing: density.pageSpacing) {
                    repositoryRisks(repository)
                    quickAccess(repository)
                }
                .frame(width: sideWidth)
            }
            .frame(width: availableWidth, alignment: .leading)
        } else if availableWidth >= 720 {
            VStack(spacing: density.pageSpacing) {
                repositoryStatus(repository)
                HStack(alignment: .top, spacing: density.pageSpacing) {
                    repositoryRisks(repository)
                        .frame(maxWidth: .infinity, alignment: .top)
                    quickAccess(repository)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: density.pageSpacing) {
                repositoryStatus(repository)
                repositoryRisks(repository)
                quickAccess(repository)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func repositoryStatus(_ repository: RepositorySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLanguage.text("当前状态", "Current Status"), symbol: "waveform.path.ecg", caption: AppLanguage.text("仓库与远程状态实时汇总", "Repository and remote status at a glance"))
            VStack(spacing: 0) {
                statusRow(
                    AppLanguage.text("远程同步", "Remote Sync"),
                    value: remoteSummary(repository),
                    symbol: remoteSymbol,
                    color: remoteStatusColor
                )
                separator
                statusRow(
                    AppLanguage.text("本地工作区", "Working Tree"),
                    value: AppLanguage.text("未提交 \(repository.changedFileCount) · 已 Stage \(repository.stagedFileCount) · 冲突 \(conflictCount)", "Changed \(repository.changedFileCount) · Staged \(repository.stagedFileCount) · Conflicts \(conflictCount)"),
                    symbol: conflictCount > 0 ? "exclamationmark.triangle.fill" : "doc.badge.ellipsis",
                    color: conflictCount > 0 ? OrbitDesign.coral : (repository.changedFileCount > 0 ? OrbitDesign.amber : OrbitDesign.accent)
                )
                separator
                statusRow(
                    AppLanguage.text("仓库流程", "Repository Flow"),
                    value: operationSummary,
                    symbol: appState.repositoryHealth.operationState == nil ? "checkmark.circle" : "arrow.triangle.2.circlepath",
                    color: appState.repositoryHealth.operationState == nil ? OrbitDesign.accent : OrbitDesign.amber
                )
                separator
                statusRow(
                    AppLanguage.text("最近 Fetch", "Last Fetch"),
                    value: lastFetchText,
                    symbol: "clock",
                    color: OrbitDesign.secondaryText
                )
            }
            .background { OrbitPanelBackground(cornerRadius: 11) }
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitDesign.panelBorder, lineWidth: 1) }
        }
    }

    @ViewBuilder
    private func repositoryRisks(_ repository: RepositorySummary) -> some View {
        let risks = riskItems(repository)
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLanguage.text("需要留意", "Needs Attention"), symbol: "checklist", caption: risks.isEmpty ? AppLanguage.text("当前没有阻塞项", "No blockers") : AppLanguage.text("建议尽快确认", "Review soon"))
            if risks.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(OrbitDesign.accent)
                    Text(AppLanguage.text("没有发现失效 Worktree、过期 Stash 或未跟踪大文件", "No invalid Worktrees, stale Stashes, or large untracked files found"))
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background { OrbitPanelBackground(cornerRadius: 11) }
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitDesign.panelBorder, lineWidth: 1) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(risks.enumerated()), id: \.offset) { index, risk in
                        Button { appState.selectSection(risk.section) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: risk.symbol).foregroundStyle(risk.color).frame(width: 20)
                                Text(risk.title).orbitFont(.caption).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").orbitFont(.caption2, weight: .bold).foregroundStyle(OrbitDesign.secondaryText)
                            }
                            .padding(12).contentShape(Rectangle())
                        }
                        .buttonStyle(OrbitInteractiveButtonStyle())
                        if index < risks.count - 1 { separator }
                    }
                }
                .background { OrbitPanelBackground(cornerRadius: 11) }
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitDesign.panelBorder, lineWidth: 1) }
            }
        }
    }

    private func quickAccess(_ repository: RepositorySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(AppLanguage.text("快速前往", "Quick Access"), symbol: "arrow.up.right.square", caption: AppLanguage.text("继续处理仓库内容", "Continue repository work"))
            VStack(spacing: 0) {
                quickAccessRow(
                    AppLanguage.text("工作区变更", "Changes"),
                    detail: repository.changedFileCount == 0 ? AppLanguage.text("工作区干净", "Working tree clean") : AppLanguage.text("\(repository.changedFileCount) 个文件待处理", "\(repository.changedFileCount) files to review"),
                    symbol: "list.bullet.rectangle",
                    color: repository.changedFileCount > 0 ? OrbitDesign.blue : OrbitDesign.secondaryText,
                    section: .changes
                )
                separator
                quickAccessRow(
                    AppLanguage.text("提交历史", "History"),
                    detail: repository.behindCount > 0 ? AppLanguage.text("\(repository.behindCount) 个远程提交待查看", "\(repository.behindCount) remote commits to review") : AppLanguage.text("查看分支演进", "Review branch timeline"),
                    symbol: "clock.arrow.circlepath",
                    color: repository.behindCount > 0 ? OrbitDesign.amber : OrbitDesign.secondaryText,
                    section: .history
                )
                separator
                quickAccessRow(
                    AppLanguage.text("分支与标签", "Branches & Tags"),
                    detail: repository.branch,
                    symbol: "arrow.triangle.branch",
                    color: OrbitDesign.violet,
                    section: .branches
                )
            }
            .background { OrbitPanelBackground(cornerRadius: 11) }
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitDesign.panelBorder, lineWidth: 1) }
        }
    }

    private func quickAccessRow(
        _ title: String,
        detail: String,
        symbol: String,
        color: Color,
        section: SidebarSection
    ) -> some View {
        Button { appState.selectSection(section) } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).orbitFont(.caption, weight: .semibold)
                    Text(detail).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: density == .compact ? 42 : 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(OrbitInteractiveButtonStyle())
    }

    private func statusRow(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(title).orbitFont(.callout, weight: .semibold).frame(width: 104, alignment: .leading)
            Text(value).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading).contentTransition(.numericText())
        }
        .padding(.horizontal, 15).frame(minHeight: density == .compact ? 46 : 54)
    }

    private var separator: some View { Divider().overlay(OrbitDesign.separator).padding(.leading, 44) }

    private func sectionTitle(_ title: String, symbol: String, caption: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: symbol).orbitFont(.headline)
            Spacer()
            if let caption {
                Text(caption).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
            }
        }
    }

    private var conflictCount: Int { appState.status.files.count(where: \.hasConflict) }

    private var operationSummary: String {
        if let operation = appState.repositoryHealth.operationState {
            return AppLanguage.text("正在进行 \(operation.rawValue)，请先完成或中止", "\(operation.rawValue) in progress. Finish or abort it first.")
        }
        if appState.repositoryHealth.isDetachedHead { return AppLanguage.text("Detached HEAD（游离状态）", "Detached HEAD") }
        return AppLanguage.text("没有未完成的 Merge、Rebase 或 Cherry-pick", "No Merge, Rebase, or Cherry-pick in progress")
    }

    private var remoteSymbol: String {
        switch appState.repositoryHealth.remoteConnection {
        case .checking: "arrow.triangle.2.circlepath"
        case .connected: "network"
        case .unavailable, .timedOut, .unauthorized, .notFound: "wifi.exclamationmark"
        case .unknown: "questionmark.circle"
        }
    }

    private var remoteStatusColor: Color {
        switch appState.repositoryHealth.remoteConnection {
        case .connected: OrbitDesign.accent
        case .checking, .unknown: OrbitDesign.amber
        case .unavailable, .timedOut, .unauthorized, .notFound: OrbitDesign.coral
        }
    }

    private func remoteSummary(_ repository: RepositorySummary) -> String {
        switch appState.repositoryHealth.remoteConnection {
        case .checking:
            return AppLanguage.text("正在检测远程更新", "Checking remote updates")
        case let .unavailable(message):
            return message
        case let .timedOut(message), let .unauthorized(message), let .notFound(message):
            return message
        case .unknown:
            return AppLanguage.text("尚未完成远程检测", "Remote not checked yet")
        case .connected:
            if repository.needsPublish {
                return AppLanguage.text("当前分支尚未发布", "Branch not published")
            }
            return AppLanguage.text("可 Pull \(repository.behindCount) · 未 Push \(repository.aheadCount)", "Pull \(repository.behindCount) · Push \(repository.aheadCount)")
        }
    }

    private func syncCaption(_ repository: RepositorySummary) -> String {
        if !appState.repositoryHealth.remoteConnection.isConnected {
            return appState.repositoryHealth.remoteConnection.title
        }
        if repository.needsPublish { return AppLanguage.text("当前分支尚未发布", "Branch not published") }
        if repository.behindCount == 0, repository.aheadCount == 0 { return AppLanguage.text("本地与远程已同步", "Local and remote are synced") }
        return AppLanguage.text("Pull \(repository.behindCount) · Push \(repository.aheadCount)", "Pull \(repository.behindCount) · Push \(repository.aheadCount)")
    }

    private var lastFetchText: String {
        guard let date = appState.repositoryHealth.lastFetchAt else { return AppLanguage.text("本次尚未完成远程检测", "No remote check completed yet") }
        return date.formatted(.relative(presentation: .named))
    }

    private func recommendation(for repository: RepositorySummary) -> OverviewRecommendation {
        if conflictCount > 0 {
            return .init(title: AppLanguage.text("先解决 \(conflictCount) 个冲突", "Resolve \(conflictCount) conflicts first"), detail: AppLanguage.text("冲突未完成前不建议继续同步或切换分支。", "Avoid syncing or switching branches until conflicts are resolved."), buttonTitle: AppLanguage.text("处理冲突", "Resolve"), symbol: "exclamationmark.triangle.fill", color: OrbitDesign.coral) {
                appState.selectSection(.changes)
            }
        }
        if let operation = appState.repositoryHealth.operationState {
            return .init(title: AppLanguage.text("继续完成 \(operation.rawValue)", "Continue \(operation.rawValue)"), detail: AppLanguage.text("仓库处于中间状态，请检查待解决文件和流程状态。", "The repository is mid-operation. Check files and flow state."), buttonTitle: AppLanguage.text("查看工作区", "View Changes"), symbol: "arrow.triangle.2.circlepath", color: OrbitDesign.amber) {
                appState.selectSection(.changes)
            }
        }
        if case .unavailable = appState.repositoryHealth.remoteConnection {
            return .init(title: AppLanguage.text("远程检测暂时不可用", "Remote check unavailable"), detail: AppLanguage.text("保留本地状态，可稍后重新 Fetch 或检查网络连接。", "Local state is safe. Retry Fetch later or check the connection."), buttonTitle: "Fetch", symbol: "wifi.exclamationmark", color: OrbitDesign.coral) {
                Task { await appState.fetch() }
            }
        }
        if repository.behindCount > 0 {
            return .init(title: AppLanguage.text("有 \(repository.behindCount) 个远程提交可 Pull", "\(repository.behindCount) remote commits ready to Pull"), detail: AppLanguage.text("已自动检测到远程更新；Pull 前会先保护本地修改。", "Remote updates were detected automatically. Local changes are protected before Pull."), buttonTitle: AppLanguage.text("安全 Pull", "Safe Pull"), symbol: "arrow.down.circle.fill", color: OrbitDesign.amber) {
                Task { await appState.pull() }
            }
        }
        if repository.needsPublish {
            return .init(
                title: AppLanguage.text("当前分支尚未发布到远程", "Publish the current branch"),
                detail: AppLanguage.text("这是一个本地分支；发布后会自动建立远程跟踪关系。", "This local branch has no upstream yet. Publishing will create its remote tracking branch."),
                buttonTitle: AppLanguage.text("发布分支", "Publish Branch"),
                symbol: "arrow.up.right.circle.fill",
                color: OrbitDesign.blue
            ) {
                Task { await appState.publishCurrentBranch() }
            }
        }
        if repository.changedFileCount > 0 {
            return .init(title: AppLanguage.text("整理 \(repository.changedFileCount) 个本地变更", "Review \(repository.changedFileCount) local changes"), detail: AppLanguage.text("先检查差异、完成 Stage，再创建提交。", "Inspect Diffs, Stage the right files, then commit."), buttonTitle: AppLanguage.text("查看变更", "View Changes"), symbol: "list.bullet.rectangle", color: OrbitDesign.amber) {
                appState.selectSection(.changes)
            }
        }
        if repository.aheadCount > 0 {
            return .init(title: AppLanguage.text("有 \(repository.aheadCount) 个本地提交未 Push", "\(repository.aheadCount) local commits to Push"), detail: AppLanguage.text("工作区干净，可以将本地提交上传到远程。", "The working tree is clean. Push local commits when ready."), buttonTitle: "Push", symbol: "arrow.up.circle.fill", color: OrbitDesign.blue) {
                Task { await appState.push() }
            }
        }
        return .init(title: AppLanguage.text("仓库已同步且工作区干净", "Repository is clean and synced"), detail: AppLanguage.text("当前没有必须处理的事项，可以开始新的工作。", "Nothing needs attention right now. Start the next piece of work."), buttonTitle: AppLanguage.text("查看历史", "View History"), symbol: "checkmark.circle.fill", color: OrbitDesign.accent) {
            appState.selectSection(.history)
        }
    }

    private func riskItems(_ repository: RepositorySummary) -> [OverviewRisk] {
        var result: [OverviewRisk] = []
        if appState.repositoryHealth.isDetachedHead {
            result.append(.init(title: AppLanguage.text("当前处于 Detached HEAD", "Detached HEAD"), symbol: "arrow.triangle.branch", color: OrbitDesign.coral, section: .branches))
        }
        if appState.repositoryHealth.invalidWorktreeCount > 0 {
            result.append(.init(title: AppLanguage.text("\(appState.repositoryHealth.invalidWorktreeCount) 个 Worktree 路径已失效", "\(appState.repositoryHealth.invalidWorktreeCount) invalid Worktree paths"), symbol: "point.3.connected.trianglepath.dotted", color: OrbitDesign.amber, section: .worktrees))
        }
        if appState.repositoryHealth.staleStashCount > 0 {
            result.append(.init(title: AppLanguage.text("\(appState.repositoryHealth.staleStashCount) 条 Stash 已超过 30 天", "\(appState.repositoryHealth.staleStashCount) Stashes older than 30 days"), symbol: "archivebox", color: OrbitDesign.amber, section: .stashes))
        }
        if !appState.repositoryHealth.largeUntrackedFiles.isEmpty {
            result.append(.init(title: AppLanguage.text("\(appState.repositoryHealth.largeUntrackedFiles.count) 个未跟踪文件超过 20 MB", "\(appState.repositoryHealth.largeUntrackedFiles.count) untracked files over 20 MB"), symbol: "externaldrive.badge.exclamationmark", color: OrbitDesign.amber, section: .changes))
        }
        if case .unavailable = appState.repositoryHealth.remoteConnection {
            result.append(.init(title: AppLanguage.text("远程仓库当前无法连接", "Remote repository is unavailable"), symbol: "wifi.exclamationmark", color: OrbitDesign.coral, section: .overview))
        }
        return result
    }

    private var emptyRepository: some View {
        VStack(spacing: 14) {
            RepositoryIdentityMark(identity: "GitIgnore", size: 60)
            Text(AppLanguage.text("还没有打开仓库", "No repository open")).orbitFont(.title3, weight: .bold)
            Text(AppLanguage.text("选择一个本地 Git 仓库后，GitIgnore 会汇总远程同步、本地修改、冲突和流程状态。", "Choose a local Git repository and GitIgnore will summarize remote sync, local changes, conflicts, and flow state."))
                .orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 480)
            Button(AppLanguage.text("选择 Git 仓库…", "Choose Git Repository…")) { appState.chooseRepository() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 70)
        .background { OrbitPanelBackground(cornerRadius: 14, emphasis: true) }
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(OrbitDesign.separator, lineWidth: 1) }
    }
}

private struct OverviewRecommendation {
    let title: String
    let detail: String
    let buttonTitle: String
    let symbol: String
    let color: Color
    let action: () -> Void
}

private struct OverviewRisk {
    let title: String
    let symbol: String
    let color: Color
    let section: SidebarSection
}
