/// WristTemperatureDetailView 由健康首页体温卡片调用，作为「手腕温度」详情页。
/// 负责展示手腕温度 7 天趋势、连续偏移分析与节律解读。

import SwiftUI

/// 腕温视图 由上级页面或路由调用，作为健康模块里的界面或内容组件。
/// 负责解释具体指标含义，并展示对应的趋势、影响因素或分析结果。
struct WristTemperatureDetailView: View {
    let card: HabitBodyMetricCardModel
    let selectedDate: Date
    let summary: String
    var showsDismissButton: Bool = false

    var body: some View {
        BodyMetricTrendDetailContainer(
            card: card,
            selectedDate: selectedDate,
            summary: summary,
            titleOverride: "手腕温度",
            heroSubtitle: "更适合看连续几天的偏移，不适合放大单次波动。",
            trendHeadline: "近 7 天手腕温度",
            chartNarrative: "手腕温度更像恢复与节律线索。看当前值是否持续偏离均值，比看单天高低更有意义。",
            guidance: [
                "先看连续偏移: 单次变化常见，连续几天同向偏移更值得留意。",
                "再结合恢复: 可以和睡眠、静息心率、HRV 一起看恢复状态。",
                "最后看趋势: 这里更适合看方向，而不是追单点数值。"
            ],
            note: "手腕温度通常在睡眠期间采样，空白天不会补零，避免把缺失误读为改善。",
            rangeLoader: { range, date in
                let points = (try? await HealthKitManager.shared.fetchDailySleepingWristTemperatureAverages(days: range.aggregateDays, endDate: range.queryEndDate(anchorDate: date))) ?? []
                return points
                    .filter { range.contains($0.date, anchorDate: date) }
                    .map { HabitTrendPoint(date: $0.date, value: $0.value) }
            },
            showsDismissButton: showsDismissButton
        )
    }
}