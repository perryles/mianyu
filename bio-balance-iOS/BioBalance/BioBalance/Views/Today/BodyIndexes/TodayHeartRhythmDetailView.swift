import SwiftUI

/// 今日页「心律稳定性」身体指数的独立二级页面入口。
struct TodayHeartRhythmDetailView: View {
    let summary: TodayOtherMetricDetailSummary
    let heartRhythmResult: HeartRhythmStabilityResult
    let personalizationContext: BodyIndexPersonalizationContext
    let initialDate: Date

    var body: some View {
        BodyIndexReferenceDetailContentView(
            summary: summary,
            destination: .heartRhythm,
            heartRhythmResult: heartRhythmResult,
            personalizationContext: personalizationContext,
            initialDate: initialDate
        )
    }
}
