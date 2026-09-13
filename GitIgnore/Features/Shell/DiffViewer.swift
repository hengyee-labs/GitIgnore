import AppKit
import SwiftUI

struct OrbitDiffViewer: View {
    @Environment(AppState.self) private var appState
    let diff: GitFileDiff
    var title: String?
    var expandsVertically: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wrapsLines = true
    @State private var didCopy = false
    @State private var visibleLineLimit: Int
    @State private var displayLines: [DiffDisplayLine]
    @State private var parserOldLine: Int?
    @State private var parserNewLine: Int?
    @State private var mode = DiffPresentationMode.unified
    @State private var searchText = ""
    @State private var ignoresWhitespace = false
    @State private var ignoresTrailingWhitespace = false
    @State private var showsInvisibleCharacters = false
    @State private var hidesMetadata = false
    @State private var contextLineCount = 3
    @State private var selectedSearchIndex = 0
    @State private var selectedChangeIndex = 0
    @State private var historyMode: DiffHistoryMode?
    @State private var isLoadingPage = false
    @State private var isCopying = false
    @State private var searchResult = DiffSearchResult()
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var pageTask: Task<Void, Never>?
    @State private var pageGeneration = UUID()
    @State private var pageStart = 0
    @State private var scrollTarget: Int?
    @State private var pageOrigin = DiffSearchMatch(line: 0, oldLine: nil, newLine: nil)
    @State private var previousPages: [DiffSearchMatch] = []

    private let linePageSize = 300

    init(diff: GitFileDiff, title: String? = nil, expandsVertically: Bool = false) {
        self.diff = diff
        self.title = title
        self.expandsVertically = expandsVertically
        let initial = DiffDisplayLine.parsePage(Array(diff.lines.prefix(300)), baseIndex: 0, oldLine: nil, newLine: nil)
        _visibleLineLimit = State(initialValue: min(diff.totalLineCount, initial.lines.count))
        _displayLines = State(initialValue: initial.lines)
        _parserOldLine = State(initialValue: initial.oldLine)
        _parserNewLine = State(initialValue: initial.newLine)
    }

    var body: some View {
        let pairs = splitRows
        let comparisons = pairs.reduce(into: [Int: String]()) { result, pair in
            if let left = pair.left, let right = pair.right,
               left.kind == .deletion, right.kind == .addition {
                result[left.id] = right.content
                result[right.id] = left.content
            }
        }
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(OrbitDesign.separator)

            ScrollViewReader { proxy in
                ScrollView(scrollAxes, showsIndicators: true) {
                    if mode == .unified {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredLines) { line in
                                DiffCodeLine(
                                    line: line,
                                    wrapsLines: wrapsLines,
                                    searchText: searchText,
                                    showsInvisibleCharacters: showsInvisibleCharacters,
                                    pathExtension: (diff.path as NSString).pathExtension,
                                    comparedWith: comparisons[line.id]
                                )
                                .id(line.id)
                            }
                        }
                        .frame(minWidth: wrapsLines ? 0 : 680, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(pairs) { row in
                                SplitDiffRow(
                                    row: row,
                                    searchText: searchText,
                                    showsInvisibleCharacters: showsInvisibleCharacters
                                )
                                .id(row.id)
                            }
                        }
                        .frame(minWidth: 920, alignment: .leading)
                    }
                }
                .onChange(of: selectedSearchIndex) { _, _ in scrollToSelectedSearch(using: proxy) }
                .onChange(of: selectedChangeIndex) { _, _ in scrollToSelectedChange(using: proxy) }
                .onChange(of: searchText) { _, _ in
                    selectedSearchIndex = 0
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            .frame(minHeight: 220, idealHeight: expandsVertically ? 520 : 320, maxHeight: expandsVertically ? .infinity : 440)
            .background(OrbitDesign.elevatedSurface)

            if pageStart > 0 {
                HStack {
                    Button(AppLanguage.text("上一页", "Previous Page"), systemImage: "chevron.up") {
                        guard let previous = previousPages.popLast() else { return }
                        loadPage(start: previous.line, old: previous.oldLine, new: previous.newLine, remember: false)
                    }.disabled(previousPages.isEmpty)
                    Spacer()
                    Button(AppLanguage.text("返回 Diff 开头", "Back to Diff Start"), systemImage: "arrow.up.to.line") {
                        previousPages = []
                        loadPage(start: 0, old: nil, new: nil, remember: false)
                    }
                }
                .buttonStyle(.plain).padding(8)
            }
            if let searchError {
                Text(searchError).orbitFont(.caption2).foregroundStyle(OrbitDesign.coral).padding(8)
            }
            if searchResult.truncatedLines > 0 {
                Text(AppLanguage.text("\(searchResult.truncatedLines) 个超长行仅搜索前 256 KB", "\(searchResult.truncatedLines) oversized lines searched within the first 256 KB"))
                    .orbitFont(.caption2).foregroundStyle(OrbitDesign.amber).padding(8)
            }
            if searchResult.total > searchResult.matches.count {
                Text(AppLanguage.text("仅导航前 5,000 个匹配行", "Navigation is limited to the first 5,000 matching lines"))
                    .orbitFont(.caption2).foregroundStyle(OrbitDesign.amber).padding(8)
            }
            if hasMoreLines {
                Divider().overlay(OrbitDesign.separator)
                Button {
                    showMoreLines()
                } label: {
                    Label(AppLanguage.text("下一页 · \(min(linePageSize, totalLineCount - visibleLineLimit)) 行", "Next Page · \(min(linePageSize, totalLineCount - visibleLineLimit)) lines"), systemImage: "chevron.down")
                        .orbitFont(.caption, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OrbitDesign.accent)
                .background(OrbitDesign.surface)
                .disabled(isLoadingPage)
            } else if isLineBudgetCapped {
                Divider().overlay(OrbitDesign.separator)
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(OrbitDesign.amber)
                    Text(AppLanguage.text("已到轻量阅读上限，可用右上角复制完整 Diff", "Lightweight reader limit reached. Use copy to get the full diff."))
                        .orbitFont(.caption2, weight: .semibold)
                        .foregroundStyle(OrbitDesign.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(OrbitDesign.surface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(OrbitDesign.separator, lineWidth: 1)
        }
        .onChange(of: diff.revision) { _, _ in
            pageTask?.cancel()
            pageGeneration = UUID()
            pageStart = 0
            previousPages = []
            pageOrigin = DiffSearchMatch(line: 0, oldLine: nil, newLine: nil)
            isLoadingPage = false
            let initial = DiffDisplayLine.parsePage(Array(diff.lines.prefix(linePageSize)), baseIndex: 0, oldLine: nil, newLine: nil)
            visibleLineLimit = min(diff.totalLineCount, initial.lines.count)
            displayLines = initial.lines
            parserOldLine = initial.oldLine
            parserNewLine = initial.newLine
        }
        .onDisappear { pageTask?.cancel(); pageGeneration = UUID() }
        .task(id: "\(diff.revision)|\(searchText)") {
            searchResult = DiffSearchResult()
            searchError = nil
            selectedSearchIndex = 0
            selectedChangeIndex = 0
            guard !searchText.isEmpty else { isSearching = false; return }
            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(180))
                let reader = diff.pagedReader
                let lines = reader == nil ? diff.lines : []
                let query = searchText
                let task = Task.detached(priority: .utility) {
                    if let reader { return try reader.search(query) }
                    return try DiffTextTools.search(file: nil, lines: lines, query: query)
                }
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                searchResult = result
                isSearching = false
                revealSearchMatch()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                isSearching = false
                searchError = error.localizedDescription
            }
        }
        .sheet(item: $historyMode) { item in
            DiffFileHistoryView(path: diff.path, showsBlame: item == .blame)
                .environment(appState)
        }
    }

    private var totalLineCount: Int { diff.totalLineCount }
    private var hasMoreLines: Bool { visibleLineLimit < totalLineCount }
    private var isLineBudgetCapped: Bool { totalLineCount < diff.lines.count }
    private var scrollAxes: Axis.Set {
        mode == .unified && wrapsLines ? .vertical : [.vertical, .horizontal]
    }

    private func showMoreLines() {
        guard !isLoadingPage else { return }
        loadPage(start: visibleLineLimit, old: parserOldLine, new: parserNewLine)
    }

    private func loadPage(start: Int, old: Int?, new: Int?, remember: Bool = true) {
        pageTask?.cancel()
        let generation = UUID()
        pageGeneration = generation
        isLoadingPage = true
        let reader = diff.pagedReader
        let fallback = reader == nil ? Array(diff.lines.dropFirst(start).prefix(linePageSize)) : []
        pageTask = Task { @MainActor in
            let page: [String]
            if let reader {
                page = await Task.detached(priority: .userInitiated) {
                    reader.readLines(start: start, count: 300)
                }.value
            } else {
                page = fallback
            }
            guard !Task.isCancelled, generation == pageGeneration else { return }
            guard !page.isEmpty else {
                isLoadingPage = false
                searchError = AppLanguage.text("此页读取失败，请重试。", "Could not read this page. Please retry.")
                return
            }
            let parsed = DiffDisplayLine.parsePage(
                page,
                baseIndex: start,
                oldLine: old,
                newLine: new
            )
            visibleLineLimit = start + page.count
            if remember, pageOrigin.line != start {
                previousPages.append(pageOrigin)
                if previousPages.count > 1_000 { previousPages.removeFirst() }
            }
            pageOrigin = DiffSearchMatch(line: start, oldLine: old, newLine: new)
            pageStart = start
            displayLines = parsed.lines
            parserOldLine = parsed.oldLine
            parserNewLine = parsed.newLine
            isLoadingPage = false
            scrollTarget = start
        }
    }

    private var filteredLines: [DiffDisplayLine] {
        if !searchText.isEmpty { return displayLines }
        let contextIDs = visibleContextIDs
        let ignoredIDs = whitespaceOnlyChangeIDs
        return displayLines.filter { line in
            if hidesMetadata && line.kind == .metadata { return false }
            if contextLineCount < 20, line.kind == .context, !contextIDs.contains(line.id) { return false }
            if ignoresWhitespace && ignoredIDs.contains(line.id) { return false }
            return true
        }
    }

    private func revealSearchMatch() {
        guard searchResult.matches.indices.contains(selectedSearchIndex) else { return }
        let match = searchResult.matches[selectedSearchIndex]
        loadPage(start: match.line, old: match.oldLine, new: match.newLine)
    }

    private var changeAnchors: [DiffDisplayLine] { filteredLines.filter { $0.kind == .hunk } }

    private var visibleContextIDs: Set<Int> {
        guard contextLineCount < 20 else { return Set(displayLines.map(\.id)) }
        var ids: Set<Int> = []
        for index in displayLines.indices where displayLines[index].kind.isChangeAnchor {
            let lower = max(displayLines.startIndex, index - contextLineCount)
            let upper = min(displayLines.endIndex - 1, index + contextLineCount)
            ids.formUnion(displayLines[lower...upper].map(\.id))
        }
        return ids
    }

    private var whitespaceOnlyChangeIDs: Set<Int> {
        guard ignoresWhitespace else { return [] }
        var ids: Set<Int> = []
        for pair in SplitDiffPair.make(from: displayLines) {
            guard let left = pair.left, let right = pair.right,
                  left.kind == .deletion, right.kind == .addition else { continue }
            if normalizedWhitespace(left.content) == normalizedWhitespace(right.content) {
                ids.formUnion([left.id, right.id])
            }
        }
        return ids
    }

    private func normalizedWhitespace(_ value: String) -> String {
        if ignoresTrailingWhitespace {
            return value.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        }
        return value.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private var splitRows: [SplitDiffPair] { SplitDiffPair.make(from: filteredLines) }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title ?? (diff.isStaged ? AppLanguage.text("已暂存内容", "Staged Changes") : AppLanguage.text("工作区内容", "Working Changes")))
                        .orbitFont(.caption, weight: .bold)
                        .foregroundStyle(OrbitDesign.primaryText)
                    HStack(spacing: 6) {
                        Label("+\(diff.document.addedLineCount)", systemImage: "plus")
                            .foregroundStyle(OrbitDesign.accent)
                        Label("-\(diff.document.removedLineCount)", systemImage: "minus")
                            .foregroundStyle(OrbitDesign.coral)
                    }
                    .font(.caption2.monospacedDigit().weight(.semibold))
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Button { moveChange(by: -1) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel(AppLanguage.text("上一个修改区块", "Previous Change"))
                    Button { moveChange(by: 1) } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel(AppLanguage.text("下一个修改区块", "Next Change"))
                }
                .buttonStyle(.plain)
                .orbitFont(.caption2, weight: .bold)
                .foregroundStyle(OrbitDesign.secondaryText)
                .disabled(changeAnchors.isEmpty)
                .help("上一个或下一个修改区块")
                Text(AppLanguage.text("本页修改 \(changeAnchors.count)", "\(changeAnchors.count) changes on page"))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(changeAnchors.isEmpty ? OrbitDesign.tertiaryText : OrbitDesign.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OrbitDesign.elevatedSurface, in: Capsule())
                Text(AppLanguage.text("\(min(pageStart + 1, totalLineCount))–\(min(visibleLineLimit, totalLineCount)) / \(totalLineCount) 行",
                                      "Lines \(min(pageStart + 1, totalLineCount))–\(min(visibleLineLimit, totalLineCount)) / \(totalLineCount)"))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(OrbitDesign.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OrbitDesign.elevatedSurface, in: Capsule())
            }
            .padding(.horizontal, 11)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().overlay(OrbitDesign.separator.opacity(0.7))

            HStack(spacing: 7) {
                Picker("显示方式", selection: $mode) {
                    ForEach(DiffPresentationMode.allCases) { item in
                        Image(systemName: item.symbol)
                            .accessibilityLabel(item.accessibilityTitle)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 76)
                .help(mode.accessibilityTitle)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OrbitDesign.secondaryText)
                    TextField("搜索变更内容", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        if isSearching { ProgressView().controlSize(.mini) }
                        Text("\(searchResult.matches.isEmpty ? 0 : selectedSearchIndex + 1)/\(searchResult.total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(OrbitDesign.secondaryText)
                        Button { moveSearch(by: -1) } label: {
                            Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain).disabled(searchResult.matches.isEmpty || isSearching)
                        .help(AppLanguage.text("上一个匹配", "Previous Match"))
                        .accessibilityLabel(AppLanguage.text("上一个匹配", "Previous Match"))
                        Button { moveSearch(by: 1) } label: {
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain).disabled(searchResult.matches.isEmpty || isSearching)
                        .help(AppLanguage.text("下一个匹配", "Next Match"))
                        .accessibilityLabel(AppLanguage.text("下一个匹配", "Next Match"))
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(OrbitDesign.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 100, maxWidth: .infinity)
                .frame(height: 28)
                .background(OrbitDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(OrbitDesign.separator, lineWidth: 1) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("在 Diff 中搜索")

                Menu {
                    Toggle("忽略空格变化", isOn: $ignoresWhitespace)
                    Toggle("只忽略行尾空格", isOn: $ignoresTrailingWhitespace)
                        .disabled(!ignoresWhitespace)
                    Toggle("显示不可见字符", isOn: $showsInvisibleCharacters)
                    Toggle("隐藏文件元信息", isOn: $hidesMetadata)
                    Picker("上下文行数", selection: $contextLineCount) {
                        Text("1 行").tag(1)
                        Text("3 行").tag(3)
                        Text("5 行").tag(5)
                        Text("10 行").tag(10)
                        Text("全部").tag(20)
                    }
                    Divider()
                    Button("查看文件历史", systemImage: "clock.arrow.circlepath") { historyMode = .history }
                    Button("查看行级 Blame", systemImage: "person.text.rectangle") { historyMode = .blame }
                } label: {
                    toolbarIcon(
                        "line.3.horizontal.decrease",
                        isActive: ignoresWhitespace || hidesMetadata || showsInvisibleCharacters || contextLineCount != 3
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Diff 阅读选项")

                Button {
                    wrapsLines.toggle()
                } label: {
                    toolbarIcon("text.word.spacing", isActive: wrapsLines)
                }
                .buttonStyle(.plain)
                .help(wrapsLines ? "关闭自动换行" : "开启自动换行")

                Button {
                    copyDiff()
                } label: {
                    toolbarIcon(isCopying ? "hourglass" : (didCopy ? "checkmark" : "doc.on.doc"), isActive: didCopy || isCopying)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "已复制" : "复制变更内容")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
        .background(OrbitDesign.surface)
    }

    private func toolbarIcon(_ symbol: String, isActive: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? OrbitDesign.accent : OrbitDesign.secondaryText)
            .frame(width: 28, height: 28)
            .background(isActive ? OrbitDesign.accent.opacity(0.10) : OrbitDesign.elevatedSurface,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(OrbitDesign.separator, lineWidth: 1) }
    }

    private func copyDiff() {
        guard !isCopying else { return }
        isCopying = true
        let reader = diff.pagedReader
        Task {
            let fullText = await Task.detached(priority: .utility) {
                reader?.readAllText() ?? diff.text
            }.value
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullText, forType: .string)
                isCopying = false
                withAnimation(reduceMotion ? .linear(duration: 0.08) : .easeOut(duration: 0.18)) {
                    didCopy = true
                }
            }
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run { didCopy = false }
        }
    }

    private func moveSearch(by offset: Int) {
        guard !searchResult.matches.isEmpty else { return }
        selectedSearchIndex = (selectedSearchIndex + offset + searchResult.matches.count) % searchResult.matches.count
    }

    private func scrollToSelectedSearch(using proxy: ScrollViewProxy) {
        revealSearchMatch()
    }

    private func moveChange(by offset: Int) {
        guard !changeAnchors.isEmpty else { return }
        selectedChangeIndex = (selectedChangeIndex + offset + changeAnchors.count) % changeAnchors.count
    }

    private func scrollToSelectedChange(using proxy: ScrollViewProxy) {
        guard changeAnchors.indices.contains(selectedChangeIndex) else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18)) {
            proxy.scrollTo(changeAnchors[selectedChangeIndex].id, anchor: .top)
        }
    }
}

private enum DiffPresentationMode: String, CaseIterable, Identifiable {
    case unified
    case sideBySide
    var id: Self { self }
    var symbol: String { self == .unified ? "rectangle.grid.1x2" : "rectangle.split.2x1" }
    var accessibilityTitle: String { self == .unified ? AppLanguage.text("统一视图", "Unified") : AppLanguage.text("并排视图", "Side by Side") }
}

private enum DiffHistoryMode: String, Identifiable {
    case history
    case blame
    var id: Self { self }
}

private struct DiffCodeLine: View {
    let line: DiffDisplayLine
    let wrapsLines: Bool
    let searchText: String
    let showsInvisibleCharacters: Bool
    let pathExtension: String
    let comparedWith: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)

            Text(line.marker)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(line.foreground)
                .frame(width: 18, alignment: .center)

            highlightedText(displayContent)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(line.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: !wrapsLines, vertical: true)
                .frame(maxWidth: wrapsLines ? .infinity : nil, alignment: .leading)
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, line.kind == .hunk ? 6 : 2.5)
        .background(line.background)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(line.accent)
                .frame(width: line.kind == .context || line.kind == .metadata ? 0 : 2)
        }
    }

    private var displayContent: String {
        let value = line.content.isEmpty ? " " : line.content
        guard showsInvisibleCharacters else { return value }
        return value.replacingOccurrences(of: "\t", with: "→   ").replacingOccurrences(of: " ", with: "·")
    }

    private func highlightedText(_ value: String) -> Text {
        guard !searchText.isEmpty,
              let range = value.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) else {
            if let comparedWith {
                return InlineDifference.text(value, comparedWith: comparedWith, color: line.accent)
            }
            return SyntaxLineHighlighter.text(value, pathExtension: pathExtension)
        }
        return Text(value[..<range.lowerBound])
            + Text(value[range]).bold().foregroundColor(OrbitDesign.amber)
            + Text(value[range.upperBound...])
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(OrbitDesign.secondaryText.opacity(0.75))
            .frame(width: 34, alignment: .trailing)
            .padding(.trailing, 7)
            .background(OrbitDesign.surface.opacity(0.72))
    }
}

private enum SyntaxLineHighlighter {
    private static let expression = try? NSRegularExpression(
        pattern: "\\b(class|struct|enum|protocol|extension|func|let|var|if|else|guard|switch|case|for|while|return|throw|try|await|async|public|private|protected|static|final|import|package|interface|const|function|new|true|false|null|nil)\\b"
    )

    static func text(_ value: String, pathExtension: String) -> Text {
        let supported = ["swift", "kt", "java", "js", "jsx", "ts", "tsx", "go", "rs", "py", "c", "cpp", "h"]
        guard supported.contains(pathExtension.lowercased()), let expression else { return Text(value) }
        if value.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            || value.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return Text(value).foregroundColor(OrbitDesign.secondaryText)
        }
        let matches = expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
        guard !matches.isEmpty else { return Text(value) }
        var result = Text("")
        var cursor = value.startIndex
        for match in matches {
            guard let range = Range(match.range, in: value) else { continue }
            result = result + Text(value[cursor..<range.lowerBound])
            result = result + Text(value[range]).foregroundColor(OrbitDesign.violet).bold()
            cursor = range.upperBound
        }
        return result + Text(value[cursor...])
    }
}

private struct SplitDiffPair: Identifiable {
    let id: Int
    let left: DiffDisplayLine?
    let right: DiffDisplayLine?

    static func make(from lines: [DiffDisplayLine]) -> [SplitDiffPair] {
        let kinds: [Character] = lines.map { $0.kind == .deletion ? "-" : $0.kind == .addition ? "+" : " " }
        return DiffTextTools.pairs(kinds: kinds).map { left, right in
            let lhs = left.map { lines[$0] }
            let rhs = right.map { lines[$0] }
            return SplitDiffPair(id: lhs?.id ?? rhs!.id, left: lhs, right: rhs)
        }
    }
}

private struct SplitDiffRow: View {
    let row: SplitDiffPair
    let searchText: String
    let showsInvisibleCharacters: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            side(row.left, isLeft: true)
            Rectangle().fill(OrbitDesign.separator).frame(width: 1)
            side(row.right, isLeft: false)
        }
    }

    private func side(_ line: DiffDisplayLine?, isLeft: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.flatMap { isLeft ? $0.oldNumber : $0.newNumber }.map(String.init) ?? "")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(OrbitDesign.secondaryText).frame(width: 38, alignment: .trailing).padding(.trailing, 7)
            inlineText(line, isLeft: isLeft)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(line?.foreground ?? OrbitDesign.secondaryText)
                .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                .padding(.leading, 8).padding(.trailing, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .background(line?.background ?? Color.clear)
        .accessibilityLabel(line?.content ?? "空行")
    }

    private func inlineText(_ line: DiffDisplayLine?, isLeft: Bool) -> Text {
        guard let line else { return Text(" ") }
        var value = line.content
        if showsInvisibleCharacters {
            value = value.replacingOccurrences(of: "\t", with: "→   ").replacingOccurrences(of: " ", with: "·")
        }
        guard let other = isLeft ? row.right : row.left,
              line.kind == (isLeft ? .deletion : .addition),
              other.kind == (isLeft ? .addition : .deletion) else {
            return Text(value)
        }
        var otherValue = other.content
        if showsInvisibleCharacters {
            otherValue = otherValue.replacingOccurrences(of: "\t", with: "→   ").replacingOccurrences(of: " ", with: "·")
        }
        let color = isLeft ? OrbitDesign.coral : OrbitDesign.accent
        return InlineDifference.text(value, comparedWith: otherValue, color: color)
    }
}

private enum InlineDifference {
    static func text(_ value: String, comparedWith other: String, color: Color) -> Text {
        let ranges = DiffTextTools.changedRanges(in: value, comparedWith: other)
        guard !ranges.isEmpty else { return Text(value) }
        var text = Text("")
        var cursor = value.startIndex
        for range in ranges {
            text = text + Text(value[cursor..<range.lowerBound]) + Text(value[range]).bold().foregroundColor(color)
            cursor = range.upperBound
        }
        return text + Text(value[cursor...])
    }
}

private struct DiffDisplayLine: Identifiable {
    enum Kind {
        case metadata
        case hunk
        case addition
        case deletion
        case context

        var isChangeAnchor: Bool {
            self == .addition || self == .deletion || self == .hunk
        }
    }

    let id: Int
    let oldNumber: Int?
    let newNumber: Int?
    let marker: String
    let content: String
    let kind: Kind

    var foreground: Color {
        switch kind {
        case .addition: OrbitDesign.accent
        case .deletion: OrbitDesign.coral
        case .hunk: OrbitDesign.violet
        case .metadata: OrbitDesign.secondaryText
        case .context: OrbitDesign.primaryText.opacity(0.82)
        }
    }

    var background: Color {
        switch kind {
        case .addition: OrbitDesign.accent.opacity(0.105)
        case .deletion: OrbitDesign.coral.opacity(0.105)
        case .hunk: OrbitDesign.violet.opacity(0.09)
        case .metadata: OrbitDesign.surface.opacity(0.45)
        case .context: Color.clear
        }
    }

    var accent: Color {
        switch kind {
        case .addition: OrbitDesign.accent
        case .deletion: OrbitDesign.coral
        case .hunk: OrbitDesign.violet
        case .metadata, .context: Color.clear
        }
    }

    static func parse(_ source: [String]) -> [DiffDisplayLine] {
        parsePage(source, baseIndex: 0, oldLine: nil, newLine: nil).lines
    }

    static func parsePage(
        _ source: [String],
        baseIndex: Int,
        oldLine initialOldLine: Int?,
        newLine initialNewLine: Int?
    ) -> (lines: [DiffDisplayLine], oldLine: Int?, newLine: Int?) {
        var oldLine = initialOldLine
        var newLine = initialNewLine
        var result: [DiffDisplayLine] = []

        for (index, rawLine) in source.enumerated() {
            let rawLine = rawLine.utf8.count > 16_384
                ? String(decoding: rawLine.utf8.prefix(16_384), as: UTF8.self) + " …"
                : rawLine
            let absoluteIndex = baseIndex + index
            if rawLine.hasPrefix("@@") {
                let rangeParts = rawLine.split(separator: " ")
                if rangeParts.count >= 3 {
                    oldLine = startLine(in: String(rangeParts[1]))
                    newLine = startLine(in: String(rangeParts[2]))
                }
                result.append(DiffDisplayLine(id: absoluteIndex, oldNumber: nil, newNumber: nil, marker: "◆", content: rawLine, kind: .hunk))
            } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                result.append(DiffDisplayLine(id: absoluteIndex, oldNumber: nil, newNumber: newLine, marker: "+", content: String(rawLine.dropFirst()), kind: .addition))
                newLine = newLine.map { $0 + 1 }
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                result.append(DiffDisplayLine(id: absoluteIndex, oldNumber: oldLine, newNumber: nil, marker: "−", content: String(rawLine.dropFirst()), kind: .deletion))
                oldLine = oldLine.map { $0 + 1 }
            } else if rawLine.hasPrefix("diff ") || rawLine.hasPrefix("index ") || rawLine.hasPrefix("---") || rawLine.hasPrefix("+++") || rawLine.hasPrefix("\\") {
                result.append(DiffDisplayLine(id: absoluteIndex, oldNumber: nil, newNumber: nil, marker: "", content: rawLine, kind: .metadata))
            } else {
                let content = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
                result.append(DiffDisplayLine(id: absoluteIndex, oldNumber: oldLine, newNumber: newLine, marker: "", content: content, kind: .context))
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            }
        }
        return (result, oldLine, newLine)
    }

    private static func startLine(in range: String) -> Int? {
        let trimmed = range.dropFirst()
        return Int(trimmed.split(separator: ",", maxSplits: 1).first ?? "")
    }
}
