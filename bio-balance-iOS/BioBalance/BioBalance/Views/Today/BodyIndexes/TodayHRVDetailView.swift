import SwiftUI

/// 今日页「HRV」身体指数的独立二级页面入口。
struct TodayHRVDetailView: View {
    let summary: TodayOtherMetricDetailSummary
    let personalizationContext: BodyIndexPersonalizationContext
    let initialDate: Date

    var body: some View {
        BodyIndexReferenceDetailContentView(
            summary: summary,
            destination: .hrv,
            heartRhythmResult: .unavailable,
            personalizationContext: personalizationContext,
            initialDate: initialDate
        )
    }
}
