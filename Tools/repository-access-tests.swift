import Foundation

@main
struct RepositoryAccessTests {
    enum Failure: Error { case corrupt, save }

    @MainActor
    static func main() throws {
        let suite = "GitIgnore.RepositoryAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }
        let parent = url("/fixtures/GitJava")
        let first = parent.appendingPathComponent("first")
        let second = parent.appendingPathComponent("nested/second")
        var starts = 0
        var stops = 0
        var refreshes = 0
        var stale = false
        var failSave = false
        func makeStore() -> RepositoryAccessStore {
            RepositoryAccessStore(defaults: defaults, resolve: { data in
                guard let path = String(data: data, encoding: .utf8), path.hasPrefix("/") else {
                    throw Failure.corrupt
                }
                return (url(path), stale)
            }, create: { value in
                if failSave { throw Failure.save }
                refreshes += 1
                return Data(value.path.utf8)
            }, start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        }
        let store = makeStore()
        try store.save(parent)
        precondition(store.access(first).path == first.path)
        precondition(store.access(second).path == second.path)
        precondition(starts == 1, "Sibling repositories must share one active scope")
        let unrelated = url("/fixtures/GitJava-other/project")
        precondition(!RepositoryAccessStore.contains(parent, unrelated))
        precondition(store.access(unrelated) == unrelated && starts == 1)
        precondition(RepositoryAccessStore.contains(parent, url("/fixtures/GitJava/one/../two")))
        store.stopAll()
        store.stopAll()
        precondition(stops == 1, "Scope must be released exactly once")

        stale = true
        let restarted = makeStore()
        precondition(restarted.access(second).path == second.path)
        precondition(starts == 2 && refreshes == 2, "Restore and refresh stale parent bookmark")
        restarted.stopAll()
        stale = false

        var bookmarks = defaults.dictionary(forKey: RepositoryAccessStore.storageKey) as! [String: Data]
        bookmarks[first.path] = Data("invalid".utf8)
        let legacy = url("/fixtures/legacy")
        bookmarks[legacy.path] = Data(legacy.path.utf8)
        defaults.set(bookmarks, forKey: RepositoryAccessStore.storageKey)
        let recovered = makeStore()
        precondition(recovered.access(first).path == first.path)
        let kept = defaults.dictionary(forKey: RepositoryAccessStore.storageKey) as! [String: Data]
        precondition(kept[first.path] == nil && kept[parent.path] != nil && kept[legacy.path] != nil)
        precondition(recovered.access(legacy).path == legacy.path, "Keep legacy exact grants")
        recovered.stopAll()

        let moved = url("/fixtures/Moved")
        defaults.set([parent.path: Data(moved.path.utf8)], forKey: RepositoryAccessStore.storageKey)
        let relocated = makeStore()
        precondition(relocated.access(second).path == "/fixtures/Moved/nested/second")
        relocated.stopAll()

        failSave = true
        let failed = makeStore()
        do { try failed.save(url("/fixtures/failure")); preconditionFailure("Expected save failure") }
        catch Failure.save {}
        precondition(starts == stops, "Failed save must balance acquired scope")
        let denied = RepositoryAccessStore(defaults: defaults, resolve: { _ in (parent, false) },
                                           start: { _ in false }, stop: { _ in preconditionFailure("No scope acquired") })
        precondition(denied.access(first) == first)
        denied.stopAll()
        print("PASS: parent reuse, boundary, normalization, lifecycle, restart, stale, corrupt fallback, legacy, relocation, save failure, denied scope")
    }
}
