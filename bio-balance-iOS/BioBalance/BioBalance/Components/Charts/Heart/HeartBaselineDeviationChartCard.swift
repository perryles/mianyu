import SwiftUI
import Charts

private struct HeartBaselineDeviationPoint: Identifiable, Hashable {
    var id: String { "\(seriesTitle)-\(timestamp)" }

    let seriesTitle: String
    let timestamp: Int64
    let originalValue: Double
    let deviationPercent: Double

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

private struct HeartBaselineDeviationSeries: Identifiable {
    var id: String { metric.title }

    let metric: TrendCategoryMetricModel
    let color: Color
    let points: [HeartBaselineDeviationPoint]
}

/// 参考 Pulse 的多上下文时间轴，将不同单位的心率指标换算成相对基线偏离后叠加。
/// 图表保留每项指标的原始读数用于选中态，标准化值仅用于比较趋势形状。
struct HeartBaselineDeviationChartCard: View {
    let metrics: [TrendCategoryMetricModel]
    let range: TrendsRange
    var isStaticForExport: Bool = false

    @State private var selectedDate: Date?
    @State private var hapticSelectionTick = 0

    private let tint = Color(hex: "F05275")

    private var series: [HeartBaselineDeviationSeries] {
        let definitions: [(title: String, color: Color)] = [
            ("心率变异性（HRV）", Color(hex: "5E5CE6")),
            ("静息心率", Color(hex: "FF7A59")),
            ("心率", Color(hex: "F05275"))
        ]

        return definitions.compactMap { definition in
            guard let metric = metrics.first(where: { $0.title == definition.title }) else { return nil }
            let finitePoints = metric.points.filter { $0.value.isFinite }.sorted { $0.timestamp < $1.timestamp }
            let deviations = HeartRelationshipAnalyzer.baselineDeviations(for: finitePoints)
            guard finitePoints.count >= 2, deviations.count == finitePoints.count else { return nil }
            let chartPoints = zip(finitePoints, deviations).map { point, deviation in
                HeartBaselineDeviationPoint(
                    seriesTitle: metric.title,
                    timestamp: point.timestamp,
                    originalValue: point.value,
                    deviationPercent: deviation
                )
            }
            return HeartBaselineDeviationSeries(metric: metric, color: definition.color, points: chartPoints)
        }
    }

    private var allPoints: [HeartBaselineDeviationPoint] {
        series.flatMap(\.points)
    }

    private var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: allPoints.first?.date ?? Date())
            return start...(calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week, .month:
            let start = calendar.startOfDay(for: range.startDate)
            return start...(calendar.date(byAdding: .day, value: range.windowDays, to: start) ?? start)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let maximum = max(allPoints.map { abs($0.deviationPercent) }.max() ?? 0, 5)
        let padded = ceil(maximum * 1.18)
        return (-padded)...padded
    }

    private var activeDate: Date? {
        selectedDate ?? allPoints.map(\.date).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BBChartHeader(
                title: "基线偏离叠图",
                subtitle: "把不同单位换算成相对各自区间均值的偏离比例，对齐观察变化节奏。",
                systemImage: "chart.line.uptrend.xyaxis",
                tint: tint
            )

            if series.count >= 2 {
                HStack(spacing: 12) {
                    ForEach(series) { item in
                        BBChartLegendItem(title: item.metric.title, tint: item.color)
                    }
                    Spacer(minLength: 0)
                }

                baselineChart

                if let activeDate {
                    Text(TrendsSelectionFormatter.title(for: activeDate, range: range))
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VStack(spacing: 8) {
                        ForEach(series) { item in
                            let point = matchingPoint(in: item, to: activeDate)
                            BBChartMetricPill(
                                title: readoutTitle(item, point: point),
                                value: point.map { "\($0.originalValue.formatted(.number.precision(.fractionLength(0...1)))) \(item.metric.unit) · \(signedPercent($0.deviationPercent))" }
                                    ?? String(localized: "该时段暂无数据"),
                                tint: item.color
                            )
                        }
                    }
                }

                Text(String(localized: "缺失日期不连线；日视图仅匹配当天 90 分钟内的邻近记录。"))
                    .font(.appSystem(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("0% 虚线是每项指标自己的区间均值；正值表示高于自身均值，负值表示低于自身均值。该图用于比较变化形状，不把不同指标合成为医学评分。")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TrendMetricEmptyStateView(
                    status: .noData,
                    title: "基线偏离",
                    message: "至少需要两项指标各有 2 个以上样本，才能在同一基线尺度上比较变化。",
                    accent: tint
                )
            }
        }
        .padding(16)
        .bbChartSurface(tint: tint, cornerRadius: 28)
        .sensoryFeedback(.selection, trigger: hapticSelectionTick)
        .onChange(of: range) { _, _ in
            selectedDate = nil
        }
    }

    private var baselineChart: some View {
        Chart {
            RuleMark(y: .value("区间均值", 0))
                .foregroundStyle(BBChartStyle.baseline.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))

            ForEach(series) { item in
                ForEach(Array(HeartBaselineTimePolicy.segments(dates: item.points.map(\.date), intraday: range == .day).enumerated()), id: \.offset) { segmentIndex, indices in
                    ForEach(indices, id: \.self) { index in
                        let point = item.points[index]
                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("偏离", point.deviationPercent),
                            series: .value("连续记录", "\(item.id)-\(segmentIndex)")
                        )
                        .foregroundStyle(item.color)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("时间", point.date), y: .value("偏离", point.deviationPercent))
                            .foregroundStyle(item.color)
                            .symbolSize(selectedDate != nil && isMatched(point, in: item) ? 72 : 16)
                    }
                }
            }

            if let selectedDate {
                RuleMark(x: .value("选中", selectedDate))
                    .foregroundStyle(BBChartStyle.selection.opacity(0.38))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: TrendsSelectionFormatter.axisDates(for: range, dateDomain: dateDomain)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(BBChartStyle.grid.opacity(0.7))
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(TrendsSelectionFormatter.axisLabel(for: date, range: range))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .font(.appSystem(size: range == .week ? 8.5 : 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(BBChartStyle.grid.opacity(0.7))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(signedPercent(number))
                    }
                }
                .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plot in
            plot
                .padding(.top, 8)
                .padding(.bottom, 8)
                .bbChartPlotSurface(tint: tint, cornerRadius: 18)
        }
        .frame(height: 232)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrameAnchor = proxy.plotFrame {
                    let frame = geometry[plotFrameAnchor]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isStaticForExport)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateDateSelection(at: location, frame: frame, proxy: proxy)
                            case .ended:
                                selectedDate = nil
                            }
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.18)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { value in
                                    guard case .second(true, let drag) = value, let drag else { return }
                                    updateDateSelection(at: drag.location, frame: frame, proxy: proxy)
                                }
                        )
                }
            }
        }
        .accessibilityLabel("心率指标基线偏离叠图")
        .accessibilityValue("\(series.count)项指标相对各自区间均值的变化")
    }

    private func matchingPoint(in item: HeartBaselineDeviationSeries, to date: Date) -> HeartBaselineDeviationPoint? {
        guard let index = HeartBaselineTimePolicy.matchingIndex(
            on: date, dates: item.points.map(\.date), intraday: range == .day
        ) else { return nil }
        return item.points[index]
    }

    private func readoutTitle(_ item: HeartBaselineDeviationSeries, point: HeartBaselineDeviationPoint?) -> String {
        guard range == .day, let point else { return item.metric.title }
        return "\(item.metric.title) · \(point.date.formatted(date: .omitted, time: .shortened))"
    }

    private func isMatched(_ point: HeartBaselineDeviationPoint, in item: HeartBaselineDeviationSeries) -> Bool {
        guard let selectedDate else { return false }
        return matchingPoint(in: item, to: selectedDate)?.id == point.id
    }

    private func updateDateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.minX
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        let target = range == .day ? date : Calendar.current.startOfDay(for: date)
        guard target != selectedDate else { return }
        let previousIDs = series.map { item in
            activeDate.flatMap { matchingPoint(in: item, to: $0)?.id }
        }
        let nextIDs = series.map { matchingPoint(in: $0, to: target)?.id }
        selectedDate = target
        // Moving within the same sample must not trigger feedback on every pixel.
        if previousIDs != nextIDs { hapticSelectionTick += 1 }
    }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%@%.1f%%", value > 0 ? "+" : "", value)
    }
}
