/// TrendDetailMetricComponents 作为趋势详情页的通用工具支撑。
/// 负责提供 chartDateDomain 等图表日期域计算和复用辅助方法。

import SwiftUI
import Charts

func chartDateDomain(for points: [TimeSeriesPointDouble]) -> ClosedRange<Date> {
    let dates = points.map(\.date)
    let lower = dates.min() ?? Date()
    let upper = dates.max() ?? Date()
    if lower == upper {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: upper) ?? upper
        return lower...end
    }
    return lower...upper
}

private func secondaryValue(
    forTimestamp timestamp: Int64?,
    in secondaryPoints: [TimeSeriesPointDouble]
) -> Double? {
    guard let timestamp else { return nil }
    if let exact = secondaryPoints.first(where: { $0.timestamp == timestamp })?.value {
        return exact
    }
    return secondaryPoints.min {
        abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp)
    }?.value
}

/// 趋势指标空状态视图 由上级页面或路由调用，作为趋势模块里的界面或内容组件。
/// 负责趋势分析展示。
struct TrendMetricEmptyStateView: View {
    let status: TrendCategoryStatus
    let title: String
    let message: String
    let accent: Color

    private var statusIcon: String {
        switch status {
        case .partial:
            return "chart.bar.doc.horizontal.fill"
        case .noData:
            return "waveform.badge.magnifyingglass"
        case .ready:
            return "chart.bar.xaxis"
        }
    }

    private var statusTitle: String {
        switch status {
        case .partial:
            return String(localized: "数据还在积累")
        case .noData:
            return String(localized: "还没有趋势数据")
        case .ready:
            return String(localized: "趋势准备中")
        }
    }

    private var statusPanelTitle: String {
        switch status {
        case .partial:
            return String(localized: "样本进度")
        case .noData:
            return String(localized: "样本积累")
        case .ready:
            return String(localized: "分析准备")
        }
    }

    private var statusPanelValue: String {
        switch status {
        case .partial:
            return String(localized: "完善中")
        case .noData:
            return String(localized: "待记录")
        case .ready:
            return String(localized: "准备中")
        }
    }

    private var recommendationTitle: String {
        switch status {
        case .partial:
            return String(localized: "建议继续积累近几日样本")
        case .noData:
            return String(localized: "建议先补充记录或持续佩戴设备")
        case .ready:
            return String(localized: "图表即将显示")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                dashboardTrendIcon(
                    primary: statusIcon,
                    badge: statusBadgeIcon,
                    accent: accent,
                    secondary: accent.opacity(0.5),
                    size: 42
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(message)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array([0.42, 0.76, 0.58, 0.9, 0.52].enumerated()), id: \.offset) { index, heightRatio in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.18 + Double(index) * 0.05),
                                    accent.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44 + 32 * heightRatio)
                }
            }
            .frame(height: 78, alignment: .bottom)

            HStack(spacing: 6) {
                summaryChip(title: "状态", value: status.title)
                summaryChip(title: statusPanelTitle, value: statusPanelValue)
            }

            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.78))
                    .frame(width: 4, height: 34)

                Text(recommendationTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
    }

    private var statusBadgeIcon: String {
        switch status {
        case .partial:
            return "sparkles"
        case .noData:
            return "tray.fill"
        case .ready:
            return "waveform.path.ecg"
        }
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 趋势分类指标卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。
struct TrendCategoryMetricCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    var category: TrendCategoryID? = nil
    var isStaticForExport: Bool = false

    @State private var selectedPoint: TimeSeriesPointDouble?

    init(
        metric: TrendCategoryMetricModel,
        range: TrendsRange,
        category: TrendCategoryID? = nil,
        isStaticForExport: Bool = false
    ) {
        self.metric = metric
        self.range = range
        self.category = category
        self.isStaticForExport = isStaticForExport
    }

    private var summaryModel: TrendChartInsightSummary? {
        TrendChartInsightFactory.make(
            metricTitle: metric.title,
            unit: metric.unit,
            points: metric.points,
            range: range,
            selectedPoint: selectedPoint,
            category: category
        )
    }

    private var visualizationStyle: TrendVisualizationStyle {
        TrendVisualizationResolver.style(for: metric, category: category)
    }

    private var hasRenderablePoints: Bool {
        !metric.points.isEmpty
    }

    private var sortedRenderablePoints: [TimeSeriesPointDouble] {
        metric.points.sorted { $0.date < $1.date }
    }

    private var rangeLowPoint: TimeSeriesPointDouble? {
        sortedRenderablePoints.min { $0.value < $1.value }
    }

    private var rangeHighPoint: TimeSeriesPointDouble? {
        sortedRenderablePoints.max { $0.value < $1.value }
    }

    private var activePoint: TimeSeriesPointDouble? {
        selectedPoint ?? sortedRenderablePoints.last
    }

    private var chartAccent: Color {
        Color(hex: metric.accentHex)
    }

    private var chartSystemImage: String {
        switch visualizationStyle {
        case .bar, .distribution:
            return "chart.bar.xaxis"
        case .heatStrip:
            return "square.grid.3x3.fill"
        case .segmentedSummary:
            return "chart.pie.fill"
        case .vitalsDualRangeBar:
            return "slider.horizontal.3"
        default:
            return "chart.line.uptrend.xyaxis"
        }
    }

    private var rangeChangeText: String {
        guard let first = sortedRenderablePoints.first?.value,
              let last = sortedRenderablePoints.last?.value else { return "--" }
        let delta = last - first
        let value = TrendMetricValueFormatter.string(for: abs(delta), unit: metric.unit)
        if abs(delta) < 0.0001 { return "持平" }
        return delta > 0 ? "+\(value)" : "-\(value)"
    }

    private var visualizationHeight: CGFloat {
        switch visualizationStyle {
        case .distribution:
            return 232
        case .heatStrip:
            return range == .month ? 248 : 222
        case .segmentedSummary:
            return 260
        default:
            return 196
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BBChartHeader(
                title: metric.title,
                subtitle: summaryModel?.selectionHeadline ?? metric.summary,
                systemImage: chartSystemImage,
                tint: chartAccent,
                titleSize: 16,
                iconSize: 30,
                iconSymbolSize: 13
            )
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedPoint?.timestamp)

            if let summaryModel, hasRenderablePoints {
                Text(summaryModel.headline)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedPoint?.timestamp)
            }

            if summaryModel != nil, hasRenderablePoints {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        metricHighlightBlock(title: "当前值", value: currentDisplayValueText, tint: chartAccent)
                        metricHighlightBlock(title: "区间均值", value: averageDisplayValueText, tint: chartAccent.opacity(0.78))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if hasRenderablePoints {
                VStack(alignment: .leading, spacing: 10) {
                    TrendVisualizationCard(
                        style: visualizationStyle,
                        metric: metric,
                        category: category,
                        range: range,
                        accentColor: chartAccent,
                        selectedPoint: $selectedPoint,
                        isStaticForExport: isStaticForExport
                    )
                    .frame(height: visualizationHeight)
                    .padding(10)
                    .bbChartPlotSurface(tint: chartAccent, cornerRadius: 18)

                    if let activePoint {
                        BBChartSelectionReadout(
                            title: TrendsSelectionFormatter.title(for: activePoint.date, range: range),
                            value: currentDisplayValueText,
                            detail: selectedPoint == nil ? "最新读数" : "当前选择",
                            tint: chartAccent,
                            systemImage: selectedPoint == nil ? "clock.fill" : "scope"
                        )
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedPoint?.timestamp)
                    }

                    HStack(spacing: 8) {
                        chartRangeFact(
                            title: "低点",
                            point: rangeLowPoint,
                            systemImage: "arrow.down.right"
                        )
                        chartRangeFact(
                            title: "高点",
                            point: rangeHighPoint,
                            systemImage: "arrow.up.right"
                        )
                        chartRangeFact(
                            title: "首末变化",
                            value: rangeChangeText,
                            detail: "\(sortedRenderablePoints.count) 个样本",
                            systemImage: "arrow.left.and.right"
                        )
                    }

                    Text(summaryModel?.footer ?? metric.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedPoint?.timestamp)

                    if let summaryModel, !summaryModel.supportingLines.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(summaryModel.supportingLines) { line in
                                metricInsightRow(line: line)
                            }
                        }
                    }
                }
            } else {
                TrendMetricEmptyStateView(
                    status: metric.status,
                    title: metric.title,
                    message: metric.emptyMessage,
                    accent: chartAccent
                )
            }
        }
        .padding(14)
        .bbChartSurface(tint: chartAccent, cornerRadius: 22)
        .onChange(of: range) { _, _ in
            selectedPoint = nil
        }
    }

    private func metricHighlightBlock(title: String, value: String, tint: Color) -> some View {
        BBChartMetricPill(title: title, value: value, tint: tint, size: .compact)
    }

    private func chartRangeFact(
        title: String,
        point: TimeSeriesPointDouble?,
        systemImage: String
    ) -> some View {
        chartRangeFact(
            title: title,
            value: point.map { TrendMetricValueFormatter.string(for: $0.value, unit: metric.unit) } ?? "--",
            detail: point.map { TrendsSelectionFormatter.title(for: $0.date, range: range) } ?? "暂无",
            systemImage: systemImage
        )
    }

    private func chartRangeFact(
        title: String,
        value: String,
        detail: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: metric.accentHex).opacity(0.10), lineWidth: 1)
        )
    }

    private var currentDisplayValueText: String {
        if metric.title.contains("血压"),
           let systolic = selectedPoint?.value ?? metric.points.last?.value,
           let diastolic = secondaryValueForMetric(timestamp: selectedPoint?.timestamp ?? metric.points.last?.timestamp) {
            return "\(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg"
        }
        return summaryModel?.currentValueText ?? metric.summary
    }

    private var averageDisplayValueText: String {
        if metric.title.contains("血压"),
           !metric.points.isEmpty,
           !metric.secondaryPoints.isEmpty {
            let systolicAverage = metric.points.map(\.value).reduce(0, +) / Double(metric.points.count)
            let diastolicAverage = metric.secondaryPoints.map(\.value).reduce(0, +) / Double(metric.secondaryPoints.count)
            return "\(Int(systolicAverage.rounded()))/\(Int(diastolicAverage.rounded())) mmHg"
        }
        return summaryModel?.averageValueText ?? metric.summary
    }

    private func secondaryValueForMetric(timestamp: Int64?) -> Double? {
        secondaryValue(forTimestamp: timestamp, in: metric.secondaryPoints)
    }

    private func metricInsightRow(line: TrendChartInsightLineItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(hex: metric.accentHex).opacity(0.82))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(line.detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}

// 详情指标图表相关的可视化、选中态、格式化和摘要逻辑统一放在这里，
// 让二级详情里的指标卡片共享同一套维护入口。
/// 趋势Visualization卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。
struct TrendVisualizationCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: TrendVisualizationStyle
    let metric: TrendCategoryMetricModel
    let category: TrendCategoryID?
    let range: TrendsRange
    let accentColor: Color
    @Binding var selectedPoint: TimeSeriesPointDouble?
    let isStaticForExport: Bool
    @State private var isLongPressActivated = false
    @State private var currentTouchLocation: CGPoint?

    init(
        style: TrendVisualizationStyle,
        metric: TrendCategoryMetricModel,
        category: TrendCategoryID?,
        range: TrendsRange,
        accentColor: Color,
        selectedPoint: Binding<TimeSeriesPointDouble?>,
        isStaticForExport: Bool
    ) {
        self.style = style
        self.metric = metric
        self.category = category
        self.range = range
        self.accentColor = accentColor
        self._selectedPoint = selectedPoint
        self.isStaticForExport = isStaticForExport
    }

    private var points: [TimeSeriesPointDouble] {
        normalizedDetailPoints(from: metric.points.sorted { $0.date < $1.date })
    }

    private var renderedLinePoints: [TimeSeriesPointDouble] {
        expandedDailySingleRenderPoints(from: points)
    }

    private var selectedBodyCompositionFocusPoints: [TimeSeriesPointDouble] {
        selectedPoint.map { [$0] } ?? []
    }

    private var latestBodyCompositionFocusPoints: [TimeSeriesPointDouble] {
        selectedPoint == nil ? points.last.map { [$0] } ?? [] : []
    }

    private var dateDomain: ClosedRange<Date> {
        resolvedDateDomain
    }

    private var meanValue: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private var minValue: Double? {
        points.map(\.value).min()
    }

    private var maxValue: Double? {
        points.map(\.value).max()
    }

    private var latestValue: Double? {
        points.last?.value
    }

    private var isWalkingSpeedMetric: Bool {
        metric.title == "步行速度"
    }

    private var shouldUseMobilityReferenceTrendChart: Bool {
        (metric.title == "步伐不对称" || metric.title == "双足支撑时间") && range != .day
    }

    private var shouldUseAppleHealthReferenceChart: Bool {
        guard range == .day else { return false }
        let supportedTitles = ["步行步长", "步行速度", "步伐不对称", "双足支撑时间"]
        return supportedTitles.contains(metric.title)
    }

    private var debugRenderMode: String {
        if shouldUseMobilityReferenceTrendChart { return "mobility_week_reference" }
        if shouldUseAppleHealthReferenceChart { return "apple_health_reference" }
        if isWalkingSpeedMetric { return "walking_speed_combo" }
        if shouldUseHRVDailyDetailChart { return "hrv_daily_detail" }
        if shouldUseHeartRateDailyDetailChart { return "heart_rate_daily_detail" }
        if shouldUseBodyWeightTrendChart { return "line_area_body_weight" }
        if shouldUseBodyCompositionBandChart { return "body_composition_band" }
        switch style {
        case .lineArea: return "line_area"
        case .bar: return "bar"
        case .rangeBand: return "range_band"
        case .distribution: return "distribution"
        case .heatStrip: return "heat_strip"
        case .segmentedSummary: return "segmented_summary"
        case .vitalsSinglePoint: return "vitals_single_point"
        case .vitalsAreaLine: return "vitals_area_line"
        case .vitalsSegmentDotTrend: return "vitals_segment_dot_trend"
        case .vitalsSoftRecoveryLine: return "vitals_soft_recovery_line"
        case .vitalsDualRangeBar: return "vitals_dual_range_bar"
        }
    }

    private var debugRenderNotes: [String] {
        var notes: [String] = []
        if shouldUseMobilityReferenceTrendChart {
            notes.append("mobility_reference=health_detail_near_7_days")
        }
        if shouldUseAppleHealthReferenceChart {
            notes.append("apple_health_titles=步行步长/步行速度/步伐不对称/双足支撑时间")
        }
        if range == .day, metric.points.count == 1 {
            notes.append("single_point_day_normalized=true")
        }
        if metric.unit == "%" {
            notes.append("percent_metric_displayed_as_percentage=true")
        }
        return notes
    }

    /// Detail HRV Daily Chart Flag 属性，负责趋势分析展示。用于趋势页面的‘HRV日视图参考步速趋势刻度图表’
    private var shouldUseHRVDailyDetailChart: Bool {
        range == .day && (metric.title == "HRV" || metric.title == "心率变异性（HRV）")
    }

    /// Detail Heart Rate Daily Chart Flag 属性，负责趋势分析展示。用于趋势页面的‘核心心血管日视图参考健康页静息心率图表’
    private var shouldUseHeartRateDailyDetailChart: Bool {
        guard range == .day else { return false }
        let heartRateTitles = ["心率", "静息心率", "步行平均心率"]
        return category == .heartCardio && heartRateTitles.contains(metric.title)
    }

    private var isBodyMetricsCategory: Bool {
        category == .bodyMetrics
    }

    private var shouldUseBodyWeightTrendChart: Bool {
        isBodyMetricsCategory && metric.title == "体重"
    }

    private var shouldUseBodyCompositionBandChart: Bool {
        isBodyMetricsCategory && (metric.title == "BMI" || metric.title == "体脂率")
    }

    /// Detail Metric Fixed Domain 属性，负责趋势分析展示。用于趋势页面的‘日常基础消耗完整周期刻度’
    private var shouldUseFixedDateDomain: Bool {
        // 周/月详情图需要始终保留完整周期刻度，避免因为前几天暂无采样导致 x 轴从中间开始。
        if range != .day {
            return true
        }
        if category == .environmentSenses {
            return true
        }
        // 日视图至少要保留完整 24 小时域，单点时也不能把时间轴压缩成一个点。
        return points.count == 1
    }

    var body: some View {
        Group {
            if shouldUseMobilityReferenceTrendChart {
                MobilityReferenceTrendChart(
                    metricTitle: metric.title,
                    points: points,
                    accentColor: accentColor
                )
            } else if shouldUseAppleHealthReferenceChart {
                AppleHealthReferenceChart(
                    metric: metric,
                    range: range,
                    selectedPoint: $selectedPoint,
                    isStaticForExport: isStaticForExport
                )
            } else if isWalkingSpeedMetric {
                WalkingSpeedTrendComboChart(
                    metric: metric,
                    range: range,
                    accentColor: accentColor,
                    selectedPoint: $selectedPoint,
                    isStaticForExport: isStaticForExport
                )
            } else if shouldUseHRVDailyDetailChart {
                hrvDailyDetailChart
            } else if shouldUseHeartRateDailyDetailChart {
                heartRateDailyDetailChart
            } else if shouldUseBodyWeightTrendChart {
                lineAreaChart
            } else if shouldUseBodyCompositionBandChart {
                bodyCompositionBandChart
            } else {
                switch style {
                case .lineArea:
                    lineAreaChart
                case .bar:
                    barTrendChart
                case .rangeBand:
                    rangeBandChart
                case .distribution:
                    distributionChart
                case .heatStrip:
                    heatStripChart
                case .segmentedSummary:
                    segmentedSummaryChart
                case .vitalsSinglePoint:
                    vitalsSinglePointChart
                case .vitalsAreaLine:
                    vitalsAreaLineChart
                case .vitalsSegmentDotTrend:
                    vitalsSegmentDotTrendChart
                case .vitalsSoftRecoveryLine:
                    vitalsSoftRecoveryLineChart
                case .vitalsDualRangeBar:
                    vitalsDualRangeBarChart
                }
            }
        }
        .onAppear {
            TrendDebugLogger.logMetricChart(
                source: "趋势可视化卡片",
                metric: metric,
                range: range,
                rawPoints: metric.points.sorted { $0.date < $1.date },
                renderedPoints: renderedLinePoints,
                renderMode: debugRenderMode,
                rawPointCount: metric.points.count,
                renderedPointCount: renderedLinePoints.count,
                notes: debugRenderNotes,
                xDomain: dateDomain,
                xAxisDates: resolvedXAxisDatesForDebug,
                yDomain: resolvedYDomainForDebug,
                yAxisValues: resolvedYAxisValuesForDebug
            )
        }
    }

    private var resolvedDateDomain: ClosedRange<Date> {
        guard shouldUseFixedDateDomain else {
            return chartDateDomain(for: points)
        }
        let calendar = Calendar.current
        let start = range == .day
            ? calendar.startOfDay(for: (points.first?.date ?? metric.points.first?.date ?? Date()))
            : calendar.startOfDay(for: range.startDate)
        let end = calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start
        return start...end
    }

    /// Detail Metric Point Normalizer 方法，负责趋势分析展示。用于趋势页面的‘二级详情日视图单点居中显示’
    private func normalizedDetailPoints(from points: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        guard range == .day, points.count == 1, let point = points.first else {
            return points
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: point.date)
        guard let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else {
            return points
        }
        return [TimeSeriesPointDouble(timestamp: Int64(noon.timeIntervalSince1970), value: point.value)]
    }

    private func expandedDailySingleRenderPoints(from points: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        guard range == .day, points.count == 1, let point = points.first else {
            return points
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: point.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let left = calendar.date(byAdding: .minute, value: -45, to: point.date),
              let right = calendar.date(byAdding: .minute, value: 45, to: point.date) else {
            return points
        }

        let clampedLeft = max(left, startOfDay)
        let clampedRight = min(right, dayEnd)
        return [
            TimeSeriesPointDouble(timestamp: Int64(clampedLeft.timeIntervalSince1970), value: point.value),
            point,
            TimeSeriesPointDouble(timestamp: Int64(clampedRight.timeIntervalSince1970), value: point.value)
        ]
    }

    private var lineAreaChart: some View {
        SimpleTrendChart(
            title: metric.title,
            color: accentColor,
            points: renderedLinePoints,
            dateDomain: dateDomain,
            range: range,
            yDomain: simpleLineYDomain,
            selectedPoint: selectedPoint,
            meanValue: meanValue,
            isStaticForExport: isStaticForExport,
            unit: metric.unit,
            onSelectDate: { date in updateSelectedPoint(for: date) },
            onClearSelection: { selectedPoint = nil }
        )
    }

    private var vitalsAreaLineChart: some View {
        lineAreaChart
    }

    private var vitalsSinglePointChart: some View {
        SimpleTrendChart(
            title: metric.title,
            color: accentColor,
            points: renderedLinePoints,
            dateDomain: dateDomain,
            range: range,
            yDomain: simpleLineYDomain,
            selectedPoint: selectedPoint,
            meanValue: meanValue,
            isStaticForExport: isStaticForExport,
            unit: metric.unit,
            onSelectDate: { date in updateSelectedPoint(for: date) },
            onClearSelection: { selectedPoint = nil }
        )
    }

    private var vitalsSoftRecoveryLineChart: some View {
        SimpleTrendChart(
            title: metric.title,
            color: accentColor.opacity(0.9),
            points: renderedLinePoints,
            dateDomain: dateDomain,
            range: range,
            yDomain: chartYDomainForMarks,
            selectedPoint: selectedPoint,
            meanValue: meanValue,
            isStaticForExport: isStaticForExport,
            unit: metric.unit,
            onSelectDate: { date in updateSelectedPoint(for: date) },
            onClearSelection: { selectedPoint = nil }
        )
        .overlay(alignment: .topLeading) {
            Text("Recovery")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(accentColor.opacity(0.76))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accentColor.opacity(0.08), in: Capsule())
                .padding(.top, 8)
                .padding(.leading, 8)
        }
    }

    private var heartRateDailyDetailChart: some View {
        Chart(points) { item in
            LineMark(
                x: .value("时间", item.date),
                y: .value("心率", item.value)
            )
            .foregroundStyle(accentColor.opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 0.94 : 0.52))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            PointMark(
                x: .value("时间", item.date),
                y: .value("心率", item.value)
            )
            .symbolSize(item.timestamp == points.last?.timestamp ? 72 : 28)
            .foregroundStyle(Theme.Colors.onAccent)
            .annotation(position: .overlay, alignment: .center) {
                Circle()
                    .fill(accentColor)
                    .frame(width: item.timestamp == points.last?.timestamp ? 11 : 8, height: item.timestamp == points.last?.timestamp ? 11 : 8)
            }
            .opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 1 : 0.42)

            if let meanValue {
                RuleMark(y: .value("基线", meanValue))
                    .foregroundStyle(accentColor.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                RuleMark(x: .value("选中", item.date))
                    .foregroundStyle(accentColor.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("时间", item.date),
                    y: .value("心率", item.value)
                )
                .symbolSize(84)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    metricTooltip(for: selectedPoint)
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: chartYDomainForMarks)
        .chartXAxis {
            rangeBandXAxisMarks
        }
        .chartYAxis {
            metricYAxisMarks
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .padding(.bottom, 10)
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    private var hrvDailyDetailChart: some View {
        Chart {
            ForEach(points) { item in
                AreaMark(
                    x: .value("时间", item.date),
                    yStart: .value("基线", chartYDomainForMarks.lowerBound),
                    yEnd: .value("HRV", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 0.22 : 0.10), accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(points) { item in
                LineMark(
                    x: .value("时间", item.date),
                    y: .value("HRV", item.value)
                )
                .foregroundStyle(accentColor.opacity(0.94))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("时间", item.date),
                    y: .value("HRV", item.value)
                )
                .symbolSize(item.timestamp == points.last?.timestamp ? 84 : 34)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .overlay, alignment: .center) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: item.timestamp == points.last?.timestamp ? 12 : 9, height: item.timestamp == points.last?.timestamp ? 12 : 9)
                }
                .opacity(selectedPoint == nil || selectedPoint?.timestamp == item.timestamp ? 1 : 0.42)
            }

            if let meanValue {
                RuleMark(y: .value("日内均值", meanValue))
                    .foregroundStyle(accentColor.opacity(0.30))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let selectedPoint {
                RuleMark(x: .value("选中", selectedPoint.date))
                    .foregroundStyle(accentColor.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("时间", selectedPoint.date),
                    y: .value("HRV", selectedPoint.value)
                )
                .symbolSize(88)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    metricTooltip(for: selectedPoint)
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: chartYDomainForMarks)
        .chartXAxis {
            healthStyleDayXAxisMarks
        }
        .chartYAxis {
            metricYAxisMarks
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .padding(.bottom, 10)
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    private var barTrendChart: some View {
        Chart(points) { item in
            BarMark(
                x: .value("Date", item.date),
                y: .value("Value", item.value),
                width: barMarkWidth
            )
            .foregroundStyle(barGradient(for: item))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                RuleMark(x: .value("Selected", item.date))
                    .foregroundStyle(accentColor.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        metricTooltip(for: selectedPoint)
                    }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: chartYDomainForMarks)
        /// Compact Trend Y Axis 结构体，负责趋势分析展示。用于趋势页面的‘紧凑趋势卡左侧数值标尺’
        .chartYAxis {
            metricYAxisMarks
        }
        .chartXAxis {
            chartXAxisMarks
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
                .padding(.top, 4)
                .padding(.trailing, 8)
                .padding(.bottom, 12)
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    private var vitalsSegmentDotTrendChart: some View {
        Chart {
            if let meanValue {
                RuleMark(y: .value("基线", meanValue))
                    .foregroundStyle(accentColor.opacity(0.16))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(Array(points.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value),
                        series: .value("Segment", "\(index)")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(accentColor.opacity(0.78))
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [3, 4]))
                }

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .symbolSize(item.timestamp == points.last?.timestamp ? 64 : 30)
                .foregroundStyle(item.timestamp == points.last?.timestamp ? accentColor : accentColor.opacity(0.68))

                if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                    RuleMark(x: .value("Selected", item.date))
                        .foregroundStyle(accentColor.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            metricTooltip(for: selectedPoint)
                        }
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: chartYDomainForMarks)
        .chartYAxis {
            metricYAxisMarks
        }
        .chartXAxis {
            chartXAxisMarks
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    /// Detail Metric Bar Width 属性，负责趋势分析展示。用于趋势页面的‘日常基础消耗不同周期柱宽适配’
    private var barMarkWidth: MarkDimension {
        switch range {
        case .day:
            return .fixed(18)
        case .week:
            return .fixed(14)
        case .month:
            return .fixed(10)
        }
    }

    private var rangeBandChart: some View {
        Chart(points) { item in
            if shouldRenderRangeEnvelope, let meanValue, let minValue, let maxValue {
                AreaMark(
                    x: .value("Date", item.date),
                    yStart: .value("Min", minValue),
                    yEnd: .value("Max", maxValue)
                )
                .foregroundStyle(accentColor.opacity(0.10))

                RuleMark(y: .value("Mean", meanValue))
                    .foregroundStyle(accentColor.opacity(0.20))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if shouldRenderFilledTrend {
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.28), accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            LineMark(
                x: .value("Date", item.date),
                y: .value("Value", item.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(accentColor)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if points.count == 1 {
                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .symbolSize(60)
                .foregroundStyle(accentColor)
            }

            if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                RuleMark(x: .value("Selected", item.date))
                    .foregroundStyle(accentColor.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .symbolSize(52)
                .foregroundStyle(accentColor)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    metricTooltip(for: selectedPoint)
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: chartYDomainForMarks)
        .chartXAxis {
            rangeBandXAxisMarks
        }
        /// Range Band Y Axis 结构体，负责趋势分析展示。用于趋势页面的‘区间带样式左侧数值标尺’
        .chartYAxis {
            metricYAxisMarks
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
                .padding(.top, 6)
                .padding(.trailing, 8)
                .padding(.bottom, 14)
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    private var vitalsDualRangeBarChart: some View {
        Chart {
            if let meanValue {
                RuleMark(y: .value("Mean", meanValue))
                    .foregroundStyle(accentColor.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(points) { item in
                let lowerValue = secondaryValue(forTimestamp: item.timestamp, in: metric.secondaryPoints) ?? max(chartYDomainForMarks.lowerBound, item.value - 8)
                BarMark(
                    x: .value("Date", item.date),
                    yStart: .value("Lower", max(chartYDomainForMarks.lowerBound, lowerValue)),
                    yEnd: .value("Upper", min(chartYDomainForMarks.upperBound, item.value)),
                    width: barMarkWidth
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.28), accentColor.opacity(0.88)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                    RuleMark(x: .value("Selected", item.date))
                        .foregroundStyle(accentColor.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            metricTooltip(for: selectedPoint)
                        }
                }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: chartYDomainForMarks)
        .chartYAxis {
            metricYAxisMarks
        }
        .chartXAxis {
            chartXAxisMarks
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    private var bodyCompositionBandChart: some View {
        Chart {
            RectangleMark(
                xStart: .value("区间起点", dateDomain.lowerBound),
                xEnd: .value("区间终点", dateDomain.upperBound),
                yStart: .value("建议下限", bodyCompositionRecommendedBand.lowerBound),
                yEnd: .value("建议上限", bodyCompositionRecommendedBand.upperBound)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [accentColor.opacity(0.14), accentColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            ForEach(points) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(selectedBodyCompositionFocusPoints) { point in
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(accentColor.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .symbolSize(56)
                .foregroundStyle(accentColor)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    metricTooltip(for: point)
                }
            }

            ForEach(latestBodyCompositionFocusPoints) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .symbolSize(40)
                .foregroundStyle(accentColor)
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: bodyCompositionChartYDomain)
        .chartXAxis {
            rangeBandXAxisMarks
        }
        .chartYAxis {
            metricYAxisMarks
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
                .padding(.top, 6)
                .padding(.trailing, 8)
                .padding(.bottom, 14)
        }
        .chartOverlay { proxy in
            chartSelectionOverlay(proxy: proxy)
        }
    }

    private var distributionChart: some View {
        let segments = distributionSegments
        let displayedPoints = Array(points.suffix(min(range == .month ? 14 : 8, points.count)))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(segment.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(segment.valueText)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Capsule()
                            .fill(segment.tint.opacity(0.18))
                            .frame(height: 8)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(segment.tint)
                                    .frame(width: max(18, segment.ratio * 88), height: 8)
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Chart {
                if let meanValue {
                    RuleMark(y: .value("区间均值", meanValue))
                        .foregroundStyle(accentColor.opacity(0.26))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                ForEach(displayedPoints) { item in
                    BarMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value),
                        width: .ratio(range == .day ? 0.72 : 0.62)
                    )
                    .foregroundStyle(barGradient(for: item))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                        RuleMark(x: .value("选中", item.date))
                            .foregroundStyle(accentColor.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                            .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                metricTooltip(for: selectedPoint)
                            }
                    }
                }
            }
            .chartXScale(domain: dateDomain)
            .chartYScale(domain: chartYDomainForMarks)
            .chartXAxis {
                chartXAxisMarks
            }
            .chartYAxis {
                metricYAxisMarks
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .clipped()
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
            }
            .chartOverlay { proxy in
                chartSelectionOverlay(proxy: proxy)
            }
            .frame(height: 116)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var heatStripChart: some View {
        let heatRows = heatmapRows
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(range == .day ? "强弱时段" : "频次矩阵")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text(metric.unit.isEmpty ? "标准化" : metric.unit)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }

            VStack(spacing: 8) {
                ForEach(Array(heatRows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 6) {
                        Text(heatRowLabel(for: row))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .frame(width: 42, alignment: .leading)

                        ForEach(0..<heatmapColumnCount, id: \.self) { index in
                            if index < row.count {
                                let point = row[index]
                                Button {
                                    selectedPoint = point
                                } label: {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(heatColor(for: normalizedHeatValue(for: point), index: index + rowIndex))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 18)
                                        .overlay {
                                            if selectedPoint?.timestamp == point.timestamp {
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(Color.white, lineWidth: 2)
                                                    .shadow(color: accentColor.opacity(0.30), radius: 3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(isStaticForExport)
                                .accessibilityLabel(selectionText(for: point))
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 18)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                heatLegendItem(title: "低", value: 0.18)
                heatLegendItem(title: "中", value: 0.55)
                heatLegendItem(title: "高", value: 0.90)
                Spacer(minLength: 0)
            }

            if let selectedPoint {
                Text(selectionText(for: selectedPoint))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private var segmentedSummaryChart: some View {
        let segments = distributionSegments
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("结构概览")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(primarySegmentLabel)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                Spacer()
                if let latestValue {
                    Text(TrendMetricValueFormatter.string(for: latestValue, unit: metric.unit))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(accentColor)
                }
            }

            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width - CGFloat(max(segments.count - 1, 0)) * 6)
                HStack(spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(segment.tint)
                            .frame(width: availableWidth * displaySegmentRatios[index], height: 22)
                            .overlay(alignment: .center) {
                                Text(segment.title)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.onAccent.opacity(0.94))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .opacity(segment.ratio > 0.01 ? 1 : 0.3)
                    }
                }
            }
            .frame(height: 22)

            HStack(spacing: 10) {
                ForEach(segments, id: \.title) { segment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(segment.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(segment.valueText)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Chart {
                if let meanValue {
                    RuleMark(y: .value("区间均值", meanValue))
                        .foregroundStyle(accentColor.opacity(0.26))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                ForEach(points) { item in
                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor.opacity(0.18), accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    if points.count == 1 {
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Value", item.value)
                        )
                        .symbolSize(44)
                        .foregroundStyle(accentColor)
                    }

                    if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                        RuleMark(x: .value("选中", item.date))
                            .foregroundStyle(accentColor.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                            .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                metricTooltip(for: selectedPoint)
                            }
                    }
                }
            }
            .chartXScale(domain: dateDomain)
            .chartYScale(domain: chartYDomainForMarks)
            .chartXAxis {
                chartXAxisMarks
            }
            .chartYAxis {
                metricYAxisMarks
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .clipped()
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
            .chartOverlay { proxy in
                chartSelectionOverlay(proxy: proxy)
            }
            .frame(height: 96)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var chartXAxisMarks: some AxisContent {
        AxisMarks(values: resolvedXAxisDatesForLabels) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(xAxisLabel(for: date))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: range == .week ? 26 : .infinity)
                }
            }
            .font(.system(size: range == .week ? 8.5 : 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var healthStyleDayXAxisMarks: some AxisContent {
        AxisMarks(values: healthStyleDayAxisDates) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(healthStyleDayAxisLabel(for: date))
                        .multilineTextAlignment(.center)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var rangeBandXAxisMarks: some AxisContent {
        AxisMarks(values: resolvedXAxisDatesForLabels) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(xAxisLabel(for: date))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: range == .week ? 26 : .infinity)
                }
            }
            .font(.system(size: range == .week ? 8.5 : 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var rangeBandAxisDates: [Date] {
        switch range {
        case .day:
            guard let anchorDate = points.first?.date ?? metric.points.first?.date else { return [] }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: anchorDate)
            return stride(from: 0, through: 24, by: 4).compactMap { hour in
                calendar.date(byAdding: .hour, value: hour, to: start)
            }
        case .week, .month:
            return TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)
        }
    }

    private var healthStyleDayAxisDates: [Date] {
        guard let anchorDate = points.first?.date ?? metric.points.first?.date else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: anchorDate)
        return [0, 6, 12, 18, 24].compactMap { hour in
            calendar.date(byAdding: .hour, value: hour, to: start)
        }
    }

    /// Detail Range Band Envelope Flag 属性，负责趋势分析展示。用于趋势页面的‘区间带图稀疏数据弱化残影’
    private var shouldRenderRangeEnvelope: Bool {
        points.count >= 2 && range != .day
    }

    /// Detail Range Band Filled Trend Flag 属性，负责趋势分析展示。用于趋势页面的‘日视图单点和稀疏点避免面积层遮挡’
    private var shouldRenderFilledTrend: Bool {
        points.count >= 2
    }

    private var metricYAxisMarks: some AxisContent {
        /// Metric Y Axis Marks 结构体，负责趋势分析展示。用于趋势页面的‘紧凑趋势卡左侧刻度’
        AxisMarks(position: .leading, values: TrendYAxisDesigner.axisValues(for: chartYDomainForMarks, range: range)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(axisValueText(number))
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var chartYDomainForMarks: ClosedRange<Double> {
        if let minValue, let maxValue {
            let domain = TrendYAxisDesigner.domain(for: [minValue, maxValue], range: range)
            if shouldClampYAxisToZero {
                return 0...max(domain.upperBound, 1)
            }
            return domain
        }
        let domain = TrendYAxisDesigner.domain(for: points.map(\.value), range: range)
        if shouldClampYAxisToZero {
            return 0...max(domain.upperBound, 1)
        }
        return domain
    }

    private var bodyCompositionRecommendedBand: ClosedRange<Double> {
        switch metric.title {
        case "BMI":
            return 18.5...24.0
        case "体脂率":
            return 18.0...28.0
        default:
            return chartYDomainForMarks
        }
    }

    private var bodyCompositionChartYDomain: ClosedRange<Double> {
        let baseDomain = chartYDomainForMarks
        return min(baseDomain.lowerBound, bodyCompositionRecommendedBand.lowerBound)...max(baseDomain.upperBound, bodyCompositionRecommendedBand.upperBound)
    }

    private var shouldClampYAxisToZero: Bool {
        if style == .bar || style == .distribution {
            return true
        }
        let zeroBasedTitles = ["步数", "活动能量", "静息能量", "步行距离", "爬楼层数", "步行速度", "睡眠总时长"]
        return zeroBasedTitles.contains(metric.title)
    }

    private var resolvedXAxisDatesForDebug: [Date] {
        if shouldUseHRVDailyDetailChart {
            return healthStyleDayAxisDates
        }
        switch style {
        case .rangeBand:
            return rangeBandAxisDates
        default:
            return resolvedXAxisDates
        }
    }

    private var resolvedYDomainForDebug: ClosedRange<Double> {
        shouldUseBodyCompositionBandChart ? bodyCompositionChartYDomain : chartYDomainForMarks
    }

    private var resolvedYAxisValuesForDebug: [Double] {
        TrendYAxisDesigner.axisValues(for: resolvedYDomainForDebug, range: range)
    }

    private var resolvedXAxisDates: [Date] {
        return TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)
    }

    private var resolvedXAxisDatesForLabels: [Date] {
        style == .rangeBand ? rangeBandAxisDates : resolvedXAxisDates
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

    private func healthStyleDayAxisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: dateDomain.lowerBound)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return TrendsSelectionFormatter.axisLabel(for: date, range: .day)
        }
        if abs(date.timeIntervalSince(end)) < 1 {
            return "24:00"
        }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func xAxisLabel(for date: Date) -> String {
        return TrendsSelectionFormatter.axisLabel(for: date, range: range)
    }

    private func chartSelectionOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .allowsHitTesting(!isStaticForExport)
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard !isStaticForExport else { return }
                            updateSelectedPoint(at: value.location, proxy: proxy, geometry: geometry)
                        }
                )
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

    private func updateSelectedPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let locationX = location.x - frame.origin.x
        guard locationX >= 0,
              locationX <= proxy.plotSize.width,
              let date: Date = proxy.value(atX: locationX) else {
            return
        }
        updateSelectedPoint(for: date)
    }

    private func updateSelectedPoint(for date: Date) {
        guard !points.isEmpty else {
            selectedPoint = nil
            return
        }
        selectedPoint = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func axisLabel(for value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 100 || value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private var yDomainForVitalsRespiratory: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 12...22
        }

        let lower = min(12, floor(minValue - 1))
        let upper = max(22, ceil(maxValue + 1))
        return lower...upper
    }

    private var simpleLineYDomain: ClosedRange<Double> {
        if category == .vitalsRespiratory && metric.title.contains("呼吸率") {
            return yDomainForVitalsRespiratory
        }
        return chartYDomainForMarks
    }

    private func metricTooltip(for point: TimeSeriesPointDouble) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectionTitle(for: point.date))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(tooltipValueText(for: point))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: MotionTokens.tooltipOffsetY)))
    }

    private func tooltipValueText(for point: TimeSeriesPointDouble) -> String {
        if metric.title.contains("血压"),
           let diastolic = secondaryValue(forTimestamp: point.timestamp, in: metric.secondaryPoints) {
            let riskLabel = bloodPressureRiskLabel(systolic: point.value, diastolic: diastolic)
            return "\(Int(point.value.rounded()))/\(Int(diastolic.rounded())) mmHg · \(riskLabel)"
        }
        return TrendMetricValueFormatter.string(for: point.value, unit: metric.unit)
    }

    private func bloodPressureRiskLabel(systolic: Double, diastolic: Double) -> String {
        if systolic >= 135 || diastolic >= 85 {
            return String(localized: "偏高")
        }
        if systolic <= 100 || diastolic <= 60 {
            return String(localized: "偏低")
        }
        return String(localized: "平稳")
    }

    private func selectionTitle(for date: Date) -> String {
        return TrendsSelectionFormatter.title(for: date, range: range)
    }

    private var distributionSegments: [TrendDistributionSegment] {
        guard !points.isEmpty,
              let minValue,
              let maxValue,
              maxValue > minValue else {
            return [
                TrendDistributionSegment(title: "低位", valueText: "--", ratio: 0.33, tint: accentColor.opacity(0.45)),
                TrendDistributionSegment(title: "中段", valueText: "--", ratio: 0.33, tint: accentColor.opacity(0.68)),
                TrendDistributionSegment(title: "高位", valueText: "--", ratio: 0.34, tint: accentColor)
            ]
        }

        let threshold1 = minValue + (maxValue - minValue) / 3
        let threshold2 = minValue + (maxValue - minValue) * 2 / 3
        let lowerCount = Double(points.filter { $0.value < threshold1 }.count)
        let middleCount = Double(points.filter { $0.value >= threshold1 && $0.value < threshold2 }.count)
        let upperCount = Double(points.filter { $0.value >= threshold2 }.count)
        let total = Double(max(points.count, 1))

        return [
            TrendDistributionSegment(title: "低位", valueText: "\(Int((lowerCount / total * 100).rounded()))%", ratio: CGFloat(lowerCount / total), tint: accentColor.opacity(0.42)),
            TrendDistributionSegment(title: "中段", valueText: "\(Int((middleCount / total * 100).rounded()))%", ratio: CGFloat(middleCount / total), tint: accentColor.opacity(0.68)),
            TrendDistributionSegment(title: "高位", valueText: "\(Int((upperCount / total * 100).rounded()))%", ratio: CGFloat(upperCount / total), tint: accentColor)
        ]
    }

    private var heatmapRows: [[TimeSeriesPointDouble]] {
        guard !points.isEmpty else { return [] }
        let bucketSize: Int
        switch range {
        case .day:
            bucketSize = 6
        case .week:
            bucketSize = max(1, min(7, points.count))
        case .month:
            bucketSize = 7
        }
        return stride(from: 0, to: points.count, by: bucketSize).map { start in
            Array(points[start..<min(start + bucketSize, points.count)])
        }
    }

    private var heatmapColumnCount: Int {
        max(1, heatmapRows.map(\.count).max() ?? 1)
    }

    private func normalizedHeatValue(for point: TimeSeriesPointDouble) -> Double {
        guard let minValue = points.map(\.value).min(),
              let maxValue = points.map(\.value).max(),
              maxValue > minValue else { return 0.55 }
        return (point.value - minValue) / (maxValue - minValue)
    }

    private func heatRowLabel(for row: [TimeSeriesPointDouble]) -> String {
        guard let first = row.first?.date, let last = row.last?.date else { return "--" }
        if range == .day {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: first)
        }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return first.formatted(.dateTime.month(.defaultDigits).day())
        }
        return "\(first.formatted(.dateTime.month(.defaultDigits).day()))-\(last.formatted(.dateTime.day()))"
    }

    private func heatLegendItem(title: String, value: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(heatColor(for: value, index: 0))
                .frame(width: 14, height: 10)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private func heatColor(for value: Double, index: Int) -> Color {
        let opacity = 0.18 + value * 0.72
        return index.isMultiple(of: 2) ? accentColor.opacity(opacity) : accentColor.opacity(opacity * 0.84)
    }

    private func selectionText(for point: TimeSeriesPointDouble) -> String {
        "\(TrendsSelectionFormatter.title(for: point.date, range: range)) · \(TrendMetricValueFormatter.string(for: point.value, unit: metric.unit))"
    }

    private var primarySegmentLabel: String {
        let best = distributionSegments.max(by: { $0.ratio < $1.ratio })
        return "\(best?.title ?? "中段")占比较高"
    }

    private var displaySegmentRatios: [CGFloat] {
        let floored = distributionSegments.map { max(0.12, $0.ratio) }
        let total = max(0.01, floored.reduce(0, +))
        return floored.map { $0 / total }
    }

    private func barGradient(for item: TimeSeriesPointDouble) -> LinearGradient {
        let isHighlighted = selectedPoint?.timestamp == item.timestamp
        return LinearGradient(
            colors: [
                accentColor.opacity(isHighlighted ? 0.98 : 0.86),
                accentColor.opacity(isHighlighted ? 0.52 : 0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}


struct TrendDistributionSegment {
    let title: String
    let valueText: String
    let ratio: CGFloat
    let tint: Color
}

private struct WalkingSpeedTrendSlot: Identifiable {
    let date: Date
    let value: Double?
    let displayPoint: TimeSeriesPointDouble?
    let isLatestSample: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct MobilityReferenceTrendChart: View {
    let metricTitle: String
    let points: [TimeSeriesPointDouble]
    let accentColor: Color

    private let topPadding: CGFloat = 8
    private let bottomPadding: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let validPoints = points.filter { $0.value >= 0 }
            let normalized = normalizedPoints(in: geometry.size, points: validPoints)
            let upperBound = chartUpperBound(for: validPoints)
            let thresholds = referenceThresholds

            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accentColor.opacity(0.05))

                    mobilityBands(size: geometry.size, upperBound: upperBound)

                    ForEach(thresholds, id: \.self) { threshold in
                        let y = yPosition(for: threshold, minValue: 0, maxValue: upperBound, size: geometry.size)
                        Path { path in
                            path.move(to: CGPoint(x: 10, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width - 34, y: y))
                        }
                        .stroke(accentColor.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        valueBubble(text: "\(Int(threshold))%", tint: accentColor.opacity(0.92))
                            .position(x: geometry.size.width - 18, y: y)
                    }

                    if normalized.count >= 2 {
                        Path { path in
                            path.move(to: normalized[0])
                            for point in normalized.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                        .stroke(
                            LinearGradient(colors: [accentColor, accentColor], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )

                        ForEach(Array(normalized.enumerated()), id: \.offset) { index, point in
                            Circle()
                                .fill(index == normalized.count - 1 ? accentColor : Color.white)
                                .overlay(Circle().stroke(accentColor, lineWidth: 3))
                                .frame(width: index == normalized.count - 1 ? 14 : 12, height: index == normalized.count - 1 ? 14 : 12)
                                .position(point)
                        }

                        if let lastPoint = normalized.last,
                           let latestValue = validPoints.last?.value {
                            valueBubble(text: String(format: "%.1f%%", latestValue), tint: accentColor)
                                .position(x: min(lastPoint.x, geometry.size.width - 32), y: max(14, lastPoint.y - 16))
                        }
                    } else if normalized.count == 1 {
                        Circle()
                            .fill(accentColor.opacity(0.22))
                            .frame(width: 14, height: 14)
                            .position(normalized[0])
                    } else {
                        Text("暂无趋势")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                HStack {
                    Text(label(for: points.first?.date))
                    Spacer()
                    Text(label(for: points.last?.date))
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func mobilityBands(size: CGSize, upperBound: Double) -> some View {
        let bands = referenceBands(upperBound: upperBound)

        ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
            let topY = yPosition(for: band.upper, minValue: 0, maxValue: upperBound, size: size)
            let bottomY = yPosition(for: band.lower, minValue: 0, maxValue: upperBound, size: size)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(band.color)
                .frame(height: max(16, bottomY - topY))
                .padding(.horizontal, 8)
                .position(x: size.width / 2, y: (topY + bottomY) / 2)
        }
    }

    private func normalizedPoints(in size: CGSize, points: [TimeSeriesPointDouble]) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let upperBound = chartUpperBound(for: points)
        let range = max(upperBound, 0.0001)
        let stepX = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
        let chartHeight = max(1, size.height - topPadding - bottomPadding)

        return points.enumerated().map { index, point in
            let normalizedY = point.value / range
            let y = (size.height - 20) - bottomPadding - CGFloat(normalizedY) * max(1, chartHeight - 16)
            return CGPoint(x: CGFloat(index) * stepX, y: y)
        }
    }

    private func yPosition(for value: Double, minValue: Double, maxValue: Double, size: CGSize) -> CGFloat {
        let normalized = (value - minValue) / max(maxValue - minValue, 0.0001)
        let chartHeight = max(1, size.height - topPadding - bottomPadding)
        return (size.height - 20) - bottomPadding - CGFloat(normalized) * max(1, chartHeight - 16)
    }

    private func chartUpperBound(for points: [TimeSeriesPointDouble]) -> Double {
        let maxValue = points.map(\.value).max() ?? 0
        if metricTitle == "双足支撑时间" {
            if maxValue <= 30 { return 34 }
            if maxValue <= 35 { return 38 }
            return max(40, ceil((maxValue + 2) / 5) * 5)
        }
        if maxValue <= 10 { return 16 }
        if maxValue <= 15 { return 18 }
        return max(20, ceil((maxValue + 1.5) / 5) * 5)
    }

    private func valueBubble(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
    }

    private func label(for date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }

    private var referenceThresholds: [Double] {
        if metricTitle == "双足支撑时间" {
            return [25.0, 30.0]
        }
        return [10.0, 15.0]
    }

    private func referenceBands(upperBound: Double) -> [(lower: Double, upper: Double, color: Color)] {
        if metricTitle == "双足支撑时间" {
            return [
                (0, 25, Color(hex: "BEECCF").opacity(0.45)),
                (25, 30, Color(hex: "FFE3A3").opacity(0.50)),
                (30, upperBound, Color(hex: "FFD0C7").opacity(0.52))
            ]
        }
        return [
            (0, 10, Color(hex: "BEECCF").opacity(0.45)),
            (10, 15, Color(hex: "FFE3A3").opacity(0.50)),
            (15, upperBound, Color(hex: "FFD0C7").opacity(0.52))
        ]
    }
}

private struct AppleHealthReferenceChart: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    @Binding var selectedPoint: TimeSeriesPointDouble?
    let isStaticForExport: Bool

    @State private var isLongPressActivated = false
    @State private var currentTouchLocation: CGPoint?

    private var points: [TimeSeriesPointDouble] {
        normalizedIntradayPoints(from: metric.points.sorted { $0.date < $1.date })
    }

    private var latestPoint: TimeSeriesPointDouble? {
        selectedPoint ?? points.last
    }

    private var highlightedPoint: TimeSeriesPointDouble? {
        selectedPoint ?? points.last
    }

    private var highlightedPoints: [TimeSeriesPointDouble] {
        highlightedPoint.map { [$0] } ?? []
    }

    private var selectedRulePoints: [TimeSeriesPointDouble] {
        selectedPoint.map { [$0] } ?? []
    }

    private var displayColor: Color {
        Color(hex: "F59A3D")
    }

    private var xAxisDates: [Date] {
        switch range {
        case .day:
            guard let anchorDate = points.first?.date ?? metric.points.first?.date else { return [] }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: anchorDate)
            return stride(from: 0, through: 24, by: 6).compactMap { hour in
                calendar.date(byAdding: .hour, value: hour, to: start)
            }
        case .week:
            return points.map(\.date)
        case .month:
            return TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)
        }
    }

    private var dateDomain: ClosedRange<Date> {
        if range == .day, let anchorDate = points.first?.date ?? metric.points.first?.date {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        }
        return chartDateDomain(for: points)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return fallbackYDomain
        }

        if range == .day {
            let padding = max(minimumPadding, (maxValue - minValue) * 0.9)
            return max(minimumLowerBound, minValue - padding)...(maxValue + padding)
        }

        return TrendYAxisDesigner.domain(for: values, range: range)
    }

    private var yAxisValues: [Double] {
        if range == .day {
            let lower = yDomain.lowerBound
            let upper = yDomain.upperBound
            let mid = (lower + upper) / 2
            return [lower, mid, upper]
        }
        return TrendYAxisDesigner.axisValues(for: yDomain, range: range)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                let spread = max(minimumSpread, (yDomain.upperBound - yDomain.lowerBound) * 0.09)

                BarMark(
                    x: .value("Date", point.date),
                    yStart: .value("Lower", max(yDomain.lowerBound, point.value - spread)),
                    yEnd: .value("Upper", min(yDomain.upperBound, point.value + spread)),
                    width: .fixed(range == .day ? 10 : 8)
                )
                .foregroundStyle(Color(hex: "D9DDE7").opacity(point.timestamp == latestPoint?.timestamp ? 0.55 : 0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            }

            ForEach(highlightedPoints) { point in
                PointMark(
                    x: .value("LatestDate", point.date),
                    y: .value("LatestValue", point.value)
                )
                .symbolSize(90)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    highlightedAnnotation(for: point)
                }

                PointMark(
                    x: .value("LatestDate", point.date),
                    y: .value("LatestValue", point.value)
                )
                .symbolSize(28)
                .foregroundStyle(displayColor)
            }

            ForEach(selectedRulePoints) { point in
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(Color(hex: "C8C9CF").opacity(0.92))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisValueText(number))
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.88))
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.top, 12)
                .padding(.leading, 4)
                .padding(.trailing, 6)
                .padding(.bottom, 14)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!isStaticForExport)
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard !isStaticForExport else { return }
                                updateSelectedPoint(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
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
        .onAppear {
            let internalNotes = [
                "component=AppleHealthReferenceChart",
                "highlightedPoint=\(highlightedPoint.map { "\(TrendMetricValueFormatter.string(for: $0.value, unit: metric.unit))@\(TrendsSelectionFormatter.title(for: $0.date, range: range))" } ?? "nil")",
                "preferredSinglePointHour=\(preferredSinglePointHour)",
                "displayUnit=\(displayUnitText)",
                "valuePreview=\(points.map { valueText($0.value) }.joined(separator: ", "))"
            ]
            TrendDebugLogger.logMetricChart(
                source: "AppleHealthReferenceChart",
                metric: metric,
                range: range,
                rawPoints: metric.points.sorted { $0.date < $1.date },
                renderedPoints: points,
                renderMode: "apple_health_reference_internal",
                rawPointCount: metric.points.count,
                renderedPointCount: points.count,
                notes: internalNotes,
                xDomain: dateDomain,
                xAxisDates: xAxisDates,
                yDomain: yDomain,
                yAxisValues: yAxisValues
            )
        }
    }

    private func normalizedIntradayPoints(from points: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        guard range == .day, points.count == 1, let point = points.first else {
            return points
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: point.date)
        guard let anchorHour = calendar.date(byAdding: .hour, value: preferredSinglePointHour, to: startOfDay) else {
            return points
        }
        return [TimeSeriesPointDouble(timestamp: Int64(anchorHour.timeIntervalSince1970), value: point.value)]
    }

    private func updateSelectedPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let locationX = location.x - frame.origin.x
        guard locationX >= 0,
              locationX <= proxy.plotSize.width,
              let date: Date = proxy.value(atX: locationX) else {
            return
        }
        selectedPoint = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    @ViewBuilder
    private func highlightedAnnotation(for point: TimeSeriesPointDouble) -> some View {
        if selectedPoint != nil {
            selectionCallout(for: point)
        } else {
            Text(valueText(point.value))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(displayColor)
        }
    }

    private func axisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            return String(localized: "\(calendar.component(.hour, from: date))时")
        case .week:
            let day = calendar.component(.day, from: date)
            let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
            let weekday = weekdaySymbols[max(0, min(6, calendar.component(.weekday, from: date) - 1))]
            return "\(day)日\n周\(weekday)"
        case .month:
            return String(localized: "\(calendar.component(.day, from: date))日")
        }
    }

    private var preferredSinglePointHour: Int {
        switch metric.title {
        case "步行步长": return 16
        case "步行速度": return 15
        case "步伐不对称": return 15
        case "双足支撑时间": return 16
        default: return 16
        }
    }

    private var fallbackYDomain: ClosedRange<Double> {
        switch metric.title {
        case "步行步长":
            return 0.4...1.0
        case "步行速度":
            return 0.6...1.8
        case "步伐不对称":
            return 0...4
        case "双足支撑时间":
            return 15...35
        default:
            return 0...1
        }
    }

    private var minimumPadding: Double {
        switch metric.title {
        case "步行步长": return 0.08
        case "步行速度": return 0.12
        case "步伐不对称": return 0.8
        case "双足支撑时间": return 3
        default: return 0.08
        }
    }

    private var minimumSpread: Double {
        switch metric.title {
        case "步行步长": return 0.03
        case "步行速度": return 0.04
        case "步伐不对称": return 0.4
        case "双足支撑时间": return 1.2
        default: return 0.03
        }
    }

    private var minimumLowerBound: Double {
        switch metric.title {
        case "步行步长": return 0
        case "步行速度": return 0
        case "双足支撑时间": return 0
        default: return 0
        }
    }

    private func valueText(_ value: Double) -> String {
        switch metric.title {
        case "步行步长":
            return "\(Int((value * 100).rounded()))"
        case "步行速度":
            return String(format: "%.2f", value)
        case "步伐不对称":
            return "\(Int(value.rounded()))"
        case "双足支撑时间":
            return "\(Int(value.rounded()))"
        default:
            return TrendMetricValueFormatter.string(for: value, unit: metric.unit)
        }
    }

    private func axisValueText(_ value: Double) -> String {
        switch metric.title {
        case "步行步长":
            return "\(Int((value * 100).rounded()))"
        case "步行速度":
            return String(format: "%.1f", value)
        case "步伐不对称":
            return "\(Int(value.rounded()))"
        case "双足支撑时间":
            return "\(Int(value.rounded()))"
        default:
            return TrendMetricValueFormatter.string(for: value, unit: metric.unit)
        }
    }

    private func selectionCallout(for point: TimeSeriesPointDouble) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedPoint == nil ? "最新" : "已选")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(valueText(point.value))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                Text(displayUnitText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(selectionTimeText(for: point.date))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "F2F2F7").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var displayUnitText: String {
        switch metric.title {
        case "步行步长":
            return String(localized: "厘米")
        case "步行速度":
            return String(localized: "米/秒")
        case "步伐不对称":
            return "%"
        case "双足支撑时间":
            return "%"
        default:
            return metric.unit
        }
    }

    private func selectionTimeText(for date: Date) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            let startHour = calendar.component(.hour, from: date)
            let endHour = min(startHour + 1, 24)
            return String(localized: "\(month)月\(day)日 \(startHour)-\(endHour)")
        case .week, .month:
            return TrendsSelectionFormatter.title(for: date, range: range)
        }
    }
}

private struct WalkingSpeedTrendComboChart: View {
    let metric: TrendCategoryMetricModel
    let range: TrendsRange
    let accentColor: Color
    @Binding var selectedPoint: TimeSeriesPointDouble?
    let isStaticForExport: Bool

    @State private var isLongPressActivated = false
    @State private var currentTouchLocation: CGPoint?

    private var points: [TimeSeriesPointDouble] {
        normalizedIntradayPoints(from: metric.points.sorted { $0.date < $1.date })
    }

    private var averageValue: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private var latestRealPoint: TimeSeriesPointDouble? {
        points.last
    }

    private var slots: [WalkingSpeedTrendSlot] {
        let calendar = Calendar.current
        guard !points.isEmpty else { return [] }

        switch range {
        case .day:
            let grouped = Dictionary(grouping: points) { startOfHour(for: $0.date) }
            let latestHour = latestRealPoint.map { startOfHour(for: $0.date) }
            return grouped.keys.sorted().map { hour in
                let items = grouped[hour] ?? []
                let value = items.map(\.value).reduce(0, +) / Double(items.count)
                let representative = items.last ?? TimeSeriesPointDouble(timestamp: Int64(hour.timeIntervalSince1970), value: value)
                return WalkingSpeedTrendSlot(
                    date: hour,
                    value: value,
                    displayPoint: representative,
                    isLatestSample: latestHour == hour
                )
            }
        case .week, .month:
            let start = range.startDate
            let slotCount = range.windowDays
            let grouped = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            let latestDay = latestRealPoint.map { calendar.startOfDay(for: $0.date) }
            return (0..<slotCount).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let dayStart = calendar.startOfDay(for: day)
                let items = grouped[dayStart] ?? []
                let value = items.isEmpty ? nil : items.map(\.value).reduce(0, +) / Double(items.count)
                let representative = value.map { TimeSeriesPointDouble(timestamp: Int64(dayStart.timeIntervalSince1970), value: $0) }
                return WalkingSpeedTrendSlot(
                    date: dayStart,
                    value: value,
                    displayPoint: representative,
                    isLatestSample: latestDay == dayStart
                )
            }
        }
    }

    private var plottedPoints: [TimeSeriesPointDouble] {
        slots.compactMap(\.displayPoint).sorted { $0.date < $1.date }
    }

    private var valueSlots: [WalkingSpeedTrendSlot] {
        slots.filter { $0.value != nil }
    }

    private var placeholderSlots: [WalkingSpeedTrendSlot] {
        range == .day ? [] : slots.filter { $0.value == nil }
    }

    private var selectedFocusPoints: [TimeSeriesPointDouble] {
        selectedPoint.map { [$0] } ?? []
    }

    private var latestFocusPoints: [TimeSeriesPointDouble] {
        selectedPoint == nil ? latestRealPoint.map { [$0] } ?? [] : []
    }

    private var xAxisDates: [Date] {
        switch range {
        case .day:
            guard let anchorDate = points.first?.date ?? metric.points.first?.date else { return [] }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: anchorDate)
            return stride(from: 0, through: 24, by: 4).compactMap { hour in
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

    private var dateDomain: ClosedRange<Date> {
        if range == .day, let anchorDate = points.first?.date ?? metric.points.first?.date {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        }
        guard let lower = slots.first?.date else {
            let now = Date()
            return now...now
        }
        guard let upper = slots.last?.date, lower != upper else {
            let end = Calendar.current.date(byAdding: range == .day ? .hour : .day, value: 1, to: lower) ?? lower
            return lower...end
        }
        return lower...upper
    }

    private var yDomain: ClosedRange<Double> {
        let domain = TrendYAxisDesigner.domain(for: slots.compactMap(\.value), range: range)
        return 0...max(domain.upperBound, 1)
    }

    private var yAxisValues: [Double] {
        TrendYAxisDesigner.axisValues(for: yDomain, range: range)
    }

    private var barWidthRatio: Double {
        switch range {
        case .day: return 0.72
        case .week: return 0.78
        case .month: return 0.58
        }
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Mean", averageValue))
                .foregroundStyle(accentColor.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(valueSlots) { slot in
                BarMark(
                    x: .value("Date", slot.date),
                    y: .value("Value", slot.value ?? yDomain.lowerBound),
                    width: .ratio(barWidthRatio)
                )
                .foregroundStyle(barGradient(for: slot))
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
                    tooltip(for: point)
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
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!isStaticForExport)
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard !isStaticForExport else { return }
                                updateSelectedPoint(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
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

    private func startOfHour(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
    }

    private func normalizedIntradayPoints(from points: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        guard range == .day, points.count == 1, let point = points.first else {
            return points
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: point.date)
        guard let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else {
            return points
        }
        return [TimeSeriesPointDouble(timestamp: Int64(noon.timeIntervalSince1970), value: point.value)]
    }

    private func axisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
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
        if metric.unit.isEmpty {
            return text
        }
        if text.hasSuffix(metric.unit) {
            return String(text.dropLast(metric.unit.count))
        }
        return text
    }

    private func barGradient(for slot: WalkingSpeedTrendSlot) -> LinearGradient {
        let topOpacity = slot.isLatestSample ? 0.96 : 0.84
        let bottomOpacity = slot.isLatestSample ? 0.42 : 0.24
        return LinearGradient(
            colors: [
                accentColor.opacity(topOpacity),
                accentColor.opacity(bottomOpacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func tooltip(for point: TimeSeriesPointDouble) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TrendsSelectionFormatter.title(for: point.date, range: range))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(TrendMetricValueFormatter.string(for: point.value, unit: metric.unit))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}


/// Simple趋势图表组件 作为趋势模块里的数据可视化组件。
/// 负责趋势分析展示。
struct SimpleTrendChart: View {
    let title: String
    let color: Color
    let points: [TimeSeriesPointDouble]
    let dateDomain: ClosedRange<Date>
    let range: TrendsRange
    let yDomain: ClosedRange<Double>?
    let selectedPoint: TimeSeriesPointDouble?
    let meanValue: Double?
    let isStaticForExport: Bool
    let unit: String
    let onSelectDate: (Date) -> Void
    let onClearSelection: () -> Void

    @State private var isLongPressActivated = false
    @State private var currentTouchLocation: CGPoint?

    var body: some View {
        Chart(points) { item in
            if let meanValue {
                RuleMark(y: .value("Mean", meanValue))
                    .foregroundStyle(color.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            LineMark(
                x: .value("Date", item.date),
                y: .value("Value", item.value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if points.count == 1 {
                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .symbolSize(56)
                .foregroundStyle(color)
            }

            if let selectedPoint, selectedPoint.timestamp == item.timestamp {
                RuleMark(x: .value("Selected", item.date))
                    .foregroundStyle(color.opacity(0.20))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .symbolSize(120)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    chartTooltip(for: selectedPoint)
                }

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .symbolSize(42)
                .foregroundStyle(color)
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: yScaleDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: axisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.28))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(String(format: "%.0f", number))
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.30))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(TrendsSelectionFormatter.axisLabel(for: date, range: range))
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
                .padding(.bottom, 18)
                .padding(.trailing, range == .month ? 12 : 4)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!isStaticForExport)
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard !isStaticForExport else { return }
                                selectDate(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .onEnded { _ in
                                guard !isStaticForExport else { return }
                                isLongPressActivated = true
                                if let location = currentTouchLocation {
                                    selectDate(at: location, proxy: proxy, geometry: geometry)
                                }
                            }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard !isStaticForExport else { return }
                                currentTouchLocation = value.location
                                guard isLongPressActivated else { return }
                                selectDate(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                guard !isStaticForExport else { return }
                                currentTouchLocation = nil
                                isLongPressActivated = false
                                onClearSelection()
                            }
                    )
            }
        }
    }

    private var yScaleDomain: ClosedRange<Double> {
        if let yDomain {
            return yDomain
        }
        let domain = TrendYAxisDesigner.domain(for: points.map(\.value), range: range)
        if shouldClampYAxisToZero {
            return 0...max(domain.upperBound, 1)
        }
        return domain
    }

    private var axisValues: [Double] {
        TrendYAxisDesigner.axisValues(for: yScaleDomain, range: range)
    }

    private var shouldClampYAxisToZero: Bool {
        let zeroBasedTitles = ["步数", "活动能量", "静息能量", "步行距离", "爬楼层数", "步行速度", "睡眠总时长"]
        return zeroBasedTitles.contains(title)
    }

    private func selectDate(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let locationX = location.x - frame.origin.x
        guard locationX >= 0,
              locationX <= proxy.plotSize.width,
              let date: Date = proxy.value(atX: locationX) else {
            return
        }
        onSelectDate(date)
    }

    private func chartTooltip(for point: TimeSeriesPointDouble) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TrendsSelectionFormatter.title(for: point.date, range: range))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(TrendMetricValueFormatter.string(for: point.value, unit: unit))
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}


enum TrendMetricValueFormatter {
    static func string(for value: Double, unit: String) -> String {
        if unit == "分/公里" {
            guard value.isFinite, value > 0 else { return "--" }
            let totalSeconds = Int((value * 60).rounded())
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%d'%02d\"/km", minutes, seconds)
        }
        let digits: Int
        switch unit {
        case "kg", "km", "km/h", "m/s", "L":
            digits = 1
        case "%":
            digits = 0
        default:
            digits = abs(value) >= 100 || value == value.rounded() ? 0 : 1
        }
        let valueText = String(format: "%.\(digits)f", value)
        return unit.isEmpty ? valueText : "\(valueText)\(unit)"
    }
}

/// 趋势图表解读工厂 作为趋势模块里的构建辅助类型。
/// 负责描述趋势分析展示过程中会用到的状态、分类或分支。
enum TrendChartInsightFactory {
    static func make(
        metricTitle: String,
        unit: String,
        points: [TimeSeriesPointDouble],
        range: TrendsRange,
        selectedPoint: TimeSeriesPointDouble?,
        category: TrendCategoryID?
    ) -> TrendChartInsightSummary? {
        guard !points.isEmpty else { return nil }
        let sortedPoints = points.sorted { $0.date < $1.date }
        let currentPoint = selectedPoint ?? sortedPoints.last ?? sortedPoints[0]
        let currentValue = currentPoint.value
        let averageValue = sortedPoints.map(\.value).reduce(0, +) / Double(sortedPoints.count)
        let direction = direction(for: sortedPoints.map(\.value))
        let selectedTitle = selectedPoint.map {
            TrendsSelectionFormatter.title(for: $0.date, range: range)
        }

        return TrendChartInsightSummary(
            currentValueText: TrendMetricValueFormatter.string(for: currentValue, unit: unit),
            averageValueText: TrendMetricValueFormatter.string(for: averageValue, unit: unit),
            headline: headline(
                metricTitle: metricTitle,
                points: sortedPoints,
                unit: unit,
                direction: direction,
                category: category
            ),
            selectionHeadline: selectedTitle.map { "\($0) · \(TrendMetricValueFormatter.string(for: currentValue, unit: unit))" },
            supportingLines: supportingLines(
                metricTitle: metricTitle,
                points: sortedPoints,
                unit: unit,
                direction: direction,
                category: category
            ),
            footer: footer(
                points: sortedPoints,
                unit: unit,
                direction: direction
            )
        )
    }

    private static func direction(for values: [Double]) -> TrendChartDirection {
        guard values.count >= 2 else { return .insufficient }
        let deltas = zip(values.dropFirst(), values).map(-)
        let averageDelta = deltas.reduce(0, +) / Double(deltas.count)
        let maxDelta = deltas.map(abs).max() ?? 0

        if maxDelta < max(1, abs(values.last ?? 0) * 0.03) {
            return .stable
        }
        if deltas.filter({ $0 > 0 }).count == deltas.count {
            return .rising
        }
        if deltas.filter({ $0 < 0 }).count == deltas.count {
            return .falling
        }
        if abs(averageDelta) < maxDelta * 0.2 {
            return .volatile
        }
        return averageDelta > 0 ? .rising : .falling
    }

    private static func headline(
        metricTitle: String,
        points: [TimeSeriesPointDouble],
        unit: String,
        direction: TrendChartDirection,
        category: TrendCategoryID?
    ) -> String {
        guard let peakPoint = points.max(by: { $0.value < $1.value }) else {
            return String(localized: "随着样本继续积累，这里将逐步形成趋势解读。")
        }
        let timeLabel = TrendsSelectionFormatter.title(for: peakPoint.date, range: inferredRange(from: points))
        let valueText = TrendMetricValueFormatter.string(for: peakPoint.value, unit: unit)

        switch direction {
        case .rising:
            return String(localized: "\(metricTitle)最近整体在上行，峰值出现在\(timeLabel)（\(valueText)）。")
        case .falling:
            return String(localized: "\(metricTitle)最近整体在回落，当前适合结合更早的高点一起读。")
        case .stable:
            return String(localized: "\(metricTitle)最近波动不大，整体维持在相对稳定的区间。")
        case .volatile:
            return String(localized: "\(metricTitle)最近波动比较明显，更适合结合上下文事件一起看。")
        case .insufficient:
            return String(localized: "当前记录还在积累中，继续同步后可形成更明确的趋势判断。")
        }
    }

    private static func supportingLines(
        metricTitle: String,
        points: [TimeSeriesPointDouble],
        unit: String,
        direction: TrendChartDirection,
        category: TrendCategoryID?
    ) -> [TrendChartInsightLineItem] {
        guard !points.isEmpty else {
            return []
        }
        let average = points.map(\.value).reduce(0, +) / Double(points.count)

        return [
            TrendChartInsightLineItem(
                title: "区间均值",
                detail: "当前区间均值约为 \(TrendMetricValueFormatter.string(for: average, unit: unit))。"
            )
        ]
    }

    private static func footer(
        points: [TimeSeriesPointDouble],
        unit: String,
        direction: TrendChartDirection
    ) -> String {
        guard let latest = points.last?.value else { return "继续同步健康数据后，将展示更完整的趋势解读。" }
        switch direction {
        case .rising:
            return String(localized: "当前最新值 \(TrendMetricValueFormatter.string(for: latest, unit: unit))，可以继续观察是否会延续这段上行。")
        case .falling:
            return String(localized: "当前最新值为 \(TrendMetricValueFormatter.string(for: latest, unit: unit))，建议结合前段高点共同理解变化幅度。")
        case .stable:
            return String(localized: "当前最新值为 \(TrendMetricValueFormatter.string(for: latest, unit: unit))，整体波动维持在相对稳定区间。")
        case .volatile:
            return String(localized: "当前最新值 \(TrendMetricValueFormatter.string(for: latest, unit: unit))，这类波动更适合结合睡眠、活动或恢复一起读。")
        case .insufficient:
            return String(localized: "继续积累样本后，将形成更完整的趋势摘要。")
        }
    }

    private static func inferredRange(from points: [TimeSeriesPointDouble]) -> TrendsRange {
        guard let first = points.first?.date, let last = points.last?.date else { return .week }
        let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        if days <= 1 { return .day }
        if days <= 7 { return .week }
        return .month
    }
}

/// 趋势YAxis设计器 作为趋势模块里的样式生成辅助类型。
/// 负责描述趋势分析展示过程中会用到的状态、分类或分支。
enum TrendYAxisDesigner {
    static func domain(for values: [Double], range: TrendsRange) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...100
        }

        if abs(maxValue - minValue) < 0.1 {
            let padding = max(1, abs(maxValue) * 0.12)
            return normalizedDomain(lower: minValue - padding, upper: maxValue + padding, range: range)
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
            upper: maxValue + span * paddingRatio,
            range: range
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

    private static func normalizedDomain(lower: Double, upper: Double, range: TrendsRange) -> ClosedRange<Double> {
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

/// TrendsSelection格式化器 作为趋势模块里的展示格式化辅助类型。
/// 负责描述趋势分析展示过程中会用到的状态、分类或分支。
enum TrendsSelectionFormatter {
    static func title(for date: Date, range: TrendsRange) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            let hour = calendar.component(.hour, from: date)
            return String(format: String(localized: "今天 %02d:00"), hour)
        case .week:
            let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let weekdayIndex = max(0, min(6, calendar.component(.weekday, from: date) - 1))
            return String(localized: "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 \(weekdaySymbols[weekdayIndex])")
        case .month:
            return String(localized: "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日")
        }
    }

    static func axisDates(for range: TrendsRange, dateDomain: ClosedRange<Date>) -> [Date] {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: dateDomain.lowerBound)
            return stride(from: 0, through: 24, by: 4).compactMap { hour in
                calendar.date(byAdding: .hour, value: hour, to: start)
            }
        case .week:
            let start = calendar.startOfDay(for: dateDomain.lowerBound)
            return (0..<range.windowDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let start = calendar.startOfDay(for: dateDomain.lowerBound)
            return [0, 4, 9, 14, 19, 24, 29]
                .compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                .filter { $0 <= dateDomain.upperBound }
        }
    }

    static func axisLabel(for date: Date, range: TrendsRange) -> String {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: date)
            if let end = calendar.date(byAdding: .day, value: 1, to: start),
               abs(date.timeIntervalSince(end)) < 1 {
                return "24时"
            }
            return String(localized: "\(calendar.component(.hour, from: date))时")
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
