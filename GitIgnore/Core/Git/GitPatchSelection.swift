import Foundation

struct GitSelectablePatchLine: Identifiable, Hashable, Sendable {
    let index: Int
    let text: String
    let oldLine: Int?
    let newLine: Int?

    var id: Int { index }
    var isAddition: Bool { text.hasPrefix("+") && !text.hasPrefix("+++") }
    var isRemoval: Bool { text.hasPrefix("-") && !text.hasPrefix("---") }
    var isSelectable: Bool { isAddition || isRemoval }
    var isNoNewlineMetadata: Bool { text.hasPrefix("\\ No newline") }

    var displayText: String {
        if isAddition || isRemoval || text.hasPrefix(" ") { return String(text.dropFirst()) }
        return text
    }

    var accessibilityDescription: String {
        if isAddition { return "新增，新行 \(newLine.map(String.init) ?? "未知")，\(displayText)" }
        if isRemoval { return "删除，旧行 \(oldLine.map(String.init) ?? "未知")，\(displayText)" }
        return "上下文，旧行 \(oldLine.map(String.init) ?? "未知")，新行 \(newLine.map(String.init) ?? "未知")，\(displayText)"
    }
}

enum GitPatchSelectionError: LocalizedError {
    case invalidHeader
    case noSelectedChanges

    var errorDescription: String? {
        switch self {
        case .invalidHeader: "无法解析该修改区块的行号。"
        case .noSelectedChanges: "请至少选择一行新增或删除内容。"
        }
    }
}

extension GitPatchHunk {
    var selectableLines: [GitSelectablePatchLine] {
        selectableLines(limit: nil)
    }

    var selectableLineCount: Int {
        max(lines.count - 1, 0)
    }

    func selectableLines(limit: Int?) -> [GitSelectablePatchLine] {
        guard let range = parsedRange else { return [] }
        var oldLine = range.oldStart
        var newLine = range.newStart
        var result: [GitSelectablePatchLine] = []
        result.reserveCapacity(min(selectableLineCount, limit ?? selectableLineCount))

        for (index, text) in lines.dropFirst().enumerated() {
            if let limit, result.count >= limit { break }
            let line: GitSelectablePatchLine
            if text.hasPrefix("+") && !text.hasPrefix("+++") {
                line = GitSelectablePatchLine(index: index, text: text, oldLine: nil, newLine: newLine)
                newLine += 1
            } else if text.hasPrefix("-") && !text.hasPrefix("---") {
                line = GitSelectablePatchLine(index: index, text: text, oldLine: oldLine, newLine: nil)
                oldLine += 1
            } else {
                line = GitSelectablePatchLine(index: index, text: text, oldLine: oldLine, newLine: newLine)
                if !text.hasPrefix("\\ No newline") {
                    oldLine += 1
                    newLine += 1
                }
            }
            result.append(line)
        }
        return result
    }

    func patchText(selecting selectedIndices: Set<Int>) throws -> String {
        guard let range = parsedRange else { throw GitPatchSelectionError.invalidHeader }
        guard !selectedIndices.isEmpty else { throw GitPatchSelectionError.noSelectedChanges }

        var oldLine = range.oldStart
        var newLine = range.newStart
        var transformed: [TransformedPatchLine] = []
        var previousWasIncluded = false

        for (index, text) in lines.dropFirst().enumerated() {
            let oldBefore = oldLine
            let newBefore = newLine
            let isAddition = text.hasPrefix("+") && !text.hasPrefix("+++")
            let isRemoval = text.hasPrefix("-") && !text.hasPrefix("---")
            let selected = selectedIndices.contains(index) && (isAddition || isRemoval)

            if isAddition {
                if selected {
                    transformed.append(.init(text: text, oldBefore: oldBefore, newBefore: newBefore, selected: true))
                    newLine += 1
                    previousWasIncluded = true
                } else {
                    previousWasIncluded = false
                }
            } else if isRemoval {
                oldLine += 1
                let output = selected ? text : " " + String(text.dropFirst())
                transformed.append(.init(text: output, oldBefore: oldBefore, newBefore: newBefore, selected: selected))
                if !selected { newLine += 1 }
                previousWasIncluded = true
            } else if text.hasPrefix("\\ No newline") {
                if previousWasIncluded {
                    transformed.append(.init(text: text, oldBefore: oldBefore, newBefore: newBefore, selected: false))
                }
            } else {
                oldLine += 1
                newLine += 1
                transformed.append(.init(text: text, oldBefore: oldBefore, newBefore: newBefore, selected: false))
                previousWasIncluded = true
            }
        }

        guard let firstSelected = transformed.firstIndex(where: \.selected),
              let lastSelected = transformed.lastIndex(where: \.selected) else {
            throw GitPatchSelectionError.noSelectedChanges
        }
        let lower = max(0, firstSelected - 3)
        let upper = min(transformed.count - 1, lastSelected + 3)
        let window = Array(transformed[lower...upper])
        guard let first = window.first else { throw GitPatchSelectionError.noSelectedChanges }

        let oldCount = window.count { !$0.text.hasPrefix("+") && !$0.text.hasPrefix("\\ No newline") }
        let newCount = window.count { !$0.text.hasPrefix("-") && !$0.text.hasPrefix("\\ No newline") }
        let suffix = header.components(separatedBy: "@@").dropFirst(2).joined(separator: "@@")
        let newHeader = "@@ -\(first.oldBefore),\(oldCount) +\(first.newBefore),\(newCount) @@\(suffix)"
        return (fileHeader + [newHeader] + window.map(\.text)).joined(separator: "\n") + "\n"
    }

    private var parsedRange: (oldStart: Int, newStart: Int)? {
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let oldRange = Range(match.range(at: 1), in: header),
              let newRange = Range(match.range(at: 2), in: header),
              let oldStart = Int(header[oldRange]),
              let newStart = Int(header[newRange]) else { return nil }
        return (oldStart, newStart)
    }
}

private struct TransformedPatchLine {
    let text: String
    let oldBefore: Int
    let newBefore: Int
    let selected: Bool
}
