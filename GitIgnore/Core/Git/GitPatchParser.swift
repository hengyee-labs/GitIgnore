import Foundation

struct GitPatchDocument: Hashable, Sendable {
    let rawLines: [String]
    let headerLines: [String]
    let hunks: [GitPatchHunk]

    var addedLineCount: Int { hunks.reduce(0) { $0 + $1.addedLineCount } }
    var removedLineCount: Int { hunks.reduce(0) { $0 + $1.removedLineCount } }
}

struct GitPatchHunk: Identifiable, Hashable, Sendable {
    let id: String
    let header: String
    let lines: [String]
    let fileHeader: [String]

    init(id: String, header: String, lines: [String], fileHeader: [String]) {
        self.id = id
        self.header = header
        self.lines = lines
        self.fileHeader = fileHeader
    }

    var addedLineCount: Int {
        lines.dropFirst().count { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
    }

    var removedLineCount: Int {
        lines.dropFirst().count { $0.hasPrefix("-") && !$0.hasPrefix("---") }
    }

    var patchText: String {
        (fileHeader + lines).joined(separator: "\n") + "\n"
    }
}

enum GitPatchParser {
    static func parse(_ text: String) -> GitPatchDocument {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !rawLines.isEmpty else {
            return GitPatchDocument(rawLines: [], headerLines: [], hunks: [])
        }

        let firstHunkIndex = rawLines.firstIndex { $0.hasPrefix("@@") }
        let headerLines = firstHunkIndex.map { Array(rawLines[..<$0]) } ?? rawLines
        guard let firstHunkIndex else {
            return GitPatchDocument(rawLines: rawLines, headerLines: headerLines, hunks: [])
        }

        var hunks: [GitPatchHunk] = []
        var currentLines: [String] = []
        var hunkIndex = 0

        func appendCurrentHunk() {
            guard let header = currentLines.first, header.hasPrefix("@@") else { return }
            hunks.append(GitPatchHunk(
                id: "\(hunkIndex)-\(header)",
                header: header,
                lines: currentLines,
                fileHeader: headerLines
            ))
            hunkIndex += 1
        }

        for line in rawLines[firstHunkIndex...] {
            if line.hasPrefix("@@"), !currentLines.isEmpty {
                appendCurrentHunk()
                currentLines.removeAll(keepingCapacity: true)
            }
            currentLines.append(line)
        }
        appendCurrentHunk()

        return GitPatchDocument(rawLines: rawLines, headerLines: headerLines, hunks: hunks)
    }
}
