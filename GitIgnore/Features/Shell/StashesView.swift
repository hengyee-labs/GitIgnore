import SwiftUI

struct StashesView: View {
    @Environment(AppState.self) private var appState
    @State private var isCreating = false
    @State private var selectedStash: GitStashSummary?
    @State private var selectedFilePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            if !conflictedFiles.isEmpty { conflictBanner }
            if appState.stashes.isEmpty {
                emptyStashState
            } else {
                HSplitView {
                    stashList
                        .frame(minWidth: 270, idealWidth: 320, maxWidth: 380, maxHeight: .infinity, alignment: .topLeading)
                    preview
                        .frame(minWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(OrbitDesign.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Stash 临时保存")
        .orbitPageReveal()
        .sheet(isPresented: $isCreating) {
            StashCreateSheet().environment(appState)
        }
        .onChange(of: appState.stashes.map(\.id)) { _, ids in
            if let selectedStash, !ids.contains(selectedStash.id) {
                self.selectedStash = nil
                appState.workflows.stashPreview = nil
                appState.workflows.stashFileDiff = nil
                selectedFilePath = nil
            }
        }
        .task(id: appState.stashes.map(\.id)) {
            guard selectedStash == nil, let first = appState.stashes.first else { return }
            await select(first)
        }
    }

    private var pageHeader: some View {
        OrbitPageHeader(
            title: AppLanguage.text("Stash 临时保存", "Stash"),
            subtitle: AppLanguage.text("先预览文件和 Diff，再恢复、Pop 或删除。", "Preview files and Diffs before restoring, popping, or deleting."),
            systemName: "archivebox"
        ) {
            HStack(spacing: 8) {
                if !appState.stashes.isEmpty {
                    Text(AppLanguage.text("\(appState.stashes.count) 条保存", "\(appState.stashes.count) stashes"))
                        .orbitFont(.caption, weight: .semibold)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(OrbitDesign.recessedSurface, in: Capsule())
                }
                Button { isCreating = true } label: {
                    Label(AppLanguage.text("创建 Stash", "Create Stash"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.repository == nil || appState.isPerformingGitAction)
            }
        }
    }

    private var emptyStashState: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 15) {
                    OrbitIconBadge(systemName: "archivebox", color: OrbitDesign.violet, size: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有临时保存")
                            .orbitFont(.title3, weight: .bold)
                        Text("把当前工作先收好，稍后可以从这里预览、恢复或删除。")
                            .orbitFont(.subheadline)
                            .foregroundStyle(OrbitDesign.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }

                Divider().overlay(OrbitDesign.separator)

                HStack(spacing: 0) {
                    stashTip(systemName: "square.stack.3d.up", title: "保存工作区", message: "整组修改一起收好")
                    Divider().frame(height: 42).overlay(OrbitDesign.separator)
                    stashTip(systemName: "doc.text.magnifyingglass", title: "先看 Diff", message: "恢复前确认影响")
                    Divider().frame(height: 42).overlay(OrbitDesign.separator)
                    stashTip(systemName: "arrow.uturn.backward", title: "安全恢复", message: "需要时再回到工作区")
                }

                HStack {
                    Text("不会自动改变当前分支或提交历史")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                    Spacer()
                    Button("创建第一条 Stash") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(appState.repository == nil || appState.isPerformingGitAction)
                }
            }
            .padding(24)
            .frame(maxWidth: 700)
            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(OrbitDesign.separator, lineWidth: 1) }

            if appState.repository == nil {
                Label("打开一个 Git 仓库后即可开始保存工作。", systemImage: "folder")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func stashTip(systemName: String, title: String, message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OrbitDesign.violet)
                .frame(width: 28, height: 28)
                .background(OrbitDesign.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).orbitFont(.caption, weight: .semibold)
                Text(message).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var stashList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(appState.stashes) { stash in
                    stashRow(stash)
                }
            }
            .padding(12)
        }
        .background(OrbitDesign.canvas)
    }

    private func stashRow(_ stash: GitStashSummary) -> some View {
        let selected = selectedStash?.id == stash.id
        return Button {
            Task { await select(stash) }
        } label: {
            HStack(spacing: 11) {
                OrbitIconBadge(systemName: "archivebox", color: selected ? OrbitDesign.violet : OrbitDesign.blue, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stash.message).orbitFont(.subheadline, weight: .semibold).lineLimit(1)
                    Text("\(stash.reference) · \(stash.branch) · \(stash.dateText)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .orbitFont(.caption2, weight: .bold)
                    .foregroundStyle(selected ? OrbitDesign.violet : OrbitDesign.secondaryText)
            }
            .padding(10)
            .background(selected ? OrbitDesign.violet.opacity(0.10) : OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? OrbitDesign.violet.opacity(0.36) : OrbitDesign.separator, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        if let selectedStash {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedStash.reference).font(.headline.monospaced())
                        Text(selectedStash.message).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
                    }
                    Spacer()
                    Button("恢复") { Task { await appState.applyStash(selectedStash) } }
                    Button("Pop") { Task { await appState.popStash(selectedStash) } }
                        .buttonStyle(.borderedProminent)
                    Menu {
                        Button("删除 Stash", role: .destructive) { Task { await appState.dropStash(selectedStash) } }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(12)
                .background(OrbitDesign.surface)
                Divider().overlay(OrbitDesign.separator)

                if appState.workflows.isLoadingPreview {
                    ProgressView("正在按需读取 Stash…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let stashPreview = appState.workflows.stashPreview,
                          stashPreview.reference == selectedStash.reference {
                    HSplitView {
                        stashFileList(stashPreview, stash: selectedStash)
                            .frame(minWidth: 220, idealWidth: 270, maxWidth: 340)
                        stashFilePreview
                            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("选择一条 Stash 查看文件与 Diff。")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            ContentUnavailableView("选择一条 Stash", systemImage: "archivebox", description: Text("预览内容后再决定如何恢复。"))
        }
    }

    private func stashFileList(_ preview: GitStashPreview, stash: GitStashSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(preview.files.count) 个文件", systemImage: "doc.on.doc")
                    .orbitFont(.caption, weight: .bold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(OrbitDesign.surface)
            Divider().overlay(OrbitDesign.separator)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(preview.files) { file in
                        let selected = selectedFilePath == file.path
                        Button {
                            selectedFilePath = file.path
                            Task { await appState.loadStashFileDiff(file, in: stash) }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(selected ? OrbitDesign.accent : OrbitDesign.secondaryText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((file.path as NSString).lastPathComponent)
                                        .orbitFont(.caption, weight: .semibold)
                                        .lineLimit(1)
                                    Text((file.path as NSString).deletingLastPathComponent)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(OrbitDesign.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 4)
                                Text(file.kind.title)
                                    .orbitFont(.caption2, weight: .semibold)
                                    .foregroundStyle(selected ? OrbitDesign.accent : OrbitDesign.secondaryText)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 42)
                            .contentShape(Rectangle())
                            .background(selected ? OrbitDesign.selectionFill : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
            }
        }
        .background(OrbitDesign.canvas)
    }

    @ViewBuilder
    private var stashFilePreview: some View {
        if appState.workflows.isLoadingStashFileDiff {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在读取所选文件…").orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff = appState.workflows.stashFileDiff {
            OrbitDiffViewer(diff: diff, title: "Stash 文件变更", expandsVertically: true)
                .padding(10)
        } else {
            OrbitEmptyState(
                title: "选择一个文件",
                message: "只会按需读取当前文件的 Diff，不会一次加载整条 Stash。",
                systemName: "doc.text.magnifyingglass",
                tint: OrbitDesign.violet
            )
        }
    }

    @MainActor
    private func select(_ stash: GitStashSummary) async {
        selectedStash = stash
        selectedFilePath = nil
        await appState.loadStashPreview(stash)
        guard selectedStash?.id == stash.id,
              let preview = appState.workflows.stashPreview,
              let first = preview.files.first else { return }
        selectedFilePath = first.path
        await appState.loadStashFileDiff(first, in: stash)
    }

    private var conflictedFiles: [GitFileStatus] { appState.status.files.filter(\.hasConflict) }

    private var conflictBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(OrbitDesign.coral)
            Text("恢复 Stash 后发现 \(conflictedFiles.count) 个冲突文件").orbitFont(.caption, weight: .bold)
            Spacer()
            Button("前往冲突中心") { appState.selectSection(.changes) }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 16).frame(height: 42)
        .background(OrbitDesign.coral.opacity(0.10))
    }
}

private struct StashCreateSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var selectedPaths: Set<String> = []
    @State private var partial = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("创建 Stash 临时保存").orbitFont(.title3, weight: .bold)
            TextField("可选描述", text: $message).textFieldStyle(.roundedBorder)
            Toggle("只保存所选文件", isOn: $partial).toggleStyle(.switch)
            if partial {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(appState.status.files) { file in
                            Toggle(isOn: Binding(
                                get: { selectedPaths.contains(file.path) },
                                set: { enabled in
                                    if enabled { selectedPaths.insert(file.path) }
                                    else { selectedPaths.remove(file.path) }
                                }
                            )) {
                                Text(file.path).font(.caption.monospaced()).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                            .padding(7)
                        }
                    }
                }
                .frame(height: 220)
                .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let text = message.isEmpty ? nil : message
                    dismiss()
                    Task {
                        if partial { await appState.createPartialStash(message: text, paths: Array(selectedPaths)) }
                        else { await appState.stash(message: text) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(partial && selectedPaths.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
