import AppKit
import SwiftUI

struct MergeEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let file: GitFileStatus

    @State private var document: GitMergeConflictDocument?
    @State private var resultText = ""
    @State private var blocks: [MergeConflictBlock] = []
    @State private var hasConflictMarkers = true
    @State private var selectedBlockIndex = 0
    @State private var deleteResult = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var parseTask: Task<Void, Never>?
    @State private var synchronizedScrollOffset: CGFloat = 0
    @State private var showsBaseReference = false
    @State private var scrollSynchronizer = MergeScrollSynchronizer()

    private var selectedBlock: MergeConflictBlock? {
        guard blocks.indices.contains(selectedBlockIndex) else { return nil }
        return blocks[selectedBlockIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitDesign.separator)

            if isLoading {
                loadingState
            } else if let loadError {
                errorState(loadError)
            } else if let document {
                conflictToolbar(document)
                Divider().overlay(OrbitDesign.separator)
                editorPanes(document)
                Divider().overlay(OrbitDesign.separator)
                footer(document)
            }
        }
        .frame(minWidth: 1_080, idealWidth: 1_380, minHeight: 680, idealHeight: 820)
        .background(OrbitDesign.canvas)
        .task { await loadDocument() }
        .onChange(of: resultText) { _, newValue in scheduleParse(newValue) }
        .onAppear {
            scrollSynchronizer.onOffset = { synchronizedScrollOffset = $0 }
        }
        .onDisappear {
            parseTask?.cancel()
            scrollSynchronizer.onOffset = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            OrbitIconBadge(systemName: "rectangle.split.3x1", color: OrbitDesign.coral, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("三方冲突编辑器")
                    .orbitFont(.headline)
                Text(file.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let document {
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(document.loadedByteCount),
                    countStyle: .file
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(OrbitDesign.secondaryText)
            }
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private func conflictToolbar(_ document: GitMergeConflictDocument) -> some View {
        HStack(spacing: 8) {
            statusChip

            if !blocks.isEmpty {
                Text("第 \(selectedBlockIndex + 1) / \(blocks.count) 处")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(OrbitDesign.secondaryText)
                iconButton("chevron.up", help: "上一个冲突") { moveSelection(by: -1) }
                    .disabled(selectedBlockIndex == 0)
                iconButton("chevron.down", help: "下一个冲突") { moveSelection(by: 1) }
                    .disabled(selectedBlockIndex >= blocks.count - 1)
            }

            Spacer()

            if document.baseText != nil {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18)) {
                        showsBaseReference.toggle()
                    }
                } label: {
                    Label(showsBaseReference ? "隐藏共同基线" : "显示共同基线", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            iconButton("arrow.uturn.backward", help: "撤销（⌘Z）") {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            }
            iconButton("arrow.uturn.forward", help: "重做（⇧⌘Z）") {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }

            if selectedBlock != nil {
                Label("当前冲突块", systemImage: "scope")
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.secondaryText)
                WorkspaceActionButton(title: "两边都保留", systemName: "arrow.left.and.right", tint: OrbitDesign.violet) {
                    resolveSelected(using: .both)
                }
            } else if document.baseText != nil {
                Label("已读取共同基线", systemImage: "checkmark.circle")
                    .orbitFont(.caption)
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(OrbitDesign.surface.opacity(0.45))
    }

    private var statusChip: some View {
        Group {
            if hasConflictMarkers {
                Label("\(blocks.count) 处未解决", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(OrbitDesign.coral)
                    .background(OrbitDesign.coral.opacity(0.10), in: Capsule())
            } else {
                Label("冲突标记已清除", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(OrbitDesign.accent)
                    .background(OrbitDesign.accent.opacity(0.10), in: Capsule())
            }
        }
        .orbitFont(.caption, weight: .semibold)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18), value: hasConflictMarkers)
    }

    private func editorPanes(_ document: GitMergeConflictDocument) -> some View {
        VStack(spacing: 0) {
            if showsBaseReference, let baseText = document.baseText {
                VStack(spacing: 0) {
                    HStack {
                        Label("共同基线", systemImage: "square.stack.3d.up")
                            .orbitFont(.caption, weight: .bold)
                        Text("Base · 只读参考")
                            .orbitFont(.caption2)
                            .foregroundStyle(OrbitDesign.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(OrbitDesign.surface)
                    MergeCodeEditor(
                        text: readOnlyBinding(baseText),
                        isEditable: false,
                        role: .current,
                        focusLine: selectedBlock?.startLine,
                        highlightedLines: selectedLineRange,
                        synchronizer: scrollSynchronizer,
                        synchronizedOffset: $synchronizedScrollOffset
                    )
                    .frame(height: 145)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                Divider().overlay(OrbitDesign.separator)
            }

            HStack(spacing: 0) {
                pane(
                    title: "当前分支",
                    subtitle: document.currentText == nil ? "此版本中不存在" : "Current / Ours",
                    color: OrbitDesign.blue,
                    text: readOnlyBinding(document.currentText ?? ""),
                    editable: false,
                    role: .current,
                    focusLine: selectedBlock?.startLine
                )
                transferRail(.current)
                pane(
                    title: "合并结果",
                    subtitle: deleteResult ? "保存后删除文件" : "Result · 可直接编辑",
                    color: deleteResult ? OrbitDesign.coral : OrbitDesign.violet,
                    text: $resultText,
                    editable: !deleteResult,
                    role: .result,
                    focusLine: selectedBlock?.startLine,
                    deleted: deleteResult
                )
                transferRail(.incoming)
                pane(
                    title: "合入分支",
                    subtitle: document.incomingText == nil ? "此版本中不存在" : "Incoming / Theirs",
                    color: OrbitDesign.accent,
                    text: readOnlyBinding(document.incomingText ?? ""),
                    editable: false,
                    role: .incoming,
                    focusLine: selectedBlock?.startLine
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pane(
        title: String,
        subtitle: String,
        color: Color,
        text: Binding<String>,
        editable: Bool,
        role: MergeEditorPaneRole,
        focusLine: Int? = nil,
        deleted: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).orbitFont(.caption, weight: .bold)
                    Text(subtitle).orbitFont(.caption2).foregroundStyle(OrbitDesign.secondaryText)
                }
                Spacer()
                Text("\(text.wrappedValue.components(separatedBy: "\n").count) 行")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OrbitDesign.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(OrbitDesign.surface)
            Divider().overlay(OrbitDesign.separator)

            if deleted {
                VStack(spacing: 12) {
                    OrbitIconBadge(systemName: "trash", color: OrbitDesign.coral, size: 44)
                    Text("合并结果将删除此文件").orbitFont(.headline)
                    Text("可以重新采用任一仍存在的版本来恢复文件。")
                        .orbitFont(.caption)
                        .foregroundStyle(OrbitDesign.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OrbitDesign.elevatedSurface)
            } else {
                MergeCodeEditor(
                    text: text,
                    isEditable: editable,
                    role: role,
                    focusLine: focusLine,
                    highlightedLines: selectedLineRange,
                    synchronizer: scrollSynchronizer,
                    synchronizedOffset: $synchronizedScrollOffset
                )
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transferRail(_ side: MergeTransferSide) -> some View {
        let isCurrent = side == .current
        let color = isCurrent ? OrbitDesign.blue : OrbitDesign.accent
        let title = isCurrent ? "采用当前" : "采用合入"
        let symbol = isCurrent ? "arrow.right" : "arrow.left"
        let choice: MergeConflictChoice = isCurrent ? .current : .incoming

        return VStack(spacing: 0) {
            Text("写入结果")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(OrbitDesign.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 44)
            Divider().overlay(OrbitDesign.separator)
            GeometryReader { geometry in
                VStack(spacing: 6) {
                    Button {
                        resolveSelected(using: choice)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: 34, height: 34)
                            .background(color.opacity(0.12), in: Circle())
                            .overlay { Circle().stroke(color.opacity(0.38), lineWidth: 1) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedBlock == nil)
                    .help("\(title)到合并结果")
                    .accessibilityLabel("\(title)到合并结果")

                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(selectedBlock == nil ? OrbitDesign.secondaryText : color)
                        .multilineTextAlignment(.center)
                }
                .position(x: geometry.size.width / 2, y: transferArrowY(in: geometry.size.height))
                .animation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18), value: selectedBlock?.id)
            }
        }
        .frame(width: 54)
        .background(OrbitDesign.sidebar)
        .overlay {
            HStack {
                Rectangle().fill(OrbitDesign.separator).frame(width: 1)
                Spacer()
                Rectangle().fill(OrbitDesign.separator).frame(width: 1)
            }
            .allowsHitTesting(false)
        }
        .opacity(selectedBlock == nil ? 0.55 : 1)
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18),
            value: selectedBlock?.id
        )
    }

    private func footer(_ document: GitMergeConflictDocument) -> some View {
        HStack(spacing: 10) {
            Button("整个文件采用当前") { useWholeFile(document.currentText) }
                .disabled(document.currentText == nil && deleteResult)
            Button("整个文件采用合入") { useWholeFile(document.incomingText) }
                .disabled(document.incomingText == nil && deleteResult)
            Button("在默认编辑器中打开") { appState.openConflictFileExternally(file) }
            Spacer()
            if hasConflictMarkers {
                Text(blocks.isEmpty ? "仍检测到不完整冲突标记" : "还剩 \(blocks.count) 处冲突")
                    .orbitFont(.caption, weight: .semibold)
                    .foregroundStyle(OrbitDesign.coral)
            }
            Button {
                saveResolution()
            } label: {
                Label(isSaving ? "正在保存…" : "标记已解决并暂存", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(hasConflictMarkers || isSaving)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(OrbitDesign.sidebar)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("正在按需读取三个版本…").orbitFont(.headline)
            Text("只加载当前冲突文件，避免占用不必要的内存。")
                .orbitFont(.caption)
                .foregroundStyle(OrbitDesign.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            OrbitIconBadge(systemName: "doc.badge.ellipsis", color: OrbitDesign.amber, size: 52)
            Text("无法在内置编辑器中打开").orbitFont(.title3, weight: .bold)
            Text(message)
                .orbitFont(.callout)
                .foregroundStyle(OrbitDesign.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("在默认编辑器中打开") { appState.openConflictFileExternally(file) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(OrbitDesign.secondaryText)
        .help(help)
        .accessibilityLabel(help)
    }

    private func readOnlyBinding(_ value: String) -> Binding<String> {
        Binding(get: { value }, set: { _ in })
    }

    private func moveSelection(by offset: Int) {
        selectedBlockIndex = min(max(selectedBlockIndex + offset, 0), max(blocks.count - 1, 0))
    }

    private var selectedLineRange: ClosedRange<Int>? {
        selectedBlock.map { $0.startLine...$0.endLine }
    }

    private func transferArrowY(in height: CGFloat) -> CGFloat {
        guard let selectedBlock else { return 46 }
        let lineHeight: CGFloat = 16
        let proposed = CGFloat(selectedBlock.startLine) * lineHeight - synchronizedScrollOffset + 30
        return min(max(proposed, 46), max(46, height - 46))
    }

    private func resolveSelected(using choice: MergeConflictChoice) {
        guard let selectedBlock else { return }
        resultText = MergeConflictParser.resolving(resultText, block: selectedBlock, using: choice)
        parseImmediately()
    }

    private func useWholeFile(_ text: String?) {
        deleteResult = text == nil
        resultText = text ?? ""
        parseImmediately()
    }

    private func scheduleParse(_ text: String) {
        parseTask?.cancel()
        parseTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let parsed = await Task.detached(priority: .utility) {
                (MergeConflictParser.blocks(in: text), MergeConflictParser.hasConflictMarkers(in: text))
            }.value
            guard !Task.isCancelled, resultText == text else { return }
            blocks = parsed.0
            hasConflictMarkers = parsed.1
            selectedBlockIndex = min(selectedBlockIndex, max(blocks.count - 1, 0))
        }
    }

    private func parseImmediately() {
        blocks = MergeConflictParser.blocks(in: resultText)
        hasConflictMarkers = MergeConflictParser.hasConflictMarkers(in: resultText)
        selectedBlockIndex = min(selectedBlockIndex, max(blocks.count - 1, 0))
    }

    private func loadDocument() async {
        do {
            let loaded = try await appState.loadMergeConflictDocument(for: file)
            document = loaded
            resultText = loaded.resultText
            deleteResult = !loaded.workingFileExists
            parseImmediately()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func saveResolution() {
        isSaving = true
        Task {
            let saved = await appState.completeMergeResolution(
                for: file,
                result: resultText,
                deleteResult: deleteResult
            )
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private enum MergeTransferSide {
    case current
    case incoming
}
