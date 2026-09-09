import SwiftUI

struct SelectablePatchView: View {
    let hunk: GitPatchHunk
    let maxVisibleLines: Int?
    let allowsTextSelection: Bool
    @Binding var selection: Set<Int>

    init(
        hunk: GitPatchHunk,
        selection: Binding<Set<Int>>,
        maxVisibleLines: Int? = nil,
        allowsTextSelection: Bool = true
    ) {
        self.hunk = hunk
        self.maxVisibleLines = maxVisibleLines
        self.allowsTextSelection = allowsTextSelection
        _selection = selection
    }

    var body: some View {
        let visibleLines = hunk.selectableLines(limit: maxVisibleLines)
        let omittedCount = max(hunk.selectableLineCount - visibleLines.count, 0)
        VStack(spacing: 0) {
            columnHeader
            LazyVStack(spacing: 0) {
                ForEach(visibleLines) { line in
                    if line.isNoNewlineMetadata {
                        metadataRow
                    } else {
                        lineRow(line)
                    }
                }
            }
            if omittedCount > 0 {
                omittedRowsFooter(omittedCount)
            }
        }
        .background(OrbitDesign.elevatedSurface)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("选择").frame(width: 40)
            Text("旧行").frame(width: 42, alignment: .trailing)
            Text("新行").frame(width: 42, alignment: .trailing)
            Text("变更").frame(width: 48)
            Text("代码内容").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(OrbitDesign.secondaryText)
        .padding(.horizontal, 4)
        .frame(height: 28)
        .background(OrbitDesign.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(OrbitDesign.separator).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("代码差异列：选择、旧行号、新行号、变更类型和代码内容")
    }

    private func lineRow(_ line: GitSelectablePatchLine) -> some View {
        HStack(spacing: 0) {
            if line.isSelectable {
                Button {
                    if selection.contains(line.index) {
                        selection.remove(line.index)
                    } else {
                        selection.insert(line.index)
                    }
                } label: {
                    Image(systemName: selection.contains(line.index) ? "checkmark.square.fill" : "square")
                        .orbitFont(.caption)
                        .foregroundStyle(selection.contains(line.index) ? OrbitDesign.accent : OrbitDesign.secondaryText)
                        .frame(width: 40, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selection.contains(line.index) ? "取消选择此行" : "选择此行")
            } else {
                Color.clear.frame(width: 40, height: 28)
            }

            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)
            changeBadge(line)
                .frame(width: 48)
            Text(line.displayText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .optionalDiffTextSelection(allowsTextSelection)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(OrbitDesign.primaryText)
        .frame(minHeight: 28)
        .background(background(line))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(line.isAddition ? OrbitDesign.accent : (line.isRemoval ? OrbitDesign.coral : .clear))
                .frame(width: line.isSelectable ? 2 : 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(OrbitDesign.separator.opacity(0.35)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture {
            guard line.isSelectable else { return }
            if selection.contains(line.index) { selection.remove(line.index) }
            else { selection.insert(line.index) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.accessibilityDescription)
        .accessibilityHint(line.isSelectable ? "点击选择或取消选择这一行" : "上下文代码行")
    }

    @ViewBuilder
    private func changeBadge(_ line: GitSelectablePatchLine) -> some View {
        if line.isAddition {
            Text("新增")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OrbitDesign.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(OrbitDesign.accent.opacity(0.10), in: Capsule())
        } else if line.isRemoval {
            Text("删除")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OrbitDesign.coral)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(OrbitDesign.coral.opacity(0.10), in: Capsule())
        } else {
            Text("上下文").font(.system(size: 9)).foregroundStyle(OrbitDesign.secondaryText.opacity(0.75))
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "return")
                .font(.system(size: 9, weight: .semibold))
            Text("文件末尾没有换行符")
                .fontWeight(.semibold)
            Text("这是 Git 的文件格式提示，不是代码内容")
                .foregroundStyle(OrbitDesign.secondaryText)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(OrbitDesign.amber)
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(OrbitDesign.amber.opacity(0.075))
        .overlay(alignment: .bottom) { Rectangle().fill(OrbitDesign.separator.opacity(0.35)).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("文件末尾没有换行符。这是 Git 的文件格式提示，不是代码内容。")
    }

    private func background(_ line: GitSelectablePatchLine) -> Color {
        if selection.contains(line.index) { return OrbitDesign.accent.opacity(0.12) }
        if line.isAddition { return OrbitDesign.accent.opacity(0.07) }
        if line.isRemoval { return OrbitDesign.coral.opacity(0.07) }
        return .clear
    }

    private func omittedRowsFooter(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OrbitDesign.amber)
            Text(AppLanguage.text("已省略 \(count) 行，避免右侧代码区卡顿", "\(count) lines omitted to keep the inspector responsive"))
                .orbitFont(.caption2, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(OrbitDesign.amber.opacity(0.07))
        .overlay(alignment: .bottom) { Rectangle().fill(OrbitDesign.separator.opacity(0.35)).frame(height: 0.5) }
        .accessibilityLabel(AppLanguage.text("已省略 \(count) 行，以保持右侧代码区响应速度", "\(count) lines omitted to keep the inspector responsive"))
    }
}

struct LightweightPatchPreview: View {
    let hunk: GitPatchHunk
    let maxVisibleLines: Int

    private var visibleLines: [GitSelectablePatchLine] {
        hunk.selectableLines(limit: maxVisibleLines)
    }

    var body: some View {
        let lines = visibleLines
        let omittedCount = max(hunk.selectableLineCount - lines.count, 0)

        VStack(spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(lines) { line in
                    lightweightRow(line)
                }
            }

            if omittedCount > 0 {
                lightweightFooter(omittedCount)
            }
        }
        .background(OrbitDesign.elevatedSurface)
    }

    private func lightweightRow(_ line: GitSelectablePatchLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 7)
                .foregroundStyle(OrbitDesign.secondaryText.opacity(0.78))

            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 7)
                .foregroundStyle(OrbitDesign.secondaryText.opacity(0.78))

            Text(marker(for: line))
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(foreground(for: line))
                .frame(width: 18, alignment: .center)

            Text(trimmedDisplayText(line.displayText))
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 10.8, design: .monospaced))
                .foregroundStyle(foreground(for: line))
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 24, alignment: .topLeading)
        .background(background(for: line))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(line.isAddition ? OrbitDesign.accent : (line.isRemoval ? OrbitDesign.coral : .clear))
                .frame(width: line.isSelectable ? 2 : 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(OrbitDesign.separator.opacity(0.22)).frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityDescription)
    }

    private func lightweightFooter(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OrbitDesign.amber)
            Text(AppLanguage.text("已轻量展示前 \(maxVisibleLines) 行，省略 \(count) 行；逐行选择时同样按需加载", "Showing first \(maxVisibleLines) lightweight lines, omitting \(count). Line selection also loads on demand."))
                .orbitFont(.caption2, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OrbitDesign.amber.opacity(0.065))
        .overlay(alignment: .top) { Rectangle().fill(OrbitDesign.separator.opacity(0.35)).frame(height: 0.5) }
    }

    private func marker(for line: GitSelectablePatchLine) -> String {
        if line.isAddition { return "+" }
        if line.isRemoval { return "−" }
        return ""
    }

    private func foreground(for line: GitSelectablePatchLine) -> Color {
        if line.isAddition { return OrbitDesign.accent }
        if line.isRemoval { return OrbitDesign.coral }
        if line.text.hasPrefix("@@") { return OrbitDesign.violet }
        return OrbitDesign.primaryText.opacity(0.84)
    }

    private func background(for line: GitSelectablePatchLine) -> Color {
        if line.isAddition { return OrbitDesign.accent.opacity(0.07) }
        if line.isRemoval { return OrbitDesign.coral.opacity(0.07) }
        return Color.clear
    }

    private func trimmedDisplayText(_ value: String) -> String {
        let maxLength = 360
        guard value.count > maxLength else { return value.isEmpty ? " " : value }
        let index = value.index(value.startIndex, offsetBy: maxLength)
        return String(value[..<index]) + " …"
    }
}

private struct OptionalDiffTextSelectionModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

private extension View {
    func optionalDiffTextSelection(_ isEnabled: Bool) -> some View {
        modifier(OptionalDiffTextSelectionModifier(isEnabled: isEnabled))
    }
}
