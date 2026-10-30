/// DailyReportView 由报告模块入口调用，作为「日报」详情页。
/// 负责按日切换展示当日健康综合评分、维度详情与行为回放。

import SwiftUI
import Charts

/// 日报视图 由上级页面或路由调用，作为报告模块里的界面或内容组件。
/// 负责组织日报、周报、月报或报告详情的展示与分享。
struct DailyReportView: View {
    @State private var viewModel = ReportSummaryViewModel()
    @State private var selectedDate: Date = Date()
    @State private var dailyWellnessSummary: DailyWellnessSummary = .empty()
    
    private var summary: ReportDaySummary? {
        viewModel.summary(for: selectedDate)
    }
    
    private var nearbyPoints: [ReportDaySummary] {
        viewModel.nearbyPoints(for: selectedDate)
    }

    private var dailyWellnessScoreBreakdown: DailyWellnessScoreBreakdown {
        DailyWellnessScoreEngine.evaluate(
            record: dailyWellnessSummary.todayRecord,
            pressureScore: summary?.stress.map { Int($0.rounded()) },
            todayHrv: summary?.hrv,
            recentAverageHrv: viewModel.recentAverageHrv(from: nearbyPoints, excluding: selectedDate)
        )
    }
    
    var body: some View {
        ZStack {
            ReportsSoftBackground()
            
            AdaptivePageScrollView(style: .reading, topPadding: 18, bottomPadding: 96) {
                VStack(alignment: .leading, spacing: 16) {
                    DailyReportHeroCard(selectedDate: selectedDate, summary: summary)

                    ReportsControlCard(title: "日期", subtitle: selectedDate.reportsFullDateString()) {
                        DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(Theme.Colors.mintGreen)
                    }

                    ReportsTakeawaysCard(
                        title: "今日关键结论",
                        subtitle: "把分数、完整度、强弱项和下一步动作整理成一组可执行摘要。",
                        items: ReportContentComposer.dailyTakeaways(summary: summary, nearbyPoints: nearbyPoints)
                    )

                    ReportDataCoverageCard(
                        title: "当天数据可信度",
                        subtitle: "先看今天哪些指标已经同步，避免把单项缺失误读成状态变化。",
                        points: summary.map { [$0] } ?? [],
                        expectedCount: 1
                    )
                    
                    DailyReportTrendCard(points: nearbyPoints)
                    ReportHRVRecoveryTrendCard(
                        title: "近 7 天 HRV 恢复基线",
                        subtitle: "看 HRV 相对个人周期基线的上下偏离，并标记压力最高的有效日。",
                        points: nearbyPoints
                    )
                    ReportDailyMetricBalanceCard(summary: summary)
                    ReportMetricCompositeTrendCard(
                        title: "近 7 天指标同屏",
                        subtitle: "每列代表一天、每行代表一项指标；数字是统一换算后的表现分，越高越好。",
                        points: nearbyPoints,
                        kinds: [.sleep, .stress, .hrv, .activity]
                    )
                    DailyReportWellnessSummaryCard(
                        summary: dailyWellnessSummary,
                        scoreBreakdown: dailyWellnessScoreBreakdown
                    )
                    ReportsBodyAgeOverviewCard(
                        title: "身体年龄",
                        subtitle: "直接把身体年龄、恢复趋势和近期状态说明放进今天的报告里一起读。",
                        actionTitle: nil
                    )
                    if let summary {
                        ReportsInsightCard(
                            title: "今天为何是这个分数",
                            subtitle: summary.scoreBreakdown?.headline ?? "正在整理当天原因",
                            detail: summary.adviceSummary?.summary ?? "同步更多样本后，这里会解释今天的主要拖累和加分项。",
                            systemImage: "sparkles",
                            tint: summary.adviceSummary?.tint ?? Theme.Colors.mintGreen
                        )
                    }
                    
                    NavigationLink {
                        ReportDetailView(reportDate: selectedDate, initialSummary: summary)
                    } label: {
                        ReportsActionCard(title: "查看详细报告", subtitle: "进入当日详情页面", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("日报")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.load(days: 30)
            loadDailyWellnessSummary()
        }
        .onChange(of: selectedDate) { _, _ in
            loadDailyWellnessSummary()
        }
    }

    private var sleepText: String {
        guard let value = summary?.sleepHours else { return "睡眠 暂无" }
        return String(format: String(localized: "睡眠 %.1f 小时"), value)
    }

    private var stressText: String {
        guard let value = summary?.stress else { return "压力 暂无" }
        return String(localized: "压力 \(Int(value.rounded()))")
    }

    private var stepsText: String {
        guard let value = summary?.steps else { return "活动 暂无" }
        return String(format: String(localized: "活动 %.1f 千步"), value / 1000.0)
    }

    private func loadDailyWellnessSummary() {
        let actionRecord = ActionRecordStore.shared.record(for: selectedDate)
        let context = DailyWellnessEvaluationContext(
            waterMl: actionRecord.waterMl,
            sunlightMinutes: actionRecord.sunlightMinutes,
            mindfulnessMinutes: actionRecord.mindfulnessMinutes,
            standHours: actionRecord.standHours,
            actionRecord: actionRecord,
            now: Date()
        )
        _ = DailyWellnessStore.shared.refreshFromHealthData(on: selectedDate, context: context)
        dailyWellnessSummary = DailyWellnessStore.shared.summary(endingAt: selectedDate, days: 7)
    }
}

private struct DailyReportHeroCard: View {
    let selectedDate: Date
    let summary: ReportDaySummary?

    var body: some View {
        ReportsPeriodHeroCard(
            reportTitle: "日报",
            periodText: selectedDate.reportsFullDateString(),
            eyebrow: "当天速览",
            headline: scoreHeadline,
            detail: "从今天的状态开始，快速看清恢复节律与下一步。",
            score: summary?.score,
            scoreLabel: "综合评分",
            tint: scoreTint,
            metrics: [
                ReportsHeroMetric(title: "睡眠", value: sleepText, tint: ReportMetricKind.sleep.tint),
                ReportsHeroMetric(title: "压力", value: stressText, tint: ReportMetricKind.stress.tint),
                ReportsHeroMetric(title: "活动", value: stepsText, tint: ReportMetricKind.activity.tint)
            ]
        )
    }

    private var scoreTint: Color {
        ReportsScorePalette.tint(for: summary?.score)
    }

    private var scoreHeadline: String {
        ReportScoreStatus.headline(for: summary?.score)
    }

    private var sleepText: String {
        guard let value = summary?.sleepHours else { return "--" }
        return String(format: "%.1f h", value)
    }

    private var stressText: String {
        guard let value = summary?.stress else { return "--" }
        return "\(Int(value.rounded()))"
    }

    private var stepsText: String {
        guard let value = summary?.steps else { return "--" }
        return String(format: "%.1fk", value / 1000.0)
    }

}

private struct DailyReportTrendCard: View {
    let points: [ReportDaySummary]
    @State private var inspectedDate: Date?
    @State private var hapticSelectionTick = 0

    private var averageScore: Double? {
        let values = points.map(\.scoreValue)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var inspectedPoint: ReportDaySummary? {
        guard let inspectedDate else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(inspectedDate)) < abs(rhs.date.timeIntervalSince(inspectedDate))
        }
    }

    private var activePoint: ReportDaySummary? {
        inspectedPoint ?? points.last
    }

    var body: some View {
        ReportsContentCard {
            ReportsSectionHeader("近 7 天评分", subtitle: "根据睡眠、压力、HRV 与活动生成")

            if points.isEmpty {
                ReportsInlineEmptyState(text: "当前日期附近暂无报告趋势")
            } else {
                ReportsChartReferenceLegend(averageTitle: "周期均值")

                Chart {
                    reportsScoreZoneBands()

                    ForEach(points) { point in
                        AreaMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .reportsScoreArea()

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .reportsScoreLine()

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .foregroundStyle(ReportsScorePalette.tint(for: point.score))
                        .symbol(.circle)
                        .symbolSize(inspectedPoint?.id == point.id ? 82 : 46)
                    }

                    if let averageScore {
                        RuleMark(y: .value("周期均值", averageScore))
                            .reportsAverageRule()
                    }

                    RuleMark(y: .value("稳定参考", 70))
                        .reportsStabilityRule()

                    if let inspectedPoint {
                        RuleMark(x: .value("当前选择", inspectedPoint.date))
                            .reportsSelectionRule(tint: ReportsScorePalette.tint(for: inspectedPoint.score))
                    }
                }
                .reportsScoreChartFrame(height: 150)
                .chartXSelection(value: $inspectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .onChange(of: inspectedPoint?.id) { _, newValue in
                    if newValue != nil {
                        hapticSelectionTick += 1
                    }
                }

                if let activePoint {
                    ReportsChartSelectionBar(
                        title: activePoint.date.reportsShortDateString(),
                        value: "\(activePoint.scoreValue) 分",
                        comparison: comparisonText(for: activePoint),
                        tint: ReportsScorePalette.tint(for: activePoint.score)
                    )
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hapticSelectionTick)
    }

    private func comparisonText(for point: ReportDaySummary) -> String {
        guard let averageScore else { return "周期均值等待更多样本" }
        let delta = Double(point.scoreValue) - averageScore
        if abs(delta) < 0.5 { return "与周期均值持平" }
        return delta > 0
            ? "较周期均值高 \(Int(delta.rounded())) 分"
            : "较周期均值低 \(Int(abs(delta).rounded())) 分"
    }
}

private struct DailyReportWellnessSummaryCard: View {
    let summary: DailyWellnessSummary
    let scoreBreakdown: DailyWellnessScoreBreakdown

    var body: some View {
        ReportsContentCard(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.Colors.mintGreen.opacity(0.12))
                    Image(systemName: "leaf.circle.fill")
                        .font(.appSystem(size: 26, weight: .black))
                        .foregroundColor(Theme.Colors.mintGreen)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("轻养生综合分")
                        .font(.appSystem(.headline, design: .default))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(scoreBreakdown.explanation)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(scoreBreakdown.totalScore)")
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.mintGreen)
                    Text(scoreBreakdown.levelTitle)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            HStack(spacing: 10) {
                smallMetric(title: "今日完成", value: "\(summary.todayCompletedCount)/5")
                smallMetric(title: "压力贡献", value: "\(Int(scoreBreakdown.pressureComponent.rounded()))/25")
                smallMetric(title: "HRV贡献", value: "\(Int(scoreBreakdown.hrvComponent.rounded()))/15")
            }

            Text(summary.reviewText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                ForEach(summary.weeklyDays) { day in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(day.score > 0 ? Theme.Colors.mintGreen.opacity(Double(day.score) / 100.0) : Color(hex: "DDE8F2"))
                        .frame(height: 28)
                        .overlay {
                            Text("\(day.completedCount)")
                                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(day.score > 0 ? .white : Theme.Colors.textTertiary)
                        }
                }
            }
        }
    }

    private func smallMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Theme.Colors.mintGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        DailyReportView()
    }
}
