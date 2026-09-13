import Foundation

struct DiffSearchMatch: Sendable {
    let line: Int
    let oldLine: Int?
    let newLine: Int?
}

struct DiffSearchResult: Sendable {
    var matches: [DiffSearchMatch] = []
    var total = 0
    var truncatedLines = 0
}

enum DiffTextTools {
    static let lineByteLimit = 256 * 1024

    /// A bounded line scanner shared by disk search and page reads. Oversized
    /// lines keep their real line identity even when their preview is shortened.
    static func scan(_ url: URL, offset: UInt64 = 0, visit: (String, Bool) throws -> Bool) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var pending = Data()
        var truncated = false
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            var start = chunk.startIndex
            for end in chunk.indices where chunk[end] == 10 {
                let part = chunk[start..<end]
                let remaining = max(0, lineByteLimit - pending.count)
                truncated = truncated || part.count > remaining
                pending.append(contentsOf: part.prefix(remaining))
                if try !visit(String(decoding: pending, as: UTF8.self), truncated) { return }
                pending.removeAll(keepingCapacity: true)
                truncated = false
                start = end + 1
            }
            let part = chunk[start...]
            let remaining = max(0, lineByteLimit - pending.count)
            truncated = truncated || part.count > remaining
            pending.append(contentsOf: part.prefix(remaining))
        }
        if !pending.isEmpty || truncated { _ = try visit(String(decoding: pending, as: UTF8.self), truncated) }
    }

    static func search(file: URL?, lines: [String], query: String) throws -> DiffSearchResult {
        guard !query.isEmpty else { return DiffSearchResult() }
        var result = DiffSearchResult()
        var line = 0
        var old: Int?
        var new: Int?
        func visit(_ text: String, _ truncated: Bool) throws -> Bool {
            try Task.checkCancellation()
            if truncated { result.truncatedLines += 1 }
            if text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                result.total += 1
                if result.matches.count < 5_000 {
                    result.matches.append(DiffSearchMatch(line: line, oldLine: old, newLine: new))
                }
            }
            advance(text, old: &old, new: &new)
            line += 1
            return true
        }
        if let file { try scan(file, visit: visit) }
        else { for text in lines { _ = try visit(text, false) } }
        return result
    }

    static func advance(_ text: String, old: inout Int?, new: inout Int?) {
        if text.hasPrefix("@@ ") {
            let fields = text.split(separator: " ")
            if fields.count >= 3 {
                old = fields[1].dropFirst().split(separator: ",").first.flatMap { Int($0) }
                new = fields[2].dropFirst().split(separator: ",").first.flatMap { Int($0) }
            }
        } else if text.hasPrefix("diff --git") { old = nil; new = nil }
        else if text.hasPrefix("+"), !text.hasPrefix("+++") { new = new.map { $0 + 1 } }
        else if text.hasPrefix("-"), !text.hasPrefix("---") { old = old.map { $0 + 1 } }
        else if text.hasPrefix(" ") { old = old.map { $0 + 1 }; new = new.map { $0 + 1 } }
    }

    /// Pair entire replacement runs, never the final deletion with the first addition.
    static func pairs(kinds: [Character]) -> [(Int?, Int?)] {
        var result: [(Int?, Int?)] = []
        var index = 0
        while index < kinds.count {
            if kinds[index] == "-" || kinds[index] == "+" {
                var removed: [Int] = []
                var added: [Int] = []
                while index < kinds.count, kinds[index] == "-" { removed.append(index); index += 1 }
                while index < kinds.count, kinds[index] == "+" { added.append(index); index += 1 }
                for position in 0..<max(removed.count, added.count) {
                    result.append((position < removed.count ? removed[position] : nil,
                                   position < added.count ? added[position] : nil))
                }
            } else { result.append((index, index)); index += 1 }
        }
        return result
    }

    /// Swift's collection diff supplies disjoint grapheme edits; cap work on minified lines.
    static func changedRanges(in value: String, comparedWith other: String) -> [Range<String.Index>] {
        guard value != other else { return [] }
        guard value.utf8.count <= 4096, other.utf8.count <= 4096 else { return [] }
        let before = Array(value)
        let after = Array(other)
        guard before.count * after.count <= 250_000 else { return [] }
        let offsets = after.difference(from: before).compactMap { change -> Int? in
            if case let .remove(offset, _, _) = change { return offset }
            return nil
        }.sorted()
        var groups: [Range<Int>] = []
        for offset in offsets {
            if let last = groups.last, last.upperBound == offset {
                groups[groups.count - 1] = last.lowerBound..<(offset + 1)
            } else { groups.append(offset..<(offset + 1)) }
        }
        let indices = Array(value.indices) + [value.endIndex]
        return groups.map { indices[$0.lowerBound]..<indices[$0.upperBound] }
    }
}
