import SwiftUI
import Charts

struct SportSpecializedTrendDashboard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: SportTrendKind
    let metrics: [TrendCategoryMetricModel]
    let status: TrendCategoryStatus
    let range: TrendsRange
    let accent: Color
    var isStaticForExport: Bool = false

    @State private var selectedVolumeMetric: SportTrendVolumeMetric = .distance
    @State private var selectedDate: Date?

    private var points: [SportTrendDayPoint] {
        SpecializedTrendChartAnalyzer.sportDays(metrics: metrics, kind: kind)
    }

    private var selectedPoint: SportTrendDayPoint? {
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var volumePoints: [SportTrendDayPoint] {
        points.filter { $0.value(for: selectedVolumeMetric) != nil }
    }

    private var efficiencyPoints: [SportTrendDayPoint] {
        points.filter { $0.efficiency != nil }
    }

    private var energyPoints: [SportTrendDayPoint] {
        points.filter { $0.energy != nil }
    }

    private var efficiencyLinePoints: [SegmentedTrendValuePoint] {
        SpecializedTrendChartAnalyzer.segmentedValues(points.map { ($0.date, $0.efficiency) })
    }

    private var volumeTint: Color { Color(hex: kind.accentHex(for: selectedVolumeMetric)) }
    private var efficiencyTint: Color { Color(hex: kind.efficiencyAccentHex) }
    private var energyTint: Color { Color(hex: kind.energyAccentHex) }

    var body: some View {
        Group {
            if points.isEmpty {
                TrendMetricEmptyStateView(
                    status: status,
                    title: "\(kind.title)趋势",
                    message: "当前区间还没有可展示的\(kind.title)记录，完成训练并同步健康 App 后会自动更新。",
                    accent: accent
                )
            } else if range == .day {
                daySnapshot
            } else {
                VStack(spacing: 14) {
                    volumeRhythmCard
                    efficiencyOutputCard
                }
            }
        }
        .onAppear { selectLatestPoint() }
        .onChange(of: range) { _, _ in selectLatestPoint() }
        .onChange(of: points.map(\.date)) { _, _ in selectLatestPointIfNeeded() }
    }

    private var daySnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            BBChartHeader(
                title: "今日\(kind.title)快照",
                subtitle: "日范围展示当天真实汇总，不用单点模拟连续趋势。",
                systemImage: kind.systemImage,
                tint: accent
            )

            if let point = selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(valueText(point.distance, unit: "km"))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("今日距离")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    snapshotMetric(title: "运动时长", value: valueText(point.duration, unit: "分钟"), tint: accent)
                    snapshotMetric(title: "训练次数", value: valueText(point.count, unit: "次"), tint: accent.opacity(0.82))
                    snapshotMetric(title: "消耗能量", value: valueText(point.energy, unit: "kcal"), tint: energyTint)
                    snapshotMetric(title: kind.efficiencyTitle, value: valueText(point.efficiency, unit: kind.efficiencyUnit), tint: efficiencyTint)
                }

                Label(kind.efficiencyReadingHint, systemImage: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(16)
        .bbChartSurface(tint: accent, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    private var volumeRhythmCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            BBChartHeader(
                title: "运动量节律",
                subtitle: "切换距离、时长和次数，查看离散日汇总的真实变化。",
                systemImage: "chart.bar.fill",
                tint: accent
            )

            Picker("运动量指标", selection: $selectedVolumeMetric) {
                ForEach(SportTrendVolumeMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isStaticForExport)

            HStack(spacing: 8) {
                BBChartMetricPill(
                    title: "区间总量",
                    value: valueText(
                        SpecializedTrendChartAnalyzer.total(points, metric: selectedVolumeMetric),
                        unit: selectedVolumeMetric.unit
                    ),
                    tint: volumeTint
                )
                BBChartMetricPill(
                    title: selectedDate == nil ? "最近记录" : "当前选择",
                    value: valueText(selectedPoint?.value(for: selectedVolumeMetric), unit: selectedVolumeMetric.unit),
                    tint: volumeTint.opacity(0.76)
                )
            }

            if volumePoints.isEmpty {
                compactEmptyState("这个区间还没有\(selectedVolumeMetric.title)数据。")
            } else {
                Chart {
                    ForEach(volumePoints) { point in
                        if let value = point.value(for: selectedVolumeMetric) {
                            BarMark(
                                x: .value("日期", point.date),
                                y: .value(selectedVolumeMetric.title, value)
                            )
                            .foregroundStyle(
                                point.date == selectedPoint?.date
                                ? LinearGradient(colors: [volumeTint, volumeTint.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [volumeTint.opacity(0.64), volumeTint.opacity(0.24)], startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(6)
                        }
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("选择", selectedPoint.date))
                            .foregroundStyle(volumeTint.opacity(0.28))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .frame(height: 214)
                .chartLegend(.hidden)
                .chartXScale(domain: range.dateDomain)
                .chartYScale(domain: volumeYDomain)
                .chartXAxis { chartXAxis }
                .chartYAxis { valueYAxis(unit: selectedVolumeMetric.unit) }
                .chartPlotStyle { plot in
                    plot.padding(.top, 6).bbChartPlotSurface(tint: volumeTint, cornerRadius: 16)
                }
                .chartOverlay { proxy in selectionOverlay(proxy: proxy) }
            }

            if let selectedPoint {
                BBChartSelectionReadout(
                    title: TrendsSelectionFormatter.title(for: selectedPoint.date, range: range),
                    value: valueText(selectedPoint.value(for: selectedVolumeMetric), unit: selectedVolumeMetric.unit),
                    detail: selectedDate == nil ? "最近有效记录" : "长按选中的记录",
                    tint: volumeTint,
                    systemImage: selectedDate == nil ? "clock.fill" : "scope"
                )
            }
        }
        .padding(16)
        .bbChartSurface(tint: accent, cornerRadius: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedVolumeMetric)
    }

    private var efficiencyOutputCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            BBChartHeader(
                title: "效率与输出",
                subtitle: "效率与能量分轨展示，共享日期选择，避免不同单位使用双 Y 轴。",
                systemImage: "gauge.with.dots.needle.67percent",
                tint: accent
            )

            HStack(spacing: 8) {
                BBChartMetricPill(
                    title: kind.efficiencyTitle,
                    value: valueText(selectedPoint?.efficiency, unit: kind.efficiencyUnit),
                    tint: efficiencyTint
                )
                BBChartMetricPill(
                    title: "能量输出",
                    value: valueText(selectedPoint?.energy, unit: "kcal"),
                    tint: energyTint
                )
            }

            Text(kind.efficiencyReadingHint)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)

            if efficiencyPoints.isEmpty && energyPoints.isEmpty {
                compactEmptyState("当前区间还没有效率或能量数据。")
            } else {
                efficiencyLane
                energyLane
            }

            if let selectedPoint {
                BBChartSelectionReadout(
                    title: TrendsSelectionFormatter.title(for: selectedPoint.date, range: range),
                    value: valueText(selectedPoint.efficiency, unit: kind.efficiencyUnit),
                    detail: "能量 \(valueText(selectedPoint.energy, unit: "kcal"))",
                    tint: efficiencyTint,
                    systemImage: "scope"
                )
            }
        }
        .padding(16)
        .bbChartSurface(tint: accent, cornerRadius: 24)
    }

    @ViewBuilder
    private var efficiencyLane: some View {
        if efficiencyPoints.isEmpty {
            compactEmptyState("暂无\(kind.efficiencyTitle)数据。")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(kind.efficiencyTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(efficiencyTint)

                Chart {
                    ForEach(efficiencyLinePoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(kind.efficiencyTitle, point.value),
                            series: .value("连续区间", point.segment)
                        )
                        .foregroundStyle(efficiencyTint)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("日期", point.date), y: .value(kind.efficiencyTitle, point.value))
                            .foregroundStyle(point.date == selectedPoint?.date ? Color.white : efficiencyTint.opacity(0.72))
                            .symbolSize(point.date == selectedPoint?.date ? 70 : 28)
                            .annotation(position: .overlay) {
                                if point.date == selectedPoint?.date {
                                    Circle().fill(efficiencyTint).frame(width: 8, height: 8)
                                }
                            }
                    }
                    selectedRuleMark(tint: efficiencyTint)
                }
                .frame(height: 142)
                .chartLegend(.hidden)
                .chartXScale(domain: range.dateDomain)
                .chartYScale(domain: efficiencyYDomain)
                .chartXAxis(.hidden)
                .chartYAxis { valueYAxis(unit: kind.efficiencyUnit) }
                .chartPlotStyle { plot in
                    plot.padding(.top, 5).bbChartPlotSurface(tint: efficiencyTint, cornerRadius: 14)
                }
                .chartOverlay { proxy in selectionOverlay(proxy: proxy) }
            }
        }
    }

    @ViewBuilder
    private var energyLane: some View {
        if energyPoints.isEmpty {
            compactEmptyState("暂无能量输出数据。")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("能量输出")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(energyTint)

                Chart {
                    ForEach(energyPoints) { point in
                        if let value = point.energy {
                            BarMark(x: .value("日期", point.date), y: .value("能量", value))
                                .foregroundStyle(
                                    point.date == selectedPoint?.date
                                    ? energyTint
                                    : energyTint.opacity(0.48)
                                )
                                .cornerRadius(5)
                        }
                    }
                    selectedRuleMark(tint: energyTint)
                }
                .frame(height: 130)
                .chartLegend(.hidden)
                .chartXScale(domain: range.dateDomain)
                .chartYScale(domain: energyYDomain)
                .chartXAxis { chartXAxis }
                .chartYAxis { valueYAxis(unit: "kcal") }
                .chartPlotStyle { plot in
                    plot.padding(.top, 5).bbChartPlotSurface(tint: energyTint, cornerRadius: 14)
                }
                .chartOverlay { proxy in selectionOverlay(proxy: proxy) }
            }
        }
    }

    @ChartContentBuilder
    private func selectedRuleMark(tint: Color) -> some ChartContent {
        if let selectedPoint {
            RuleMark(x: .value("选择", selectedPoint.date))
                .foregroundStyle(tint.opacity(0.28))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

    @AxisContentBuilder
    private var chartXAxis: some AxisContent {
        AxisMarks(values: TrendsSelectionFormatter.axisDates(for: range, dateDomain: range.dateDomain)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Color.black.opacity(0.07))
            AxisValueLabel(centered: true) {
                if let date = value.as(Date.self) {
                    Text(TrendsSelectionFormatter.axisLabel(for: date, range: range))
                        .multilineTextAlignment(.center)
                        .font(.system(size: range == .week ? 8.5 : 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    @AxisContentBuilder
    private func valueYAxis(unit: String) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                .foregroundStyle(Color.black.opacity(0.07))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(shortAxisText(number, unit: unit))
                }
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func selectionOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!isStaticForExport)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                guard case .second(true, let drag?) = value else { return }
                                updateSelection(at: drag.location, frame: frame, proxy: proxy)
                            }
                            .onEnded { value in
                                guard case .second(true, let drag?) = value else { return }
                                updateSelection(at: drag.location, frame: frame, proxy: proxy)
                            }
                    )
            } else {
                Color.clear
            }
        }
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        selectedDate = points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date
    }

    private var volumeYDomain: ClosedRange<Double> {
        zeroBasedDomain(volumePoints.compactMap { $0.value(for: selectedVolumeMetric) })
    }

    private var efficiencyYDomain: ClosedRange<Double> {
        paddedDomain(efficiencyPoints.compactMap(\.efficiency))
    }

    private var energyYDomain: ClosedRange<Double> {
        zeroBasedDomain(energyPoints.compactMap(\.energy))
    }

    private func zeroBasedDomain(_ values: [Double]) -> ClosedRange<Double> {
        let maximum = values.max() ?? 1
        return 0...max(1, maximum * 1.18)
    }

    private func paddedDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        if abs(maximum - minimum) < 0.0001 {
            let padding = max(0.5, abs(maximum) * 0.12)
            return max(0, minimum - padding)...(maximum + padding)
        }
        let padding = max((maximum - minimum) * 0.18, 0.25)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private func snapshotMetric(title: String, value: String, tint: Color) -> some View {
        BBChartMetricPill(title: title, value: value, tint: tint)
    }

    private func compactEmptyState(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(accent)
            Text(message)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func valueText(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "--" }
        return TrendMetricValueFormatter.string(for: value, unit: unit)
    }

    private func shortAxisText(_ value: Double, unit: String) -> String {
        if unit == "分/公里" {
            guard value.isFinite else { return "--" }
            return String(format: "%.1f", value)
        }
        if abs(value) >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        if abs(value) >= 100 || value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func selectLatestPoint() {
        selectedDate = nil
    }

    private func selectLatestPointIfNeeded() {
        guard let selectedDate else { return }
        if !points.contains(where: { $0.date == selectedDate }) {
            self.selectedDate = nil
        }
    }
}
