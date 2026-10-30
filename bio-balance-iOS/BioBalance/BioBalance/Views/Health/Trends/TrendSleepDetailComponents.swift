/// SleepRecoveryBaselineCard 作为趋势模块的内容展示卡片，负责展示睡眠恢复基线。
/// 负责呈现 HRV、夜间心率与呼吸频率的基线指标趋势。

import SwiftUI
import Charts


/// 睡眠恢复基线卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。用于趋势页面的‘睡眠恢复’。
struct SleepRecoveryBaselineCard: View {
    let metrics: [TrendCategoryMetricModel]
    var isStaticForExport: Bool = false
    @State private var revealCard = false

    private var baselineMetrics: [TrendCategoryMetricModel] {
        metrics.filter {
            $0.title.contains("HRV") || $0.title.contains("夜间心率") || $0.title.contains("呼吸频率")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("把恢复解读收敛到最关键的睡眠基线信号，便于判断恢复储备是否真的在回升。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(baselineMetrics) { metric in
                    SleepRecoveryBaselineTile(metric: metric)
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
        .opacity(isStaticForExport ? 1 : (revealCard ? 1 : 0))
        .offset(y: isStaticForExport ? 0 : (revealCard ? 0 : 10))
        .onAppear {
            guard !isStaticForExport else {
                revealCard = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                revealCard = true
            }
        }
    }
}

/// 睡眠Core指标趋势卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。用于趋势页面的‘睡眠恢复核心睡眠趋势’。
struct SleepCoreMetricTrendCard: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    var nightSummaries: [SleepTrendNightSummary] = []
    var sleepStages: [SleepStage] = []
    var sleepCompositeScores: [SleepCompositeScoreBreakdown] = []
    var isStaticForExport: Bool = false

    @State private var selectedPoint: TimeSeriesPointDouble?

    private var tint: Color { Color(hex: metric.accentHex) }

    private var chartPoints: [TimeSeriesPointDouble] {
        guard range == .day, metric.points.count == 1, let point = metric.points.first else {
            return metric.points.sorted { $0.date < $1.date }
        }
        let anchorDate = sleepIntradayAnchorDate(for: point) ?? point.date
        return [TimeSeriesPointDouble(timestamp: Int64(anchorDate.timeIntervalSince1970), value: point.value)]
    }

    private var renderedChartPoints: [TimeSeriesPointDouble] {
        guard range == .day, chartPoints.count == 1, let point = chartPoints.first else {
            return chartPoints
        }
        guard let domain = sleepSessionDateDomain else {
            return chartPoints
        }

        let sessionDuration = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let spread = max(15 * 60.0, min(sessionDuration * 0.12, 60 * 60.0))
        let left = max(domain.lowerBound.timeIntervalSince1970, point.date.timeIntervalSince1970 - spread)
        let right = min(domain.upperBound.timeIntervalSince1970, point.date.timeIntervalSince1970 + spread)

        return [
            TimeSeriesPointDouble(timestamp: Int64(left), value: point.value),
            point,
            TimeSeriesPointDouble(timestamp: Int64(right), value: point.value)
        ]
    }

    private var lineInterpolationMethod: InterpolationMethod {
        range == .day && chartPoints.count == 1 ? .linear : .catmullRom
    }

    private var hasTrendBaseline: Bool {
        metric.points.count >= 2
    }

    private var averageValue: Double? {
        guard hasTrendBaseline else { return nil }
        return metric.points.map(\.value).reduce(0, +) / Double(metric.points.count)
    }

    private var latestValue: Double? {
        selectedPoint?.value ?? chartPoints.last?.value
    }

    private var latestValueText: String {
        guard let latestValue else { return "--" }
        return TrendMetricValueFormatter.string(for: latestValue, unit: metric.unit)
    }

    private var averageValueText: String {
        guard let averageValue else { return "--" }
        return TrendMetricValueFormatter.string(for: averageValue, unit: metric.unit)
    }

    private var peakValueText: String {
        guard let peak = metric.points.map(\.value).max() else { return "--" }
        return TrendMetricValueFormatter.string(for: peak, unit: metric.unit)
    }

    private var statusText: String {
        guard hasTrendBaseline else {
            return String(localized: "\(metric.title) 当前样本不足，至少需要 2 个真实样本后才能形成趋势判断。")
        }
        if metric.title == "睡眠评分", let composite = latestCompositeScore {
            return sleepScoreHeadline(for: composite)
        }
        guard let latestValue, let averageValue else {
            return String(localized: "继续同步健康样本后，这里会形成更稳定的睡眠趋势判断。")
        }
        let delta = latestValue - averageValue
        if abs(delta) <= max(0.1, abs(averageValue) * 0.05) {
            return String(localized: "\(metric.title) 与近期基线接近，当前变化整体还在相对稳定的区间里。")
        }
        if delta > 0 {
            return String(localized: "\(metric.title) 当前高于近期基线，更适合继续结合睡眠结构一起判断变化质量。")
        }
        return String(localized: "\(metric.title) 当前低于近期基线，建议结合昨夜结构与睡眠节律一起理解恢复变化。")
    }

    private var detailText: String {
        guard hasTrendBaseline else {
            return String(localized: "当前样本不足，继续积累记录后再与近期基线比较。")
        }
        if metric.title == "睡眠评分", let composite = latestCompositeScore {
            return sleepScoreDetail(for: composite)
        }
        guard let latestValue, let averageValue else {
            return String(localized: "先看近期趋势，再判断单次变化是否值得重点关注。")
        }
        let delta = latestValue - averageValue
        let deltaText = TrendMetricValueFormatter.string(for: abs(delta), unit: metric.unit)
        if abs(delta) <= max(0.1, abs(averageValue) * 0.05) {
            return String(localized: "当前值与近期基线接近，短期内没有出现明显偏离。")
        }
        return delta > 0 ? "当前值较近期基线高 \(deltaText)。" : "当前值较近期基线低 \(deltaText)。"
    }

    private var yDomain: ClosedRange<Double> {
        let values = renderedChartPoints.map(\.value) + [averageValue].compactMap { $0 }
        let domain = TrendYAxisDesigner.domain(for: values.isEmpty ? [0, 1] : values, range: range)
        if zeroBasedMetricTitles.contains(metric.title) {
            return 0...max(domain.upperBound, 1)
        }
        return domain
    }

    private var axisValues: [Double] {
        TrendYAxisDesigner.axisValues(for: yDomain, range: range)
    }

    private var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        switch range {
        case .day:
            if let sleepDomain = sleepSessionDateDomain {
                return sleepDomain
            }
            let start = calendar.startOfDay(for: chartPoints.first?.date ?? metric.points.first?.date ?? Date())
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        case .week, .month:
            let start = calendar.startOfDay(for: range.startDate)
            let end = calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start
            return start...end
        }
    }

    private var axisDates: [Date] {
        if range == .day, let sleepDomain = sleepSessionDateDomain {
            return sleepSessionAxisDates(for: sleepDomain)
        }
        return TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BBChartHeader(
                title: metric.title,
                subtitle: statusText,
                systemImage: "bed.double.fill",
                tint: tint
            )

            if !shouldShowSleepStageTimeline && !shouldShowSleepScoreBreakdownChart {
                HStack(spacing: 8) {
                    sleepCoreMetricChip(title: "当前", value: latestValueText)
                    sleepCoreMetricChip(title: "基线", value: averageValueText)
                    sleepCoreMetricChip(title: "高点", value: peakValueText)
                }
            }

            if shouldShowSleepStageTimeline {
                SleepStageTimelineContainer(
                    metric: metric,
                    range: range,
                    stages: sleepStages,
                    sleepInterval: latestSleepInterval
                )
            } else if shouldShowSleepScoreBreakdownChart,
                      let sleepInterval = latestSleepInterval,
                      let compositeScore = latestCompositeScore {
                SleepScoreBreakdownCard(
                    metric: metric,
                    range: range,
                    breakdown: compositeScore,
                    sleepInterval: sleepInterval,
                    accent: tint
                )
            } else if shouldShowSleepSessionBandChart, let sleepInterval = latestSleepInterval {
                SleepSessionMetricBandChart(
                    metric: metric,
                    range: range,
                    chartPoints: chartPoints,
                    sleepInterval: sleepInterval,
                    averageValue: averageValue,
                    accent: tint,
                    yAxisValues: axisValues,
                    yDomain: yDomain
                )
            } else if chartPoints.isEmpty {
                TrendMetricEmptyStateView(
                    status: metric.status,
                    title: metric.title,
                    message: metric.emptyMessage,
                    accent: tint
                )
            } else {
                Chart {
                    ForEach(renderedChartPoints) { item in
                        AreaMark(
                            x: .value("时间", item.date),
                            y: .value(metric.title, item.value)
                        )
                        .interpolationMethod(lineInterpolationMethod)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.18),
                                    tint.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("时间", item.date),
                            y: .value(metric.title, item.value)
                        )
                        .foregroundStyle(tint.opacity(0.94))
                        .interpolationMethod(lineInterpolationMethod)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }

                    ForEach(chartPoints) { item in
                        PointMark(
                            x: .value("时间", item.date),
                            y: .value(metric.title, item.value)
                        )
                        .foregroundStyle(Theme.Colors.onAccent)
                        .symbolSize(selectedPoint?.timestamp == item.timestamp ? 84 : (item.timestamp == chartPoints.last?.timestamp ? 64 : 28))
                        .annotation(position: .overlay, alignment: .center) {
                            Circle()
                                .fill(tint)
                                .frame(
                                    width: selectedPoint?.timestamp == item.timestamp ? 10 : (item.timestamp == chartPoints.last?.timestamp ? 9 : 7),
                                    height: selectedPoint?.timestamp == item.timestamp ? 10 : (item.timestamp == chartPoints.last?.timestamp ? 9 : 7)
                                )
                        }
                        .opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 1 : 0.42)
                    }

                    if let averageValue {
                        RuleMark(y: .value("近期基线", averageValue))
                            .foregroundStyle(tint.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("选中", selectedPoint.date))
                            .foregroundStyle(tint.opacity(0.24))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 216)
                .chartLegend(.hidden)
                .chartYScale(domain: yDomain)
                .chartXScale(domain: dateDomain)
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(sleepCoreAxisLabel(for: date))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.72)
                                    .font(.system(size: range == .week ? 8.5 : 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(sleepCoreAxisValueText(number))
                            }
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .clipped()
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                        .padding(.bottom, 10)
                        .bbChartPlotSurface(tint: tint, cornerRadius: 18)
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
                                    LongPressGesture(minimumDuration: 0.2)
                                        .sequenced(before: DragGesture(minimumDistance: 12))
                                        .onChanged { value in
                                            switch value {
                                            case .first:
                                                break
                                            case .second(true, let drag):
                                                guard let drag else { return }
                                                updateSelection(at: drag.location, frame: frame, proxy: proxy)
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { value in
                                            switch value {
                                            case .second(true, let drag):
                                                if let drag {
                                                    updateSelection(at: drag.location, frame: frame, proxy: proxy)
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
            }

            if let selectedPoint {
                BBChartSelectionReadout(
                    title: TrendsSelectionFormatter.title(for: selectedPoint.date, range: range),
                    value: TrendMetricValueFormatter.string(for: selectedPoint.value, unit: metric.unit),
                    detail: selectionDescription(for: selectedPoint),
                    tint: tint
                )
            }

            Text(detailText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .detailCardSurface(tint: tint)
        .onAppear {
            if !shouldShowSleepStageTimeline && !shouldShowSleepSessionBandChart && !shouldShowSleepScoreBreakdownChart {
                TrendDebugLogger.logMetricChart(
                    source: "睡眠核心指标趋势卡",
                    metric: metric,
                    range: range,
                    rawPoints: metric.points.sorted { $0.date < $1.date },
                    renderedPoints: renderedChartPoints,
                    xDomain: dateDomain,
                    xAxisDates: axisDates,
                    yDomain: yDomain,
                    yAxisValues: axisValues
                )
            }
        }
    }

    private var shouldShowSleepStageTimeline: Bool {
        range == .day && metric.title == "睡眠总时长" && !sleepStages.isEmpty && latestSleepInterval != nil
    }

    private var shouldShowSleepSessionBandChart: Bool {
        range == .day && metric.title != "睡眠总时长" && metric.title != "睡眠评分" && latestSleepInterval != nil && !chartPoints.isEmpty
    }

    private var shouldShowSleepScoreBreakdownChart: Bool {
        range == .day && metric.title == "睡眠评分" && latestSleepInterval != nil && latestCompositeScore != nil
    }

    private var latestCompositeScore: SleepCompositeScoreBreakdown? {
        guard let summary = nightSummaries.last else { return sleepCompositeScores.last }
        let calendar = Calendar.current
        return sleepCompositeScores.last(where: { calendar.isDate($0.day, inSameDayAs: summary.day) }) ?? sleepCompositeScores.last
    }

    private var latestSleepInterval: SleepInterval? {
        guard let summary = nightSummaries.last else { return nil }
        return SleepInterval(start: summary.startTime, end: summary.endTime)
    }

    private func sleepCoreMetricChip(title: String, value: String) -> some View {
        BBChartMetricPill(title: title, value: value, tint: tint)
    }

    private func sleepScoreHeadline(for composite: SleepCompositeScoreBreakdown) -> String {
        let weakest = weakestSleepScoreTitle(for: composite)
        switch composite.overallScore {
        case 85...:
            return String(localized: "昨夜综合恢复完成度较稳，当前更适合继续盯住 \(weakest) 是否能进一步补强。")
        case 70..<85:
            return String(localized: "昨夜综合恢复已进入可读区间，但 \(weakest) 仍在拉低整体睡眠评分。")
        case 55..<70:
            return String(localized: "昨夜睡眠评分仍有明显短板，当前主要受 \(weakest) 拖累。")
        default:
            return String(localized: "昨夜综合恢复偏弱，建议先从 \(weakest) 这一项开始排查。")
        }
    }

    private func sleepScoreDetail(for composite: SleepCompositeScoreBreakdown) -> String {
        let strongest = strongestSleepScoreTitle(for: composite)
        let weakest = weakestSleepScoreTitle(for: composite)
        return String(localized: "这张评分卡把时长、规律性、效率、深度恢复、精神恢复和生理恢复合成一张可解释结果。当前由 \(strongest) 提供主要支撑，而 \(weakest) 是更值得优先跟进的短板。")
    }

    private func weakestSleepScoreTitle(for composite: SleepCompositeScoreBreakdown) -> String {
        sleepScoreComponents(for: composite).min(by: { $0.value < $1.value })?.title ?? "睡眠时长"
    }

    private func strongestSleepScoreTitle(for composite: SleepCompositeScoreBreakdown) -> String {
        sleepScoreComponents(for: composite).max(by: { $0.value < $1.value })?.title ?? "睡眠时长"
    }

    private func sleepScoreComponents(for composite: SleepCompositeScoreBreakdown) -> [(title: String, value: Double)] {
        [
            ("睡眠时长", composite.sleepDurationScore),
            ("睡眠规律性", composite.sleepRegularityScore),
            ("睡眠效率", composite.sleepEfficiencyScore),
            ("深度恢复", composite.deepRecoveryScore),
            ("精神恢复", composite.mentalRecoveryScore),
            ("生理恢复", composite.physiologicalRecoveryScore)
        ]
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        selectedPoint = chartPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func selectionDescription(for point: TimeSeriesPointDouble) -> String {
        guard hasTrendBaseline else {
            return String(localized: "当前样本不足，至少需要 2 个真实样本后才能判断与近期基线的差异。")
        }
        guard let averageValue else {
            return String(localized: "当前样本已记录，继续积累更多天后更适合做基线判断。")
        }
        let delta = point.value - averageValue
        let deltaText = TrendMetricValueFormatter.string(for: abs(delta), unit: metric.unit)
        if abs(delta) <= max(0.1, abs(averageValue) * 0.05) {
            return String(localized: "这一时点与近期基线接近，变化相对平稳。")
        }
        return delta > 0 ? "这一时点高于近期基线 \(deltaText)。" : "这一时点低于近期基线 \(deltaText)。"
    }

    private func sleepIntradayAnchorDate(for point: TimeSeriesPointDouble) -> Date? {
        guard range == .day else { return nil }

        let calendar = Calendar.current
        if let matchedNight = nightSummaries.first(where: { calendar.isDate($0.day, inSameDayAs: point.date) }) {
            let midpoint = matchedNight.startTime.timeIntervalSince1970
                + matchedNight.endTime.timeIntervalSince(matchedNight.startTime) / 2.0
            return Date(timeIntervalSince1970: midpoint)
        }

        let startOfDay = calendar.startOfDay(for: point.date)
        return calendar.date(byAdding: .hour, value: 12, to: startOfDay)
    }

    private func sleepCoreAxisLabel(for date: Date) -> String {
        if range == .day, sleepSessionDateDomain != nil {
            return sleepSessionTimeLabel(for: date)
        }
        let label = TrendsSelectionFormatter.axisLabel(for: date, range: range)
        if range == .day, label == "24时" {
            return "24:00"
        }
        return label
    }

    private var sleepSessionDateDomain: ClosedRange<Date>? {
        guard range == .day else { return nil }

        let calendar = Calendar.current
        let referenceDates = chartPoints.map(\.date) + metric.points.map(\.date)

        if let matchedNight = referenceDates.compactMap({ referenceDate in
            nightSummaries.first(where: { calendar.isDate($0.day, inSameDayAs: referenceDate) })
        }).last {
            return matchedNight.startTime...matchedNight.endTime
        }

        return nil
    }

    private func sleepSessionAxisDates(for domain: ClosedRange<Date>) -> [Date] {
        let start = domain.lowerBound
        let end = domain.upperBound
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [start] }

        let tickCount = 4
        let step = duration / Double(tickCount)
        return (0...tickCount).map { index in
            if index == tickCount { return end }
            return start.addingTimeInterval(step * Double(index))
        }
    }

    private func sleepSessionTimeLabel(for date: Date) -> String {
        sleepSessionAxisFormatter.string(from: date)
    }

    private var sleepSessionAxisFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private func sleepCoreAxisValueText(_ value: Double) -> String {
        let text = TrendMetricValueFormatter.string(for: value, unit: metric.unit)
        if metric.unit.isEmpty {
            return text
        }
        if text.hasSuffix(metric.unit) {
            return String(text.dropLast(metric.unit.count))
        }
        return text
    }

    private let zeroBasedMetricTitles = ["睡眠总时长", "深睡占比", "REM 占比", "睡眠效率", "睡眠规律性", "睡眠评分"]
}

struct SleepStageTimelineContainer: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    let stages: [SleepStage]
    let sleepInterval: SleepInterval?

    private var filteredStages: [SleepStage] {
        guard let sleepInterval else { return stages }
        return stages.filter { stage in
            guard let start = stage.startDate, let end = stage.endDate else { return false }
            return end > sleepInterval.start && start < sleepInterval.end
        }
    }

    private var axisDates: [Date] {
        guard let sleepInterval else { return [] }
        return SleepTimelineAxisHelper.axisDates(start: sleepInterval.start, end: sleepInterval.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("昨夜睡眠阶段时间轴")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            SleepStageTimelineChart(
                stages: filteredStages,
                sleepInterval: sleepInterval,
                mode: .detailed
            )
            .frame(height: 216)

            SleepStageTimelineLegend()
        }
        .padding(.top, 2)
        .onAppear {
            guard let sleepInterval else { return }
            TrendDebugLogger.logSleepTimelineChart(
                source: "睡眠阶段时间轴趋势卡",
                metric: metric,
                range: range,
                sleepInterval: sleepInterval,
                axisDates: axisDates,
                stages: filteredStages
            )
        }
    }
}

private struct SleepSessionMetricBandChart: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    let chartPoints: [TimeSeriesPointDouble]
    let sleepInterval: SleepInterval
    let averageValue: Double?
    let accent: Color
    let yAxisValues: [Double]
    let yDomain: ClosedRange<Double>

    private var axisDates: [Date] {
        SleepTimelineAxisHelper.axisDates(start: sleepInterval.start, end: sleepInterval.end)
    }

    private var bandFill: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.18),
                accent.opacity(0.07)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("昨夜主睡眠窗口")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Chart {
                ForEach(chartPoints) { point in
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value(metric.title, point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(bandFill)

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value(metric.title, point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(accent.opacity(0.94))
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }

                if let latestPoint = chartPoints.last {
                    PointMark(
                        x: .value("最新时间", latestPoint.date),
                        y: .value(metric.title, latestPoint.value)
                    )
                    .foregroundStyle(Theme.Colors.onAccent)
                    .symbolSize(56)
                    .annotation(position: .overlay, alignment: .center) {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                    }
                }

                RuleMark(x: .value("开始时间", sleepInterval.start))
                    .foregroundStyle(accent.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                RuleMark(x: .value("结束时间", sleepInterval.end))
                    .foregroundStyle(accent.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if let averageValue {
                    RuleMark(y: .value("近期基线", averageValue))
                        .foregroundStyle(accent.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 216)
            .chartLegend(.hidden)
            .chartXScale(domain: sleepInterval.start...sleepInterval.end)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(timeLabel(for: date))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisValueText(number))
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .clipped()
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
                    .bbChartPlotSurface(tint: accent, cornerRadius: 18)
            }
            .onAppear {
                TrendDebugLogger.logMetricChart(
                    source: "睡眠主窗口趋势卡",
                    metric: metric,
                    range: range,
                    rawPoints: metric.points.sorted { $0.date < $1.date },
                    renderedPoints: chartPoints,
                    xDomain: sleepInterval.start...sleepInterval.end,
                    xAxisDates: axisDates,
                    yDomain: yDomain,
                    yAxisValues: yAxisValues
                )
            }
        }
        .padding(.top, 2)
    }

    private func axisValueText(_ value: Double) -> String {
        let text = TrendMetricValueFormatter.string(for: value, unit: metric.unit)
        if metric.unit.isEmpty {
            return text
        }
        if text.hasSuffix(metric.unit) {
            return String(text.dropLast(metric.unit.count))
        }
        return text
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct SleepScoreBreakdownCard: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    let breakdown: SleepCompositeScoreBreakdown
    let sleepInterval: SleepInterval
    let accent: Color

    private struct RadarItem: Identifiable {
        let id = UUID()
        let title: String
        let value: Double
        let color: Color
    }

    private var radarItems: [RadarItem] {
        [
            RadarItem(title: "睡眠时长", value: breakdown.sleepDurationScore, color: Color(hex: "5468FF")),
            RadarItem(title: "睡眠规律性", value: breakdown.sleepRegularityScore, color: Color(hex: "7B61FF")),
            RadarItem(title: "睡眠效率", value: breakdown.sleepEfficiencyScore, color: Color(hex: "5FC8BE")),
            RadarItem(title: "深度恢复", value: breakdown.deepRecoveryScore, color: Color(hex: "4B48B8")),
            RadarItem(title: "精神恢复", value: breakdown.mentalRecoveryScore, color: Color(hex: "86E4E5")),
            RadarItem(title: "生理恢复", value: breakdown.physiologicalRecoveryScore, color: Color(hex: "FF8A5B")),
            RadarItem(title: "综合评分", value: breakdown.overallScore, color: Color(hex: "F5B33F"))
        ]
    }

    private var axisDates: [Date] {
        SleepTimelineAxisHelper.axisDates(start: sleepInterval.start, end: sleepInterval.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("昨夜睡眠评分雷达图")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            sleepScoreRadarChart
                .frame(height: 260)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(radarItems) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        Text("\(Int(item.value.rounded()))分")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(item.color)
                        Text(scoreItemDescription(for: item.title, value: item.value))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.Colors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .onAppear {
                TrendDebugLogger.logSleepCompositeScoreChart(
                    metric: metric,
                    range: range,
                    sleepInterval: sleepInterval,
                    axisDates: axisDates,
                    breakdown: breakdown
                )
            }
        }
        .padding(.top, 2)
    }

    private var sleepScoreRadarChart: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = max(56, size * 0.34)
            let ringValues: [Double] = [25, 50, 75, 100]

            ZStack {
                ForEach(ringValues, id: \.self) { ringValue in
                    radarRingPath(center: center, radius: radius * CGFloat(ringValue / 100.0))
                        .stroke(
                            Color.black.opacity(ringValue == 100 ? 0.12 : 0.07),
                            style: StrokeStyle(lineWidth: ringValue == 100 ? 1 : 0.8, dash: [4, 4])
                        )
                }

                ForEach(Array(radarItems.enumerated()), id: \.offset) { index, item in
                    let axisEnd = radarPoint(
                        index: index,
                        total: radarItems.count,
                        normalizedValue: 1,
                        center: center,
                        radius: radius
                    )

                    Path { path in
                        path.move(to: center)
                        path.addLine(to: axisEnd)
                    }
                    .stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))

                    let labelPoint = radarPoint(
                        index: index,
                        total: radarItems.count,
                        normalizedValue: 1.18,
                        center: center,
                        radius: radius
                    )

                    VStack(spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text("\(Int(item.value.rounded()))")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(item.color)
                    }
                    .position(labelPoint)
                }

                radarAreaPath(center: center, radius: radius)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.24), Color(hex: "F5B33F").opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                radarAreaPath(center: center, radius: radius)
                    .stroke(accent.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                ForEach(Array(radarItems.enumerated()), id: \.offset) { index, item in
                    let point = radarPoint(
                        index: index,
                        total: radarItems.count,
                        normalizedValue: max(0, min(item.value / 100.0, 1)),
                        center: center,
                        radius: radius
                    )

                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                        )
                        .position(point)
                }

                VStack(spacing: 2) {
                    Text("综合评分")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("\(Int(breakdown.overallScore.rounded()))")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(sleepScoreCenterHint)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 2) {
                    ForEach(ringValues.reversed(), id: \.self) { ringValue in
                        Text("\(Int(ringValue))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary.opacity(0.9))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
                .position(x: center.x - radius - 24, y: center.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [accent.opacity(0.05), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    private func radarAreaPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for index in radarItems.indices {
                let point = radarPoint(
                    index: index,
                    total: radarItems.count,
                    normalizedValue: max(0, min(radarItems[index].value / 100.0, 1)),
                    center: center,
                    radius: radius
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }

    private func radarRingPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for index in radarItems.indices {
                let point = radarPoint(
                    index: index,
                    total: radarItems.count,
                    normalizedValue: 1,
                    center: center,
                    radius: radius
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }

    private func radarPoint(
        index: Int,
        total: Int,
        normalizedValue: Double,
        center: CGPoint,
        radius: CGFloat
    ) -> CGPoint {
        let safeTotal = max(total, 1)
        let angle = (-Double.pi / 2) + (Double(index) / Double(safeTotal)) * Double.pi * 2
        let scaledRadius = radius * CGFloat(normalizedValue)
        return CGPoint(
            x: center.x + cos(angle) * scaledRadius,
            y: center.y + sin(angle) * scaledRadius
        )
    }

    private var sleepScoreCenterHint: String {
        let weakest = radarItems.min(by: { $0.value < $1.value })?.title ?? "睡眠时长"
        return String(localized: "短板：\(weakest)")
    }

    private func scoreItemDescription(for title: String, value: Double) -> String {
        switch title {
        case "睡眠时长":
            return value >= 80 ? "睡眠时长基本够用" : "睡眠时长仍然偏短"
        case "睡眠规律性":
            return value >= 80 ? "作息节律较稳定" : "作息波动仍在影响恢复"
        case "睡眠效率":
            return value >= 80 ? "整夜完成度较好" : "夜里仍有一定损耗"
        case "深度恢复":
            return value >= 80 ? "深睡占比对身体恢复有支撑" : "深睡恢复仍然偏弱"
        case "精神恢复":
            return value >= 80 ? "REM 对情绪认知恢复较有支撑" : "REM 恢复仍需继续观察"
        case "生理恢复":
            return value >= 80 ? "HRV 与夜间心率恢复较稳" : "自主神经恢复仍不够稳"
        case "综合评分":
            return value >= 80 ? "整体恢复已进入较稳区间" : "整体恢复仍有提升空间"
        default:
            return "继续观察后续变化"
        }
    }
}

private extension View {
    func detailCardSurface(tint: Color? = nil) -> some View {
        self
            .padding(16)
            .bbChartSurface(tint: tint ?? Theme.Colors.accentBlue, cornerRadius: 28)
    }
}


/// 睡眠恢复基线结构体 作为趋势模块里的辅助类型。
/// 负责趋势分析展示。用于趋势页面的‘睡眠恢复’。
private struct SleepRecoveryBaselineTile: View {
    let metric: TrendCategoryMetricModel

    private var chartPoints: [TimeSeriesPointDouble] {
        metric.points.sorted { $0.date < $1.date }
    }

    private var latestValue: Double? {
        chartPoints.last?.value
    }

    private var averageValue: Double? {
        guard !chartPoints.isEmpty else { return nil }
        return chartPoints.map(\.value).reduce(0, +) / Double(chartPoints.count)
    }

    private var formattedLatest: String {
        guard let latestValue else { return metric.summary }
        return TrendMetricValueFormatter.string(for: latestValue, unit: metric.unit)
    }

    private var formattedAverage: String {
        guard let averageValue else { return "--" }
        return TrendMetricValueFormatter.string(for: averageValue, unit: metric.unit)
    }

    private var interpretationText: String {
        if metric.title.contains("夜间心率") {
            return String(localized: "夜间心率更适合看睡眠期间负荷是否回落到个人稳定区间，偏高通常提示夜间放松不足。")
        }
        if metric.title.contains("呼吸频率") {
            return String(localized: "呼吸频率更适合看睡眠期间呼吸节律是否平稳，连续偏高时更值得结合睡眠结构一起判断。")
        }
        return String(localized: "睡眠 HRV 更适合看副交感恢复反馈，持续回到基线以上时通常说明恢复储备更好。")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(interpretationText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("当前值")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(formattedLatest)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }

            HStack(spacing: 8) {
                baselineTag(title: "近期基线", value: formattedAverage)
            }
        }
        .padding(14)
        .background(Color(hex: metric.accentHex).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func baselineTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
