import SwiftUI

struct RebasePlannerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [RebaseTodoItem] = []
    @State private var confirmsRun = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitDesign.separator)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach($items) { $item in
                        itemRow($item)
                            .draggable(item.id)
                            .dropDestination(for: String.self) { values, _ in
                                guard let sourceID = values.first,
                                      let source = items.firstIndex(where: { $0.id == sourceID }),
                                      let target = items.firstIndex(where: { $0.id == item.id }),
                                      source != target else { return false }
                                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18)) {
                                    let moved = items.remove(at: source)
                                    items.insert(moved, at: target)
                                }
                                return true
                            }
                    }
                }
                .padding(14)
            }
            Divider().overlay(OrbitDesign.separator)
            footer
        }
        .frame(minWidth: 700, minHeight: 560)
        .background(OrbitDesign.canvas)
        .onAppear { items = appState.workflows.rebaseItems }
        .alert("执行交互式 Rebase？", isPresented: $confirmsRun) {
            Button("取消", role: .cancel) {}
            Button("执行 Rebase") {
                appState.workflows.rebaseItems = items
                Task {
                    if await appState.runInteractiveRebase() { dismiss() }
                }
            }
        } message: {
            Text("Rebase 会改写这些提交的历史。若出现冲突，将保留当前状态并引导到冲突中心。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            OrbitIconBadge(systemName: "arrow.triangle.swap", color: OrbitDesign.violet, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("交互式 Rebase").orbitFont(.title3, weight: .bold)
                Text("基于 \(appState.workflows.rebaseBase) · 从上到下按执行顺序排列")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer()
            Text("\(items.count) 个提交")
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.violet)
            Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private func itemRow(_ item: Binding<RebaseTodoItem>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(OrbitDesign.secondaryText)
                .frame(width: 18)
            Menu {
                ForEach(RebaseTodoAction.allCases) { action in
                    Button(action.title) { item.wrappedValue.action = action }
                }
            } label: {
                Text(item.wrappedValue.action.title)
                    .orbitFont(.caption, weight: .bold)
                    .foregroundStyle(actionColor(item.wrappedValue.action))
                    .frame(width: 86, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            Text(item.wrappedValue.shortHash)
                .font(.caption2.monospaced())
                .foregroundStyle(OrbitDesign.secondaryText)
                .frame(width: 58, alignment: .leading)
            if item.wrappedValue.action == .reword {
                TextField("新的提交说明", text: item.editedSubject)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(OrbitDesign.separator, lineWidth: 1) }
            } else {
                Text(item.wrappedValue.subject)
                    .orbitFont(.callout)
                    .foregroundStyle(item.wrappedValue.action == .drop ? OrbitDesign.secondaryText : OrbitDesign.primaryText)
                    .strikethrough(item.wrappedValue.action == .drop)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(OrbitDesign.separator, lineWidth: 1) }
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label("将改写所选提交的历史", systemImage: "exclamationmark.triangle")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.amber)
            Spacer()
            Button("取消") { dismiss() }
            Button("执行 Rebase") { confirmsRun = true }
                .buttonStyle(.borderedProminent)
                .tint(OrbitDesign.violet)
                .disabled(items.isEmpty || appState.isPerformingGitAction)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(OrbitDesign.sidebar)
    }

    private func actionColor(_ action: RebaseTodoAction) -> Color {
        switch action {
        case .pick: OrbitDesign.accent
        case .reword: OrbitDesign.blue
        case .squash, .fixup: OrbitDesign.violet
        case .drop: OrbitDesign.coral
        }
    }
}
