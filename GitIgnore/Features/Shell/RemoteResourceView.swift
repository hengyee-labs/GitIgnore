import AppKit
import SwiftUI

struct RemoteResourceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let section: SidebarSection

    @State private var items: [RemoteCollaborationItem] = []
    @State private var selectedItemID: String?
    @State private var query = ""
    @State private var filter: RemoteResourceFilter = .open
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var kind: RemoteResourceKind { section == .pullRequests ? .review : .issue }
    private var isEnglish: Bool { AppLanguage.isEnglish }
    private var resourceTitle: String { kind == .review ? text("代码评审", "Code Review") : text("问题跟踪", "Issues") }
    private var resolvedProvider: RemoteHostingProvider? {
        guard let remote = appState.remoteInfo else { return nil }
        return RemoteHostingProvider.resolved(for: remote)
    }
    private var loadKey: String {
        "\(kind.rawValue)|\(appState.repository?.path ?? "")|\(appState.remoteInfo?.url ?? "")"
    }

    private var visibleItems: [RemoteCollaborationItem] {
        items.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .open: matchesFilter = item.state == .open
            case .closed: matchesFilter = item.state == .closed
            case .merged: matchesFilter = item.state == .merged
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(query)
                || item.author.localizedCaseInsensitiveContains(query)
                || String(item.number).contains(query)
                || item.labels.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectedItem: RemoteCollaborationItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(OrbitDesign.canvas)
        .navigationTitle(resourceTitle)
        .task(id: loadKey) {
            guard appState.remoteInfo != nil else {
                items = []
                selectedItemID = nil
                errorMessage = nil
                return
            }
            await load(forceRefresh: false)
        }
        .onChange(of: visibleItems.map(\.id)) { _, ids in
            if let selectedItemID, ids.contains(selectedItemID) { return }
            self.selectedItemID = ids.first
        }
        .orbitPageReveal()
    }

    private var header: some View {
        OrbitPageHeader(
            title: resourceTitle,
            subtitle: remoteDescription,
            systemName: section.symbol,
            tint: kind == .review ? OrbitDesign.blue : OrbitDesign.coral
        ) {
            HStack(spacing: 8) {
                if !items.isEmpty {
                    Text(text("共 \(items.count) 项", "\(items.count) items"))
                        .orbitFont(.caption, weight: .medium)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(OrbitDesign.recessedSurface, in: Capsule())
                }

                Button {
                    Task { await load(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading || appState.remoteInfo == nil)
                .help(text("刷新远程数据", "Refresh remote data"))

                Button {
                    openRemoteCollection()
                } label: {
                    Label(text("浏览器打开", "Open in Browser"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.remoteInfo?.webURL == nil || resolvedProvider == nil)
                .help(resolvedProvider == nil
                      ? text("请先在设置中指定远程平台类型", "Choose the remote platform type in Settings first")
                      : text("在远程平台创建新内容", "Create on the remote platform"))

                Button {
                    openNewItem()
                } label: {
                    Label(kind == .review ? text("新建评审", "New Review") : text("新建问题", "New Issue"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.remoteInfo?.webURL == nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.remoteInfo == nil {
            stateView(
                symbol: "network.slash",
                title: text("尚未识别远程仓库", "No Remote Repository"),
                message: text("为当前仓库配置 origin 后，即可在 GitIgnore 中查看真实的远程数据。", "Configure an origin remote to view live collaboration data in GitIgnore."),
                showsSettings: false
            )
        } else if resolvedProvider == nil {
            stateView(
                symbol: "questionmark.app.dashed",
                title: text("尚未识别远程平台", "Remote Platform Not Identified"),
                message: text(
                    "此远程地址可能来自私有部署。请前往“设置 > 远程与通知”，指定 GitHub、GitLab 或 Gitee 后再读取数据。",
                    "This may be a self-hosted remote. Open Settings > Remote & Notifications and choose GitHub, GitLab, or Gitee before loading data."
                ),
                showsSettings: true
            )
        } else if isLoading && items.isEmpty {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(text("正在读取远程数据…", "Loading remote data…"))
                    .orbitFont(.subheadline)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, items.isEmpty {
            stateView(
                symbol: "exclamationmark.triangle",
                title: text("暂时无法读取", "Unable to Load"),
                message: errorMessage,
                showsSettings: true
            )
        } else {
            HSplitView {
                listPane
                    .frame(minWidth: 330, idealWidth: 390, maxWidth: 500)
                detailPane
                    .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(OrbitDesign.tertiaryText)
                    TextField(text("搜索标题、作者、编号或标签", "Search title, author, number or label"), text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(OrbitDesign.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }

                Picker(text("状态", "State"), selection: $filter) {
                    ForEach(availableFilters) { value in
                        Text(value.title(kind: kind, isEnglish: isEnglish)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
            .background(OrbitDesign.surface)

            if visibleItems.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: query.isEmpty ? "checkmark.circle" : "magnifyingglass")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(OrbitDesign.tertiaryText)
                    Text(query.isEmpty ? text("这个状态下暂无内容", "Nothing in this state") : text("没有匹配的结果", "No matching results"))
                        .orbitFont(.subheadline, weight: .medium)
                    Text(query.isEmpty ? text("切换状态或刷新远程数据后再查看。", "Choose another state or refresh remote data.") : text("尝试缩短关键词或清除搜索条件。", "Try a shorter keyword or clear the search."))
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleItems, selection: $selectedItemID) { item in
                    RemoteResourceRow(item: item, isEnglish: isEnglish)
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(OrbitDesign.surface)
            }

            if let errorMessage, !items.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.amber)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OrbitDesign.amber.opacity(0.08))
            }
        }
        .background(OrbitDesign.surface)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let item = selectedItem {
            RemoteResourceDetail(item: item, isEnglish: isEnglish)
                .id(item.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 8)))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.and.hand.point.up.left")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(OrbitDesign.tertiaryText)
                Text(text("选择一项查看详情", "Select an item to inspect"))
                    .orbitFont(.subheadline, weight: .medium)
                Text(text("标题、状态、分支、标签和描述会显示在这里。", "Title, state, branches, labels and description appear here."))
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OrbitDesign.canvas)
        }
    }

    private func stateView(symbol: String, title: String, message: String, showsSettings: Bool) -> some View {
        VStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(OrbitDesign.tertiaryText)
            Text(title).orbitFont(.title3, weight: .semibold)
            Text(message)
                .orbitFont(.subheadline)
                .foregroundStyle(OrbitDesign.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
            HStack(spacing: 9) {
                Button(text("重新读取", "Retry")) {
                    Task { await load(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
                if showsSettings {
                    SettingsLink {
                        Text(text("配置远程访问", "Configure Remote Access"))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var availableFilters: [RemoteResourceFilter] {
        kind == .review ? [.open, .merged, .closed, .all] : [.open, .closed, .all]
    }

    private var remoteDescription: String {
        guard let remote = appState.remoteInfo else {
            return text("等待连接 origin", "Waiting for origin")
        }
        let host = remote.webURL?.host ?? remote.provider
        return "\(remote.provider) · \(host)"
    }

    @MainActor
    private func load(forceRefresh: Bool) async {
        guard let remote = appState.remoteInfo else { return }
        guard RemoteHostingProvider.resolved(for: remote) != nil else {
            items = []
            selectedItemID = nil
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await RemoteCollaborationService.shared.items(
                kind: kind,
                remote: remote,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            items = loaded
            if selectedItemID == nil || !loaded.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = loaded.first(where: { $0.state == .open })?.id ?? loaded.first?.id
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func openRemoteCollection() {
        appState.openRemote(path: collectionPath)
    }

    private func openNewItem() {
        appState.openRemote(path: newItemPath)
    }

    private var collectionPath: String {
        switch (appState.remoteInfo?.provider ?? "", kind) {
        case ("GitLab", .review): "-/merge_requests"
        case ("GitLab", .issue): "-/issues"
        case (_, .review): "pulls"
        case (_, .issue): "issues"
        }
    }

    private var newItemPath: String {
        switch (appState.remoteInfo?.provider ?? "", kind) {
        case ("GitLab", .review): "-/merge_requests/new"
        case ("GitLab", .issue): "-/issues/new"
        case (_, .review): "compare"
        case (_, .issue): "issues/new"
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

private enum RemoteResourceFilter: String, CaseIterable, Identifiable {
    case open
    case merged
    case closed
    case all

    var id: Self { self }

    func title(kind: RemoteResourceKind, isEnglish: Bool) -> String {
        switch self {
        case .open: isEnglish ? "Open" : "进行中"
        case .merged: isEnglish ? "Merged" : "已合并"
        case .closed: isEnglish ? "Closed" : "已关闭"
        case .all: isEnglish ? "All" : "全部"
        }
    }
}

private struct RemoteResourceRow: View {
    let item: RemoteCollaborationItem
    let isEnglish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: stateSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(stateColor)
                Text(item.isDraft ? (isEnglish ? "Draft · \(item.title)" : "草稿 · \(item.title)") : item.title)
                    .orbitFont(.subheadline, weight: .semibold)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text("#\(item.number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OrbitDesign.tertiaryText)
            }

            HStack(spacing: 7) {
                Text(item.author)
                    .lineLimit(1)
                if let updatedAt = item.updatedAt {
                    Text("·")
                    Text(updatedAt, style: .relative)
                }
                if item.commentCount > 0 {
                    Spacer(minLength: 3)
                    Label("\(item.commentCount)", systemImage: "bubble.left")
                }
            }
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)

            if !item.labels.isEmpty {
                HStack(spacing: 5) {
                    ForEach(item.labels.prefix(3), id: \.self) { label in
                        Text(label)
                            .orbitFont(.caption2, weight: .medium)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OrbitDesign.recessedSurface, in: Capsule())
                    }
                    if item.labels.count > 3 {
                        Text("+\(item.labels.count - 3)")
                            .orbitFont(.caption2)
                            .foregroundStyle(OrbitDesign.tertiaryText)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var stateColor: Color {
        switch item.state {
        case .open: OrbitDesign.accent
        case .merged: OrbitDesign.violet
        case .closed: OrbitDesign.coral
        }
    }

    private var stateSymbol: String {
        switch item.state {
        case .open: item.kind == .review ? "arrow.triangle.pull" : "exclamationmark.circle"
        case .merged: "arrow.triangle.merge"
        case .closed: "checkmark.circle"
        }
    }
}
