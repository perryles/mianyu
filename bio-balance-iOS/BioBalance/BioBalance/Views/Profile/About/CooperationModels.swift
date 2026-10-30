import Foundation

enum CooperationType: String, CaseIterable, Identifiable {
    case general
    case content
    case brand
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "商务合作")
        case .content: String(localized: "内容共创")
        case .brand: String(localized: "品牌联名")
        case .community: String(localized: "社区伙伴")
        }
    }
}

enum CooperationIdentity: String, CaseIterable, Identifiable {
    case creator
    case brand
    case community
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creator: String(localized: "创作者")
        case .brand: String(localized: "品牌")
        case .community: String(localized: "社区")
        case .other: String(localized: "其他")
        }
    }
}

struct CooperationApplication {
    var cooperationType: CooperationType
    var identity: CooperationIdentity
    var name: String = ""
    var organization: String = ""
    var contact: String = ""
    var idea: String = ""

    init(cooperationType: CooperationType) {
        self.cooperationType = cooperationType
        switch cooperationType {
        case .general: identity = .other
        case .content: identity = .creator
        case .brand: identity = .brand
        case .community: identity = .community
        }
    }
}

enum CooperationServiceError: LocalizedError {
    case missingName
    case missingContact
    case missingIdea

    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "请填写称呼。")
        case .missingContact: String(localized: "请填写联系方式。")
        case .missingIdea: String(localized: "请简单说说你的合作想法。")
        }
    }
}
