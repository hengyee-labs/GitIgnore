import SwiftUI

struct ChangesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPaths: Set<String> = []
    @State private var dropTarget: ChangeDropTarget?
    @State private var branchOperation: GitBranchOperation?
    @State private var operationPendingAbort: GitBranchOperation?
    @State private var query = ""
    @State private var filter = ChangeFilter.all
    @State private var grouping = ChangeGrouping.folder
    @State private var collapsedFolders: Set<String> = []
    @Namespace private var fileMovementNamespace

    private var stagedFiles: [GitFileStatus] {
        appState.status.files.filter(\.isStaged)
    }

    private var unstagedFiles: [GitFileStatus] {
        appState.status.files.filter(\.hasUnstagedChanges)
    }

    private var conflictedFiles: [GitFileStatus] {
        appState.status.files.filter(\.hasConflict)
    }

    private var visibleStagedFiles: [GitFileStatus] { filtered(stagedFiles) }
    private var visibleUnstagedFiles: [GitFileStatus] { filtered(unstagedFiles) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if appState.repository == nil {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let branchOperation {
                            branchOperationBanner(branchOperation)
                        }
                        if !conflictedFiles.isEmpty {
                            ConflictCenterView(files: conflictedFiles)
                        }
                        summaryCard
                        fileGroup(title: "已暂存的更改", files: visibleStagedFiles, stagedGroup: true)
                        fileGroup(title: "未暂存的更改", files: visibleUnstagedFiles, stagedGroup: false)
                    }
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)

                CommitComposerView(stagedCount: stagedFiles.count)
            }
        }
        .background(OrbitDesign.canvas)
        .navigationTitle("工作区变更")
        .orbitPageReveal()
        .onChange(of: Set(appState.status.files.map(\.path))) { _, availablePaths in
            selectedPaths.formIntersection(availablePaths)
        }
        .task(id: branchOperationRefreshKey) {
            let refreshKey = branchOperationRefreshKey
            let operation = await appState.currentBranchOperation()
            guard refreshKey == branchOperationRefreshKey else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18)) {
                branchOperation = operation
            }
        }
        .alert("中止 \(operationPendingAbort?.title ?? "分支操作")？", isPresented: Binding(
            get: { operationPendingAbort != nil },
            set: { if !$0 { operationPendingAbort = nil } }
        )) {
            Button("取消", role: .cancel) { operationPendingAbort = nil }
            Button("中止并恢复", role: .destructive) {
                guard let operation = operationPendingAbort else { return }
                operationPendingAbort = nil
                Task {
                    if await appState.abortBranchOperation(operation) {
                        branchOperation = await appState.currentBranchOperation()
                    }
                }
            }
        } message: {
            Text("当前冲突处理结果会被丢弃，分支恢复到 \(operationPendingAbort?.title ?? "操作") 开始前的状态。")
        }
        .sheet(isPresented: Binding(
            get: { appState.isCommitStudioPresented },
            set: { appState.isCommitStudioPresented = $0 }
        )) {
            CommitStudioView().environment(appState)
        }
    }

    private var branchOperationRefreshKey: String {
        let repositoryPath = appState.repository?.path ?? ""
        return repositoryPath + "#conflicts=" + (conflictedFiles.isEmpty ? "0" : "1")
    }

    private var header: some View {
        OrbitPageHeader(
            title: AppLanguage.text("工作区变更", "Changes"),
            subtitle: appState.repository?.path
                ?? AppLanguage.text("打开仓库后，这里会显示文件变更。", "Open a repository to inspect file changes."),
            systemName: "list.bullet.rectangle"
        ) {
            HStack(spacing: 8) {
                if appState.isPerformingGitAction || appState.isLoadingRepository {
                    ProgressView().controlSize(.small).tint(OrbitDesign.accent)
                }
                WorkspaceActionButton(title: AppLanguage.text("全部暂存", "Stage All"), systemName: "tray.and.arrow.down") {
                    Task { await appState.stageAll() }
                }
                .disabled(unstagedFiles.isEmpty || appState.isPerformingGitAction)
                WorkspaceActionButton(title: AppLanguage.text("提交编排", "Commit Studio"), systemName: "square.stack.3d.up", tint: OrbitDesign.accent) {
                    Task { await appState.openCommitStudio() }
                }
                .disabled(appState.status.changedFileCount == 0 || appState.isPerformingGitAction)
                WorkspaceActionButton(title: AppLanguage.text("创建 Stash", "Create Stash"), systemName: "archivebox", tint: OrbitDesign.secondaryText) {
                    Task { await appState.stash(message: "GitIgnore 临时保存") }
                }
                .disabled(appState.repository == nil || appState.isPerformingGitAction)
            }
        } accessory: {
            HStack(spacing: 8) {
                OrbitSearchField(
                    prompt: AppLanguage.text("搜索文件或路径…", "Search files or paths…"),
                    text: $query
                )
                .frame(minWidth: 220)
                .layoutPriority(0)

                Picker(AppLanguage.text("状态", "Status"), selection: $filter) {
                    ForEach(ChangeFilter.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

                Picker(AppLanguage.text("分组", "Grouping"), selection: $grouping) {
                    ForEach(ChangeGrouping.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 88)

                if !selectedPaths.isEmpty {
                    batchActionMenu
                }
            }
        }
    }

    private var batchActionMenu: some View {
        Menu {
            let selectedUnstaged = Set(unstagedFiles.map(\.path)).intersection(selectedPaths)
            let selectedStaged = Set(stagedFiles.map(\.path)).intersection(selectedPaths)
            Button("Stage 所选 \(selectedUnstaged.count)", systemImage: "tray.and.arrow.down") {
                transferSelected(paths: selectedUnstaged, stagedGroup: false)
            }
            .disabled(selectedUnstaged.isEmpty)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("取消 Stage 所选 \(selectedStaged.count)", systemImage: "tray.and.arrow.up") {
                transferSelected(paths: selectedStaged, stagedGroup: true)
            }
            .disabled(selectedStaged.isEmpty)
            .keyboardShortcut("u", modifiers: [.command, .shift])
        } label: {
            Label("已选 \(selectedPaths.count)", systemImage: "checkmark.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("⌘⇧S Stage，⌘⇧U 取消 Stage")
    }

    private var summaryCard: some View {
        OrbitCard(emphasis: true) {
            HStack(spacing: 14) {
                OrbitIconBadge(
                    systemName: appState.status.changedFileCount == 0 ? "checkmark.circle" : "arrow.triangle.branch",
                    color: appState.status.changedFileCount == 0 ? OrbitDesign.accent : OrbitDesign.amber,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.status.changedFileCount == 0 ? "工作区干净" : "\(appState.status.changedFileCount) 个文件有变更")
                        .orbitFont(.headline)
                    Text(appState.status.changedFileCount == 0
                         ? "没有需要暂存或提交的内容"
                         : "已暂存 \(stagedFiles.count) · 未暂存 \(unstagedFiles.count)")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                if !unstagedFiles.isEmpty {
                    Text("\(unstagedFiles.count) 待处理")
                        .orbitFont(.caption, weight: .semibold)
                        .foregroundStyle(OrbitDesign.amber)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(OrbitDesign.amber.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func branchOperationBanner(_ operation: GitBranchOperation) -> some View {
        HStack(spacing: 12) {
            OrbitIconBadge(
                systemName: operation == .merge ? "arrow.triangle.merge" : "arrow.triangle.swap",
                color: conflictedFiles.isEmpty ? OrbitDesign.accent : OrbitDesign.amber,
                size: 38
            )
            VStack(alignment: .leading, spacing: 3) {
                Text("正在进行 \(operation.title)")
                    .orbitFont(.callout, weight: .semibold)
                Text(conflictedFiles.isEmpty
                     ? "冲突已全部处理，可以继续完成这次分支操作。"
                     : "还有 \(conflictedFiles.count) 个冲突文件，处理并暂存后才能继续。")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer(minLength: 12)
            Button("中止…", role: .destructive) {
                operationPendingAbort = operation
            }
            .buttonStyle(.bordered)
            .disabled(appState.isPerformingGitAction)

            Button("继续 \(operation.title)") {
                Task {
                    if await appState.continueBranchOperation(operation) {
                        branchOperation = await appState.currentBranchOperation()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OrbitDesign.accent)
            .disabled(!conflictedFiles.isEmpty || appState.isPerformingGitAction)
        }
        .padding(13)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    (conflictedFiles.isEmpty ? OrbitDesign.accent : OrbitDesign.amber).opacity(0.4),
                    lineWidth: 1
                )
        }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func fileGroup(title: String, files: [GitFileStatus], stagedGroup: Bool) -> some View {
        let groupPaths = Set(files.map(\.path))
        let selectedInGroup = selectedPaths.intersection(groupPaths)
        let isDropTarget = dropTarget == (stagedGroup ? .staged : .unstaged)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .orbitFont(.caption2, weight: .bold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                Text("\(files.count)")
                    .orbitFont(.caption2, weight: .bold)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.16), value: files.count)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(OrbitDesign.surface, in: Capsule())
                Spacer()

                if !files.isEmpty {
                    Button(selectedInGroup.count == files.count ? "取消全选" : "全选") {
                        withAnimation(selectionAnimation) {
                            if selectedInGroup.count == files.count {
                                selectedPaths.subtract(groupPaths)
                            } else {
                                selectedPaths.formUnion(groupPaths)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .orbitFont(.caption2, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                }

                if !selectedInGroup.isEmpty {
                    Button {
                        transferSelected(paths: selectedInGroup, stagedGroup: stagedGroup)
                    } label: {
                        Label(
                            stagedGroup ? "移出暂存区 \(selectedInGroup.count)" : "暂存所选 \(selectedInGroup.count)",
                            systemImage: stagedGroup ? "arrow.down" : "arrow.up"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(stagedGroup ? OrbitDesign.secondaryText : OrbitDesign.accent)
                    .disabled(appState.isPerformingGitAction)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                }
            }

            LazyVStack(spacing: 1) {
                if files.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: isDropTarget ? "arrow.down.circle.fill" : "tray")
                            .foregroundStyle(isDropTarget ? OrbitDesign.accent : OrbitDesign.secondaryText)
                        Text(stagedGroup ? "暂存区为空，可将文件拖到这里" : "没有未暂存的文件")
                            .orbitFont(.caption)
                            .foregroundStyle(OrbitDesign.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                } else if grouping == .folder {
                    ForEach(folderGroups(files)) { group in
                        folderHeader(group.name, count: group.files.count)
                        if !collapsedFolders.contains(group.name) || !query.isEmpty {
                            fileRows(group.files, stagedGroup: stagedGroup)
                        }
                    }
                } else {
                    fileRows(files, stagedGroup: stagedGroup)
                }
            }
            .animation(moveAnimation, value: files.map { $0.id + $0.statusCode })
            .padding(4)
            .background(
                isDropTarget ? OrbitDesign.accent.opacity(0.10) : OrbitDesign.surface,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTarget ? OrbitDesign.accent : OrbitDesign.separator, lineWidth: isDropTarget ? 1.5 : 1)
            }
            .scaleEffect(isDropTarget && !reduceMotion ? 1.006 : 1)
            .dropDestination(for: String.self) { paths, _ in
                handleDrop(paths: paths, intoStagedGroup: stagedGroup)
                return true
            } isTargeted: { targeted in
                withAnimation(selectionAnimation) {
                    if targeted {
                        dropTarget = stagedGroup ? .staged : .unstaged
                    } else if dropTarget == (stagedGroup ? .staged : .unstaged) {
                        dropTarget = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fileRows(_ files: [GitFileStatus], stagedGroup: Bool) -> some View {
        ForEach(files) { file in
            ChangeFileRow(
                file: file,
                stagedGroup: stagedGroup,
                isBatchSelected: selectedPaths.contains(file.path),
                isCurrentFile: appState.selectedFile?.path == file.path,
                isInteractionDisabled: appState.isPerformingGitAction,
                selectedFileCount: selectedPaths.count,
                onToggleSelection: { toggleSelection(for: file.path) },
                onOpen: { Task { await appState.selectFile(file, staged: stagedGroup) } },
                onTransfer: {
                    Task {
                        if stagedGroup { await appState.unstage(file) }
                        else { await appState.stage(file) }
                    }
                }
            )
            .equatable()
            .matchedGeometryEffect(
                id: movementID(for: file, stagedGroup: stagedGroup),
                in: fileMovementNamespace
            )
        }
    }

    private func folderHeader(_ folder: String, count: Int) -> some View {
        let collapsed = collapsedFolders.contains(folder) && query.isEmpty
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.16)) {
                if collapsedFolders.contains(folder) { collapsedFolders.remove(folder) }
                else { collapsedFolders.insert(folder) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
                Image(systemName: "folder")
                    .foregroundStyle(OrbitDesign.secondaryText)
                Text(folder).orbitFont(.caption, weight: .semibold)
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(OrbitDesign.tertiaryText)
                Spacer()
            }
            .foregroundStyle(OrbitDesign.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(collapsed ? "已收起" : "已展开")
    }

    private func filtered(_ files: [GitFileStatus]) -> [GitFileStatus] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { file in
            let matchesQuery = normalized.isEmpty || file.path.localizedCaseInsensitiveContains(normalized)
            return matchesQuery && filter.matches(file)
        }
    }

    private func folderGroups(_ files: [GitFileStatus]) -> [ChangeFolderGroup] {
        let groups = Dictionary(grouping: files) { file -> String in
            let first = file.path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            return file.path.contains("/") && !first.isEmpty ? first : AppLanguage.text("项目根目录", "Project Root")
        }
        return groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ChangeFolderGroup(name: $0, files: groups[$0, default: []]) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            OrbitIconBadge(systemName: "folder.badge.questionmark", color: OrbitDesign.violet, size: 56)
            Text("先打开一个 Git 仓库").orbitFont(.title3, weight: .bold)
            Text("选择仓库后，GitIgnore 会在这里显示文件变更并支持暂存和提交。")
                .orbitFont(.subheadline)
                .foregroundStyle(OrbitDesign.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.86)
    }

    private var moveAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private func toggleSelection(for path: String) {
        withAnimation(selectionAnimation) {
            if selectedPaths.contains(path) {
                selectedPaths.remove(path)
            } else {
                selectedPaths.insert(path)
            }
        }
    }

    private func transferSelected(paths: Set<String>, stagedGroup: Bool) {
        let files = appState.status.files.filter { paths.contains($0.path) }
        Task {
            if stagedGroup {
                await appState.unstage(files)
            } else {
                await appState.stage(files)
            }
        }
    }

    private func handleDrop(paths: [String], intoStagedGroup: Bool) {
        let incomingPaths = Set(paths)
        let transferPaths = incomingPaths.contains(where: selectedPaths.contains)
            ? incomingPaths.union(selectedPaths)
            : incomingPaths
        let files = appState.status.files.filter { file in
            guard transferPaths.contains(file.path) else { return false }
            return intoStagedGroup ? file.hasUnstagedChanges : file.isStaged
        }
        guard !files.isEmpty else { return }

        withAnimation(moveAnimation) { dropTarget = nil }
        Task {
            if intoStagedGroup {
                await appState.stage(files)
            } else {
                await appState.unstage(files)
            }
        }
    }

    private func movementID(for file: GitFileStatus, stagedGroup: Bool) -> String {
        if file.isStaged && file.hasUnstagedChanges {
            return file.path + (stagedGroup ? "#staged" : "#unstaged")
        }
        return file.path
    }

}

private enum ChangeDropTarget {
    case staged
    case unstaged
}

private struct ChangeFolderGroup: Identifiable {
    let name: String
    let files: [GitFileStatus]
    var id: String { name }
}

private enum ChangeGrouping: String, CaseIterable, Identifiable {
    case folder
    case flat
    var id: Self { self }
    var title: String { self == .folder ? AppLanguage.text("目录", "Folders") : AppLanguage.text("列表", "List") }
    var symbol: String { self == .folder ? "folder" : "list.bullet" }
}

private enum ChangeFilter: String, CaseIterable, Identifiable {
    case all
    case modified
    case added
    case deleted
    case conflicted

    var id: Self { self }
    var title: String {
        switch self {
        case .all: AppLanguage.text("全部状态", "All Statuses")
        case .modified: AppLanguage.text("已修改", "Modified")
        case .added: AppLanguage.text("新增", "Added")
        case .deleted: AppLanguage.text("已删除", "Deleted")
        case .conflicted: AppLanguage.text("冲突", "Conflicts")
        }
    }
    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .modified: "pencil"
        case .added: "plus"
        case .deleted: "minus"
        case .conflicted: "exclamationmark.triangle"
        }
    }
    func matches(_ file: GitFileStatus) -> Bool {
        switch self {
        case .all: true
        case .modified: file.kind == .modified || file.kind == .renamed
        case .added: file.kind == .added || file.kind == .untracked
        case .deleted: file.kind == .deleted
        case .conflicted: file.hasConflict
        }
    }
}
