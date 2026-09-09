import AppKit
import SwiftUI

struct RemoteResourceDetail: View {
    let item: RemoteCollaborationItem
    let isEnglish: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        stateBadge
                        if item.isDraft {
                            Text(isEnglish ? "Draft" : "草稿")
                                .orbitFont(.caption, weight: .semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(OrbitDesign.recessedSurface, in: Capsule())
                        }
                        Spacer()
                        Text("#\(item.number)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(OrbitDesign.tertiaryText)
                    }
                    Text(item.title)
                        .orbitFont(.title2, weight: .bold)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Label(item.author, systemImage: "person.crop.circle")
                        if let updatedAt = item.updatedAt {
                            Text("·")
                            Text(updatedAt, style: .relative)
                        }
                        if item.commentCount > 0 {
                            Text("·")
                            Label("\(item.commentCount)", systemImage: "bubble.left")
                        }
                    }
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
                }

                if let source = item.sourceBranch, let target = item.targetBranch {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(isEnglish ? "Branch direction" : "分支方向")
                            .orbitFont(.caption, weight: .semibold)
                            .foregroundStyle(OrbitDesign.secondaryText)
                        HStack(spacing: 9) {
                            branchPill(source)
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OrbitDesign.tertiaryText)
                            branchPill(target)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
                }

                if !item.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isEnglish ? "Labels" : "标签")
                            .orbitFont(.caption, weight: .semibold)
                            .foregroundStyle(OrbitDesign.secondaryText)
                        FlexibleRemoteLabels(labels: item.labels)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text(isEnglish ? "Description" : "描述")
                        .orbitFont(.headline, weight: .semibold)
                    Text(item.body.isEmpty ? (isEnglish ? "No description provided." : "没有填写描述。") : item.body)
                        .orbitFont(.body)
                        .foregroundStyle(item.body.isEmpty ? OrbitDesign.secondaryText : OrbitDesign.primaryText)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack {
                    Text(isEnglish ? "Comments and review actions continue on the hosting platform." : "评论与评审写操作继续在远程平台完成。")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(item.webURL)
                    } label: {
                        Label(isEnglish ? "Open Details" : "打开完整详情", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(22)
        }
        .background(OrbitDesign.canvas)
    }

    private var stateBadge: some View {
        Text(item.state.title)
            .orbitFont(.caption, weight: .semibold)
            .foregroundStyle(stateColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(stateColor.opacity(0.10), in: Capsule())
    }

    private var stateColor: Color {
        switch item.state {
        case .open: OrbitDesign.accent
        case .merged: OrbitDesign.violet
        case .closed: OrbitDesign.coral
        }
    }

    private func branchPill(_ name: String) -> some View {
        Text(name)
            .font(.caption.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(OrbitDesign.recessedSurface, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FlexibleRemoteLabels: View {
    let labels: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .orbitFont(.caption, weight: .medium)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OrbitDesign.recessedSurface, in: Capsule())
            }
        }
    }
}
