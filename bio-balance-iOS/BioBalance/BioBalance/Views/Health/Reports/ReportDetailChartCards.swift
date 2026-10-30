/// ReportDetailChartCards 作为报告详情页的支撑组件，负责管理深度分析图表。
/// 负责统一四张分析图的选中态展示与样式规范。

import SwiftUI
import Charts

// 报告详情页的深度分析图表集中在本文件。
// 各卡片保留自己的选中状态和解读逻辑，主详情页只负责按顺序组装。

// MARK: - 共享图表选中状态

/// 选中某个图表样本后，在摘要条中并排展示的一项数值。
private struct ReportChartSelectionMetric: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

/// 统一四张分析图的选中态展示，避免每张图重复定义布局和样式。
private struct ReportChartSelectionStrip: View {
    let title: String
    let tint: Color
    let metrics: [ReportChartSelectionMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.ink)
                Spacer(minLength: 0)
                Image(systemName: "scope")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundColor(ReportsEditorialStyle.lavenderAccent)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(1)
                        Text(metric.value)
                            .font(.appSystem(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(ReportsEditorialStyle.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.horizontal, index == 0 ? 0 : 10)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if index < metrics.count - 1 {
                        Rectangle()
                            .fill(ReportsEditorialStyle.border)
                            .frame(width: 1, height: 28)
                    }
                }
            }
        }
        .padding(13)
        .background(ReportsEditorialStyle.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReportsEditorialStyle.lavenderAccent.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 七日评分趋势

/// 展示报告日附近的评分走势、参考线与点选详情。
struct ReportDetailTrendCard: View {
    let reportDate: Date
    let points: [ReportDaySummary]
    let context: ReportTrendContext?
    @State private var inspectedDate: Date?

    private var scoredPoints: [ReportDaySummary] {
        points.filter { $0.score != nil }.sorted { $0.date < $1.date }
    }

    private var recentAverageScore: Double? {
        let values = scoredPoints.map(\.scoreValue)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var selectedPoint: ReportDaySummary? {
        scoredPoints.first { Calendar.current.isDate($0.date, inSameDayAs: reportDate) }
    }

    private var inspectedPoint: ReportDaySummary? {
        guard let target = inspectedDate else { return selectedPoint }
        return scoredPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(target)) < abs(rhs.date.timeIntervalSince(target))
        }
    }

    private var bestPoint: ReportDaySummary? {
        scoredPoints.max { $0.scoreValue < $1.scoreValue }
    }

    private var weakestPoint: ReportDaySummary? {
        scoredPoints.min { $0.scoreValue < $1.scoreValue }
    }

    private var scoreRangeText: String {
        guard let minScore = scoredPoints.map(\.scoreValue).min(),
              let maxScore = scoredPoints.map(\.scoreValue).max() else {
            return "--"
        }
        return "\(minScore)-\(maxScore)"
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(
                "近 7 天背景",
                subtitle: context?.summary ?? "把今天放回近 7 天里看，更容易判断是短期波动还是连续承压。"
            )

            if let context {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "状态", value: context.title, tint: trendTint)
                    ReportsCompactMetricPill(title: "对比", value: context.comparisonText, tint: Color(hex: "5B8CFF"))
                    ReportsCompactMetricPill(title: "均值", value: recentAverageScore.map { "\(Int($0.rounded()))" } ?? "--", tint: Theme.Colors.mintGreen)
                }
            }

            if scoredPoints.isEmpty {
                ReportsInlineEmptyState(text: "这一天附近暂无趋势数据")
            } else {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "当天", value: selectedPoint.map { "\($0.scoreValue)分" } ?? "--", tint: ReportsScorePalette.tint(for: selectedPoint?.score))
                    ReportsCompactMetricPill(title: "高点", value: bestPoint.map { "\($0.scoreValue) · \($0.date.reportsShortDateString())" } ?? "--", tint: Theme.Colors.mintGreen)
                    ReportsCompactMetricPill(title: "区间", value: scoreRangeText, tint: Color(hex: "8E6CFF"))
                }

                ReportsChartReferenceLegend(averageTitle: "近 7 天均值")

                Chart {
                    reportsScoreZoneBands()

                    ForEach(scoredPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .reportsScoreLine()

                        AreaMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .reportsScoreArea()

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .foregroundStyle(pointTint(for: point))
                        .symbolSize(inspectedPoint.map { Calendar.current.isDate(point.date, inSameDayAs: $0.date) } == true ? 72 : 34)
                    }

                    if let recentAverageScore {
                        RuleMark(y: .value("均值", recentAverageScore))
                            .reportsAverageRule()
                    }

                    RuleMark(y: .value("稳定线", 70))
                        .reportsStabilityRule()

                    if let inspectedPoint {
                        RuleMark(x: .value("当前选择", inspectedPoint.date))
                            .reportsSelectionRule(tint: ReportsScorePalette.tint(for: inspectedPoint.score))
                    }
                }
                .reportsScoreChartFrame(height: 172)
                .chartXSelection(value: $inspectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }

                if let inspectedPoint {
                    ReportChartSelectionStrip(
                        title: inspectedPoint.date.reportsShortDateString(),
                        tint: ReportsScorePalette.tint(for: inspectedPoint.score),
                        metrics: [
                            .init(title: "综合评分", value: "\(inspectedPoint.scoreValue)"),
                            .init(title: "睡眠", value: ReportMetricFormatter.rawValueText(for: .sleep, in: inspectedPoint)),
                            .init(title: "压力", value: ReportMetricFormatter.rawValueText(for: .stress, in: inspectedPoint))
                        ]
                    )
                }

                ReportsReadableConclusionStrip(
                    judgment: trendJudgment,
                    evidence: trendEvidence,
                    action: trendAction,
                    tint: trendTint
                )
            }
        }
    }

    private var trendTint: Color {
        switch context?.state {
        case .recovering: return Theme.Colors.mintGreen
        case .strained: return Color(hex: "F46B5A")
        case .stable: return Color(hex: "5B8CFF")
        case nil: return Color(hex: "8AA0B8")
        }
    }

    private var trendNarrative: String {
        guard let selectedPoint else {
            return String(localized: "继续积累更多评分后，这里会说明当天在最近一周曲线里的具体位置。")
        }
        if let weakestPoint, Calendar.current.isDate(weakestPoint.date, inSameDayAs: selectedPoint.date) {
            return String(localized: "当天是近 7 天低点，建议重点回看下方的拖累维度、睡眠-压力组合和行为时间线。")
        }
        if let bestPoint, Calendar.current.isDate(bestPoint.date, inSameDayAs: selectedPoint.date) {
            return String(localized: "当天是近 7 天高点，可以把当天的支撑项当作后续维持节律的参考。")
        }
        guard let recentAverageScore else {
            return String(localized: "当前样本偏少，先把这张图作为单日状态参考。")
        }
        let delta = Double(selectedPoint.scoreValue) - recentAverageScore
        if delta >= 5 {
            return String(localized: "当天明显高于近 7 天均值，说明这一天的恢复条件比近期常态更友好。")
        }
        if delta <= -5 {
            return String(localized: "当天低于近 7 天均值，需要结合指标上下文确认是哪一项把曲线往下拉。")
        }
        return String(localized: "当天接近近 7 天均值，更像常规波动，适合从分项细节里找小幅优化。")
    }

    private var trendJudgment: String {
        guard let selectedPoint else {
            return String(localized: "当前还不能判断今天在近 7 天里的位置。")
        }
        if let weakestPoint, Calendar.current.isDate(weakestPoint.date, inSameDayAs: selectedPoint.date) {
            return String(localized: "今天是近 7 天低点，需要优先复盘拖累项。")
        }
        if let bestPoint, Calendar.current.isDate(bestPoint.date, inSameDayAs: selectedPoint.date) {
            return String(localized: "今天是近 7 天高点，说明当天节律值得保留。")
        }
        return String(localized: "今天更像近 7 天内的常规波动。")
    }

    private var trendEvidence: String {
        guard let selectedPoint, let recentAverageScore else {
            return String(localized: "近 7 天有效评分不足，暂时只能看单日分数。")
        }
        let delta = Double(selectedPoint.scoreValue) - recentAverageScore
        let direction = delta >= 0 ? "高于" : "低于"
        return String(localized: "当天 \(selectedPoint.scoreValue) 分，近 7 天均值 \(Int(recentAverageScore.rounded())) 分，\(direction)均值 \(Int(abs(delta).rounded())) 分。")
    }

    private var trendAction: String {
        guard let selectedPoint, let recentAverageScore else {
            return String(localized: "继续同步几天数据，再判断是否存在连续趋势。")
        }
        let delta = Double(selectedPoint.scoreValue) - recentAverageScore
        if delta <= -5 {
            return String(localized: "先看下方指标上下文和睡眠-压力散点，找出把分数拉低的具体组合。")
        }
        if delta >= 5 {
            return String(localized: "回看当天的支撑项，把有效的睡眠、压力和活动安排复制到后续几天。")
        }
        return String(localized: "不需要大幅调整，从最低的分项做一个小优化即可。")
    }

    private func pointTint(for point: ReportDaySummary) -> Color {
        if let inspectedPoint, Calendar.current.isDate(point.date, inSameDayAs: inspectedPoint.date) {
            return ReportsScorePalette.tint(for: point.score)
        }
        return ReportsScorePalette.tint(for: point.score).opacity(0.54)
    }
}

// MARK: - 七日位置

/// 将当日评分放到近 7 天序列中，同屏展示排名、均值差和最佳日。
struct ReportDetailSevenDayPositionCard: View {
    let reportDate: Date
    let summary: ReportDaySummary?
    let points: [ReportDaySummary]
    @State private var inspectedDate: Date?

    private var scoredPoints: [ReportDaySummary] {
        points.filter { $0.score != nil }.sorted { $0.date < $1.date }
    }

    /// 共享口径会自动忽略缺失评分，并保持原有四舍五入规则。
    private var averageScore: Int? {
        scoredPoints.reportsAverageScore
    }

    private var rankText: String {
        guard let summary, summary.score != nil, !scoredPoints.isEmpty else { return "--" }
        let sorted = scoredPoints.sorted { $0.scoreValue > $1.scoreValue }
        guard let index = sorted.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: reportDate) }) else { return "--" }
        return "\(index + 1)/\(sorted.count)"
    }

    private var deltaText: String {
        guard let score = summary?.score, let averageScore else { return "--" }
        let delta = score - averageScore
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return String(localized: "持平")
    }

    private var bestPoint: ReportDaySummary? {
        scoredPoints.max { $0.scoreValue < $1.scoreValue }
    }

    private var weakestPoint: ReportDaySummary? {
        scoredPoints.min { $0.scoreValue < $1.scoreValue }
    }

    private var inspectedPoint: ReportDaySummary? {
        let target = inspectedDate ?? reportDate
        return scoredPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(target)) < abs(rhs.date.timeIntervalSince(target))
        }
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("近 7 天位置对比", subtitle: "柱色对应评分区间，竖线标出当前查看日期。")

            if scoredPoints.isEmpty {
                ReportsInlineEmptyState(text: "附近暂无足够评分样本，暂时无法计算位置对比。")
            } else {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "排名", value: rankText, tint: ReportsScorePalette.tint(for: summary?.score))
                    ReportsCompactMetricPill(title: "较均值", value: deltaText, tint: deltaTint)
                    ReportsCompactMetricPill(title: "均值", value: averageScore.map { "\($0)" } ?? "--", tint: Color(hex: "5B8CFF"))
                }

                ReportsScoreBandLegend()

                HStack(spacing: 14) {
                    BBChartLegendItem(title: "近 7 天均值", tint: ReportsChartStyle.averageLine)
                    BBChartLegendItem(title: "所选日期", tint: ReportsChartStyle.selectionLine)
                }

                Chart {
                    reportsScoreZoneBands()

                    ForEach(scoredPoints) { point in
                        BarMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .foregroundStyle(barTint(for: point))
                        .cornerRadius(4)
                    }

                    if let averageScore {
                        RuleMark(y: .value("近7天均值", averageScore))
                            .reportsAverageRule()
                    }

                    if let inspectedPoint {
                        RuleMark(x: .value("当前选择", inspectedPoint.date))
                            .reportsSelectionRule(tint: ReportsScorePalette.tint(for: inspectedPoint.score))
                    }
                }
                .reportsScoreChartFrame(height: 150)
                .chartXSelection(value: $inspectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }


                if let inspectedPoint {
                    ReportChartSelectionStrip(
                        title: inspectedPoint.date.reportsShortDateString(),
                        tint: ReportsScorePalette.tint(for: inspectedPoint.score),
                        metrics: [
                            .init(title: "评分", value: "\(inspectedPoint.scoreValue)"),
                            .init(title: "较均值", value: inspectedDeltaText(for: inspectedPoint)),
                            .init(title: "周内排名", value: inspectedRankText(for: inspectedPoint))
                        ]
                    )
                }

                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "高点", value: bestPoint.map { "\($0.scoreValue) · \($0.date.reportsShortDateString())" } ?? "--", tint: Theme.Colors.mintGreen)
                    ReportsCompactMetricPill(title: "低点", value: weakestPoint.map { "\($0.scoreValue) · \($0.date.reportsShortDateString())" } ?? "--", tint: Color(hex: "F46B5A"))
                }

                Text(positionNarrative)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deltaTint: Color {
        guard let score = summary?.score, let averageScore else { return Color(hex: "8AA0B8") }
        let delta = score - averageScore
        if delta >= 4 { return Theme.Colors.mintGreen }
        if delta <= -4 { return Color(hex: "F46B5A") }
        return Color(hex: "5B8CFF")
    }

    private var positionNarrative: String {
        guard let score = summary?.score, let averageScore else {
            return String(localized: "继续积累几天评分后，这里会说明今天相对近 7 天的位置。")
        }
        let delta = score - averageScore
        if delta >= 6 {
            return String(localized: "今天明显高于近 7 天均值，可以回看支撑项，把有效做法保留下来。")
        }
        if delta <= -6 {
            return String(localized: "今天明显低于近 7 天均值，建议优先回看拖累项和当天行为时间线。")
        }
        return String(localized: "今天接近近 7 天均值，更像是常规波动，可以从分项里找小的优化点。")
    }

    private func barTint(for point: ReportDaySummary) -> Color {
        if let inspectedPoint, Calendar.current.isDate(point.date, inSameDayAs: inspectedPoint.date) {
            return ReportsScorePalette.tint(for: point.score)
        }
        return ReportsScorePalette.tint(for: point.score).opacity(0.66)
    }

    private func inspectedDeltaText(for point: ReportDaySummary) -> String {
        guard let averageScore else { return "--" }
        let delta = point.scoreValue - averageScore
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func inspectedRankText(for point: ReportDaySummary) -> String {
        let ranked = scoredPoints.sorted { $0.scoreValue > $1.scoreValue }
        guard let index = ranked.firstIndex(where: { $0.id == point.id }) else { return "--" }
        return "\(index + 1)/\(ranked.count)"
    }
}

// MARK: - 指标相关性

/// 对齐同一天的评分、睡眠贴合度和压力恢复度，用于观察走势同步性。
struct ReportDetailCorrelationChartCard: View {
    let points: [ReportDaySummary]
    @State private var inspectedDate: Date?

    private var chartPoints: [CorrelationPoint] {
        points
            .filter { $0.score != nil }
            .sorted { $0.date < $1.date }
            .flatMap { point in
                [
                    CorrelationPoint(date: point.date, title: "评分", value: Double(point.scoreValue)),
                    point.sleepHours.map {
                        CorrelationPoint(date: point.date, title: "睡眠贴合", value: max(0, min(100, 100 - abs($0 - 7.5) * 16)))
                    },
                    point.stress.map {
                        CorrelationPoint(date: point.date, title: "压力恢复", value: max(0, min(100, 100 - $0)))
                    }
                ]
                .compactMap { $0 }
            }
    }

    private var availableDates: [Date] {
        Array(Dictionary(grouping: chartPoints, by: { $0.date.reportsDayKey() }).values.compactMap { $0.first?.date })
            .sorted()
    }

    private var inspectedDay: Date? {
        guard !availableDates.isEmpty else { return nil }
        guard let inspectedDate else { return availableDates.last }
        return availableDates.min { lhs, rhs in
            abs(lhs.timeIntervalSince(inspectedDate)) < abs(rhs.timeIntervalSince(inspectedDate))
        }
    }

    private var inspectedPoints: [CorrelationPoint] {
        guard let inspectedDay else { return [] }
        return chartPoints.filter { Calendar.current.isDate($0.date, inSameDayAs: inspectedDay) }
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("评分关联图", subtitle: "把综合评分、睡眠贴合度和压力恢复度放在一起，观察分数波动跟谁同步。")

            if chartPoints.isEmpty {
                ReportsInlineEmptyState(text: "暂无足够样本生成评分关联图")
            } else {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "评分均值", value: averageText(for: "评分"), tint: Theme.Colors.mintGreen)
                    ReportsCompactMetricPill(title: "睡眠均值", value: averageText(for: "睡眠贴合"), tint: ReportMetricKind.sleep.tint)
                    ReportsCompactMetricPill(title: "压力恢复", value: averageText(for: "压力恢复"), tint: ReportMetricKind.stress.tint)
                }

                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "同步度", value: "\(couplingScore)", tint: couplingTint)
                    ReportsCompactMetricPill(title: "睡眠偏差", value: gapText(for: "睡眠贴合"), tint: ReportMetricKind.sleep.tint)
                    ReportsCompactMetricPill(title: "压力偏差", value: gapText(for: "压力恢复"), tint: ReportMetricKind.stress.tint)
                }

                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("状态分", point.value),
                            series: .value("指标", point.title)
                        )
                        .foregroundStyle(by: .value("指标", point.title))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("状态分", point.value)
                        )
                        .foregroundStyle(by: .value("指标", point.title))
                        .symbolSize(30)
                    }

                    RuleMark(y: .value("稳定参考", 70))
                        .reportsStabilityRule()

                    if let inspectedDay {
                        RuleMark(x: .value("当前选择", inspectedDay))
                            .reportsSelectionRule()
                    }
                }
                .chartForegroundStyleScale([
                    "评分": Theme.Colors.mintGreen,
                    "睡眠贴合": ReportMetricKind.sleep.tint,
                    "压力恢复": ReportMetricKind.stress.tint
                ])
                .reportsScoreChartFrame(height: 186)
                .chartXSelection(value: $inspectedDate)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel(format: .dateTime.day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }

                if let inspectedDay {
                    ReportChartSelectionStrip(
                        title: inspectedDay.reportsShortDateString(),
                        tint: couplingTint,
                        metrics: [
                            .init(title: "评分", value: inspectedValue(for: "评分")),
                            .init(title: "睡眠贴合", value: inspectedValue(for: "睡眠贴合")),
                            .init(title: "压力恢复", value: inspectedValue(for: "压力恢复"))
                        ]
                    )
                }

                ReportsReadableConclusionStrip(
                    judgment: correlationJudgment,
                    evidence: correlationEvidence,
                    action: correlationAction,
                    tint: couplingTint
                )
            }
        }
    }

    private func averageText(for title: String) -> String {
        let values = chartPoints.filter { $0.title == title }.map(\.value)
        guard !values.isEmpty else { return "--" }
        return "\(Int((values.reduce(0, +) / Double(values.count)).rounded()))"
    }

    private func inspectedValue(for title: String) -> String {
        guard let value = inspectedPoints.first(where: { $0.title == title })?.value else { return "--" }
        return "\(Int(value.rounded()))"
    }

    private var couplingScore: Int {
        let gaps = ["睡眠贴合", "压力恢复"].flatMap { title in
            pairedGaps(for: title)
        }
        guard !gaps.isEmpty else { return 0 }
        let averageGap = gaps.reduce(0, +) / Double(gaps.count)
        return max(0, min(100, Int((100 - averageGap).rounded())))
    }

    private var couplingTint: Color {
        switch couplingScore {
        case 78...: return Theme.Colors.mintGreen
        case 58..<78: return Color(hex: "5B8CFF")
        case 38..<58: return Color(hex: "F3A53B")
        default: return Color(hex: "F46B5A")
        }
    }

    private func gapText(for title: String) -> String {
        let gaps = pairedGaps(for: title)
        guard !gaps.isEmpty else { return "--" }
        let value = gaps.reduce(0, +) / Double(gaps.count)
        return "\(Int(value.rounded()))"
    }

    private func pairedGaps(for title: String) -> [Double] {
        // 先按自然日对齐，避免带时分秒的样本被误当成不同日期。
        let scoreByDate = Dictionary(grouping: chartPoints.filter { $0.title == "评分" }, by: { $0.date.reportsDayKey() })
            .compactMapValues { $0.first?.value }
        return chartPoints
            .filter { $0.title == title }
            .compactMap { point in
                guard let score = scoreByDate[point.date.reportsDayKey()] else { return nil }
                return abs(score - point.value)
            }
    }

    private var correlationNarrative: String {
        if couplingScore >= 78 {
            return String(localized: "评分与睡眠、压力恢复走势比较同步，说明综合分主要能被这两项解释。")
        }
        if averageGap(for: "睡眠贴合") > averageGap(for: "压力恢复") {
            return String(localized: "评分与睡眠贴合度偏差更大，建议结合 HRV 和活动一起判断，不只看睡眠时长。")
        }
        return String(localized: "评分与压力恢复度偏差更明显，说明压力之外可能还有睡眠、HRV 或活动在影响当天状态。")
    }

    private var correlationJudgment: String {
        if couplingScore >= 78 {
            return String(localized: "综合评分主要能被睡眠和压力走势解释。")
        }
        if averageGap(for: "睡眠贴合") > averageGap(for: "压力恢复") {
            return String(localized: "睡眠时长不是唯一解释，需要联动 HRV 和活动。")
        }
        return String(localized: "压力恢复与评分不同步，可能还有其他拖累项。")
    }

    private var correlationEvidence: String {
        return "同步度 \(couplingScore)，睡眠偏差 \(gapText(for: "睡眠贴合"))，压力偏差 \(gapText(for: "压力恢复"))。"
    }

    private var correlationAction: String {
        if couplingScore >= 78 {
            return String(localized: "优先围绕睡眠窗口和压力高峰做调整，通常最容易影响评分。")
        }
        if averageGap(for: "睡眠贴合") > averageGap(for: "压力恢复") {
            return String(localized: "不要只补时长，同时看 HRV、活动和睡眠质量是否跟上。")
        }
        return String(localized: "继续结合指标上下文确认压力之外的短板，避免把所有波动都归因于压力。")
    }

    private func averageGap(for title: String) -> Double {
        let gaps = pairedGaps(for: title)
        guard !gaps.isEmpty else { return 0 }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    private struct CorrelationPoint: Identifiable {
        let date: Date
        let title: String
        let value: Double

        var id: String { "\(Int64(date.timeIntervalSince1970))-\(title)" }
    }
}

// MARK: - 睡眠与压力散点图

/// 以睡眠时长和压力为两轴，用活动量表达点大小，识别“好睡低压”组合。
struct ReportDetailSleepStressScatterCard: View {
    let points: [ReportDaySummary]
    @State private var selectedPointID: Int64?
    @State private var showsThreeDimensions = false

    private var scatterPoints: [SleepStressScatterPoint] {
        points
            .filter { $0.score != nil }
            .sorted { $0.date < $1.date }
            .compactMap { point in
                guard let sleep = point.sleepHours, let stress = point.stress else { return nil }
                return SleepStressScatterPoint(
                    date: point.date,
                    sleepHours: sleep,
                    stress: stress,
                    score: point.scoreValue,
                    activityValue: activitySymbolSize(for: point.steps),
                    activitySteps: point.steps
                )
            }
    }

    private var selectedPoint: SleepStressScatterPoint? {
        if let selectedPointID, let selected = scatterPoints.first(where: { $0.id == selectedPointID }) {
            return selected
        }
        return scatterPoints.max(by: { comboScore($0) < comboScore($1) })
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("睡眠-压力散点", subtitle: "横轴是睡眠时长，纵轴是压力；点越靠右下，通常越接近恢复友好区。")

            if scatterPoints.isEmpty {
                ReportsInlineEmptyState(text: "暂无足够睡眠与压力样本生成散点图")
            } else {
                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "样本", value: "\(scatterPoints.count)天", tint: Color(hex: "5B8CFF"))
                    ReportsCompactMetricPill(title: "低压好睡", value: "\(restfulCount)天", tint: Theme.Colors.mintGreen)
                    ReportsCompactMetricPill(title: "高压短睡", value: "\(strainedCount)天", tint: Color(hex: "F46B5A"))
                }

                HStack(spacing: 8) {
                    ReportsCompactMetricPill(title: "平均睡眠", value: averageSleepText, tint: ReportMetricKind.sleep.tint)
                    ReportsCompactMetricPill(title: "平均压力", value: averageStressText, tint: ReportMetricKind.stress.tint)
                    ReportsCompactMetricPill(title: "最佳组合", value: bestComboText, tint: Theme.Colors.mintGreen)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("点色表示综合评分")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    ReportsScoreBandLegend()
                }

                // 有至少三天完整数据时才开放 3D，避免少量散点形成虚假的空间模式。
                if #available(iOS 26.0, *), threeDimensionalPoints.count >= 3 {
                    HStack(spacing: 8) {
                        Text(showsThreeDimensions ? "旋转图表观察三项指标的聚类" : "活动量当前通过点大小表达")
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsThreeDimensions.toggle()
                            }
                        } label: {
                            Label(showsThreeDimensions ? "查看 2D" : "探索 3D", systemImage: showsThreeDimensions ? "square" : "cube")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .foregroundStyle(showsThreeDimensions ? Color.white : Color(hex: "5B8CFF"))
                                .background(
                                    showsThreeDimensions ? Color(hex: "5B8CFF") : Color(hex: "5B8CFF").opacity(0.10),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if #available(iOS 26.0, *), showsThreeDimensions, threeDimensionalPoints.count >= 3 {
                    sleepStressActivityChart3D
                } else {
                    Chart {
                    RectangleMark(
                        xStart: .value("理想睡眠起", 7.0),
                        xEnd: .value("理想睡眠止", 8.5),
                        yStart: .value("低压起", 0),
                        yEnd: .value("低压止", 45)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen.opacity(0.10))

                    RuleMark(x: .value("睡眠下限", 7.0))
                        .foregroundStyle(ReportMetricKind.sleep.tint.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    RuleMark(x: .value("睡眠上限", 8.5))
                        .foregroundStyle(ReportMetricKind.sleep.tint.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    RuleMark(y: .value("低压参考", 45))
                        .foregroundStyle(ReportMetricKind.stress.tint.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    RuleMark(y: .value("高压参考", 60))
                        .foregroundStyle(Color(hex: "F46B5A").opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))

                    ForEach(scatterPoints) { point in
                        PointMark(
                            x: .value("睡眠时长", point.sleepHours),
                            y: .value("压力", point.stress)
                        )
                        .foregroundStyle(ReportsScorePalette.tint(for: point.score))
                        .symbolSize(point.id == selectedPoint?.id ? point.activityValue + 44 : point.activityValue)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("选择睡眠", selectedPoint.sleepHours))
                            .foregroundStyle(ReportMetricKind.sleep.tint.opacity(0.34))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        RuleMark(y: .value("选择压力", selectedPoint.stress))
                            .foregroundStyle(ReportMetricKind.stress.tint.opacity(0.34))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                    }
                    .frame(height: 180)
                    .chartXScale(domain: 3...11)
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: [4, 6, 8, 10]) { _ in
                            AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                            AxisValueLabel()
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(ReportsChartStyle.axisLabel)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                            AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                            AxisValueLabel()
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(ReportsChartStyle.axisLabel)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(ReportsChartStyle.plotBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        SpatialTapGesture()
                                            .onEnded { value in
                                                selectNearestPoint(at: value.location, plotFrame: frame, proxy: proxy)
                                            }
                                    )
                            }
                        }
                    }
                }

                if let selectedPoint {
                    ReportChartSelectionStrip(
                        title: selectedPoint.date.reportsShortDateString(),
                        tint: ReportsScorePalette.tint(for: selectedPoint.score),
                        metrics: [
                            .init(title: "睡眠", value: String(format: "%.1f h", selectedPoint.sleepHours)),
                            .init(title: "压力", value: "\(Int(selectedPoint.stress.rounded()))"),
                            .init(title: "评分", value: "\(selectedPoint.score)")
                        ]
                    )
                }

                HStack(spacing: 10) {
                    scatterLegendItem(title: "绿色区域：7-8.5h 且压力≤45", tint: Theme.Colors.mintGreen)
                    Spacer(minLength: 0)
                }

                ReportsReadableConclusionStrip(
                    judgment: scatterJudgment,
                    evidence: scatterEvidence,
                    action: scatterAction,
                    tint: scatterTint
                )
            }
        }
    }

    private var restfulCount: Int {
        scatterPoints.filter { $0.sleepHours >= 7.0 && $0.stress <= 45 }.count
    }

    private var strainedCount: Int {
        scatterPoints.filter { $0.sleepHours < 6.5 && $0.stress >= 60 }.count
    }

    private var averageSleepText: String {
        let values = scatterPoints.map(\.sleepHours)
        guard !values.isEmpty else { return "--" }
        return String(format: "%.1f h", values.reduce(0, +) / Double(values.count))
    }

    private var averageStressText: String {
        let values = scatterPoints.map(\.stress)
        guard !values.isEmpty else { return "--" }
        return "\(Int((values.reduce(0, +) / Double(values.count)).rounded()))"
    }

    private var bestComboText: String {
        guard let point = scatterPoints.max(by: { comboScore($0) < comboScore($1) }) else { return "--" }
        return "\(point.date.reportsShortDateString()) · \(point.score)"
    }

    private var scatterTint: Color {
        if strainedCount > 0 { return Color(hex: "F46B5A") }
        if restfulCount >= max(1, scatterPoints.count / 2) { return Theme.Colors.mintGreen }
        return Color(hex: "5B8CFF")
    }

    private var scatterNarrative: String {
        if restfulCount >= max(1, scatterPoints.count / 2) {
            return String(localized: "最近样本更多落在低压好睡区，说明睡眠和压力正在形成相对友好的组合。")
        }
        if strainedCount > 0 {
            return String(localized: "出现了高压短睡样本，建议优先回看这些日期的晚间收尾和白天压力负荷。")
        }
        return String(localized: "睡眠和压力的关系还在中间区间波动，继续观察是否逐渐向右下角移动。")
    }

    private var scatterJudgment: String {
        if strainedCount > 0 {
            return String(localized: "存在高压短睡组合，这是最需要优先回看的风险点。")
        }
        if restfulCount >= max(1, scatterPoints.count / 2) {
            return String(localized: "睡眠和压力组合整体偏恢复友好。")
        }
        return String(localized: "睡眠和压力还没有形成稳定友好组合。")
    }

    private var scatterEvidence: String {
        return String(localized: "\(scatterPoints.count) 天样本中，低压好睡 \(restfulCount) 天，高压短睡 \(strainedCount) 天；平均睡眠 \(averageSleepText)，平均压力 \(averageStressText)。")
    }

    private var scatterAction: String {
        if strainedCount > 0 {
            return String(localized: "优先回看这些日期的晚间收尾、咖啡因、任务密度和睡前刺激。")
        }
        if restfulCount >= max(1, scatterPoints.count / 2) {
            return String(localized: "继续保留当前睡眠窗口，并避免把压力高峰推到夜间。")
        }
        return String(localized: "先把睡眠拉到 7 小时附近，再观察压力点是否向绿色区域移动。")
    }

    private func comboScore(_ point: SleepStressScatterPoint) -> Double {
        let sleepFit = max(0, min(100, 100 - abs(point.sleepHours - 7.5) * 16))
        let stressFit = max(0, min(100, 100 - point.stress))
        return sleepFit * 0.55 + stressFit * 0.45
    }

    private func scatterLegendItem(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.20))
                .frame(width: 16, height: 10)
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func activitySymbolSize(for steps: Double?) -> CGFloat {
        guard let steps else { return 42 }
        return CGFloat(max(34, min(110, steps / 100.0)))
    }

    private var threeDimensionalPoints: [SleepStressScatterPoint] {
        // 睡眠和压力有效但缺少步数的日期仍可进入 2D 图，只从 3D 模式排除。
        scatterPoints.filter { $0.activitySteps != nil }
    }

    @available(iOS 26.0, *)
    private var sleepStressActivityChart3D: some View {
        // 将 2D 中编码为点大小的步数提升到 Z 轴，颜色继续表示综合得分。
        Chart3D(threeDimensionalPoints) { point in
            PointMark(
                x: .value("睡眠时长", point.sleepHours),
                y: .value("压力", point.stress),
                z: .value("活动步数", point.activitySteps ?? 0)
            )
            .foregroundStyle(ReportsScorePalette.tint(for: point.score))
        }
        .frame(height: 260)
        .chartXScale(domain: 3...11)
        .chartYScale(domain: 0...100)
        .accessibilityLabel("睡眠、压力与活动量三维关系图")
        .accessibilityValue("\(threeDimensionalPoints.count)天样本，可旋转图表观察数据聚类")
    }

    private func selectNearestPoint(at location: CGPoint, plotFrame: CGRect, proxy: ChartProxy) {
        // ChartProxy 使用绘图区局部坐标，先换算再按欧氏距离选取最近样本。
        let localLocation = CGPoint(x: location.x - plotFrame.minX, y: location.y - plotFrame.minY)
        let nearest = scatterPoints.min { lhs, rhs in
            chartDistance(from: localLocation, to: lhs, proxy: proxy) < chartDistance(from: localLocation, to: rhs, proxy: proxy)
        }
        selectedPointID = nearest?.id
    }

    private func chartDistance(from location: CGPoint, to point: SleepStressScatterPoint, proxy: ChartProxy) -> CGFloat {
        guard let x = proxy.position(forX: point.sleepHours),
              let y = proxy.position(forY: point.stress) else {
            return .greatestFiniteMagnitude
        }
        return hypot(location.x - x, location.y - y)
    }

    private struct SleepStressScatterPoint: Identifiable {
        let date: Date
        let sleepHours: Double
        let stress: Double
        let score: Int
        let activityValue: CGFloat
        let activitySteps: Double?

        var id: Int64 { Int64(date.timeIntervalSince1970) }
    }
}
