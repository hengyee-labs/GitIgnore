import Foundation

@main
struct HistoryDiffTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitIgnore-Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String], input: Data? = nil) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let inputURL = root.appendingPathComponent("input")
            if let input {
                try input.write(to: inputURL)
                process.standardInput = try FileHandle(forReadingFrom: inputURL)
            }
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0, "Git failed: \(args)")
            return String(decoding: data, as: UTF8.self)
        }
        _ = try git(["init", "-q", "-b", "main"])
        var stream = ""
        for index in 1...2_105 {
            let subject = index == 1 ? "initial searchable" : "commit \(index)"
            stream += "commit refs/heads/main\nmark :\(index)\ncommitter Author <author@example.test> 1700000000 +0000\ndata \(subject.utf8.count)\n\(subject)\n"
            if index > 1 { stream += "from :\(index - 1)\n" }
            stream += "\n"
        }
        stream += "done\n"
        _ = try git(["fast-import", "--quiet"], input: Data(stream.utf8))
        let page = try git(["log", "--format=%s"] + GitHistoryQuery(scope: "current").arguments(skip: 2_100, limit: 100))
        precondition(page.split(separator: "\n").count == 5 && page.contains("initial searchable"))
        let found = try git(["log", "--format=%s"] + GitHistoryQuery(author: "author@example.test", text: "initial searchable").arguments(skip: 0, limit: 100))
        precondition(found.trimmingCharacters(in: .whitespacesAndNewlines) == "initial searchable")
        let none = try git(["log", "--format=%s"] + GitHistoryQuery(days: 7).arguments(skip: 0, limit: 100))
        precondition(none.isEmpty)
        let flags = GitHistoryQuery(branch: "--all", author: "--all").arguments(skip: 0, limit: 100)
        precondition(flags.firstIndex(of: "--end-of-options")! < flags.lastIndex(of: "--all")!)

        let pairs = DiffTextTools.pairs(kinds: Array(" --+++ "))
        precondition(pairs.count == 5)
        precondition(pairs[1].0 == 1 && pairs[1].1 == 3)
        precondition(pairs[2].0 == 2 && pairs[2].1 == 4)
        precondition(pairs[3].0 == nil && pairs[3].1 == 5)
        let old = "let first = 1; let second = 2"
        let edits = DiffTextTools.changedRanges(in: old, comparedWith: "let first = 3; let second = 4")
        precondition(edits.map { String(old[$0]) } == ["1", "2"])
        let unicode = "中文变量 = 你好"
        precondition(!DiffTextTools.changedRanges(in: unicode, comparedWith: "中文变量 = 您好").isEmpty)

        let diffURL = root.appendingPathComponent("large.diff")
        FileManager.default.createFile(atPath: diffURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: diffURL)
        try handle.write(contentsOf: Data("@@ -1,1 +1,1000000 @@\n".utf8))
        let chunk = Data((String(repeating: "+unchanged filler line\n", count: 4_000)).utf8)
        let targetMB = Int(ProcessInfo.processInfo.environment["GITIGNORE_TEST_DIFF_MB"] ?? "1") ?? 1
        for _ in 0..<max(1, targetMB * 1_024 * 1_024 / chunk.count) { try handle.write(contentsOf: chunk) }
        try handle.write(contentsOf: Data("+unique needle\n".utf8))
        try handle.write(contentsOf: Data(String(repeating: "x", count: 400_000).utf8))
        try handle.write(contentsOf: Data("\n+after oversized\n".utf8))
        try handle.close()
        let result = try DiffTextTools.search(file: diffURL, lines: [], query: "unique needle")
        precondition(result.total == 1 && result.matches[0].line > 1_200)
        precondition(result.truncatedLines == 1)
        let after = try DiffTextTools.search(file: diffURL, lines: [], query: "after oversized")
        precondition(after.matches[0].line == result.matches[0].line + 2, "Oversized lines must not shift IDs")
        let cap = try DiffTextTools.search(file: nil, lines: Array(repeating: "+needle", count: 6_000), query: "needle")
        precondition(cap.total == 6_000 && cap.matches.count == 5_000)
        print("PASS: Git ancestry beyond 2000, full-history filters, date filter, option boundary, replacement pairing, disjoint Unicode edits, \(targetMB) MB disk search, oversized line identity, bounded results")
    }
}
