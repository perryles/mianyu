/// EnvironmentDetailContent 由 TrendCategoryDetailView 调用，作为趋势页「环境感官」详情页主体。
/// 负责独立承接环境感官详情页的布局、空态、指标卡片与图表分发。

import SwiftUI
import Charts


/// Environment Detail Content 由 [TrendCategoryDetailView] 调用，作为趋势页里的“环境感官”详情页主体页面。
/// 负责独立承接环境感官详情页的布局、空态、指标卡片与图表分发，不依赖公共趋势详情组件。
struct EnvironmentDetailContent: View {
    let detail: TrendCategoryDetailModel
    let range: TrendsRange
    var isStaticForExport: Bool = false

    private var orderedMetrics: [TrendCategoryMetricModel] {
        ["环境音量", "日照时长", "耳机暴露量", "耳机暴露时长"].compactMap { title in
            detail.metrics.first(where: { $0.title == title })
        }
    }

    private var latestEnvironmentInsight: SleepEnvironmentSnoreInsight? {
        guard let environmentMetric = orderedMetrics.first(where: { $0.title == "环境音量" }) else {
            return nil
        }
        let validPoints = environmentMetric.points.filter { $0.value > 0 }.sorted { $0.date < $1.date }
        let currentValue = validPoints.last?.value
        let averageValue = validPoints.isEmpty ? nil : validPoints.map(\.value).reduce(0, +) / Double(validPoints.count)
        let sleepSummary = AppGroupManager.shared.getSleepLatestSummary()

        guard currentValue != nil || sleepSummary != nil else { return nil }

        return SleepEnvironmentSnoreInsightBuilder().build(
            from: .init(
                date: sleepSummary?.sourceDate ?? Date(),
                environmentalAudioDb: currentValue,
                recentEnvironmentalAudioAverageDb: averageValue,
                snoreSummary: sleepSummary?.snoreSummary,
                sleepSummary: sleepSummary.map(makeNightSummary(from:))
            )
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            if orderedMetrics.isEmpty {
                EnvironmentMetricEmptyStateCard(
                    title: "环境感官",
                    message: "当前区间还没有环境样本，继续同步后这里会自动补成完整趋势。",
                    accent: detail.category.accentColor,
                    status: detail.status
                )
            } else {
                if let latestEnvironmentInsight {
                    EnvironmentSleepInsightCard(insight: latestEnvironmentInsight)
                }
                ForEach(orderedMetrics) { metric in
                    EnvironmentMetricDetailCard(
                        metric: metric,
                        range: range,
                        isPrimary: metric.title == "环境音量",
                        isStaticForExport: isStaticForExport
                    )
                }
            }
        }
    }

    private func makeNightSummary(from summary: SleepSessionSummary) -> SleepTrendNightSummary {
        let estimatedAwakeMinutes = max(0, Int(summary.endTime.timeIntervalSince(summary.startTime) / 60.0) - summary.sleepDurationMinutes)
        return SleepTrendNightSummary(
            day: summary.sourceDate,
            startTime: summary.startTime,
            endTime: summary.endTime,
            inBedMinutes: Int(summary.endTime.timeIntervalSince(summary.startTime) / 60.0),
            asleepMinutes: summary.sleepDurationMinutes,
            awakeMinutes: estimatedAwakeMinutes,
            coreMinutes: Int(summary.stageSummary.lightSleepMinutesEstimated.rounded()),
            deepMinutes: Int(summary.stageSummary.deepSleepMinutesEstimated.rounded()),
            remMinutes: Int(summary.stageSummary.remSleepMinutesEstimated.rounded())
        )
    }
}

private struct EnvironmentSleepInsightCard: View {
    let insight: SleepEnvironmentSnoreInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                dashboardTrendIcon(
                    primary: "waveform.and.mic",
                    badge: "bed.double.fill",
                    accent: insight.tone.tint,
                    secondary: Color(hex: "75C7E8"),
                    size: 42
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("最近一晚环境协同")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(insight.headline)
                        .font(.system(size: 18, weight: .black, design: .serif))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(insight.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(insight.tone == .elevated ? "重点关注" : (insight.tone == .caution ? "有干扰" : "可观察"))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(insight.tone.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(insight.tone.tint.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 8) {
                summaryChip(title: "环境", value: insight.environmentLabel, tint: Color(hex: "75C7E8"))
                summaryChip(title: "鼾声", value: insight.snoreLabel, tint: Color(hex: "F28B54"))
            }

            Text(insight.stageLinkText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "35506F"))
                .fixedSize(horizontal: false, vertical: true)

            if !insight.coverageFlags.isEmpty {
                Text(insight.coverageFlags.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(insight.tone.tint.opacity(0.10), lineWidth: 1)
        )
    }

    private func summaryChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Environment Metric Detail Card 由 [EnvironmentDetailContent] 调用，作为环境感官详情页里的单张指标卡片视图。
/// 负责当前值摘要、有效点过滤、空态切换以及独立图表容器的渲染，不复用公共趋势卡片。
private struct EnvironmentMetricDetailCard: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    let isPrimary: Bool
    let isStaticForExport: Bool

    @State private var selectedPoint: TimeSeriesPointDouble?

    private var accentColor: Color {
        Color(hex: metric.accentHex)
    }

    /// 过滤有效点的方法，负责环境感官指标只保留真正有意义的输入样本。
    /// 日照保留数据源明确返回的零值；耳机指标继续排除没有暴露量的零值。
    private var effectivePoints: [TimeSeriesPointDouble] {
        let sorted = metric.points.sorted { $0.date < $1.date }
        switch metric.title {
        case "环境音量", "日照时长":
            return sorted
        case "耳机暴露量", "耳机暴露时长":
            return sorted.filter { $0.value > 0 }
        default:
            return sorted
        }
    }

    private var displayStatus: TrendCategoryStatus {
        if effectivePoints.isEmpty {
            return .noData
        }
        return metric.status
    }

    private var displaySummary: String {
        if effectivePoints.isEmpty {
            return String(localized: "暂无记录")
        }
        return metric.summary
    }

    private var headline: String {
        switch metric.title {
        case "环境音量":
            return String(localized: "先看当天噪声是在几个小时集中抬高，还是整体都处在更高底噪中。")
        case "日照时长":
            return String(localized: "按小时看自然光输入更直观，能直接分辨是晨间补光还是午后零散暴露。")
        case "耳机暴露量":
            return range == .day
                ? "按小时查看今天的耳机暴露强度，更容易定位播放音量集中抬高的时段。"
                : "按天查看当前区间的耳机暴露强度，更适合判断播放音量是否持续偏高。"
        case "耳机暴露时长":
            return range == .day
                ? "按小时查看今天的耳机收听时长，更容易定位听觉刺激集中的时段。"
                : "按天查看当前区间的耳机收听时长，更适合判断听觉刺激是否连续堆积。"
        default:
            return String(localized: "环境感官指标更适合按原始时段直接阅读。")
        }
    }

    private var latestValueText: String {
        let point = selectedPoint ?? effectivePoints.last
        guard let point else { return displaySummary }
        return TrendMetricValueFormatter.string(for: point.value, unit: metric.unit)
    }

    private var averageValueText: String {
        guard !effectivePoints.isEmpty else { return "--" }
        let average = effectivePoints.map(\.value).reduce(0, +) / Double(effectivePoints.count)
        return TrendMetricValueFormatter.string(for: average, unit: metric.unit)
    }

    /// 环境感官摘要卡片，负责展示当前值、均值和样本数量，让阅读者先拿到结论再看图。
    private var summaryItems: [(String, String)] {
        let pointCountText = "\(effectivePoints.count)\(range == .day ? "段" : "天")"
        return [
            ("当前值", latestValueText),
            ("区间均值", averageValueText),
            ("有效样本", pointCountText)
        ]
    }

    private var emptyMessage: String {
        switch metric.title {
        case "环境音量":
            return String(localized: "当前区间没有读取到可展示的环境音量样本。")
        case "日照时长":
            return String(localized: "当前区间没有读取到自然光暴露记录。")
        case "耳机暴露量":
            return String(localized: "当前区间没有读取到耳机播放音量记录。")
        case "耳机暴露时长":
            return String(localized: "当前区间没有读取到耳机收听时长。")
        default:
            return metric.emptyMessage
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title)
                    .font(.system(size: isPrimary ? 20 : 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(headline)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if effectivePoints.isEmpty {
                EnvironmentMetricEmptyStateCard(
                    title: metric.title,
                    message: emptyMessage,
                    accent: accentColor,
                    status: displayStatus
                )
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(summaryItems.enumerated()), id: \.offset) { _, item in
                        EnvironmentSummaryChip(title: item.0, value: item.1, tint: accentColor)
                    }
                }

                if metric.title == "日照时长" {
                    EnvironmentSunlightTrendCard(
                        range: range,
                        accentColor: accentColor,
                        points: effectivePoints,
                        isStaticForExport: isStaticForExport
                    )
                    .frame(height: isPrimary ? 224 : 196)
                } else {
                    EnvironmentComboTrendChart(
                        metric: metric,
                        range: range,
                        accentColor: accentColor,
                        points: effectivePoints,
                        selectedPoint: $selectedPoint,
                        isStaticForExport: isStaticForExport
                    )
                    .frame(height: isPrimary ? 224 : 196)
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: accentColor, cornerRadius: 24)
    }
}

/// Environment Sunlight Trend Card 由 [EnvironmentMetricDetailCard] 调用，作为环境感官详情页里“日照时长”的专用图表卡片。
/// 负责直接复用晒太阳页的聚合口径、柱图结构与选中逻辑，保证环境页里的日照图与今日页面一致。
private struct EnvironmentSunlightTrendCard: View {
    let range: TrendsRange
    let accentColor: Color
    let points: [TimeSeriesPointDouble]
    let isStaticForExport: Bool

    @State private var selectedBarTime: Date?

    private var summary: EnvironmentSunlightSummary {
        EnvironmentSunlightSummary.make(range: range, anchorDate: points.first?.date ?? Date(), currentPoints: points)
    }

    private var chartBars: [EnvironmentSunlightBarPoint] {
        summary.barPoints
    }

    private var selectedBar: EnvironmentSunlightBarPoint? {
        guard let selectedBarTime else { return nil }
        return chartBars.first(where: { Calendar.current.isDate($0.time, equalTo: selectedBarTime, toGranularity: range == .day ? .hour : .day) })
    }

    private var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: points.first?.date ?? Date())
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        case .week, .month:
            let start = calendar.startOfDay(for: range.startDate)
            let end = calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start
            return start...end
        }
    }

    private var xAxisMarks: [Date] {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: xAxisDomain.lowerBound)
            return [0, 4, 8, 12, 16, 20, 24].compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }
        case .week:
            let start = calendar.startOfDay(for: xAxisDomain.lowerBound)
            return (0..<range.windowDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let start = calendar.startOfDay(for: xAxisDomain.lowerBound)
            let indices = [0, 4, 9, 14, 19, 24, 29]
            return indices.compactMap { index in
                guard index < range.windowDays else { return nil }
                return calendar.date(byAdding: .day, value: index, to: start)
            }
        }
    }

    private var yAxisUpperBound: Double {
        let maxValue = max(chartBars.map(\.value).max() ?? 0, 20)
        let step = max(5, ceil((maxValue / 4) / 5) * 5)
        return step * 4
    }

    private var yAxisMarks: [Double] {
        let step = yAxisUpperBound / 4
        return (0...4).map { Double($0) * step }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(chartBars) { item in
                BarMark(
                    x: .value("时间", item.time),
                    y: .value("分钟", item.value)
                )
                .foregroundStyle(sunlightBarGradient(for: item))
                .opacity(selectedBar == nil || selectedBar?.id == item.id ? 1 : 0.42)
                .cornerRadius(5)

                if let target = targetBarReferenceValue {
                    RuleMark(y: .value("参考", target))
                        .foregroundStyle(accentColor.opacity(0.30))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if let peakBar = summary.peakBar, item.id == peakBar.id, item.value > 0 {
                    PointMark(
                        x: .value("时间", item.time),
                        y: .value("分钟", item.value)
                    )
                    .symbolSize(64)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .annotation(position: .top) {
                        Text("峰值 \(Int(item.value.rounded()))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXScale(domain: xAxisDomain)
            .chartYScale(domain: 0...yAxisUpperBound)
            .chartPlotStyle { plotArea in
                plotArea
                    .padding(.bottom, 8)
                    .bbChartPlotSurface(tint: accentColor, cornerRadius: 18)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .allowsHitTesting(!isStaticForExport)
                            .gesture(
                                LongPressGesture(minimumDuration: 0.25)
                                    .sequenced(before: DragGesture(minimumDistance: 0))
                                    .onChanged { value in
                                        switch value {
                                        case .first:
                                            break
                                        case .second(true, let drag):
                                            guard let drag else { return }
                                            let location = drag.location
                                            guard frame.contains(location) else { return }
                                            let xPosition = location.x - frame.origin.x
                                            guard let date: Date = proxy.value(atX: xPosition) else { return }
                                            selectedBarTime = bar(at: date)?.time
                                        default:
                                            break
                                        }
                                    }
                                    .onEnded { value in
                                        switch value {
                                        case .second(true, let drag):
                                            if let drag {
                                                let location = drag.location
                                                guard frame.contains(location) else {
                                                    selectedBarTime = nil
                                                    return
                                                }
                                                let xPosition = location.x - frame.origin.x
                                                guard let date: Date = proxy.value(atX: xPosition) else {
                                                    selectedBarTime = nil
                                                    return
                                                }
                                                selectedBarTime = bar(at: date)?.time
                                            }
                                        default:
                                            break
                                        }
                                    }
                            )
                    } else {
                        Color.clear
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisMarks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text("\(Int(amount.rounded()))")
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisMarks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                        }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Text(chartInsightText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let selectedBar {
                BBChartSelectionReadout(
                    title: axisLabel(for: selectedBar.time),
                    value: "\(Int(selectedBar.value.rounded())) 分钟",
                    detail: selectedBarDescription(for: selectedBar),
                    tint: accentColor,
                    systemImage: "sun.max.fill"
                )
            }
        }
    }

    private var targetBarReferenceValue: Double? {
        switch range {
        case .day:
            return nil
        case .week, .month:
            return 20
        }
    }

    private var chartInsightText: String {
        if chartBars.isEmpty {
            return String(localized: "当前范围内没有可用自然光记录。")
        }
        if summary.displayMinutes == 0 {
            return String(localized: "当前范围内有自然光记录，记录值合计为 0 分钟。")
        }
        if selectedBar != nil {
            return String(localized: "已切换到单个时段/日期视角，可以直接比较这一根柱子和整体节律的位置。")
        }
        switch range {
        case .day:
            return summary.morningMinutes >= summary.afternoonMinutes
                ? "今天的自然光更多落在上午，这通常更有利于白天清醒和夜间节律稳定。"
                : "今天的自然光主要集中在午后，如果想更稳地拉回节律，可以把一部分暴露前移到上午。"
        case .week:
            return String(localized: "这张图按天展示近 7 天真实暴露分钟数，先看有没有连续几天稳定接近 20 分钟。")
        case .month:
            return String(localized: "这张图按天展示近 30 天真实暴露分钟数，重点看是否形成连续稳定的日照习惯。")
        }
    }

    private func sunlightBarGradient(for item: EnvironmentSunlightBarPoint) -> LinearGradient {
        if range == .day {
            let hour = Calendar.current.component(.hour, from: item.time)
            if hour < 12 {
                return LinearGradient(
                    colors: [Color(hex: "FFE08A"), Color(hex: "F4A259")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            return LinearGradient(
                colors: [Color(hex: "FFD36F"), Color(hex: "E98B4A")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let isPeak = item.id == summary.peakBar?.id && item.value > 0
        return LinearGradient(
            colors: isPeak ? [Color(hex: "FFD36F"), Color(hex: "E98B4A")] : [Color(hex: "FFD36F"), accentColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func bar(at date: Date) -> EnvironmentSunlightBarPoint? {
        let granularity: Calendar.Component = range == .day ? .hour : .day
        return chartBars.first { Calendar.current.isDate($0.time, equalTo: date, toGranularity: granularity) }
    }

    private func selectedBarDescription(for bar: EnvironmentSunlightBarPoint) -> String {
        switch range {
        case .day:
            if bar.value == 0 {
                return String(localized: "这一小时有自然光记录，暴露时长为 0 分钟。")
            }
            let hour = Calendar.current.component(.hour, from: bar.time)
            if hour < 12 {
                return String(localized: "这一小时的自然光暴露发生在上午，更有利于帮助身体建立清醒信号。")
            }
            return String(localized: "这一小时的自然光暴露发生在午后，若能有一部分前移到上午，节律会更理想。")
        case .week:
            if bar.value == 0 {
                return String(localized: "这一天有自然光记录，暴露时长为 0 分钟。")
            }
            if bar.value >= 20 {
                return String(localized: "这一天已经达到建议暴露量，是近 7 天值得复用的外出节奏。")
            }
            return String(localized: "这一天有自然光暴露，但距离建议目标还有空间。")
        case .month:
            if bar.value == 0 {
                return String(localized: "这一天有自然光记录，暴露时长为 0 分钟。")
            }
            if bar.value >= 20 {
                return String(localized: "这一天已经达到建议暴露量，说明当日的作息更贴近日照目标。")
            }
            return String(localized: "这一天有自然光暴露记录，但还没有达到理想目标。")
        }
    }

    private func axisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            if abs(date.timeIntervalSince(xAxisDomain.upperBound)) < 1 {
                return "24"
            }
            return "\(calendar.component(.hour, from: date))"
        case .week:
            let day = calendar.component(.day, from: date)
            let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
            let weekday = weekdaySymbols[max(0, min(6, calendar.component(.weekday, from: date) - 1))]
            return "\(day)日\n周\(weekday)"
        case .month:
            return String(localized: "\(calendar.component(.day, from: date))日")
        }
    }
}

private struct EnvironmentSunlightBarPoint: Identifiable {
    let time: Date
    let value: Double

    var id: TimeInterval { time.timeIntervalSince1970 }
}

private struct EnvironmentSunlightSummary {
    let displayMinutes: Double
    let morningMinutes: Double
    let afternoonMinutes: Double
    let barPoints: [EnvironmentSunlightBarPoint]
    let peakBar: EnvironmentSunlightBarPoint?

    static func make(
        range: TrendsRange,
        anchorDate: Date,
        currentPoints: [TimeSeriesPointDouble]
    ) -> EnvironmentSunlightSummary {
        let calendar = Calendar.current
        let start: Date
        let end: Date
        let grouped: [Date: [TimeSeriesPointDouble]]
        switch range {
        case .day:
            start = calendar.startOfDay(for: anchorDate)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            grouped = Dictionary(grouping: currentPoints.filter { $0.date >= start && $0.date < end }) { point in
                calendar.dateInterval(of: .hour, for: point.date)?.start ?? point.date
            }
        case .week, .month:
            start = calendar.startOfDay(for: range.startDate)
            end = calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start
            grouped = Dictionary(grouping: currentPoints.filter { $0.date >= start && $0.date < end }) { point in
                calendar.startOfDay(for: point.date)
            }
        }

        let bars = grouped.map { time, bucketPoints in
            EnvironmentSunlightBarPoint(
                time: time,
                value: bucketPoints.reduce(0) { $0 + $1.value }
            )
        }
        .sorted { $0.time < $1.time }
        let morning = range == .day
            ? bars.filter { calendar.component(.hour, from: $0.time) < 12 }.reduce(0) { $0 + $1.value }
            : 0
        let afternoon = range == .day
            ? bars.filter { calendar.component(.hour, from: $0.time) >= 12 }.reduce(0) { $0 + $1.value }
            : 0

        return EnvironmentSunlightSummary(
            displayMinutes: bars.reduce(0) { $0 + $1.value },
            morningMinutes: morning,
            afternoonMinutes: afternoon,
            barPoints: bars,
            peakBar: bars.max(by: { $0.value < $1.value })
        )
    }
}

/// Environment Summary Chip 由 [EnvironmentMetricDetailCard] 调用，作为环境感官指标卡里的摘要信息条组件。
/// 负责展示当前值、区间均值和有效样本数量，帮助用户先读结论，再回看图表走势。
private struct EnvironmentSummaryChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        BBChartMetricPill(title: title, value: value, tint: tint)
    }
}

/// Environment Metric Empty State Card 由 [EnvironmentDetailContent] 和 [EnvironmentMetricDetailCard] 调用，作为环境感官详情页的专用空态页面卡片。
/// 负责在无权限、暂无记录或样本不足时，统一表达当前状态和后续提示。
private struct EnvironmentMetricEmptyStateCard: View {
    let title: String
    let message: String
    let accent: Color
    let status: TrendCategoryStatus

    private var statusLabel: String {
        switch status {
        case .noData:
            return String(localized: "暂无记录")
        case .partial:
            return String(localized: "积累中")
        case .ready:
            return String(localized: "准备中")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(statusLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(0.12), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Environment Combo Trend Chart 由 [EnvironmentMetricDetailCard] 调用，作为环境感官详情页里每张指标卡的独立图表页面。
/// 负责按“步行速度图表同款”的阅读方式渲染柱图、折线、选点、tooltip 与日周月坐标轴。
private struct EnvironmentComboTrendChart: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    let accentColor: Color
    let points: [TimeSeriesPointDouble]
    @Binding var selectedPoint: TimeSeriesPointDouble?
    let isStaticForExport: Bool

    @State private var isLongPressActivated = false
    @State private var currentTouchLocation: CGPoint?

    private var latestPoint: TimeSeriesPointDouble? {
        points.last
    }

    /// 环境图表槽位构造方法，负责把原始样本聚合成小时槽或天槽，并保留空槽位占位。
    private var slots: [EnvironmentTrendSlot] {
        let calendar = Calendar.current
        switch range {
        case .day:
            let anchorDate = points.first?.date ?? Date()
            let start = calendar.startOfDay(for: anchorDate)
            let grouped = Dictionary(grouping: points) { startOfHour(for: $0.date) }

            return (0..<24).compactMap { offset in
                guard let hour = calendar.date(byAdding: .hour, value: offset, to: start) else { return nil }
                let items = grouped[hour] ?? []
                let value = items.isEmpty ? nil : resolvedSlotValue(for: items)
                return EnvironmentTrendSlot(date: hour, value: value)
            }
        case .week, .month:
            let start = range.startDate
            let grouped = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            return (0..<range.windowDays).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let dayStart = calendar.startOfDay(for: day)
                let items = grouped[dayStart] ?? []
                let value = items.isEmpty ? nil : resolvedSlotValue(for: items)
                return EnvironmentTrendSlot(date: dayStart, value: value)
            }
        }
    }

    private var plottedPoints: [TimeSeriesPointDouble] {
        slots.compactMap { slot in
            guard let value = slot.value else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(slot.date.timeIntervalSince1970), value: value)
        }
    }

    private var meanRuleValues: [Double] {
        plottedPoints.isEmpty ? [] : [averageValue]
    }

    private var placeholderSlots: [EnvironmentTrendSlot] {
        range == .day ? [] : slots.filter { $0.value == nil }
    }

    private var selectedFocusPoints: [TimeSeriesPointDouble] {
        selectedPoint.map { [$0] } ?? []
    }

    private var latestFocusPoints: [TimeSeriesPointDouble] {
        selectedPoint == nil ? latestPoint.map { [$0] } ?? [] : []
    }

    /// X 轴日期序列方法，负责固定环境感官在日/周/月下的刻度节奏。
    private var xAxisDates: [Date] {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: dateDomain.lowerBound)
            return [0, 4, 8, 12, 16, 20, 24].compactMap { hour in
                calendar.date(byAdding: .hour, value: hour, to: start)
            }
        case .week:
            return slots.map(\.date)
        case .month:
            let indices = [0, 4, 9, 14, 19, 24, 29]
            return indices.compactMap { index in
                guard slots.indices.contains(index) else { return nil }
                return slots[index].date
            }
        }
    }

    /// Date Domain 计算方法，负责保证日视图始终是完整 24 小时，周/月始终保留完整天序列。
    private var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        switch range {
        case .day:
            let anchorDate = points.first?.date ?? Date()
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        case .week, .month:
            let start = calendar.startOfDay(for: range.startDate)
            let end = calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start
            return start...end
        }
    }

    /// Y 轴范围方法，负责分钟类指标从 0 起步，dB 类指标围绕有效区间紧凑展开。
    private var yDomain: ClosedRange<Double> {
        let values = plottedPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return usesZeroBaseline ? 0...1 : 0...100
        }

        if usesZeroBaseline {
            let rawUpper = max(1, maxValue)
            let domain = EnvironmentAxisDesigner.domain(for: [0, rawUpper], range: range)
            return 0...max(domain.upperBound, 1)
        }

        let lower = max(0, floor((minValue - 8) / 5) * 5)
        let upper = max(lower + 10, ceil((maxValue + 8) / 5) * 5)
        return lower...upper
    }

    private var yAxisValues: [Double] {
        EnvironmentAxisDesigner.axisValues(for: yDomain, range: range)
    }

    private var barWidthRatio: Double {
        switch range {
        case .day: return 0.72
        case .week: return 0.78
        case .month: return 0.58
        }
    }

    private var usesZeroBaseline: Bool {
        metric.title == "日照时长" || metric.title == "耳机暴露时长"
    }

    var body: some View {
        Chart {
            ForEach(meanRuleValues, id: \.self) { value in
                RuleMark(y: .value("Mean", value))
                    .foregroundStyle(accentColor.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(plottedPoints) { point in
                BarMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    width: .ratio(barWidthRatio)
                )
                .foregroundStyle(barGradient(isLatest: latestPoint?.timestamp == point.timestamp))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            ForEach(placeholderSlots) { slot in
                BarMark(
                    x: .value("Date", slot.date),
                    y: .value("Placeholder", yDomain.lowerBound),
                    width: .ratio(barWidthRatio)
                )
                .foregroundStyle(accentColor.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            ForEach(plottedPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trend", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor.opacity(0.88))
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }

            ForEach(selectedFocusPoints) { point in
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(accentColor.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                PointMark(
                    x: .value("SelectedDate", point.date),
                    y: .value("SelectedValue", point.value)
                )
                .symbolSize(108)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    EnvironmentTooltipView(point: point, range: range, unit: metric.unit, accentColor: accentColor)
                }

                PointMark(
                    x: .value("SelectedDate", point.date),
                    y: .value("SelectedValue", point.value)
                )
                .symbolSize(36)
                .foregroundStyle(accentColor)
            }

            ForEach(latestFocusPoints) { point in
                PointMark(
                    x: .value("LatestDate", point.date),
                    y: .value("LatestValue", point.value)
                )
                .symbolSize(72)
                .foregroundStyle(Theme.Colors.onAccent)

                PointMark(
                    x: .value("LatestDate", point.date),
                    y: .value("LatestValue", point.value)
                )
                .symbolSize(24)
                .foregroundStyle(accentColor)
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.24))
                AxisValueLabel(anchor: .trailing) {
                    if let number = value.as(Double.self) {
                        Text(axisValueText(number))
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.top, 6)
                .padding(.trailing, 8)
                .padding(.bottom, 14)
                .bbChartPlotSurface(tint: accentColor, cornerRadius: 18)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!isStaticForExport)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .onEnded { _ in
                                guard !isStaticForExport else { return }
                                isLongPressActivated = true
                                if let location = currentTouchLocation {
                                    updateSelectedPoint(at: location, proxy: proxy, geometry: geometry)
                                }
                            }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard !isStaticForExport else { return }
                                currentTouchLocation = value.location
                                guard isLongPressActivated else { return }
                                updateSelectedPoint(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                guard !isStaticForExport else { return }
                                currentTouchLocation = nil
                                isLongPressActivated = false
                                selectedPoint = nil
                            }
                    )
            }
        }
    }

    private var averageValue: Double {
        guard !plottedPoints.isEmpty else { return 0 }
        return plottedPoints.map(\.value).reduce(0, +) / Double(plottedPoints.count)
    }

    /// 槽位聚合方法，负责环境感官在不同单位下采用合适的聚合口径。
    private func resolvedSlotValue(for items: [TimeSeriesPointDouble]) -> Double {
        switch metric.title {
        case "环境音量", "耳机暴露量":
            return items.map(\.value).reduce(0, +) / Double(items.count)
        case "日照时长", "耳机暴露时长":
            return items.map(\.value).reduce(0, +)
        default:
            return items.map(\.value).reduce(0, +) / Double(items.count)
        }
    }

    /// 选点更新方法，负责在环境详情页里沿用步行速度图的长按与拖动选点体验。
    private func updateSelectedPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let locationX = location.x - frame.origin.x
        guard locationX >= 0,
              locationX <= proxy.plotSize.width,
              let date: Date = proxy.value(atX: locationX) else {
            return
        }
        selectedPoint = plottedPoints.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// X 轴标签方法，负责日视图使用 0 / 4 / 8 的纯数字标签，周/月沿用日期标签。
    private func axisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            if abs(date.timeIntervalSince(dateDomain.upperBound)) < 1 { return "24" }
            return "\(calendar.component(.hour, from: date))"
        case .week:
            let day = calendar.component(.day, from: date)
            let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
            let weekday = weekdaySymbols[max(0, min(6, calendar.component(.weekday, from: date) - 1))]
            return "\(day)日\n周\(weekday)"
        case .month:
            return String(localized: "\(calendar.component(.day, from: date))日")
        }
    }

    private func axisValueText(_ value: Double) -> String {
        let text = TrendMetricValueFormatter.string(for: value, unit: metric.unit)
        if text.hasSuffix(metric.unit) {
            return String(text.dropLast(metric.unit.count))
        }
        return text
    }

    private func startOfHour(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
    }

    private func barGradient(isLatest: Bool) -> LinearGradient {
        let topOpacity = isLatest ? 0.96 : 0.84
        let bottomOpacity = isLatest ? 0.42 : 0.24
        return LinearGradient(
            colors: [
                accentColor.opacity(topOpacity),
                accentColor.opacity(bottomOpacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Environment Tooltip View 由 [EnvironmentComboTrendChart] 调用，作为环境感官详情图里的选中提示气泡视图。
/// 负责展示当前选中时段的时间文案与数值结果，保持环境页自己的提示风格。
private struct EnvironmentTooltipView: View {
    let point: TimeSeriesPointDouble
    let range: TrendsRange
    let unit: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(EnvironmentSelectionFormatter.title(for: point.date, range: range))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(TrendMetricValueFormatter.string(for: point.value, unit: unit))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

/// Environment Axis Designer 由 [EnvironmentComboTrendChart] 调用，作为环境详情页 Y 轴范围与刻度的独立计算器类型。
/// 负责根据分钟类和 dB 类指标的特性，生成适合环境感官阅读的纵轴区间与刻度。
private enum EnvironmentAxisDesigner {
    static func domain(for values: [Double], range: TrendsRange) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...100
        }

        if abs(maxValue - minValue) < 0.1 {
            let padding = max(1, abs(maxValue) * 0.12)
            return normalizedDomain(lower: minValue - padding, upper: maxValue + padding)
        }

        let span = maxValue - minValue
        let paddingRatio: Double
        switch range {
        case .day:
            paddingRatio = 0.16
        case .week:
            paddingRatio = 0.20
        case .month:
            paddingRatio = 0.24
        }

        return normalizedDomain(
            lower: minValue - span * paddingRatio,
            upper: maxValue + span * paddingRatio
        )
    }

    static func axisValues(for domain: ClosedRange<Double>, range: TrendsRange) -> [Double] {
        let desiredCount: Int
        switch range {
        case .day:
            desiredCount = 5
        case .week:
            desiredCount = 4
        case .month:
            desiredCount = 3
        }

        let lower = domain.lowerBound
        let upper = domain.upperBound
        let span = max(upper - lower, 1)
        let rawStep = span / Double(max(desiredCount - 1, 1))
        let step = niceStep(for: rawStep)
        let first = floor(lower / step) * step
        let last = ceil(upper / step) * step

        var marks: [Double] = []
        var current = first
        while current <= last + step * 0.25 {
            marks.append(current)
            current += step
        }

        if marks.count > desiredCount + 2 {
            return stride(from: 0, to: marks.count, by: 2).map { marks[$0] }
        }
        return marks
    }

    private static func normalizedDomain(lower: Double, upper: Double) -> ClosedRange<Double> {
        let span = max(upper - lower, 1)
        let step = niceStep(for: span / 4)
        var adjustedLower = floor(lower / step) * step
        let adjustedUpper = ceil(upper / step) * step

        if adjustedLower > 0, adjustedLower <= step {
            adjustedLower = 0
        }
        return adjustedLower...adjustedUpper
    }

    private static func niceStep(for rawStep: Double) -> Double {
        let magnitude = pow(10.0, floor(log10(max(rawStep, 0.0001))))
        let residual = rawStep / magnitude
        let niceResidual: Double
        switch residual {
        case ..<1.5:
            niceResidual = 1
        case ..<3:
            niceResidual = 2
        case ..<7:
            niceResidual = 5
        default:
            niceResidual = 10
        }
        return niceResidual * magnitude
    }
}

/// Environment Selection Formatter 由 [EnvironmentTooltipView] 调用，作为环境详情页 tooltip 的时间文案格式化工具类型。
/// 负责把日、周、月三种范围下的选中时间转换成环境感官页面自己的中文提示文案。
private enum EnvironmentSelectionFormatter {
    static func title(for date: Date, range: TrendsRange) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            return String(localized: "今天 \(calendar.component(.hour, from: date)):00")
        case .week:
            let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let weekdayIndex = max(0, min(6, calendar.component(.weekday, from: date) - 1))
            return String(localized: "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 \(weekdaySymbols[weekdayIndex])")
        case .month:
            return String(localized: "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日")
        }
    }

}

/// Environment Trend Slot 由 [EnvironmentComboTrendChart] 调用，作为环境感官小时槽位和天槽位的承载结构体。
/// 负责保存每个时间槽对应的日期和值，让环境图表在保留空槽位时仍能稳定渲染。
private struct EnvironmentTrendSlot: Identifiable {
    let date: Date
    let value: Double?

    var id: TimeInterval { date.timeIntervalSince1970 }
}
