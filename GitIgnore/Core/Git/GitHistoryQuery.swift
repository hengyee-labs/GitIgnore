import Foundation

struct GitHistoryQuery: Hashable, Sendable {
    var scope = "all"
    var branch = ""
    var author = ""
    var text = ""
    var days = 0
    var kind = "all"

    func arguments(skip: Int, limit: Int) -> [String] {
        var result = ["--topo-order", "--skip=\(max(0, skip))", "--max-count=\(max(1, min(limit, 200)))",
                      "--fixed-strings", "--regexp-ignore-case"]
        if !author.isEmpty { result.append("--author=\(author)") }
        if !text.isEmpty { result.append("--grep=\(text)") }
        if days > 0 { result.append("--since-as-filter=\(days) days ago") }
        if kind == "merge" { result.append("--merges") }
        if kind == "commit" { result.append("--no-merges") }
        result.append("--end-of-options")
        if !branch.isEmpty { result.append(branch) }
        else if scope == "current" { result.append("HEAD") }
        else if scope == "incoming" { result.append("HEAD..@{upstream}") }
        else if scope == "outgoing" { result.append("@{upstream}..HEAD") }
        else {
            // --all must precede --end-of-options; branch values never become flags.
            result.insert("--all", at: 0)
        }
        result.append("--")
        return result
    }
}
