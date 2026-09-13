import Foundation

/// Stores grants, not repositories. A parent grant is shared by its descendants.
@MainActor
final class RepositoryAccessStore {
    static let storageKey = "orbit.repositoryBookmarks"
    private let defaults: UserDefaults
    private let resolve: (Data) throws -> (URL, Bool)
    private let create: (URL) throws -> Data
    private let start: (URL) -> Bool
    private let stop: (URL) -> Void
    private var active: [String: URL] = [:]

    init(
        defaults: UserDefaults = .standard,
        resolve: @escaping (Data) throws -> (URL, Bool) = { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        },
        create: @escaping (URL) throws -> Data = {
            try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.defaults = defaults
        self.resolve = resolve
        self.create = create
        self.start = start
        self.stop = stop
    }

    static func contains(_ root: URL, _ target: URL) -> Bool {
        target.standardizedFileURL.pathComponents.starts(with: root.standardizedFileURL.pathComponents)
    }

    func access(_ target: URL) -> URL {
        var bookmarks = defaults.dictionary(forKey: Self.storageKey) as? [String: Data] ?? [:]
        let keys = Set(bookmarks.keys).union(active.keys).filter {
            Self.contains(URL(fileURLWithPath: $0, isDirectory: true), target)
        }.sorted { $0.count > $1.count }
        for key in keys {
            let original = URL(fileURLWithPath: key, isDirectory: true)
            if let root = active[key] { return relocated(target, from: original, to: root) }
            guard let data = bookmarks[key] else { continue }
            do {
                let (root, stale) = try resolve(data)
                guard start(root) else { continue }
                active[key] = root
                if stale, let refreshed = try? create(root) {
                    bookmarks[key] = refreshed
                    defaults.set(bookmarks, forKey: Self.storageKey)
                }
                return relocated(target, from: original, to: root)
            } catch {
                // One corrupt grant must not erase unrelated grants or projects.
                bookmarks.removeValue(forKey: key)
                defaults.set(bookmarks, forKey: Self.storageKey)
            }
        }
        return target
    }

    func save(_ url: URL) throws {
        let key = url.standardizedFileURL.path
        let acquired = active[key] == nil && start(url)
        do {
            let data = try create(url)
            var bookmarks = defaults.dictionary(forKey: Self.storageKey) as? [String: Data] ?? [:]
            bookmarks[key] = data
            defaults.set(bookmarks, forKey: Self.storageKey)
            if acquired { active[key] = url }
        } catch {
            if acquired { stop(url) }
            throw error
        }
    }

    func stopAll() {
        active.values.forEach(stop)
        active.removeAll()
    }

    private func relocated(_ target: URL, from original: URL, to resolved: URL) -> URL {
        target.standardizedFileURL.pathComponents.dropFirst(original.standardizedFileURL.pathComponents.count)
            .reduce(resolved) { $0.appendingPathComponent($1, isDirectory: true) }
    }
}
