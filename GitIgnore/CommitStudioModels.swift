import Foundation

struct CommitStudioUnit: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let title: String
    let patch: String?
    let addedLines: Int
    let removedLines: Int

    var isWholeFile: Bool { patch == nil }
}

struct CommitStudioDraft: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var message = ""
    var unitIDs: Set<String> = []
}

struct CommitStudioState: Sendable {
    var units: [CommitStudioUnit] = []
    var drafts: [CommitStudioDraft] = [CommitStudioDraft()]
    var isLoading = false
    var isCommitting = false

    var assignedUnitIDs: Set<String> {
        drafts.reduce(into: Set<String>()) { $0.formUnion($1.unitIDs) }
    }

    var unassignedUnits: [CommitStudioUnit] {
        units.filter { !assignedUnitIDs.contains($0.id) }
    }
}

struct CommitStudioResult: Sendable {
    let commitIDs: [String]
}

enum CommitStudioError: LocalizedError, Sendable {
    case headChanged
    case emptyDraft(Int)
    case noChanges

    var errorDescription: String? {
        switch self {
        case .headChanged: "执行期间分支位置发生变化，已安全停止且没有修改当前分支。"
        case let .emptyDraft(index): "第 \(index + 1) 个提交草稿没有说明或没有分配内容。"
        case .noChanges: "没有可编排的工作区变更。"
        }
    }
}
