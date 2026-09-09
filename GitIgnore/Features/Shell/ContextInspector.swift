import AppKit
import SwiftUI

struct ContextInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch appState.selectedSection {
                case .overview:
                    repositorySummary
                case .changes:
                    changesSummary
                case .history:
                    historySummary
                default:
                    sectionSummary
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var repositorySummary: some View {
        inspectorEyebrow("仓库摘要")
        Text(appState.repository?.name ?? "尚未打开仓库")
            .orbitFont(.title3, weight: .bold)
        if let repository = appState.repository {
            HStack(spacing: 10) {
                OrbitIconBadge(
                    systemName: repository.isClean ? "checkmark.circle" : "exclamationmark.circle",
                    color: repository.isClean ? OrbitDesign.accent : OrbitDesign.amber,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository.isClean ? "工作区干净" : "\(repository.changedFileCount) 个文件待处理")
                        .orbitFont(.callout, weight: .semibold)
                        .contentTransition(.numericText())
                    Text("当前分支 · \(repository.branch)")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }

            detailRow("已暂存", value: "\(repository.stagedFileCount) 个文件")
            detailRow("与远程分支", value: "领先 \(repository.aheadCount) · 落后 \(repository.behindCount)")
            detailRow("仓库位置", value: repository.path, monospaced: true)

            Button("前往工作区变更") { appState.selectSection(.changes) }
                .buttonStyle(.borderedProminent)
        } else {
            Text("从左上项目区域选择一个本地仓库，仓库状态和常用入口会显示在这里。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开仓库…") { appState.chooseRepository() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var changesSummary: some View {
        inspectorEyebrow("工作区摘要")
        Text("选择文件查看内容差异")
            .orbitFont(.title3, weight: .bold)
        Text("也可以多选文件批量操作，或直接拖入已暂存和未暂存区域。")
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        detailRow("已暂存", value: "\(appState.status.stagedFileCount) 个文件")
        detailRow("尚未暂存", value: "\(appState.status.unstagedFileCount) 个文件")
    }

    @ViewBuilder
    private var historySummary: some View {
        inspectorEyebrow("提交历史")
        Text("选择一条提交查看完整内容")
            .orbitFont(.title3, weight: .bold)
        Text("右侧会显示提交正文、变更文件以及逐行内容对比。")
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        if let latest = appState.commits.first {
            Divider()
            Text("最近提交")
                .orbitFont(.caption, weight: .bold)
                .foregroundStyle(OrbitDesign.secondaryText)
            Text(latest.subject)
                .orbitFont(.callout, weight: .semibold)
            Text("\(latest.author) · \(latest.dateText)")
                .orbitFont(.caption2)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
    }

    @ViewBuilder
    private var sectionSummary: some View {
        inspectorEyebrow("当前模块")
        OrbitIconBadge(systemName: appState.selectedSection.symbol, color: OrbitDesign.violet, size: 44)
        Text(appState.selectedSection.title).orbitFont(.title3, weight: .bold)
        Text("在中间区域选择具体内容后，相关操作和详细信息会在这里展开。")
            .orbitFont(.caption)
            .foregroundStyle(OrbitDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FileInspector: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mergeEditorPresented = false
    let file: GitFileStatus

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitDesign.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusStrip
                    if file.hasConflict {
                        conflictActions
                    }
                    previewContent
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .sheet(isPresented: $mergeEditorPresented) {
            MergeEditorView(file: file)
                .environment(appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorEyebrow("文件变更")
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: fileSymbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(fileColor)
                    .frame(width: 34, height: 34)
                    .background(fileColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .orbitFont(.headline)
                        .foregroundStyle(OrbitDesign.primaryText)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if !parentPath.isEmpty {
                        Text(parentPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(OrbitDesign.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 36)
            }

            HStack(spacing: 6) {
                statusPill(file.kind.title, color: fileColor)
                statusPill(file.indexCode == " " ? "未 Stage" : "已 Stage", color: OrbitDesign.violet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var statusStrip: some View {
        HStack(spacing: 0) {
            statusItem(
                title: "索引",
                value: file.indexCode == " " ? "未暂存" : "已暂存",
                symbol: file.indexCode == " " ? "tray" : "tray.full"
            )
            Rectangle()
                .fill(OrbitDesign.separator)
                .frame(width: 1, height: 32)
                .padding(.horizontal, 14)
            statusItem(
                title: "工作区",
                value: file.worktreeCode == " " ? "无变更" : "有变更",
                symbol: file.worktreeCode == " " ? "checkmark.circle" : "pencil.line"
            )
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(OrbitDesign.separator, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if appState.isLoadingDiff {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(AppLanguage.text("正在读取内容差异…", "Reading changes…"))
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(OrbitDesign.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity)
        } else if let message = appState.selectedFileDiffError {
            VStack(spacing: 10) {
                Label(
                    AppLanguage.text("暂时无法读取这项变更", "Unable to read this change"),
                    systemImage: "arrow.clockwise.circle"
                )
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.primaryText)

                Text(message)
                    .orbitFont(.caption2)
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Button(AppLanguage.text("重新读取", "Try Again")) {
                    Task {
                        await appState.selectFile(file, staged: appState.selectedFileDiffIsStaged)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(OrbitDesign.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity)
        } else if let diff = appState.selectedFileDiff {
            if diff.supportsInlinePreview {
                HunkDiffView(diff: diff, file: file)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            } else {
                SpecialDiffStateView(diff: diff)
            }
        } else if file.hasConflict {
            Text("当前文件暂时没有可阅读的文本差异，可直接打开三方冲突编辑器处理。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var conflictActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("冲突处理", systemImage: "exclamationmark.triangle.fill")
                .orbitFont(.caption, weight: .bold)
                .foregroundStyle(OrbitDesign.coral)
            Button {
                mergeEditorPresented = true
            } label: {
                Label("打开三方冲突编辑器", systemImage: "rectangle.split.3x1")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(OrbitDesign.accent)
            HStack(spacing: 7) {
                Button("保留当前") { Task { await appState.resolveUsingOurs(file) } }
                Button("采用合入") { Task { await appState.resolveUsingTheirs(file) } }
                Button("标记解决") { Task { await appState.markResolved(file) } }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(OrbitDesign.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(OrbitDesign.coral.opacity(0.24), lineWidth: 1)
        }
    }

    private func statusItem(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .orbitFont(.caption2, weight: .semibold)
                .foregroundStyle(OrbitDesign.secondaryText)
            Text(value)
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(OrbitDesign.primaryText)
        }
    }

    private func statusPill(_ title: String, color: Color) -> some View {
        Text(title)
            .orbitFont(.caption2, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.09), in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.18), lineWidth: 1) }
    }

    private var fileName: String {
        let value = (file.path as NSString).lastPathComponent
        return value.isEmpty ? file.path : value
    }

    private var parentPath: String {
        (file.path as NSString).deletingLastPathComponent
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

    private var fileSymbol: String {
        switch file.kind {
        case .modified: "pencil"
        case .added: "plus"
        case .deleted: "minus"
        case .renamed: "arrow.right"
        case .untracked: "sparkles"
        case .conflicted: "exclamationmark.triangle"
        }
    }
}

struct SpecialDiffStateView: View {
    @Environment(AppState.self) private var appState
    let diff: GitFileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if diff.contentKind == .image {
                imagePreview
            }
            OrbitIconBadge(systemName: symbol, color: OrbitDesign.violet, size: 38)
            Text(diff.contentKind.title).orbitFont(.headline)
            Text(detail).orbitFont(.caption).foregroundStyle(OrbitDesign.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Label("不会构建完整富文本", systemImage: "memorychip")
                Text(ByteCountFormatter.string(fromByteCount: Int64(diff.byteCount), countStyle: .file))
            }
            .orbitFont(.caption2, weight: .semibold).foregroundStyle(OrbitDesign.secondaryText)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitDesign.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if appState.isLoadingImageDiff {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取图片前后版本…").orbitFont(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
        } else if let preview = appState.selectedImageDiffPreview {
            ImageDiffComparisonView(preview: preview)
        }
    }

    private var symbol: String {
        switch diff.contentKind {
        case .image: "photo.on.rectangle.angled"
        case .binary: "doc.zipper"
        case .large: "externaldrive.badge.exclamationmark"
        case .generated: "gearshape.2"
        case .text: "doc.text"
        }
    }

    private var detail: String {
        switch diff.contentKind {
        case .image: "图片文件采用专门预览状态，避免把二进制内容误当代码渲染。"
        case .binary: "该文件没有可安全解析的文本 Diff，可继续进行文件级 Stage、Unstage 或丢弃。"
        case .large: "Diff 超过 10 MB，GitIgnore 已停止创建完整富文本；可按区块继续读取。"
        case .generated: "这是生成文件，默认减少高亮工作量，以保证滚动和选择响应。"
        case .text: ""
        }
    }
}

private struct ImageDiffComparisonView: View {
    let preview: GitImageDiffPreview
    @State private var mode = ImageComparisonMode.sideBySide
    @State private var overlayOpacity = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("图片对比方式", selection: $mode) {
                Text("并排").tag(ImageComparisonMode.sideBySide)
                Text("叠加").tag(ImageComparisonMode.overlay)
            }
            .pickerStyle(.segmented)

            if mode == .sideBySide {
                HStack(alignment: .top, spacing: 8) {
                    imagePane("修改前", preview.before)
                    imagePane("修改后", preview.after)
                }
            } else {
                ZStack {
                    checkerboard
                    if let before = image(preview.before) { before.resizable().scaledToFit() }
                    if let after = image(preview.after) { after.resizable().scaledToFit().opacity(overlayOpacity) }
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text("修改后透明度").orbitFont(.caption2)
                    Slider(value: $overlayOpacity, in: 0...1)
                    Text("\(Int(overlayOpacity * 100))%")
                        .font(.caption2.monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private func imagePane(_ title: String, _ version: GitImageVersion?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).orbitFont(.caption, weight: .bold)
            ZStack {
                checkerboard
                if let image = image(version) { image.resizable().scaledToFit().padding(4) }
                else { Text("无此版本").orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText) }
            }
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            if let version {
                Text("\(version.pixelWidth) × \(version.pixelHeight) · \(version.hasAlpha ? "含透明通道" : "不透明")")
                    .font(.caption2.monospacedDigit()).foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var checkerboard: some View {
        Color(nsColor: .controlBackgroundColor)
            .overlay {
                Canvas { context, size in
                    let cell: CGFloat = 10
                    for row in 0...Int(size.height / cell) {
                        for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                            context.fill(
                                Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                with: .color(OrbitDesign.separator.opacity(0.34))
                            )
                        }
                    }
                }
            }
    }

    private func image(_ version: GitImageVersion?) -> Image? {
        guard let version, let nsImage = NSImage(data: version.data) else { return nil }
        return Image(nsImage: nsImage)
    }
}

private enum ImageComparisonMode: Hashable {
    case sideBySide
    case overlay
}
