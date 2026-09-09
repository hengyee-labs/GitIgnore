import SwiftUI

@MainActor
struct ChangeFileRow: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let file: GitFileStatus
    let stagedGroup: Bool
    let isBatchSelected: Bool
    let isCurrentFile: Bool
    let isInteractionDisabled: Bool
    let selectedFileCount: Int
    let onToggleSelection: () -> Void
    let onOpen: () -> Void
    let onTransfer: () -> Void

    nonisolated static func == (lhs: ChangeFileRow, rhs: ChangeFileRow) -> Bool {
        lhs.file == rhs.file
            && lhs.stagedGroup == rhs.stagedGroup
            && lhs.isBatchSelected == rhs.isBatchSelected
            && lhs.isCurrentFile == rhs.isCurrentFile
            && lhs.isInteractionDisabled == rhs.isInteractionDisabled
            && lhs.selectedFileCount == rhs.selectedFileCount
    }

    var body: some View {
        HStack(spacing: 10) {
            selectionButton
            fileButton
            stageButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isCurrentFile {
                Capsule()
                    .fill(OrbitDesign.accent)
                    .frame(width: 3, height: 28)
                    .offset(x: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(selectionAnimation, value: isCurrentFile)
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .draggable(file.path) { dragPreview }
    }

    private var selectionButton: some View {
        Button {
            onToggleSelection()
        } label: {
            Image(systemName: isBatchSelected ? "checkmark.square.fill" : "square")
                .orbitFont(.subheadline, weight: .medium)
                .foregroundStyle(isBatchSelected ? OrbitDesign.accent : OrbitDesign.secondaryText)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isBatchSelected ? AppLanguage.text("取消选择", "Deselect") : AppLanguage.text("加入批量选择", "Add to batch selection"))
        .accessibilityLabel(isBatchSelected
                            ? AppLanguage.text("取消选择 \(file.path)", "Deselect \(file.path)")
                            : AppLanguage.text("选择 \(file.path) 进行批量操作", "Select \(file.path) for batch actions"))
    }

    private var fileButton: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 10) {
                Text(shortLabel)
                    .orbitFont(.caption2, weight: .bold)
                    .foregroundStyle(fileColor)
                    .frame(width: 25, height: 25)
                    .background(fileColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .orbitFont(.callout, weight: .medium)
                        .foregroundStyle(OrbitDesign.primaryText)
                        .lineLimit(1)
                    Text(file.kind.title + (stagedGroup ? AppLanguage.text(" · 已在暂存区", " · Staged") : AppLanguage.text(" · 尚未暂存", " · Unstaged")))
                        .orbitFont(.caption2)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AppLanguage.text("查看 \(file.path) 的变更", "View changes in \(file.path)"))
        .accessibilityLabel(AppLanguage.text("查看 \(file.path) 的变更", "View changes in \(file.path)"))
        .accessibilityHint(AppLanguage.text("在代码区打开此文件", "Open this file in the code viewer"))
    }

    private var stageButton: some View {
        Button {
            onTransfer()
        } label: {
            Image(systemName: stagedGroup ? "minus.circle" : "plus.circle")
                .orbitFont(.subheadline, weight: .semibold)
                .foregroundStyle(stagedGroup ? OrbitDesign.secondaryText : OrbitDesign.accent)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(stagedGroup ? AppLanguage.text("取消暂存", "Unstage") : AppLanguage.text("暂存文件", "Stage file"))
        .accessibilityLabel(stagedGroup
                            ? AppLanguage.text("取消暂存 \(file.path)", "Unstage \(file.path)")
                            : AppLanguage.text("暂存 \(file.path)", "Stage \(file.path)"))
        .disabled(isInteractionDisabled)
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
            Text(isBatchSelected && selectedFileCount > 1
                 ? AppLanguage.text("移动 \(selectedFileCount) 个文件", "Move \(selectedFileCount) files")
                 : file.path)
                .lineLimit(1)
        }
        .orbitFont(.caption, weight: .semibold)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitDesign.accent.opacity(0.45), lineWidth: 1) }
    }

    private var rowBackground: Color {
        if isCurrentFile { return OrbitDesign.accent.opacity(0.075) }
        return isHovering ? OrbitDesign.primaryText.opacity(0.035) : .clear
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.25, dampingFraction: 0.88)
    }

    private var shortLabel: String {
        switch file.kind {
        case .modified: "改"
        case .added: "增"
        case .deleted: "删"
        case .renamed: "移"
        case .untracked: "新"
        case .conflicted: "冲"
        }
    }

    private var fileColor: Color {
        switch file.kind {
        case .modified: OrbitDesign.amber
        case .added: OrbitDesign.accent
        case .deleted: OrbitDesign.coral
        case .renamed: OrbitDesign.violet
        case .untracked: OrbitDesign.blue
        case .conflicted: OrbitDesign.coral
        }
    }
}
