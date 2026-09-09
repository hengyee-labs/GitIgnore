import SwiftUI

struct IncomingDiffRequest: Identifiable {
    let commit: GitCommitSummary
    let file: GitCommitFileChange
    var id: String { "\(commit.id):\(file.path)" }
}

struct IncomingDiffPreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let request: IncomingDiffRequest
    @State private var diff: GitFileDiff?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                OrbitIconBadge(systemName: "doc.text.magnifyingglass", color: OrbitDesign.amber, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.file.path).orbitFont(.headline).lineLimit(1).truncationMode(.middle)
                    Text("\(request.commit.shortHash) · \(request.commit.subject)")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            .background(OrbitDesign.surface)
            Divider().overlay(OrbitDesign.separator)

            if let diff {
                ScrollView {
                    OrbitDiffViewer(diff: diff)
                        .padding(14)
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "无法读取远程文件 Diff",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("正在按需读取 Diff…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(OrbitDesign.canvas)
        .task { await loadDiff() }
    }

    private func loadDiff() async {
        guard let repository = appState.repository else { return }
        do {
            diff = try await appState.gitRunner.commitFileDiff(
                hash: request.commit.hash,
                path: request.file.path,
                at: URL(fileURLWithPath: repository.path, isDirectory: true)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
