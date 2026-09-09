import SwiftUI

struct DiffFileHistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let path: String
    let showsBlame: Bool
    @State private var history: [GitCommitSummary] = []
    @State private var blameText = ""
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                OrbitIconBadge(systemName: showsBlame ? "person.text.rectangle" : "clock.arrow.circlepath", color: OrbitDesign.violet, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(showsBlame ? "行级 Blame" : "文件历史").orbitFont(.title3, weight: .semibold)
                    Text(path).font(.caption.monospaced()).foregroundStyle(OrbitDesign.secondaryText).lineLimit(1)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider().overlay(OrbitDesign.separator)
            if loading {
                ProgressView("正在读取…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showsBlame {
                ScrollView([.vertical, .horizontal]) {
                    Text(blameText.isEmpty ? "没有可显示的行级归属。" : blameText)
                        .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                }.background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(history) { commit in
                            Button { Task { await appState.selectCommit(commit); dismiss() } } label: {
                                HStack(spacing: 8) {
                                    Text(commit.shortHash).font(.caption.monospaced()).foregroundStyle(OrbitDesign.violet)
                                    Text(commit.subject).orbitFont(.caption).lineLimit(1)
                                    Spacer(); Text(commit.dateText).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
                                }.padding(.horizontal, 9).frame(height: 34).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20).frame(width: 700, height: 480).background(OrbitDesign.canvas)
        .task { await load() }
    }

    private func load() async {
        guard let root = appState.repositoryRootURL else { loading = false; return }
        if showsBlame { blameText = (try? await appState.gitRunner.blame(path: path, at: root)) ?? "" }
        else { history = (try? await appState.gitRunner.fileHistory(path: path, at: root)) ?? [] }
        loading = false
    }
}
