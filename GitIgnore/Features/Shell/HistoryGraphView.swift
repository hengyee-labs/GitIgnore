import SwiftUI

enum HistoryGraphMode: String, CaseIterable {
    case clear
    case full
}

enum HistoryScope: String, CaseIterable {
    case all
    case current
    case incoming
    case outgoing

    var title: String {
        switch self {
        case .all: AppLanguage.text("所有分支", "All branches")
        case .current: AppLanguage.text("当前分支", "Current branch")
        case .incoming: AppLanguage.text("待 Pull", "Ready to pull")
        case .outgoing: AppLanguage.text("待 Push", "Ready to push")
        }
    }
}

struct GitGraphNode: Sendable, Equatable {
    let lane: Int
    let incomingLanes: [Int]
    let outgoingLanes: [Int]
    let parentLanes: [Int]
    let maximumLane: Int

    static let fallback = GitGraphNode(
        lane: 0,
        incomingLanes: [0],
        outgoingLanes: [0],
        parentLanes: [0],
        maximumLane: 0
    )
}

enum GitGraphLayout {
    static func build(commits: [GitCommitSummary]) -> [String: GitGraphNode] {
        var lanes: [String] = []
        var result: [String: GitGraphNode] = [:]

        for commit in commits {
            let lane: Int
            if let existing = lanes.firstIndex(of: commit.hash) {
                lane = existing
            } else {
                lanes.insert(commit.hash, at: 0)
                lane = 0
            }
            let incoming = Array(lanes.indices)

            if let firstParent = commit.parents.first {
                lanes[lane] = firstParent
                for (offset, parent) in commit.parents.dropFirst().enumerated() where !lanes.contains(parent) {
                    lanes.insert(parent, at: min(lane + offset + 1, lanes.count))
                }
            } else {
                lanes.remove(at: lane)
            }

            var seen: Set<String> = []
            lanes = lanes.filter { seen.insert($0).inserted }
            let parentLanes = commit.parents.compactMap { lanes.firstIndex(of: $0) }
            let outgoing = Array(lanes.indices)
            let maximumLane = max(
                incoming.max() ?? 0,
                outgoing.max() ?? 0,
                parentLanes.max() ?? lane,
                lane
            )
            result[commit.id] = GitGraphNode(
                lane: lane,
                incomingLanes: incoming,
                outgoingLanes: outgoing,
                parentLanes: parentLanes,
                maximumLane: maximumLane
            )
        }
        return result
    }
}

struct HistoryGraphView: View {
    let node: GitGraphNode
    let mode: HistoryGraphMode
    let parentCount: Int
    let isSelected: Bool
    let isLast: Bool

    private let graphHeight: CGFloat = 70
    private let maximumVisibleLaneCount = 7

    private var graphWidth: CGFloat {
        mode == .clear ? 38 : 118
    }


    private var activeLanes: [Int] {
        Array(Set(node.incomingLanes + node.outgoingLanes + node.parentLanes + [node.lane])).sorted()
    }

    private var visibleLanes: [Int] {
        let lanes = activeLanes
        guard lanes.count > maximumVisibleLaneCount,
              let nodeIndex = lanes.firstIndex(of: node.lane) else {
            return lanes
        }
        let preferredStart = max(0, nodeIndex - maximumVisibleLaneCount / 2)
        let start = min(preferredStart, lanes.count - maximumVisibleLaneCount)
        return Array(lanes[start..<(start + maximumVisibleLaneCount)])
    }

    private var hiddenLaneCount: Int {
        max(0, activeLanes.count - visibleLanes.count)
    }

    var body: some View {
        let hiddenCount = max(0, activeLanes.count - visibleLanes.count)
        return HStack(spacing: 5) {
            Image(systemName: parentCount > 1 ? "arrow.triangle.branch" : "circle.fill")
                .font(.system(size: parentCount > 1 ? 15 : 9, weight: .semibold))
                .foregroundStyle(parentCount > 1 ? OrbitDesign.violet : OrbitDesign.accent)
            if mode == .full, hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(OrbitDesign.tertiaryText)
            }
        }
        .frame(width: graphWidth, height: graphHeight, alignment: .leading)
        .frame(width: graphWidth, height: graphHeight)
        .overlay(alignment: .topTrailing) {
            if mode == .full, hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(OrbitDesign.tertiaryText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(OrbitDesign.recessedSurface, in: Capsule())
                    .accessibilityLabel(AppLanguage.text(
                        "另有 \(hiddenCount) 条分支路径未显示",
                        "\(hiddenCount) additional branch paths hidden"
                    ))
            }
        }
        .accessibilityHidden(true)
    }

}
