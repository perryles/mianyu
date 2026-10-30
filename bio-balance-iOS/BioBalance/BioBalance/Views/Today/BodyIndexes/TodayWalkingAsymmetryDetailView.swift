import SwiftUI

/// 今日页「步态不对称」身体指数的独立二级页面入口。
struct TodayWalkingAsymmetryDetailView: View {
    let summary: TodayOtherMetricDetailSummary
    let personalizationContext: BodyIndexPersonalizationContext
    let initialDate: Date

    var body: some View {
        BodyIndexReferenceDetailContentView(
            summary: summary,
            destination: .walkingAsymmetry,
            heartRhythmResult: .unavailable,
            personalizationContext: personalizationContext,
            initialDate: initialDate
        )
    }
}
