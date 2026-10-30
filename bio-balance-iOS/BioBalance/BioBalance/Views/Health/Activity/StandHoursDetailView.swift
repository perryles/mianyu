/// StandHoursDetailView 由健康首页站立卡片调用，作为「站立时间」详情页。
/// 负责展示站立节律趋势、7 天对比与白天活动分析。

import SwiftUI

/// 站立时长视图 由上级页面或路由调用，作为健康模块里的界面或内容组件。
/// 负责解释具体指标含义，并展示对应的趋势、影响因素或分析结果。
struct StandHoursDetailView: View {
    let card: HabitBodyMetricCardModel
    let selectedDate: Date
    let summary: String
    var showsDismissButton: Bool = false

    var body: some View {
        BodyMetricTrendDetailContainer(
            card: card,
            selectedDate: selectedDate,
            summary: summary,
            titleOverride: "站立时间",
            heroSubtitle: "更适合看白天活动节律有没有被久坐打断。",
            trendHeadline: "近 7 天站立节律",
            chartNarrative: "站立小时不是训练指标，更像日常活动连续性的信号。当前值高亮后，更容易判断这段时间里有没有明显掉下来。",
            guidance: [
                "先看断档: 如果这段时间明显低于均值，通常意味着白天活动被打断了。",
                "再看均匀度: 站立时间稳定，往往比偶尔一天特别高更有参考价值。",
                "最后结合久坐: 和久坐提醒一起看，更容易理解白天节律。"
            ],
            note: "站立时间记录的是一天内有起身并活动的小时数，不等同于运动训练时长。",
            rangeLoader: { range, date in
                let points = (try? await HealthKitManager.shared.fetchDailyStandHours(days: range.aggregateDays, endDate: range.queryEndDate(anchorDate: date))) ?? []
                return points
                    .filter { range.contains($0.date, anchorDate: date) }
                    .map { HabitTrendPoint(date: $0.date, value: $0.value) }
            },
            showsDismissButton: showsDismissButton
        )
    }
}