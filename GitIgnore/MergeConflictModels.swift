import Foundation

struct GitMergeConflictDocument: Sendable {
    let path: String
    let baseText: String?
    let currentText: String?
    let incomingText: String?
    let resultText: String
    let workingFileExists: Bool

    var loadedByteCount: Int {
        [baseText, currentText, incomingText, resultText]
            .compactMap { $0?.utf8.count }
            .reduce(0, +)
    }
}

struct MergeConflictBlock: Identifiable, Equatable, Sendable {
    let ordinal: Int
    let startLine: Int
    let endLine: Int
    let currentText: String
    let baseText: String?
    let incomingText: String

    var id: String { "\(ordinal)-\(startLine)-\(endLine)" }
}

enum MergeConflictChoice: Sendable {
    case current
    case incoming
    case both
}

enum GitBranchOperation: String, Sendable {
    case merge
    case rebase

    var title: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        }
    }
}

enum MergeConflictParser {
    static func blocks(in text: String) -> [MergeConflictBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MergeConflictBlock] = []
        var cursor = 0

        while cursor < lines.count {
            guard lines[cursor].hasPrefix("<<<<<<<") else {
                cursor += 1
                continue
            }

            let startLine = cursor
            cursor += 1
            let currentStart = cursor
            while cursor < lines.count,
                  !lines[cursor].hasPrefix("|||||||"),
                  !lines[cursor].hasPrefix("=======") {
                cursor += 1
            }
            guard cursor < lines.count else { break }
            let currentText = lines[currentStart..<cursor].joined(separator: "\n")

            var baseText: String?
            if lines[cursor].hasPrefix("|||||||") {
                cursor += 1
                let baseStart = cursor
                while cursor < lines.count, !lines[cursor].hasPrefix("=======") {
                    cursor += 1
                }
                guard cursor < lines.count else { break }
                baseText = lines[baseStart..<cursor].joined(separator: "\n")
            }

            guard lines[cursor].hasPrefix("=======") else { break }
            cursor += 1
            let incomingStart = cursor
            while cursor < lines.count, !lines[cursor].hasPrefix(">>>>>>>") {
                cursor += 1
            }
            guard cursor < lines.count else { break }

            blocks.append(MergeConflictBlock(
                ordinal: blocks.count,
                startLine: startLine,
                endLine: cursor,
                currentText: currentText,
                baseText: baseText,
                incomingText: lines[incomingStart..<cursor].joined(separator: "\n")
            ))
            cursor += 1
        }
        return blocks
    }

    static func hasConflictMarkers(in text: String) -> Bool {
        text.components(separatedBy: "\n").contains { line in
            line.hasPrefix("<<<<<<<") || line.hasPrefix("|||||||")
                || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>")
        }
    }

    static func resolving(
        _ text: String,
        block: MergeConflictBlock,
        using choice: MergeConflictChoice
    ) -> String {
        var lines = text.components(separatedBy: "\n")
        guard block.startLine >= 0, block.endLine < lines.count, block.startLine <= block.endLine else {
            return text
        }

        let replacement: String
        switch choice {
        case .current:
            replacement = block.currentText
        case .incoming:
            replacement = block.incomingText
        case .both:
            if block.currentText.isEmpty {
                replacement = block.incomingText
            } else if block.incomingText.isEmpty {
                replacement = block.currentText
            } else {
                replacement = block.currentText + "\n" + block.incomingText
            }
        }

        let replacementLines = replacement.isEmpty ? [] : replacement.components(separatedBy: "\n")
        lines.replaceSubrange(block.startLine...block.endLine, with: replacementLines)
        return lines.joined(separator: "\n")
    }
}

enum MergeEditorError: LocalizedError, Sendable {
    case repositoryUnavailable
    case invalidPath
    case fileTooLarge(path: String, bytes: Int)
    case binaryFile(path: String)
    case unresolvedMarkers

    var errorDescription: String? {
        switch self {
        case .repositoryUnavailable:
            "当前没有可用的仓库。"
        case .invalidPath:
            "冲突文件路径不在当前仓库中。"
        case let .fileTooLarge(path, bytes):
            "\(path) 大小为 \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))，请使用外部编辑器处理。"
        case let .binaryFile(path):
            "\(path) 不是可编辑的 UTF-8 文本文件。"
        case .unresolvedMarkers:
            "合并结果中仍有冲突标记，请先处理全部冲突。"
        }
    }
}
