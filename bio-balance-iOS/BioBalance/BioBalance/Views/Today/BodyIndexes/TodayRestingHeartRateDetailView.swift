import SwiftUI

/// 今日页「静息心率」身体指数的独立二级页面入口。
struct TodayRestingHeartRateDetailView: View {
    let summary: TodayOtherMetricDetailSummary
    let personalizationContext: BodyIndexPersonalizationContext
    let initialDate: Date

    var body: some View {
        BodyIndexReferenceDetailContentView(
            summary: summary,
            destination: .restingHeartRate,
            heartRhythmResult: .unavailable,
            personalizationContext: personalizationContext,
            initialDate: initialDate
        )
    }
}
