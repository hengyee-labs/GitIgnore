import Foundation
import Security

enum RemoteResourceKind: String, Sendable {
    case review
    case issue
}

enum RemoteHostingProvider: String, CaseIterable, Identifiable, Sendable {
    case github
    case gitlab
    case gitee

    var id: Self { self }

    var title: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .gitee: "Gitee"
        }
    }

    static func resolved(for remote: GitRemoteInfo) -> RemoteHostingProvider? {
        guard let host = remote.webURL?.host?.lowercased() else { return nil }
        if let override = RemoteCollaborationPreferences.providerOverride(for: host) {
            return override
        }
        switch remote.provider {
        case "GitHub": return .github
        case "GitLab": return .gitlab
        case "Gitee": return .gitee
        default: return nil
        }
    }
}

enum RemoteItemState: String, Sendable {
    case open
    case closed
    case merged

    var title: String {
        switch self {
        case .open: AppLanguage.isEnglish ? "Open" : "进行中"
        case .closed: AppLanguage.isEnglish ? "Closed" : "已关闭"
        case .merged: AppLanguage.isEnglish ? "Merged" : "已合并"
        }
    }
}

struct RemoteCollaborationItem: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let kind: RemoteResourceKind
    let title: String
    let body: String
    let author: String
    let state: RemoteItemState
    let isDraft: Bool
    let sourceBranch: String?
    let targetBranch: String?
    let labels: [String]
    let commentCount: Int
    let updatedAt: Date?
    let webURL: URL
}

enum RemoteCollaborationError: LocalizedError, Sendable {
    case unsupportedProvider
    case invalidRemote
    case authenticationRequired(String)
    case rateLimited
    case server(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            "无法自动识别远程平台，请在设置中指定 GitHub、GitLab 或 Gitee。"
        case .invalidRemote:
            "当前 origin 地址无法解析为远程项目。"
        case let .authenticationRequired(host):
            "\(host) 拒绝了访问。请在设置中保存具有只读 API 权限的访问令牌。"
        case .rateLimited:
            "远程平台的访问频率已达到上限，请稍后重试或配置访问令牌。"
        case let .server(status, message):
            message.isEmpty ? "远程平台返回错误（HTTP \(status)）。" : message
        case .invalidResponse:
            "远程平台返回了无法识别的数据。"
        }
    }
}

enum RemoteCollaborationPreferences {
    static func providerOverride(for host: String) -> RemoteHostingProvider? {
        guard let raw = UserDefaults.standard.string(forKey: providerKey(host)) else { return nil }
        return RemoteHostingProvider(rawValue: raw)
    }

    static func setProviderOverride(_ provider: RemoteHostingProvider?, for host: String) {
        let key = providerKey(host)
        if let provider {
            UserDefaults.standard.set(provider.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func providerKey(_ host: String) -> String {
        "orbit.remoteCollaboration.provider.\(host.lowercased())"
    }
}

enum RemoteAccessTokenStore {
    private static let service = "com.hengyee.GitIgnore.remote-access"

    static func token(for host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host.lowercased(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String, for host: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try removeToken(for: host)
            return
        }
        try removeToken(for: host)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host.lowercased(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(normalized.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func removeToken(for host: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host.lowercased()
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "无法访问 macOS 钥匙串（\(status)）。"
        }
    }
}

actor RemoteCollaborationService {
    static let shared = RemoteCollaborationService()

    private struct CacheKey: Hashable {
        let host: String
        let project: String
        let provider: RemoteHostingProvider
        let kind: RemoteResourceKind
    }

    private struct CacheEntry {
        let items: [RemoteCollaborationItem]
        let createdAt: Date
    }

    private struct Descriptor {
        let provider: RemoteHostingProvider
        let host: String
        let projectPath: String
        let webURL: URL
    }

    private var cache: [CacheKey: CacheEntry] = [:]

    func items(
        kind: RemoteResourceKind,
        remote: GitRemoteInfo,
        forceRefresh: Bool = false
    ) async throws -> [RemoteCollaborationItem] {
        let descriptor = try descriptor(for: remote)
        let key = CacheKey(
            host: descriptor.host,
            project: descriptor.projectPath,
            provider: descriptor.provider,
            kind: kind
        )
        if !forceRefresh,
           let entry = cache[key],
           Date().timeIntervalSince(entry.createdAt) < 60 {
            return entry.items
        }

        let token = RemoteAccessTokenStore.token(for: descriptor.host)
        let url = try endpoint(kind: kind, descriptor: descriptor, token: token)
        let data = try await request(url: url, provider: descriptor.provider, token: token, host: descriptor.host)
        let loaded: [RemoteCollaborationItem]
        switch descriptor.provider {
        case .github, .gitee:
            loaded = try decodeGitHubStyle(data: data, kind: kind, provider: descriptor.provider)
        case .gitlab:
            loaded = try decodeGitLab(data: data, kind: kind)
        }
        cache[key] = CacheEntry(items: loaded, createdAt: Date())
        if cache.count > 8 {
            let oldest = cache.min { $0.value.createdAt < $1.value.createdAt }?.key
            if let oldest { cache.removeValue(forKey: oldest) }
        }
        return loaded
    }

    private func descriptor(for remote: GitRemoteInfo) throws -> Descriptor {
        guard let webURL = remote.webURL,
              let host = webURL.host?.lowercased(),
              let provider = RemoteHostingProvider.resolved(for: remote) else {
            throw RemoteCollaborationError.unsupportedProvider
        }
        var projectPath = webURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if projectPath.hasSuffix(".git") { projectPath.removeLast(4) }
        guard !projectPath.isEmpty else { throw RemoteCollaborationError.invalidRemote }
        return Descriptor(provider: provider, host: host, projectPath: projectPath, webURL: webURL)
    }

    private func endpoint(
        kind: RemoteResourceKind,
        descriptor: Descriptor,
        token: String?
    ) throws -> URL {
        switch descriptor.provider {
        case .github:
            let apiRoot = descriptor.host == "github.com"
                ? "https://api.github.com"
                : "https://\(descriptor.host)/api/v3"
            let suffix = kind == .review ? "pulls" : "issues"
            guard var components = URLComponents(string: "\(apiRoot)/repos/\(descriptor.projectPath)/\(suffix)") else {
                throw RemoteCollaborationError.invalidRemote
            }
            components.queryItems = [
                URLQueryItem(name: "state", value: "all"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ]
            guard let url = components.url else { throw RemoteCollaborationError.invalidRemote }
            return url
        case .gitlab:
            let encodedProject = descriptor.projectPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? descriptor.projectPath
            let suffix = kind == .review ? "merge_requests" : "issues"
            guard var components = URLComponents(string: "https://\(descriptor.host)/api/v4/projects/\(encodedProject)/\(suffix)") else {
                throw RemoteCollaborationError.invalidRemote
            }
            components.queryItems = [
                URLQueryItem(name: "scope", value: "all"),
                URLQueryItem(name: "state", value: "all"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
            guard let url = components.url else { throw RemoteCollaborationError.invalidRemote }
            return url
        case .gitee:
            let suffix = kind == .review ? "pulls" : "issues"
            guard var components = URLComponents(string: "https://gitee.com/api/v5/repos/\(descriptor.projectPath)/\(suffix)") else {
                throw RemoteCollaborationError.invalidRemote
            }
            var query = [
                URLQueryItem(name: "state", value: "all"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ]
            if let token, !token.isEmpty { query.append(URLQueryItem(name: "access_token", value: token)) }
            components.queryItems = query
            guard let url = components.url else { throw RemoteCollaborationError.invalidRemote }
            return url
        }
    }

    private func request(
        url: URL,
        provider: RemoteHostingProvider,
        token: String?,
        host: String
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitIgnore/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = max(
            5,
            UserDefaults.standard.double(forKey: RemoteCheckPreferences.timeoutKey)
        )
        if let token, !token.isEmpty {
            switch provider {
            case .github:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            case .gitlab:
                request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            case .gitee:
                break
            }
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteCollaborationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 404 {
                throw RemoteCollaborationError.authenticationRequired(host)
            }
            if http.statusCode == 429 || (http.statusCode == 403 && token == nil) {
                throw RemoteCollaborationError.rateLimited
            }
            let message = (try? JSONDecoder().decode(RemoteErrorPayload.self, from: data).message) ?? ""
            throw RemoteCollaborationError.server(http.statusCode, message)
        }
        return data
    }

    private func decodeGitHubStyle(
        data: Data,
        kind: RemoteResourceKind,
        provider: RemoteHostingProvider
    ) throws -> [RemoteCollaborationItem] {
        let values = try JSONDecoder().decode([GitHubItem].self, from: data)
        return values.compactMap { value in
            if kind == .issue, value.pull_request != nil { return nil }
            guard let webURL = URL(string: value.html_url ?? value.url ?? "") else { return nil }
            let merged = value.merged_at != nil || value.merged == true
            let state: RemoteItemState = merged ? .merged : (value.state == "closed" ? .closed : .open)
            let source = value.head?.ref ?? value.head?.label
            let target = value.base?.ref ?? value.base?.label
            return RemoteCollaborationItem(
                id: "\(provider.rawValue)-\(kind.rawValue)-\(value.number)",
                number: value.number,
                kind: kind,
                title: value.title,
                body: value.body ?? "",
                author: value.user?.login ?? value.user?.name ?? "—",
                state: state,
                isDraft: value.draft ?? false,
                sourceBranch: source,
                targetBranch: target,
                labels: value.labels?.compactMap { $0.name }.filter { !$0.isEmpty } ?? [],
                commentCount: (value.comments ?? 0) + (value.review_comments ?? 0),
                updatedAt: parseDate(value.updated_at),
                webURL: webURL
            )
        }
    }

    private func decodeGitLab(data: Data, kind: RemoteResourceKind) throws -> [RemoteCollaborationItem] {
        let values = try JSONDecoder().decode([GitLabItem].self, from: data)
        return values.compactMap { value in
            guard let webURL = URL(string: value.web_url) else { return nil }
            let state: RemoteItemState = value.state == "merged"
                ? .merged
                : (value.state == "closed" ? .closed : .open)
            return RemoteCollaborationItem(
                id: "gitlab-\(kind.rawValue)-\(value.iid)",
                number: value.iid,
                kind: kind,
                title: value.title,
                body: value.description ?? "",
                author: value.author?.username ?? value.author?.name ?? "—",
                state: state,
                isDraft: value.draft ?? value.work_in_progress ?? false,
                sourceBranch: value.source_branch,
                targetBranch: value.target_branch,
                labels: value.labels ?? [],
                commentCount: value.user_notes_count ?? 0,
                updatedAt: parseDate(value.updated_at),
                webURL: webURL
            )
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct RemoteErrorPayload: Decodable {
    let message: String
}

private struct GitHubItem: Decodable {
    struct User: Decodable { let login: String?; let name: String? }
    struct Label: Decodable { let name: String }
    struct Reference: Decodable { let ref: String?; let label: String? }
    struct PullMarker: Decodable {}

    let number: Int
    let title: String
    let body: String?
    let state: String
    let html_url: String?
    let url: String?
    let draft: Bool?
    let merged: Bool?
    let merged_at: String?
    let updated_at: String?
    let comments: Int?
    let review_comments: Int?
    let user: User?
    let labels: [Label]?
    let head: Reference?
    let base: Reference?
    let pull_request: PullMarker?
}

private struct GitLabItem: Decodable {
    struct Author: Decodable { let username: String?; let name: String? }

    let iid: Int
    let title: String
    let description: String?
    let state: String
    let web_url: String
    let draft: Bool?
    let work_in_progress: Bool?
    let source_branch: String?
    let target_branch: String?
    let labels: [String]?
    let user_notes_count: Int?
    let updated_at: String?
    let author: Author?
}
