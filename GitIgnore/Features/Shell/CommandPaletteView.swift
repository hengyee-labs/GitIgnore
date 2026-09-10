import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private struct CommandItem: Identifiable {
        let id: String
        let title: String
        let shortcut: String
        let symbol: String
        let action: (AppState) -> Void
    }

    private var commands: [CommandItem] {
        [
            CommandItem(id: "overview", title: "打开仓库概览", shortcut: "⌘1", symbol: "square.grid.2x2") { $0.selectSection(.overview) },
            CommandItem(id: "changes", title: "查看工作区变更", shortcut: "⌘2", symbol: "list.bullet.rectangle") { $0.selectSection(.changes) },
            CommandItem(id: "history", title: "查看提交历史", shortcut: "⌘3", symbol: "clock.arrow.circlepath") { $0.selectSection(.history) },
            CommandItem(id: "branches", title: "管理分支", shortcut: "⌘4", symbol: "arrow.triangle.branch") { $0.selectSection(.branches) },
            CommandItem(id: "stashes", title: "查看 Stash 临时保存", shortcut: "", symbol: "archivebox") { $0.selectSection(.stashes) },
            CommandItem(id: "worktrees", title: "查看并行工作区", shortcut: "", symbol: "point.3.connected.trianglepath.dotted") { $0.selectSection(.worktrees) },
            CommandItem(id: "refresh", title: "刷新仓库", shortcut: "⌘R", symbol: "arrow.clockwise") { state in Task { await state.refreshRepository() }; state.isCommandPalettePresented = false },
            CommandItem(id: "fetch", title: "Fetch 远程更新", shortcut: "", symbol: "arrow.down.circle") { state in Task { await state.fetch() }; state.isCommandPalettePresented = false },
            CommandItem(id: "pull", title: "Pull 远程提交", shortcut: "", symbol: "arrow.down.to.line") { state in Task { await state.pull() }; state.isCommandPalettePresented = false },
            CommandItem(id: "push", title: "Push 本地提交", shortcut: "", symbol: "arrow.up.to.line") { state in Task { await state.push() }; state.isCommandPalettePresented = false },
            CommandItem(id: "terminal", title: "在终端中打开", shortcut: "⌥T", symbol: "terminal") { $0.openTerminal(); $0.isCommandPalettePresented = false }
        ]
    }

    private var filteredCommands: [CommandItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(OrbitDesign.secondaryText)
                TextField("输入命令…", text: $query)
                    .textFieldStyle(.plain)
                    .orbitFont(.title3)
                    .focused($searchFocused)
                    .onSubmit { filteredCommands.first?.action(appState) }
                Text("ESC").font(.caption2.monospaced()).foregroundStyle(OrbitDesign.secondaryText)
            }
            .padding(16)
            .background(OrbitDesign.surface)

            Divider()
            if filteredCommands.isEmpty {
                ContentUnavailableView("没有匹配命令", systemImage: "command", description: Text("试试“刷新”“终端”或“分支”。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredCommands) { item in
                            Button {
                                item.action(appState)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.symbol).frame(width: 20)
                                    Text(item.title)
                                    Spacer()
                                    if !item.shortcut.isEmpty { Text(item.shortcut).font(.caption.monospaced()).foregroundStyle(OrbitDesign.secondaryText) }
                                }
                                .foregroundStyle(OrbitDesign.primaryText)
                                .padding(.horizontal, 14).frame(height: 38)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 320)
            }
        }
        .background(OrbitDesign.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(width: 520)
        .task { searchFocused = true }
        .onExitCommand { appState.isCommandPalettePresented = false }
    }
}
