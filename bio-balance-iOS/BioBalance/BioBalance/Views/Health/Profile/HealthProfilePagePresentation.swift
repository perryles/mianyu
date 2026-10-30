import Foundation

struct HealthProfilePagePresentation: Equatable, Sendable {
    let primaryFocus: HealthHubFocusItem?
    let supportingFocus: [HealthHubFocusItem]
    let dimensions: [HealthProfileDimension]

    static func make(summary: HealthProfileSummary) -> HealthProfilePagePresentation {
        let focusItems = HealthHubPresentationBuilder.focusItems(from: summary)
        return HealthProfilePagePresentation(
            primaryFocus: focusItems.first,
            supportingFocus: Array(focusItems.dropFirst().prefix(2)),
            dimensions: summary.dimensions.sorted {
                priority(for: $0.trend) < priority(for: $1.trend)
            }
        )
    }

    private static func priority(for trend: HealthProfileTrend) -> Int {
        switch trend {
        case .declining: return 0
        case .observing: return 1
        case .stable: return 2
        case .improving: return 3
        case .missing: return 4
        }
    }
}
