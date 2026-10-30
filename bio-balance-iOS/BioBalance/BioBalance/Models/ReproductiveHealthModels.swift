import Foundation

nonisolated enum ReproductiveHealthSection: String, CaseIterable, Identifiable, Sendable {
    case period
    case pregnancy

    static let defaultSection: ReproductiveHealthSection = .period

    var id: String { rawValue }

    var title: String {
        switch self {
        case .period: return "经期"
        case .pregnancy: return "孕期"
        }
    }

    static func resolved(hasActivePregnancy: Bool) -> ReproductiveHealthSection {
        hasActivePregnancy ? .pregnancy : .period
    }
}
