import SwiftUI
import Charts

struct MindfulnessSpecializedTrendDashboard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let metrics: [TrendCategoryMetricModel]
    let status: TrendCategoryStatus
    let range: TrendsRange
    var isStaticForExport: Bool = false

    @State private var selectedDate: Date?

    private let mindfulTint = Color(hex: "5E5CE6")
    private let stateTint = Color(hex: "C98BFF")

    private var points: [MindfulnessTrendDayPoint] {
        SpecializedTrendChartAnalyzer.mindfulnessDays(metrics: metrics)
    }

    private var selectedPoint: MindfulnessTrendDayPoint? {
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var mindfulPoints: [MindfulnessTrendDayPoint] {
        points.filter { $0.mindfulMinutes != nil }
    }

    private var statePoints: [MindfulnessTrendDayPoint] {
        points.filter { $0.stateScore != nil }
    }

    private var stateLinePoints: [SegmentedTrendValuePoint] {
        SpecializedTrendChartAnalyzer.segmentedValues(points.map { ($0.date, $0.stateScore) })
    }

    var body: some View {
        Group {
            if points.isEmpty {
                TrendMetricEmptyStateView(
                    status: status,
                    title: "心理正念",
                    message: "继续记录正念或在健康 App 记录心理状态后，这里会形成连续趋势。",
                    accent: mindfulTint
                )
            } else if range == .day {
                daySnapshot
            } else {
                balanceTrendCard
            }
        }
        .onAppear { selectedDate = nil }
        .onChange(of: range) { _, _ in selectedDate = nil }
        .onChange(of: points.map(\.date)) { _, _ in
            guard let selectedDate else { return }
            if !points.contains(where: { $0.date == selectedDate }) {
                self.selectedDate = nil
            }
        }
    }

    private var daySnapshot: some View {
        VStack(alignment: .leading, spacing: 15) {
            BBChartHeader(
                title: "今日调节快照",
                subtitle: "日范围只展示当天真实记录，不把单个汇总点画成趋势。",
                systemImage: "brain.head.profile.fill",
                tint: mindfulTint
            )

            if let point = selectedPoint {
                HStack(spacing: 9) {
                    BBChartMetricPill(
                        title: "正念时长",
                        value: valueText(point.mindfulMinutes, unit: "分钟"),
                        tint: mindfulTint,
                        size: .regular
                    )
                    BBChartMetricPill(
                        title: "心理状态",
                        value: stateValueText(point.stateScore),
                        tint: stateTint,
                        size: .regular
                    )
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: stateSymbol(point.stateScore))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(stateTint)
                        .frame(width: 36, height: 36)
                        .background(stateTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stateLabel(point.stateScore))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("心理状态来自健康 App 的 0–100 标准化心情记录。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: mindfulTint, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    private var balanceTrendCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            BBChartHeader(
                title: "调节投入与心理状态",
                subtitle: "上下双轨共享日期选择，分别保留分钟与 0–100 心理状态刻度。",
                systemImage: "waveform.path.ecg.rectangle",
                tint: mindfulTint
            )

            HStack(spacing: 8) {
                BBChartMetricPill(
                    title: selectedDate == nil ? "最近正念" : "所选正念",
                    value: valueText(selectedPoint?.mindfulMinutes, unit: "分钟"),
                    tint: mindfulTint
                )
                BBChartMetricPill(
                    title: selectedDate == nil ? "最近状态" : "所选状态",
                    value: stateValueText(selectedPoint?.stateScore),
                    tint: stateTint
                )
            }

            mindfulLane
            stateLane

            if let selectedPoint {
                BBChartSelectionReadout(
                    title: TrendsSelectionFormatter.title(for: selectedPoint.date, range: range),
                    value: valueText(selectedPoint.mindfulMinutes, unit: "分钟"),
                    detail: "心理状态 \(stateValueText(selectedPoint.stateScore)) · \(stateLabel(selectedPoint.stateScore))",
                    tint: mindfulTint,
                    systemImage: selectedDate == nil ? "clock.fill" : "scope"
                )
            }
        }
        .padding(16)
        .bbChartSurface(tint: mindfulTint, cornerRadius: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selectedDate)
    }

    @ViewBuilder
    private var mindfulLane: some View {
        if mindfulPoints.isEmpty {
            compactEmptyState("当前区间没有正念时长记录。", tint: mindfulTint)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("正念时长", systemImage: "timer")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(mindfulTint)
                    Spacer()
                    Text("分钟")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Chart {
                    ForEach(mindfulPoints) { point in
                        if let value = point.mindfulMinutes {
                            BarMark(x: .value("日期", point.date), y: .value("正念分钟", value))
                                .foregroundStyle(
                                    point.date == selectedPoint?.date
                                    ? mindfulTint
                                    : mindfulTint.opacity(0.46)
                                )
                                .cornerRadius(6)
                        }
                    }
                    selectedRuleMark(tint: mindfulTint)
                }
                .frame(height: 150)
                .chartLegend(.hidden)
                .chartXScale(domain: range.dateDomain)
                .chartYScale(domain: mindfulYDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.07))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0f", number))
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartPlotStyle { plot in
                    plot.padding(.top, 5).bbChartPlotSurface(tint: mindfulTint, cornerRadius: 14)
                }
                .chartOverlay { proxy in selectionOverlay(proxy: proxy) }
            }
        }
    }

    @ViewBuilder
    private var stateLane: some View {
        if statePoints.isEmpty {
            compactEmptyState("当前区间没有心理状态记录。", tint: stateTint)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("心理状态", systemImage: "heart.text.square.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(stateTint)
                    Spacer()
                    Text("固定 0–100")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Chart {
                    ForEach(stateBands) { band in
                        RectangleMark(
                            xStart: .value("开始", range.dateDomain.lowerBound),
                            xEnd: .value("结束", range.dateDomain.upperBound),
                            yStart: .value("下界", band.lowerBound),
                            yEnd: .value("上界", band.upperBound)
                        )
                        .foregroundStyle(band.color.opacity(0.08))
                    }

                    RuleMark(y: .value("中性", 50))
                        .foregroundStyle(stateTint.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(stateLinePoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("心理状态", point.value),
                            series: .value("连续区间", point.segment)
                        )
                        .foregroundStyle(stateTint)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("日期", point.date), y: .value("心理状态", point.value))
                            .foregroundStyle(point.date == selectedPoint?.date ? Color.white : stateTint.opacity(0.76))
                            .symbolSize(point.date == selectedPoint?.date ? 72 : 30)
                            .annotation(position: .overlay) {
                                if point.date == selectedPoint?.date {
                                    Circle().fill(stateTint).frame(width: 8, height: 8)
                                }
                            }
                    }
                    selectedRuleMark(tint: stateTint)
                }
                .frame(height: 166)
                .chartLegend(.hidden)
                .chartXScale(domain: range.dateDomain)
                .chartYScale(domain: 0...100)
                .chartXAxis { chartXAxis }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.06))
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)")
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartPlotStyle { plot in
                    plot.padding(.top, 5).bbChartPlotSurface(tint: stateTint, cornerRadius: 14)
                }
                .chartOverlay { proxy in selectionOverlay(proxy: proxy) }
            }
        }
    }

    private var stateBands: [StateBand] {
        [
            StateBand(lowerBound: 0, upperBound: 25, color: Color(hex: "8A94A6")),
            StateBand(lowerBound: 25, upperBound: 50, color: Color(hex: "7D8BFF")),
            StateBand(lowerBound: 50, upperBound: 75, color: Color(hex: "B58AF3")),
            StateBand(lowerBound: 75, upperBound: 100, color: Color(hex: "57C7B6"))
        ]
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

    private var mindfulYDomain: ClosedRange<Double> {
        let maximum = mindfulPoints.compactMap(\.mindfulMinutes).max() ?? 1
        return 0...max(1, maximum * 1.18)
    }

    private func compactEmptyState(_ message: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "chart.xyaxis.line")
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func valueText(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "--" }
        return TrendMetricValueFormatter.string(for: value, unit: unit)
    }

    private func stateValueText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))分"
    }

    private func stateLabel(_ value: Double?) -> String {
        guard let value else { return "等待心理状态记录" }
        return switch value {
        case ..<20: "很难受"
        case ..<40: "不舒服"
        case ..<60: "平静"
        case ..<80: "愉快"
        default: "非常愉快"
        }
    }

    private func stateSymbol(_ value: Double?) -> String {
        guard let value else { return "heart.slash.fill" }
        return switch value {
        case ..<40: "cloud.rain.fill"
        case ..<60: "circle.lefthalf.filled"
        case ..<80: "sun.min.fill"
        default: "sun.max.fill"
        }
    }
}

private struct StateBand: Identifiable {
    var id: Double { lowerBound }
    let lowerBound: Double
    let upperBound: Double
    let color: Color
}
