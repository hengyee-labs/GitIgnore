import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "orbit.interfaceLanguage"
    var id: Self { self }
    var title: String { self == .simplifiedChinese ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
    static var isEnglish: Bool {
        UserDefaults.standard.string(forKey: storageKey) == english.rawValue
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case changes
    case history
    case pullRequests
    case issues
    case branches
    case stashes
    case worktrees

    var id: Self { self }

    var title: String {
        let isEnglish = AppLanguage.isEnglish
        switch self {
        case .overview: return isEnglish ? "Repository" : "仓库概览"
        case .changes: return isEnglish ? "Changes" : "工作区变更"
        case .history: return isEnglish ? "History" : "提交历史"
        case .pullRequests: return isEnglish ? "Code Review" : "代码评审"
        case .issues: return isEnglish ? "Issues" : "问题跟踪"
        case .branches: return isEnglish ? "Branches & Tags" : "分支与标签"
        case .stashes: return isEnglish ? "Stash" : "Stash 临时保存"
        case .worktrees: return isEnglish ? "Worktrees" : "并行工作区"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .changes: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .pullRequests: "arrow.triangle.pull"
        case .issues: "exclamationmark.circle"
        case .branches: "arrow.triangle.branch"
        case .stashes: "archivebox"
        case .worktrees: "point.3.connected.trianglepath.dotted"
        }
    }

    static let workspace: [SidebarSection] = [.overview, .changes, .history]
    static let collaboration: [SidebarSection] = [.pullRequests, .issues]
    static let resources: [SidebarSection] = [.branches, .stashes, .worktrees]
}

struct RepositorySummary: Sendable {
    let name: String
    let path: String
    let branch: String
    let changedFileCount: Int
    let stagedFileCount: Int
    let aheadCount: Int
    let behindCount: Int

    /// A newly-created local branch has no tracking ref yet. Keep this state
    /// separate from aheadCount so the toolbar can offer a first publish.
    var needsPublish: Bool = false

    var isClean: Bool { changedFileCount == 0 }
}

struct RecentRepository: Identifiable, Codable, Hashable, Sendable {
    let name: String
    let path: String
    let lastOpened: Date

    var id: String { path }
}

struct GitStatusSummary: Sendable {
    let files: [GitFileStatus]

    var changedFileCount: Int { files.count }
    var stagedFileCount: Int { files.filter(\.isStaged).count }
    var unstagedFileCount: Int { files.filter(\.hasUnstagedChanges).count }
}

enum GitFileChangeKind: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"
    case conflicted = "U"

    var title: String {
        switch self {
        case .modified: return AppLanguage.isEnglish ? "Modified" : "已修改"
        case .added: return AppLanguage.isEnglish ? "Added" : "新增"
        case .deleted: return AppLanguage.isEnglish ? "Deleted" : "已删除"
        case .renamed: return AppLanguage.isEnglish ? "Renamed" : "已重命名"
        case .untracked: return AppLanguage.isEnglish ? "Untracked" : "未跟踪"
        case .conflicted: return AppLanguage.isEnglish ? "Conflicted" : "存在冲突"
        }
    }
}

struct GitFileStatus: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let indexCode: Character
    let worktreeCode: Character
    let kind: GitFileChangeKind

    var isStaged: Bool { indexCode != " " && indexCode != "?" }
    var hasUnstagedChanges: Bool { worktreeCode != " " }
    var hasConflict: Bool {
        indexCode == "U" || worktreeCode == "U"
            || (indexCode == worktreeCode && (indexCode == "A" || indexCode == "D"))
    }
    var statusCode: String { "\(indexCode)\(worktreeCode)" }
}

struct GitFileDiff: Sendable {
    let revision = UUID()
    let path: String
    let text: String
    let isStaged: Bool
    let document: GitPatchDocument
    let pagedReader: GitDiffPagedReader?

    init(path: String, text: String, isStaged: Bool) {
        self.path = path
        self.text = text
        self.isStaged = isStaged
        pagedReader = nil
        document = GitPatchParser.parse(text)
    }

    init(path: String, reader: GitDiffPagedReader, isStaged: Bool) {
        self.path = path
        self.text = reader.previewText
        self.isStaged = isStaged
        pagedReader = reader
        document = GitPatchParser.parse(reader.previewText)
    }

    var lines: [String] {
        document.rawLines
    }

    var byteCount: Int { pagedReader?.byteCount ?? text.utf8.count }

    var totalLineCount: Int { pagedReader?.totalLineCount ?? lines.count }

    var interactiveLineCount: Int {
        document.hunks.reduce(0) { $0 + max($1.lines.count - 1, 0) }
    }

    var interactivePreviewPlan: GitDiffInteractivePreviewPlan {
        let hunkCount = document.hunks.count
        let lineCount = interactiveLineCount
        if contentKind == .generated || byteCount > 2 * 1_024 * 1_024 || lineCount > 3_200 || hunkCount > 36 {
            return GitDiffInteractivePreviewPlan(
                isBudgeted: true,
                renderedHunkLimit: 4,
                renderedLineLimitPerHunk: 90,
                allowsLineTextSelection: false,
                reason: AppLanguage.text(
                    "这个 Diff 比较大，已启用性能保护，只先渲染前 4 个区块和每个区块前 90 行。",
                    "This diff is large, so performance guard renders the first 4 hunks and first 90 lines per hunk."
                )
            )
        }
        if byteCount > 768 * 1_024 || lineCount > 1_000 || hunkCount > 14 {
            return GitDiffInteractivePreviewPlan(
                isBudgeted: true,
                renderedHunkLimit: 8,
                renderedLineLimitPerHunk: 140,
                allowsLineTextSelection: false,
                reason: AppLanguage.text(
                    "这个 Diff 行数较多，已减少首屏渲染量，避免滚动和点击卡顿。",
                    "This diff has many lines, so the first render is reduced to keep scrolling and clicks responsive."
                )
            )
        }
        return GitDiffInteractivePreviewPlan(
            isBudgeted: false,
            renderedHunkLimit: Int.max,
            renderedLineLimitPerHunk: nil,
            allowsLineTextSelection: true,
            reason: ""
        )
    }

    var pagedReaderLineLimit: Int {
        interactivePreviewPlan.isBudgeted ? min(totalLineCount, 1_200) : totalLineCount
    }

    var supportsInlinePreview: Bool {
        contentKind == .text || contentKind == .generated || contentKind == .large
    }

    var contentKind: GitDiffContentKind {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty, !normalizedPath.hasSuffix("/") else { return .binary }
        if byteCount > 10 * 1_024 * 1_024 { return .large }

        let imageExtensions: Set<String> = ["bmp", "gif", "heic", "jpeg", "jpg", "png", "tiff", "webp"]
        let pathExtension = (normalizedPath as NSString).pathExtension.lowercased()
        if imageExtensions.contains(pathExtension) { return .image }
        if text.localizedCaseInsensitiveContains("binary files") { return .binary }
        let generatedNames = [".min.js", ".min.css", ".lock", "package-lock.json", "project.pbxproj"]
        if generatedNames.contains(where: { normalizedPath.hasSuffix($0) }) { return .generated }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .binary }
        let nonTextExtensions: Set<String> = [
            "7z", "a", "avi", "bin", "bmp", "class", "dmg", "doc", "docx",
            "eot", "exe", "gif", "gz", "heic", "ico", "jar", "jpeg", "jpg",
            "mov", "mp3", "mp4", "otf", "pdf", "png", "rar", "so", "tar",
            "tiff", "ttf", "wav", "webp", "woff", "woff2", "xls", "xlsx", "zip"
        ]
        return nonTextExtensions.contains(pathExtension) ? .binary : .text
    }
}

enum GitDiffContentKind: Sendable {
    case text
    case image
    case binary
    case large
    case generated

    var title: String {
        switch self {
        case .text: "文本差异"
        case .image: "图片变更"
        case .binary: "二进制文件"
        case .large: "大型 Diff"
        case .generated: "生成文件"
        }
    }
}

struct GitDiffInteractivePreviewPlan: Sendable {
    let isBudgeted: Bool
    let renderedHunkLimit: Int
    let renderedLineLimitPerHunk: Int?
    let allowsLineTextSelection: Bool
    let reason: String
}

struct GitImageVersion: Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let hasAlpha: Bool
}

struct GitImageDiffPreview: Sendable {
    let before: GitImageVersion?
    let after: GitImageVersion?
}

struct GitCommitSummary: Identifiable, Hashable, Sendable {
    let hash: String
    let shortHash: String
    let subject: String
    let author: String
    let dateText: String
    let refs: [String]
    let parents: [String]

    var id: String { hash }
}

struct GitCommitFileChange: Identifiable, Hashable, Sendable {
    let path: String
    let kind: GitFileChangeKind
    var addedLines: Int? = nil
    var removedLines: Int? = nil

    var id: String { path }
}

struct GitCommitDetail: Sendable {
    let message: String
    let files: [GitCommitFileChange]
}

struct GitBranchSummary: Identifiable, Hashable, Sendable {
    let name: String
    let isCurrent: Bool
    let upstream: String?

    var id: String { name }

    var needsPublish: Bool { isCurrent && upstream == nil }
}

struct GitStashSummary: Identifiable, Hashable, Sendable {
    let reference: String
    let branch: String
    let message: String
    let dateText: String
    var id: String { reference }
}

struct GitWorktreeSummary: Identifiable, Hashable, Sendable {
    let path: String
    let branch: String?
    let head: String
    let isMain: Bool
    var id: String { path }
}

struct GitRemoteBranchSummary: Identifiable, Hashable, Sendable {
    let name: String
    let remote: String
    let trackingBranch: String?
    var id: String { "\(remote)/\(name)" }
}

struct GitRemoteInfo: Hashable, Sendable {
    let name: String
    let url: String
    let webURL: URL?
    let provider: String
}

struct GitIdentity: Hashable, Sendable {
    let name: String
    let email: String

    var displayName: String {
        name.isEmpty ? "尚未配置提交身份" : name
    }

    var detail: String {
        email.isEmpty ? "请在 Git 配置中补充邮箱" : email
    }
}

enum AppFeedbackKind: Equatable, Sendable {
    case success
    case warning
    case failure
}

struct AppFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: AppFeedbackKind
    let title: String
    let message: String
    let technicalDetails: String?

    init(kind: AppFeedbackKind, title: String, message: String, technicalDetails: String? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.technicalDetails = technicalDetails
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return AppLanguage.isEnglish ? "System" : "跟随系统"
        case .light: return AppLanguage.isEnglish ? "Light" : "浅色"
        case .dark: return AppLanguage.isEnglish ? "Dark" : "深色"
        }
    }
}
