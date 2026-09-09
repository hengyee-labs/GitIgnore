import SwiftUI

struct RepositoryIdentityMark: View {
    let identity: String
    var size: CGFloat = 34

    private static let palettes: [[Color]] = [
        [.teal, .blue, .indigo], [.blue, .purple, .pink], [.orange, .pink, .red],
        [.mint, .teal, .blue], [.purple, .indigo, .cyan], [.green, .teal, .mint],
        [.pink, .purple, .indigo], [.yellow, .orange, .pink], [.cyan, .blue, .purple],
        [.red, .orange, .purple]
    ]

    private var fingerprint: UInt64 {
        identity.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private var palette: [Color] {
        Self.palettes[Int(fingerprint % UInt64(Self.palettes.count))]
    }

    private var rotation: Angle {
        .degrees(Double(fingerprint % 360))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(AngularGradient(colors: palette, center: .center, angle: rotation))
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.28), .clear, .black.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: max(1, size * 0.035))
                .frame(width: size * 0.72, height: size * 0.72)
                .rotationEffect(rotation)
            Canvas { context, canvasSize in
                let side = min(canvasSize.width, canvasSize.height)
                let center = CGPoint(x: canvasSize.width * 0.48, y: canvasSize.height * 0.54)
                let spread = side * 0.27
                let nodes = [
                    CGPoint(x: center.x - spread, y: center.y - side * 0.18),
                    CGPoint(x: center.x + spread, y: center.y - side * 0.18),
                    CGPoint(x: center.x + spread * 0.82, y: center.y + side * 0.25)
                ]
                for node in nodes {
                    var link = Path()
                    link.move(to: center)
                    link.addCurve(
                        to: node,
                        control1: CGPoint(x: center.x, y: node.y),
                        control2: CGPoint(x: node.x, y: center.y)
                    )
                    context.stroke(
                        link,
                        with: .color(.white.opacity(0.78)),
                        style: StrokeStyle(lineWidth: max(1, side * 0.045), lineCap: .round)
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: node.x - side * 0.075, y: node.y - side * 0.075,
                                               width: side * 0.15, height: side * 0.15)),
                        with: .color(.white.opacity(0.95))
                    )
                }
                var core = Path()
                core.move(to: CGPoint(x: center.x, y: center.y - side * 0.14))
                core.addLine(to: CGPoint(x: center.x + side * 0.14, y: center.y))
                core.addLine(to: CGPoint(x: center.x, y: center.y + side * 0.14))
                core.addLine(to: CGPoint(x: center.x - side * 0.14, y: center.y))
                core.closeSubpath()
                context.fill(core, with: .color(.white))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28)
                .stroke(.white.opacity(0.34), lineWidth: max(1, size * 0.025))
        }
        .shadow(color: palette[1].opacity(0.28), radius: size * 0.14, y: size * 0.08)
        .accessibilityLabel("仓库标识")
    }
}

struct PulseMetric: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(value == 0 ? Color.clear : color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value, format: .number)
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(title)
                    .orbitFont(.caption2, weight: .medium)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

struct BranchTrajectory: View {
    let branch: String
    let behindCount: Int
    let aheadCount: Int
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Canvas { context, size in
                let centerY = size.height * 0.50
                var trunk = Path()
                trunk.move(to: CGPoint(x: size.width * 0.05, y: centerY))
                trunk.addLine(to: CGPoint(x: size.width * 0.95, y: centerY))
                context.stroke(trunk, with: .color(accent.opacity(0.48)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                var branchPath = Path()
                branchPath.move(to: CGPoint(x: size.width * 0.28, y: centerY))
                branchPath.addCurve(
                    to: CGPoint(x: size.width * 0.88, y: centerY),
                    control1: CGPoint(x: size.width * 0.47, y: size.height * 0.10),
                    control2: CGPoint(x: size.width * 0.72, y: size.height * 0.10)
                )
                context.stroke(branchPath, with: .color(accent.opacity(0.28)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                for position in [0.12, 0.28, 0.50, 0.72, 0.88] {
                    let rect = CGRect(x: size.width * position - 3.5, y: centerY - 3.5, width: 7, height: 7)
                    context.fill(Path(ellipseIn: rect), with: .color(OrbitDesign.opaqueElevatedSurface))
                    context.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(0.78)), lineWidth: 1.5)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                Spacer()
                Text("↓\(behindCount)  ↑\(aheadCount)").monospacedDigit()
            }
            .orbitFont(.caption2, weight: .medium)
            .foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("分支 \(branch)，可 Pull \(behindCount)，未 Push \(aheadCount)")
    }
}
