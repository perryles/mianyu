import SwiftUI

/// 今日页「心肺能力」的独立二级页面入口。
struct CardioFitnessDetailView: View {
    let summary: TodayOtherMetricDetailSummary
    let personalizationContext: BodyIndexPersonalizationContext
    let initialDate: Date

    var body: some View {
        BodyIndexReferenceDetailContentView(
            summary: summary,
            destination: .vo2Max,
            heartRhythmResult: .unavailable,
            personalizationContext: personalizationContext,
            initialDate: initialDate
        )
    }
}
