import SwiftUI

struct RepositoryToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isSidebarCollapsed: Bool
    @Binding var appearancePresented: Bool
    let appearanceRawValue: String
    @State private var toolsPresented = false
    @State private var remoteStatusPresented = false
    @State private var operationCenterPresented = false

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton(
                "sidebar.left",
                help: isSidebarCollapsed ? "展开左侧栏（⌃⌘S）" : "收起左侧栏（⌃⌘S）"
            ) {
                isSidebarCollapsed.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Divider()
                .frame(height: 18)
                .overlay(OrbitDesign.separator)

            if let repository = appState.repository {
                repositoryStatus(repository)
            } else {
                Label(AppLanguage.text("尚未打开仓库", "No Repository Open"), systemImage: "folder")
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }

            Spacer(minLength: 12)

            WorkspaceActionButton(title: "Fetch", systemName: "arrow.down.circle") {
                Task { await appState.fetch() }
            }
            .disabled(appState.repository == nil || appState.isPerformingGitAction)

            if let behindCount = appState.repository?.behindCount, behindCount > 0 {
                WorkspaceActionButton(
                    title: "Pull \(behindCount)",
                    systemName: "arrow.down.to.line",
                    tint: OrbitDesign.amber
                ) {
                    Task { await appState.pull() }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .disabled(appState.isPerformingGitAction)
            }

            if let currentBranch, currentBranch.needsPublish {
                WorkspaceActionButton(
                    title: AppLanguage.text("发布分支", "Publish Branch"),
                    systemName: "arrow.up.right",
                    tint: OrbitDesign.blue
                ) {
                    Task { await appState.publishCurrentBranch() }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .disabled(appState.isPerformingGitAction)
            } else if let aheadCount = appState.repository?.aheadCount, aheadCount > 0 {
                WorkspaceActionButton(
                    title: "Push \(aheadCount)",
                    systemName: "arrow.up.to.line",
                    tint: OrbitDesign.blue
                ) {
                    Task { await appState.push() }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .disabled(appState.isPerformingGitAction)
            }

            utilityMenu
                .disabled(appState.repository == nil)
                .popover(isPresented: $operationCenterPresented, arrowEdge: .top) {
                    GitOperationCenterView().environment(appState)
                }
                .sheet(isPresented: $toolsPresented) {
                    RepositoryToolsView().environment(appState)
                }

            toolbarButton(
                appearanceRawValue == AppAppearance.dark.rawValue ? "moon.stars" : "circle.lefthalf.filled",
                help: AppLanguage.text("外观与界面字体", "Appearance and UI fonts")
            ) {
                appearancePresented.toggle()
            }
            .popover(isPresented: $appearancePresented, arrowEdge: .top) {
                AppearancePopover()
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietToolbarButtonStyle())
            .help(AppLanguage.text("打开完整设置", "Open full settings"))
        }
        .padding(.trailing, 14)
        .padding(.leading, isSidebarCollapsed ? 82 : 14)
        .frame(height: 46)
        .background { OrbitChromeBackground(region: .toolbar) }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18), value: appState.repository?.behindCount)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18), value: appState.repository?.aheadCount)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18), value: currentBranch?.needsPublish)
    }

    private func repositoryStatus(_ repository: RepositorySummary) -> some View {
        Button {
            remoteStatusPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Label(repository.branch, systemImage: "arrow.triangle.branch")
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if appState.isCheckingRemoteUpdates {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle()
                            .fill(remoteStatusColor(repository))
                            .frame(width: 7, height: 7)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
                    }
                    Text(remoteStatusText(repository))
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(OrbitDesign.tertiaryText)
                }
                .foregroundStyle(remoteStatusColor(repository))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(remoteStatusColor(repository).opacity(0.09), in: Capsule())
                .overlay { Capsule().stroke(remoteStatusColor(repository).opacity(0.20), lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .orbitFont(.caption, weight: .semibold)
        .lineLimit(1)
        .help(AppLanguage.text("查看远程同步详情", "View remote sync details"))
        .popover(isPresented: $remoteStatusPresented, arrowEdge: .top) {
            remoteStatusPopover(repository)
        }
    }

    private func remoteStatusPopover(_ repository: RepositorySummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                OrbitIconBadge(systemName: "network", color: remoteStatusColor(repository), size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLanguage.text("远程同步状态", "Remote Sync Status"))
                        .orbitFont(.callout, weight: .bold)
                    Text(appState.repositoryHealth.remoteConnection.title)
                        .orbitFont(.caption)
                        .foregroundStyle(remoteStatusColor(repository))
                }
            }

            if case let .unavailable(message) = appState.repositoryHealth.remoteConnection {
                Text(message)
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                remoteDetailRow(AppLanguage.text("可 Pull", "Ready to Pull"), value: "\(repository.behindCount)")
                remoteDetailRow(AppLanguage.text("待 Push", "Ready to Push"), value: "\(repository.aheadCount)")
                remoteDetailRow(
                    AppLanguage.text("上次检查", "Last Checked"),
                    value: appState.repositoryHealth.lastFetchAt.map(Self.remoteDateFormatter.string(from:))
                        ?? AppLanguage.text("尚未检查", "Not Checked")
                )
            }

            HStack(spacing: 8) {
                Button {
                    appState.scheduleRemoteUpdateCheck(for: URL(fileURLWithPath: repository.path, isDirectory: true))
                } label: {
                    Label(
                        appState.isCheckingRemoteUpdates ? AppLanguage.text("正在检查", "Checking") : AppLanguage.text("重新检查", "Check Again"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.isCheckingRemoteUpdates || appState.isPerformingGitAction)

                SettingsLink {
                    Text(AppLanguage.text("通知与远程设置", "Remote & Notification Settings"))
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func remoteDetailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(OrbitDesign.secondaryText)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(OrbitDesign.primaryText)
        }
        .orbitFont(.caption)
    }

    private static let remoteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func remoteStatusText(_ repository: RepositorySummary) -> String {
        if appState.isCheckingRemoteUpdates {
            return AppLanguage.text("正在检查远程更新", "Checking remote updates")
        }
        if case .unavailable = appState.repositoryHealth.remoteConnection {
            return AppLanguage.text("远程暂时不可用", "Remote unavailable")
        }
        if case .timedOut = appState.repositoryHealth.remoteConnection { return AppLanguage.text("远程连接超时", "Remote connection timed out") }
        if case .unauthorized = appState.repositoryHealth.remoteConnection { return AppLanguage.text("远程认证失败", "Remote authentication failed") }
        if case .notFound = appState.repositoryHealth.remoteConnection { return AppLanguage.text("远程仓库不存在", "Remote not found") }
        if repository.behindCount > 0 {
            return AppLanguage.text("\(repository.behindCount) 个提交可拉取", "\(repository.behindCount) commits ready to Pull")
        }
        if repository.aheadCount > 0 {
            return AppLanguage.text("\(repository.aheadCount) 个提交待 Push", "\(repository.aheadCount) commits to Push")
        }
        if currentBranch?.needsPublish == true {
            return AppLanguage.text("当前分支尚未发布", "Branch not published")
        }
        return AppLanguage.text("已与远程同步", "Synced")
    }

    private var currentBranch: GitBranchSummary? {
        appState.branches.first(where: \.isCurrent)
    }

    private func remoteStatusColor(_ repository: RepositorySummary) -> Color {
        if appState.isCheckingRemoteUpdates { return OrbitDesign.secondaryText }
        if case .unavailable = appState.repositoryHealth.remoteConnection { return OrbitDesign.coral }
        if case .timedOut = appState.repositoryHealth.remoteConnection { return OrbitDesign.coral }
        if case .unauthorized = appState.repositoryHealth.remoteConnection { return OrbitDesign.coral }
        if case .notFound = appState.repositoryHealth.remoteConnection { return OrbitDesign.coral }
        if repository.behindCount > 0 { return OrbitDesign.amber }
        if repository.aheadCount > 0 { return OrbitDesign.blue }
        if currentBranch?.needsPublish == true { return OrbitDesign.blue }
        return OrbitDesign.accent
    }

    private var utilityMenu: some View {
        Menu {
            Button(AppLanguage.text("重新读取仓库状态", "Refresh Repository"), systemImage: "arrow.clockwise") {
                Task { await appState.refreshRepository() }
            }
            .disabled(appState.isLoadingRepository)

            Button(AppLanguage.text("在终端中打开", "Open in Terminal"), systemImage: "terminal") {
                appState.openTerminal()
            }

            Divider()

            Button(AppLanguage.text("Git 操作中心", "Git Operation Center"), systemImage: "waveform.path.ecg") {
                operationCenterPresented = true
            }

            Button(AppLanguage.text("专业工具", "Professional Tools"), systemImage: "slider.horizontal.3") {
                toolsPresented = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                if appState.workflows.activeOperation != nil {
                    Circle()
                        .fill(OrbitDesign.amber)
                        .frame(width: 7, height: 7)
                        .overlay { Circle().stroke(OrbitDesign.canvas, lineWidth: 1) }
                        .padding(3)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(QuietToolbarButtonStyle())
        .help(AppLanguage.text("更多仓库工具", "More repository tools"))
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietToolbarButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

}

struct WorkspaceActionButton: View {
    let title: String
    let systemName: String
    var tint: Color = OrbitDesign.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceActionButtonStyle(tint: tint))
    }
}

private struct WorkspaceActionButtonStyle: ButtonStyle {
    let tint: Color
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(isHovering ? 0.12 : 0.075), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(tint.opacity(isHovering ? 0.28 : 0.14), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.68 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct QuietToolbarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? OrbitDesign.primaryText : OrbitDesign.secondaryText)
            .background(
                OrbitDesign.primaryText.opacity(isHovering ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct SafePullSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let request: SafePullRequest
    @State private var incomingDiffRequest: IncomingDiffRequest?

    private var isRunning: Bool { appState.safePullPhase != nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                metrics
                incomingPreview
                if request.changedFileCount > 0 {
                    progressCard
                } else {
                    Label("工作区干净，将直接执行 fast-forward Pull。", systemImage: "checkmark.shield")
                        .orbitFont(.caption, weight: .semibold)
                        .foregroundStyle(OrbitDesign.accent)
                }
                Label(
                    AppLanguage.isEnglish
                        ? "If restore creates conflicts, GitIgnore keeps the Stash and opens the three-way editor."
                        : "若恢复时出现冲突，GitIgnore 会保留 Stash，并自动打开三栏冲突编辑器。",
                    systemImage: "shield.checkered"
                )
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
        .task { await appState.loadIncomingPreview() }
        .sheet(item: $incomingDiffRequest) { request in
            IncomingDiffPreviewView(request: request).environment(appState)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.2),
            value: appState.safePullPhase
        )
    }

    private var header: some View {
        HStack(spacing: 13) {
            OrbitIconBadge(systemName: "arrow.down.to.line", color: OrbitDesign.amber, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLanguage.isEnglish ? "Safe Pull remote updates" : "安全拉取远程更新")
                    .orbitFont(.title3, weight: .bold)
                Text(AppLanguage.isEnglish
                     ? "Local work will be protected before Pull. Nothing is discarded."
                     : "先保护当前本地修改，再执行 Pull；不会丢弃任何内容。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            metric(AppLanguage.isEnglish ? "Changed" : "本地变更", value: request.changedFileCount, color: OrbitDesign.amber)
            metric(AppLanguage.isEnglish ? "Staged" : "已暂存", value: request.stagedFileCount, color: OrbitDesign.accent)
            metric(AppLanguage.isEnglish ? "Untracked" : "未跟踪", value: request.untrackedFileCount, color: OrbitDesign.blue)
            metric(AppLanguage.isEnglish ? "Incoming" : "待拉取", value: request.incomingCommitCount, color: OrbitDesign.violet)
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
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private var progressCard: some View {
        VStack(spacing: 0) {
            phaseRow(.protecting, title: AppLanguage.isEnglish ? "Protect local changes" : "临时保护本地修改")
            Divider().padding(.leading, 42).overlay(OrbitDesign.separator)
            phaseRow(.pulling, title: AppLanguage.isEnglish ? "Pull remote commits" : "Pull 远程提交")
            Divider().padding(.leading, 42).overlay(OrbitDesign.separator)
            phaseRow(.restoring, title: AppLanguage.isEnglish ? "Restore local changes" : "恢复本地修改")
        }
        .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private var incomingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pull 前更新预览", systemImage: "eye")
                    .orbitFont(.caption, weight: .bold)
                Spacer()
                if appState.workflows.isLoadingPreview {
                    ProgressView().controlSize(.mini)
                }
            }
            if appState.incomingCommits.isEmpty {
                Text("当前没有读取到待拉取提交；执行时 Git 仍会再次核对远程状态。")
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.incomingCommits.prefix(30)) { commit in
                            DisclosureGroup {
                                if let detail = appState.workflows.incomingPreview[commit.id] {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        ForEach(detail.files) { file in
                                            Button {
                                                incomingDiffRequest = IncomingDiffRequest(commit: commit, file: file)
                                            } label: {
                                                HStack {
                                                    Label(file.path, systemImage: "doc")
                                                        .font(.caption2.monospaced())
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .orbitFont(.caption2)
                                                }
                                                .foregroundStyle(OrbitDesign.secondaryText)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .help("查看此远程提交中的文件 Diff")
                                        }
                                    }
                                    .padding(.vertical, 5)
                                } else {
                                    Text("正在读取文件列表…")
                                        .orbitFont(.caption2)
                                        .foregroundStyle(OrbitDesign.secondaryText)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(commit.shortHash)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(OrbitDesign.amber)
                                    Text(commit.subject).orbitFont(.caption).lineLimit(1)
                                    Spacer()
                                    if let count = appState.workflows.incomingPreview[commit.id]?.files.count {
                                        Text("\(count) 文件").orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(11)
        .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func phaseRow(_ phase: SafePullPhase, title: String) -> some View {
        let current = appState.safePullPhase
        let completed = current.map { $0.rawValue > phase.rawValue } ?? false
        let active = current == phase
        return HStack(spacing: 11) {
            Group {
                if active {
                    ProgressView().controlSize(.small).tint(OrbitDesign.accent)
                } else if completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OrbitDesign.accent)
                } else {
                    Text("\(phase.rawValue + 1)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .frame(width: 17, height: 17)
                        .background(OrbitDesign.surface, in: Circle())
                }
            }
            .frame(width: 20)
            Text(title)
                .orbitFont(.caption, weight: active ? .bold : .medium)
                .foregroundStyle(active ? OrbitDesign.primaryText : OrbitDesign.secondaryText)
            Spacer()
            if active {
                Text(AppLanguage.isEnglish ? "In progress" : "进行中")
                    .orbitFont(.caption2, weight: .semibold)
                    .foregroundStyle(OrbitDesign.accent)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(AppLanguage.isEnglish ? "Review workspace" : "先处理工作区") {
                appState.reviewChangesBeforePull()
            }
            .disabled(isRunning)
            Spacer()
            Button(AppLanguage.isEnglish ? "Cancel" : "取消") {
                appState.cancelSafePull()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isRunning)
            Button {
                Task { await appState.performSafePull() }
            } label: {
                Label(
                    isRunning
                        ? (AppLanguage.isEnglish ? "Safe Pull in progress…" : "正在安全拉取…")
                        : (request.changedFileCount > 0
                           ? (AppLanguage.isEnglish ? "Safe Pull" : "安全拉取")
                           : (AppLanguage.isEnglish ? "Pull updates" : "确认 Pull")),
                    systemImage: "shield.lefthalf.filled"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(OrbitDesign.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(isRunning)
        }
        .buttonStyle(.bordered)
    }
}
