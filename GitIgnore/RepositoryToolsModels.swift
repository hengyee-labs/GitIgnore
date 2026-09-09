import Foundation

struct RepositoryToolReport: Sendable {
    var lfs: String = "未检查"
    var submodules: String = "未检查"
    var sparseCheckout: String = "未检查"
    var hooks: String = "未检查"
    var health: String = "未检查"
    var objectCount: Int?
    var generatedAt: Date?
}

enum RepositoryToolKind: String, CaseIterable, Identifiable {
    case history
    case extensions
    case automation
    case health
    var id: Self { self }
    var title: String {
        switch self {
        case .history: "历史与比较"
        case .extensions: "仓库扩展"
        case .automation: "协作与自动化"
        case .health: "健康检查"
        }
    }
    var symbol: String {
        switch self {
        case .history: "line.3.horizontal.decrease.circle"
        case .extensions: "shippingbox"
        case .automation: "wand.and.stars"
        case .health: "heart.text.square"
        }
    }
}
