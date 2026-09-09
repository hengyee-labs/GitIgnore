import SwiftUI

struct ConflictCenterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingFile: GitFileStatus?
    let files: [GitFileStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                OrbitIconBadge(systemName: "exclamationmark.triangle", color: OrbitDesign.coral, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("需要处理 \(files.count) 个冲突")
                        .orbitFont(.headline)
                    Text("选择当前版本、合入版本，或编辑完成后标记已解决。")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
            }

            ForEach(GitConflictKind.allCases) { kind in
                let matches = files.filter { $0.conflictKind == kind }
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(kind.title) · \(matches.count)")
                            .orbitFont(.caption, weight: .bold)
                            .foregroundStyle(OrbitDesign.coral)
                        ForEach(matches) { file in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(OrbitDesign.coral)
                                    Text(file.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        editingFile = file
                                    } label: {
                                        Label("三方冲突编辑器", systemImage: "rectangle.split.3x1")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(OrbitDesign.accent)
                                }

                                HStack(spacing: 8) {
                                    Text("快速处理整份文件")
                                        .orbitFont(.caption2)
                                        .foregroundStyle(OrbitDesign.secondaryText)
                                    Spacer()
                                    Button("保留当前") { Task { await appState.resolveUsingOurs(file) } }
                                    Button("采用合入") { Task { await appState.resolveUsingTheirs(file) } }
                                    Button("已手动解决") { Task { await appState.markResolved(file) } }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(10)
                            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(OrbitDesign.separator, lineWidth: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(OrbitDesign.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(OrbitDesign.coral.opacity(0.32), lineWidth: 1) }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .sheet(item: $editingFile) { file in
            MergeEditorView(file: file)
                .environment(appState)
        }
    }
}
