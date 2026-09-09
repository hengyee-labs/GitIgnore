import AppKit
import SwiftUI

enum WorkspaceResizeDirection {
    case increasing
    case decreasing
}

struct WorkspaceResizeHandle: View {
    @Binding var width: Double
    let limits: ClosedRange<Double>
    let direction: WorkspaceResizeDirection
    @State private var dragOrigin: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(.clear)
            Rectangle()
                .fill(OrbitDesign.separator.opacity(isHovering || dragOrigin != nil ? 0.72 : 0.22))
                .frame(width: 1)
        }
        .frame(width: 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = width }
                    let sign = direction == .increasing ? 1.0 : -1.0
                    let proposed = (dragOrigin ?? width) + Double(value.translation.width) * sign
                    width = min(max(proposed, limits.lowerBound), limits.upperBound)
                }
                .onEnded { _ in dragOrigin = nil }
        )
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel(AppLanguage.text("调整栏宽", "Resize Pane"))
        .accessibilityValue(AppLanguage.text("\(Int(width)) 点", "\(Int(width)) points"))
        .accessibilityHint(AppLanguage.text(
            "上下调整可改变宽度，范围 \(Int(limits.lowerBound)) 到 \(Int(limits.upperBound)) 点",
            "Adjust up or down to change width from \(Int(limits.lowerBound)) to \(Int(limits.upperBound)) points"
        ))
        .accessibilityAdjustableAction { action in
            let delta = action == .increment ? 20.0 : -20.0
            width = min(max(width + delta, limits.lowerBound), limits.upperBound)
        }
    }
}
