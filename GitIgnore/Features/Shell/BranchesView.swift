import SwiftUI

struct BranchesView: View {
    @Environment(AppState.self) private var appState
    @State private var isCreatingBranch = false
    @State private var branchName = ""
    @State private var query = ""
    @State private var showsBranchTools = false

    private var visibleBranches: [GitBranchSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return appState.branches }
        return appState.branches.filter { $0.name.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if appState.repository == nil {
                emptyState
            } else if visibleBranches.isEmpty {
                noBranches
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        localBranchGroup
                        if !appState.remoteBranches.isEmpty { remoteBranchGroup }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(OrbitDesign.canvas)
        .navigationTitle("分支与标签")
        .orbitPageReveal()
        .sheet(isPresented: $isCreatingBranch) {
            CreateBranchSheet(name: $branchName) {
                let name = branchName
                branchName = ""
                isCreatingBranch = false
                Task { await appState.createBranch(name: name) }
            } cancel: {
                branchName = ""
                isCreatingBranch = false
            }
        }
        .sheet(isPresented: $showsBranchTools) {
            BranchToolsView().environment(appState)
        }
        .sheet(isPresented: rebasePlannerBinding) {
            RebasePlannerView().environment(appState)
        }
    }

    private var header: some View {
        OrbitPageHeader(
            title: AppLanguage.text("分支与标签", "Branches & Tags"),
            subtitle: AppLanguage.text("在不同工作线上切换，保持每个任务彼此独立。", "Keep parallel lines of work focused and independent."),
            systemName: "arrow.triangle.branch"
        ) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(AppLanguage.text("\(appState.branches.count) 个本地分支", "\(appState.branches.count) local branches"))
                    .orbitFont(.caption, weight: .semibold)
                Text(AppLanguage.text("\(appState.remoteBranches.count) 个远程分支", "\(appState.remoteBranches.count) remote branches"))
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
        } accessory: {
            VStack(alignment: .leading, spacing: 10) {
                OrbitSearchField(
                    prompt: AppLanguage.text("筛选分支…", "Filter branches…"),
                    text: $query
                )

                HStack(spacing: 8) {
                    WorkspaceActionButton(title: AppLanguage.text("新建分支", "New Branch"), systemName: "plus") {
                        isCreatingBranch = true
                    }
                    .disabled(appState.repository == nil || appState.isPerformingGitAction)

                    Button {
                        showsBranchTools = true
                    } label: {
                        Label(AppLanguage.text("比较与清理", "Compare & Clean"), systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.branches.count < 2)

                    Menu {
                        ForEach(appState.branches.filter { !$0.isCurrent }) { branch in
                            Button(AppLanguage.text("基于 \(branch.name)", "Onto \(branch.name)")) {
                                Task { await appState.prepareInteractiveRebase(base: branch.name) }
                            }
                        }
                    } label: {
                        Label(AppLanguage.text("整理提交", "Rebase"), systemImage: "arrow.triangle.swap")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(appState.branches.count < 2 || appState.isPerformingGitAction)

                    Spacer()
                    WorkspaceActionButton(title: AppLanguage.text("Fetch 并清理", "Fetch & Prune"), systemName: "arrow.down.circle", tint: OrbitDesign.secondaryText) {
                        Task { await appState.fetchPrune() }
                    }
                    .disabled(appState.repository == nil || appState.isPerformingGitAction)
                }
            }
        }
    }

    private var rebasePlannerBinding: Binding<Bool> {
        Binding(
            get: { appState.workflows.rebasePlannerPresented },
            set: { appState.workflows.rebasePlannerPresented = $0 }
        )
    }

    private var localBranchGroup: some View {
        branchGroup(title: "本地分支", count: visibleBranches.count) {
            ForEach(Array(visibleBranches.enumerated()), id: \.element.id) { index, branch in
                branchRow(branch)
                if index < visibleBranches.count - 1 {
                    Divider().padding(.leading, 58).overlay(OrbitDesign.separator)
                }
            }
        }
    }

    private var remoteBranchGroup: some View {
        branchGroup(title: "远程分支", count: appState.remoteBranches.count) {
            ForEach(Array(appState.remoteBranches.enumerated()), id: \.element.id) { index, branch in
                remoteBranchRow(branch)
                if index < appState.remoteBranches.count - 1 {
                    Divider().padding(.leading, 58).overlay(OrbitDesign.separator)
                }
            }
        }
    }

    private func branchGroup<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OrbitDesign.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OrbitDesign.elevatedSurface)

            Divider().overlay(OrbitDesign.separator)
            content()
        }
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(OrbitDesign.separator, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func branchRow(_ branch: GitBranchSummary) -> some View {
        HStack(spacing: 4) {
            Button {
                guard !branch.isCurrent else { return }
                Task { await appState.checkout(branch) }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(branch.isCurrent ? OrbitDesign.accent : OrbitDesign.violet)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(branch.name)
                            .orbitFont(.callout, weight: branch.isCurrent ? .semibold : .medium)
                            .foregroundStyle(OrbitDesign.primaryText)
                            .lineLimit(1)
                        Text(
                            branch.isCurrent && branch.needsPublish
                                ? AppLanguage.text("尚未发布到远程", "Not published to remote")
                                : (branch.isCurrent
                                    ? AppLanguage.text("当前签出分支", "Current branch")
                                    : (branch.upstream ?? AppLanguage.text("本地分支", "Local branch")))
                        )
                            .orbitFont(.caption2)
                            .foregroundStyle(OrbitDesign.secondaryText)
                    }
                    Spacer()
                    if branch.needsPublish {
                        Text(AppLanguage.text("未发布", "Not published"))
                            .orbitFont(.caption2, weight: .semibold)
                            .foregroundStyle(OrbitDesign.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(OrbitDesign.blue.opacity(0.12), in: Capsule())
                    } else if branch.isCurrent {
                        Text(AppLanguage.text("已签出", "Checked out"))
                            .orbitFont(.caption2, weight: .semibold)
                            .foregroundStyle(OrbitDesign.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(OrbitDesign.accent.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .buttonStyle(OrbitInteractiveButtonStyle())
            .disabled(branch.isCurrent || appState.isPerformingGitAction)
            if branch.needsPublish {
                WorkspaceActionButton(
                    title: AppLanguage.text("发布", "Publish"),
                    systemName: "arrow.up.right",
                    tint: OrbitDesign.blue
                ) {
                    Task { await appState.publishCurrentBranch() }
                }
                .fixedSize()
                .disabled(appState.isPerformingGitAction)
            }
            BranchActionMenu(branch: branch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(branch.isCurrent ? OrbitDesign.selectionFill : OrbitDesign.surface)
        .overlay(alignment: .leading) {
            if branch.isCurrent {
                Capsule()
                    .fill(OrbitDesign.accent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }

    private func remoteBranchRow(_ branch: GitRemoteBranchSummary) -> some View {
        Button {
            Task { await appState.checkoutRemote(branch) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "cloud")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrbitDesign.blue)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(branch.remote)/\(branch.name)")
                        .orbitFont(.callout, weight: .medium)
                    Text(branch.trackingBranch ?? "点击检出为本地分支")
                        .orbitFont(.caption2)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.down.to.line")
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.blue)
            }
            .foregroundStyle(OrbitDesign.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
        }
        .buttonStyle(OrbitInteractiveButtonStyle())
        .disabled(appState.isPerformingGitAction)
        .help("检出为本地分支")
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            OrbitIconBadge(systemName: "arrow.triangle.branch", color: OrbitDesign.violet, size: 56)
            Text("先打开一个 Git 仓库").orbitFont(.title3, weight: .bold)
            Text("打开仓库后，GitIgnore 会读取本地分支。")
                .orbitFont(.subheadline)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noBranches: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(OrbitDesign.secondaryText)
            Text("没有匹配的分支").orbitFont(.headline)
            Text("可以点击右上角新建一个本地分支。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CreateBranchSheet: View {
    @Binding var name: String
    let create: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                OrbitIconBadge(systemName: "arrow.triangle.branch", color: OrbitDesign.violet, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("新建分支").orbitFont(.headline)
                    Text("从当前提交创建并立即切换").orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
                }
            }
            TextField("例如：feature/command-palette", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("创建分支", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 410)
    }
}
