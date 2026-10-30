import SwiftUI

/// 今日页「手腕温度」身体指数的独立二级页面入口。
struct TodayWristTemperatureDetailView: View {
    let summary: TodayOtherMetricDetailSummary
    let personalizationContext: BodyIndexPersonalizationContext
    let initialDate: Date

    var body: some View {
        BodyIndexReferenceDetailContentView(
            summary: summary,
            destination: .wristTemperature,
            heartRhythmResult: .unavailable,
            personalizationContext: personalizationContext,
            initialDate: initialDate
        )
    }
}
