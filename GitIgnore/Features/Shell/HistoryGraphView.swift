import SwiftUI

enum HistoryGraphMode: String, CaseIterable {
    case clear
    case full
}

enum HistoryScope: String, CaseIterable {
    case all
    case current
    case incoming

    var title: String {
        switch self {
        case .all: AppLanguage.text("所有分支", "All branches")
        case .current: AppLanguage.text("当前分支", "Current branch")
        case .incoming: AppLanguage.text("待 Pull", "Ready to pull")
        }
    }
}

struct GitGraphNode: Sendable {
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
        mode == .clear ? 68 : 118
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
        Canvas { context, size in
            let centerY = size.height * 0.5
            let palette = [
                OrbitDesign.violet,
                OrbitDesign.blue,
                OrbitDesign.accent,
                OrbitDesign.amber,
                OrbitDesign.coral
            ]

            if mode == .clear {
                let trunkX: CGFloat = 20
                var trunk = Path()
                trunk.move(to: CGPoint(x: trunkX, y: 0))
                trunk.addLine(to: CGPoint(x: trunkX, y: isLast ? centerY : size.height))
                context.stroke(
                    trunk,
                    with: .color(OrbitDesign.violet.opacity(0.62)),
                    lineWidth: 2.2
                )

                let visibleBranchCount = min(max(parentCount - 1, 0), 2)
                if visibleBranchCount > 0, !isLast {
                    for branchIndex in 0..<visibleBranchCount {
                        let branchX = CGFloat(46 + branchIndex * 13)
                        var branch = Path()
                        branch.move(to: CGPoint(x: trunkX, y: centerY))
                        branch.addCurve(
                            to: CGPoint(x: branchX, y: size.height),
                            control1: CGPoint(x: trunkX, y: centerY + 14),
                            control2: CGPoint(x: branchX, y: size.height - 14)
                        )
                        context.stroke(
                            branch,
                            with: .color((branchIndex == 0 ? OrbitDesign.blue : OrbitDesign.accent).opacity(0.88)),
                            lineWidth: 2.3
                        )
                    }
                }

                let nodeColor = parentCount > 1 ? OrbitDesign.violet : OrbitDesign.accent
                let nodeRect = CGRect(x: trunkX - 6.5, y: centerY - 6.5, width: 13, height: 13)
                context.fill(
                    Path(ellipseIn: nodeRect),
                    with: .color(isSelected ? nodeColor : OrbitDesign.canvas)
                )
                context.stroke(Path(ellipseIn: nodeRect), with: .color(nodeColor), lineWidth: 2.4)

                if parentCount > 1 {
                    context.stroke(
                        Path(ellipseIn: nodeRect.insetBy(dx: -3.5, dy: -3.5)),
                        with: .color(nodeColor.opacity(0.38)),
                        lineWidth: 1.2
                    )
                }
            } else {
                let visibleLaneSet = Set(visibleLanes)
                for lane in node.incomingLanes where visibleLaneSet.contains(lane) {
                    var line = Path()
                    line.move(to: CGPoint(x: fullGraphX(lane), y: 0))
                    line.addLine(to: CGPoint(x: fullGraphX(lane), y: centerY))
                    context.stroke(
                        line,
                        with: .color(palette[lane % palette.count].opacity(0.72)),
                        lineWidth: 2.2
                    )
                }

                if !isLast {
                    for lane in node.outgoingLanes where visibleLaneSet.contains(lane) {
                        var line = Path()
                        line.move(to: CGPoint(x: fullGraphX(lane), y: centerY))
                        line.addLine(to: CGPoint(x: fullGraphX(lane), y: size.height))
                        context.stroke(
                            line,
                            with: .color(palette[lane % palette.count].opacity(0.72)),
                            lineWidth: 2.2
                        )
                    }
                }

                for parentLane in node.parentLanes
                where parentLane != node.lane && visibleLaneSet.contains(parentLane) {
                    var branch = Path()
                    branch.move(to: CGPoint(x: fullGraphX(node.lane), y: centerY))
                    branch.addCurve(
                        to: CGPoint(x: fullGraphX(parentLane), y: size.height),
                        control1: CGPoint(x: fullGraphX(node.lane), y: centerY + 18),
                        control2: CGPoint(x: fullGraphX(parentLane), y: size.height - 18)
                    )
                    context.stroke(
                        branch,
                        with: .color(palette[parentLane % palette.count].opacity(0.94)),
                        lineWidth: 2.4
                    )
                }

                let nodeColor = palette[node.lane % palette.count]
                let nodeX = fullGraphX(node.lane)
                let rect = CGRect(x: nodeX - 6.5, y: centerY - 6.5, width: 13, height: 13)
                context.fill(Path(ellipseIn: rect), with: .color(isSelected ? nodeColor : OrbitDesign.canvas))
                context.stroke(Path(ellipseIn: rect), with: .color(nodeColor), lineWidth: 2.4)

                if parentCount > 1 {
                    let mergeRing = rect.insetBy(dx: -3.5, dy: -3.5)
                    context.stroke(
                        Path(ellipseIn: mergeRing),
                        with: .color(nodeColor.opacity(0.42)),
                        lineWidth: 1.2
                    )
                }
            }
        }
        .frame(width: graphWidth, height: graphHeight)
        .overlay(alignment: .topTrailing) {
            if mode == .full, hiddenLaneCount > 0 {
                Text("+\(hiddenLaneCount)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(OrbitDesign.tertiaryText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(OrbitDesign.recessedSurface, in: Capsule())
                    .accessibilityLabel(AppLanguage.text(
                        "另有 \(hiddenLaneCount) 条分支路径未显示",
                        "\(hiddenLaneCount) additional branch paths hidden"
                    ))
            }
        }
        .accessibilityHidden(true)
    }

    private func fullGraphX(_ lane: Int) -> CGFloat {
        guard let index = visibleLanes.firstIndex(of: lane) else { return 10 }
        guard visibleLanes.count > 1 else { return 18 }
        let laneSpacing = min(14, (graphWidth - 24) / CGFloat(visibleLanes.count - 1))
        return 10 + CGFloat(index) * laneSpacing
    }
}
