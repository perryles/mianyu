import SwiftUI
import Charts

enum BodyMetricChartPolicy {
    static func usesBars(_ kind: HabitBodyMetricKind) -> Bool {
        switch kind {
        case .basal, .active, .stand, .sunlight: return true
        case .hrv, .restingHeartRate, .wristTemperature, .walkingAsymmetry: return false
        }
    }

    static func point(on date: Date, in points: [HabitTrendPoint], calendar: Calendar = .current) -> HabitTrendPoint? {
        points.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Calendar-day continuity also works across daylight-saving transitions.
    static func segments(_ points: [HabitTrendPoint], calendar: Calendar = .current) -> [[HabitTrendPoint]] {
        var result: [[HabitTrendPoint]] = []
        for point in points.sorted(by: { $0.date < $1.date }) {
            if let previous = result.last?.last,
               let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.date), to: calendar.startOfDay(for: point.date)).day,
               days <= 1 {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }
}

/// 身体指标趋势详情容器组件 作为健康模块里的外层容器组件。
/// 负责解释具体指标含义，并展示对应的趋势、影响因素或分析结果。
struct BodyMetricTrendDetailContainer: View {
    let card: HabitBodyMetricCardModel
    let selectedDate: Date
    let summary: String
    let titleOverride: String
    let heroSubtitle: String
    let trendHeadline: String
    let chartNarrative: String
    let guidance: [String]
    let note: String
    let rangeLoader: (MetricDetailRange, Date) async -> [HabitTrendPoint]
    var showsDismissButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2
    @State private var selectedTrendPointID: HabitTrendPoint.ID?
    @State private var selectedMissingDate: Date?
    @State private var selectedRange: MetricDetailRange = .week
    @State private var anchorDate: Date
    @State private var points: [HabitTrendPoint]
    @State private var isLoading = false
    @State private var showingReminderSettings = false
    @State private var loadRequestID = UUID()

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }

    private var tint: Color { Color(hex: card.tintHex) }
    private var accent: Color { tint.opacity(0.28) }
    private var reminderMetricKey: String {
        switch card.kind {
        case .wristTemperature:
            return "wrist_temperature"
        default:
            return titleOverride
        }
    }
    private var selectedPoint: HabitTrendPoint? {
        guard selectedMissingDate == nil else { return nil }
        if let selectedTrendPointID {
            return points.first(where: { $0.id == selectedTrendPointID }) ?? points.last
        }
        return points.last
    }
    private var averageValue: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
    private var minValue: Double? { points.map(\.value).min() }
    private var maxValue: Double? { points.map(\.value).max() }
    private var latestValue: Double? { points.last?.value }
    private var canMoveForward: Bool {
        selectedRange.canShiftForward(from: anchorDate)
    }

    init(
        card: HabitBodyMetricCardModel,
        selectedDate: Date,
        summary: String,
        titleOverride: String,
        heroSubtitle: String,
        trendHeadline: String,
        chartNarrative: String,
        guidance: [String],
        note: String,
        rangeLoader: @escaping (MetricDetailRange, Date) async -> [HabitTrendPoint],
        showsDismissButton: Bool = false
    ) {
        self.card = card
        self.selectedDate = selectedDate
        self.summary = summary
        self.titleOverride = titleOverride
        self.heroSubtitle = heroSubtitle
        self.trendHeadline = trendHeadline
        self.chartNarrative = chartNarrative
        self.guidance = guidance
        self.note = note
        self.rangeLoader = rangeLoader
        self.showsDismissButton = showsDismissButton

        let normalizedDate = Calendar.current.startOfDay(for: selectedDate)
        _anchorDate = State(initialValue: normalizedDate)
        _points = State(
            initialValue: card.trendPoints
                .filter { MetricDetailRange.week.contains($0.date, anchorDate: normalizedDate) }
                .sorted { $0.date < $1.date }
        )
    }

    private var chartDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max() else {
            switch card.kind {
            case .basal, .active: return 0...500
            case .stand: return 0...12
            case .hrv: return 0...100
            case .restingHeartRate: return 40...100
            case .sunlight: return 0...60
            case .wristTemperature: return 34...38
            case .walkingAsymmetry: return 0...20
            }
        }
        let padding = Swift.max((max - min) * 0.18, minimumPadding)
        return (BodyMetricChartPolicy.usesBars(card.kind) ? 0 : Swift.max(0, min - padding))...(max + padding)
    }

    private var chartXDomain: ClosedRange<Date> {
        let interval = selectedRange.visibleDateInterval(anchorDate: anchorDate)
        let start = interval.start
        let end = Calendar.current.date(byAdding: .second, value: -1, to: interval.end) ?? start
        return start...max(end, start)
    }

    private var xAxisDates: [Date] {
        let calendar = Calendar.current
        let interval = selectedRange.visibleDateInterval(anchorDate: anchorDate)
        let start = interval.start

        switch selectedRange {
        case .day:
            return [start]
        case .week:
            return (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start)
            }
        case .month:
            let offsets = [0, 7, 14, 21, 29]
            return offsets.compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start)
            }
        }
    }

    private var minimumPadding: Double {
        switch card.kind {
        case .basal, .active: return 40
        case .stand: return 1
        case .wristTemperature: return 0.2
        default: return 0.5
        }
    }

    var body: some View {
        ZStack {
            HealthDetailPageBackground()
            ambientBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    heroCard
                    overviewCard
                    rhythmCard
                    trendCard
                    guideCard
                    noteCard
                    disclaimerCard
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, HealthDetailDesignSystem.pageBottomPadding)
            }
        }
        .healthDetailNavigation(title: LocalizedStringKey(titleOverride))
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    HealthNavigationDismissButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置") { showingReminderSettings = true }
                }
            }
        }
        .sheet(isPresented: $showingReminderSettings) {
            NavigationStack {
                MetricReminderSettingsView(metricKey: reminderMetricKey, metricTitle: titleOverride)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .task {
            await reloadPoints()
        }
        .onChange(of: selectedRange) { _, _ in
            Task { await reloadPoints() }
        }
        .onChange(of: anchorDate) { _, _ in
            Task { await reloadPoints() }
        }
    }

    private var ambientBackground: some View {
        Color.clear
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(titleOverride)
                        .font(Theme.Typography.scaled(size: 16, weight: .bold, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.valueText)
                            .font(Theme.Typography.scaled(size: 50, weight: .heavy, design: .rounded, level: appFontScaleLevel))
                            .foregroundColor(Theme.Colors.textPrimary)
                        if !card.unitText.isEmpty {
                            Text(card.unitText)
                                .font(Theme.Typography.scaled(size: 16, weight: .bold, design: .rounded, level: appFontScaleLevel))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }

                Spacer()

                vitalitySectionBadge(card.trendSummaryText, tint: tint)
            }

            Text(heroSubtitle)
                .font(Theme.Typography.scaled(size: 14, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $selectedRange) {
                ForEach(MetricDetailRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    anchorDate = selectedRange.shiftClampedToToday(anchorDate, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(selectedRange.title(for: anchorDate))
                    .font(Theme.Typography.scaled(size: 16, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    anchorDate = selectedRange.shiftClampedToToday(anchorDate, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(canMoveForward ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }

            HStack(spacing: 10) {
                metricTag(title: "阶段变化", value: card.comparisonText)
                metricTag(title: "所选范围", value: selectedRange.title(for: anchorDate))
            }
        }
        .metricDetailSurface(tint: tint, accent: accent)
    }

    private var overviewCard: some View {
        HStack(spacing: 10) {
            metricPill(title: selectedRange == .day ? "本次" : "当前", value: selectedPoint.map { formattedValue($0.value) } ?? "--", tint: tint)
            metricPill(title: "均值", value: averageValue.map(formattedValue) ?? "暂无", tint: Color.white)
            metricPill(title: "范围", value: rangeText, tint: Color.white)
        }
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("节律摘要")
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(summary)
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                vitalitySectionBadge(card.isEmpty ? "暂无数据" : "解读", tint: tint)
            }

            HStack(spacing: 10) {
                metricTag(title: "趋势判断", value: card.trendSummaryText)
                metricTag(title: "目标提示", value: card.goalText)
            }

            Text(card.comparisonText)
                .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .metricBlock(tint: tint.opacity(0.08))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dynamicTrendHeadline)
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(dynamicTrendNarrative)
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                vitalitySectionBadge(points.isEmpty ? "暂无数据" : "图表", tint: tint)
            }

            if isLoading {
                ProgressView()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            } else if points.isEmpty {
                emptyTrendChart
            } else {
                HStack(spacing: 8) {
                    chartMetricChip(title: String(localized: "最新记录"), value: latestValue.map(formattedValue) ?? "—")
                    chartMetricChip(title: "均值", value: averageValue.map(formattedValue) ?? "—")
                    chartMetricChip(title: selectedRange == .day ? "最高" : "高点", value: maxValue.map(formattedValue) ?? "—")
                }

                Chart {
                    if let averageValue {
                        RuleMark(y: .value("均值", averageValue))
                            .foregroundStyle(tint.opacity(0.22))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    if !BodyMetricChartPolicy.usesBars(card.kind) {
                        ForEach(Array(BodyMetricChartPolicy.segments(points).enumerated()), id: \.offset) { segmentIndex, segment in
                            ForEach(segment) { point in
                                LineMark(
                                    x: .value("日期", point.date),
                                    y: .value("值", point.value),
                                    series: .value("连续记录", segmentIndex)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(tint)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }

                    ForEach(points) { point in
                        if BodyMetricChartPolicy.usesBars(card.kind) {
                        BarMark(
                            x: .value("日期", point.date),
                            y: .value("值", point.value)
                        )
                        .foregroundStyle(
                            point.id == selectedPoint?.id || point.id == points.last?.id
                            ? LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [tint.opacity(0.76), tint.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                        )
                        .cornerRadius(6)
                        } else {
                            PointMark(x: .value("日期", point.date), y: .value("值", point.value))
                                .foregroundStyle(tint)
                                .symbolSize(point.id == selectedPoint?.id ? 65 : 25)
                        }

                        if point.id == selectedPoint?.id {
                            RuleMark(x: .value("选中", point.date))
                                .foregroundStyle(tint.opacity(0.22))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                }
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartYScale(domain: chartDomain)
                .chartXScale(domain: chartXDomain)
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisDateText(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(tint.opacity(0.14))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0))
                        AxisValueLabel {
                            if let y = value.as(Double.self) {
                                Text(axisText(y))
                                    .font(.appSystem(size: 9, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                        .padding(.bottom, 10)
                        .clipped()
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.2)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { value in
                                            switch value {
                                            case .second(true, let drag):
                                                guard let drag else { return }
                                                updateSelection(at: drag.location, frame: frame, proxy: proxy)
                                            default:
                                                break
                                            }
                                        }
                                )
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if let selectedPoint {
                    selectedTrendCard(for: selectedPoint)
                } else if let selectedMissingDate {
                    Text("\(selectedPointDateText(for: selectedMissingDate)) · 该日暂无数据")
                        .font(.appSystem(.footnote))
                        .foregroundStyle(.secondary)
                }

                Text(String(localized: "长按查看日期读数；缺失日期不补零，折线不跨缺失日期连接。"))
                    .font(.appSystem(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .metricBlock(tint: accent.opacity(0.16))
        .onChange(of: points.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedTrendPointID }) {
                selectedTrendPointID = ids.last
            }
        }
    }

    private var emptyTrendChart: some View {
        ZStack {
            Chart(points) { point in
                BarMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
            }
            .frame(height: 220)
            .chartLegend(.hidden)
            .chartYScale(domain: chartDomain)
            .chartXScale(domain: chartXDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisDateText(for: date))
                                .font(.appSystem(size: 10, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(tint.opacity(0.14))
                    AxisValueLabel {
                        if let y = value.as(Double.self) {
                            Text(axisText(y))
                                .font(.appSystem(size: 9, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }

            vitalityBodyHabitChartEmptyState(
                message: "暂无数据",
                detail: "继续同步健康 App 后，这里会显示当前范围内的变化。"
            )
            .padding(.horizontal, 24)
        }
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("怎么看")
                    .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                vitalitySectionBadge("阅读建议", tint: tint)
            }

            ForEach(Array(guidance.enumerated()), id: \.offset) { index, item in
                guidanceRow(index: index + 1, text: item)
            }
        }
        .metricBlock(tint: tint.opacity(0.08))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据说明")
                .font(Theme.Typography.scaled(size: 18, weight: .bold, design: .serif, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(note)
                .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .metricBlock(tint: accent.opacity(0.14))
    }

    private var disclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页\(titleOverride)数据、趋势和解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。若身体不适或需要做出重要健康决定，请咨询专业医生。"
        )
    }

    private var rangeText: String {
        guard let minValue, let maxValue else { return "暂无" }
        return "\(formattedValue(minValue)) - \(formattedValue(maxValue))"
    }

    private var dynamicTrendNarrative: String {
        switch selectedRange {
        case .day:
            return dayScopedText(from: chartNarrative)
        case .week:
            return weekScopedText(from: chartNarrative)
        case .month:
            return monthScopedText(from: chartNarrative)
        }
    }

    private var dynamicTrendHeadline: String {
        switch selectedRange {
        case .day:
            return dayScopedText(from: trendHeadline)
        case .week:
            return weekScopedText(from: trendHeadline)
        case .month:
            return monthScopedText(from: trendHeadline)
        }
    }

    private func formattedValue(_ value: Double) -> String {
        let unit = card.unitText.isEmpty ? trendUnit : card.unitText
        switch card.kind {
        case .wristTemperature, .walkingAsymmetry:
            return String(format: "%.1f %@", value, unit)
        default:
            return "\(Int(value.rounded())) \(unit)".trimmingCharacters(in: .whitespaces)
        }
    }

    private var trendUnit: String {
        switch card.kind {
        case .basal, .active: return "kcal"
        case .stand: return String(localized: "小时")
        case .sunlight: return String(localized: "分钟")
        case .hrv: return "ms"
        case .restingHeartRate: return "bpm"
        case .wristTemperature: return "℃"
        case .walkingAsymmetry: return "%"
        }
    }

    private func axisText(_ value: Double) -> String {
        switch card.kind {
        case .wristTemperature:
            return String(format: "%.1f", value)
        case .stand:
            return "\(Int(value.rounded()))h"
        default:
            return "\(Int(value.rounded()))"
        }
    }

    private func dayScopedText(from text: String) -> String {
        text
            .replacingOccurrences(of: "近 7 天", with: "当天")
            .replacingOccurrences(of: "最近一周", with: "当天")
            .replacingOccurrences(of: "最近几天", with: "当天")
            .replacingOccurrences(of: "连续几天", with: "单次记录")
            .replacingOccurrences(of: "最近值", with: "当前值")
            .replacingOccurrences(of: "最近柱高亮", with: "当前柱高亮")
    }

    private func weekScopedText(from text: String) -> String {
        text
            .replacingOccurrences(of: "近 7 天", with: "这一周")
            .replacingOccurrences(of: "最近一周", with: "这一周")
            .replacingOccurrences(of: "最近几天", with: "这几天")
            .replacingOccurrences(of: "最近值", with: "当前值")
            .replacingOccurrences(of: "最近柱高亮", with: "当前柱高亮")
    }

    private func monthScopedText(from text: String) -> String {
        text
            .replacingOccurrences(of: "近 7 天", with: "这个月")
            .replacingOccurrences(of: "最近一周", with: "这个月")
            .replacingOccurrences(of: "最近几天", with: "这段时间")
            .replacingOccurrences(of: "连续几天", with: "连续多天")
            .replacingOccurrences(of: "最近值", with: "当前值")
            .replacingOccurrences(of: "最近柱高亮", with: "当前柱高亮")
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        let point = BodyMetricChartPolicy.point(on: date, in: points)
        selectedTrendPointID = point?.id
        selectedMissingDate = point == nil ? date : nil
    }

    @ViewBuilder
    private func selectedTrendCard(for point: HabitTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedPointDateText(for: point.date))
                    .font(Theme.Typography.scaled(size: 13, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(formattedValue(point.value))
                    .font(Theme.Typography.scaled(size: 13, weight: .bold, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(tint)
            }

            Text(selectedDescription(for: point))
                .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.12), Color.white.opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func selectedDescription(for point: HabitTrendPoint) -> String {
        guard points.count > 1 else {
            return String(localized: "当前范围只有一条记录，尚不足以判断变化趋势。")
        }
        if let averageValue {
            let delta = point.value - averageValue
            if abs(delta) < minimumPadding * 0.2 {
                return String(localized: "读数接近当前范围均值；均值仅作记录对照，不是正常范围。")
            }
            if delta > 0 {
                return String(localized: "高于当前范围均值 \(formattedValue(delta))；高低本身不代表改善或恶化。")
            }
            return String(localized: "低于当前范围均值 \(formattedValue(abs(delta)))；高低本身不代表改善或恶化。")
        }
        return selectedRange == .day ? "这次记录可作为当前区间里的单点参考。" : "这一天的数值可作为当前区间里的单点参考。"
    }

    private func axisDateText(for date: Date) -> String {
        switch selectedRange {
        case .day:
            return ChineseDateText.compactMonthDay(date)
        case .week:
            return ChineseDateText.compactMonthDay(date)
        case .month:
            return ChineseDateText.compactMonthDay(date)
        }
    }

    private func selectedPointDateText(for date: Date) -> String {
        switch selectedRange {
        case .day:
            return ChineseDateText.fullDate(date)
        case .week, .month:
            return ChineseDateText.compactMonthDay(date)
        }
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 14, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.scaled(size: 10, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 12, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chartMetricChip(title: String, value: String) -> some View {
        metricTag(title: title, value: value)
    }

    private func guidanceRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(Theme.Typography.scaled(size: 12, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            Text(text)
                .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @MainActor
    private func reloadPoints() async {
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        defer {
            if loadRequestID == requestID {
                isLoading = false
            }
        }
        let loaded = await rangeLoader(selectedRange, anchorDate).sorted { $0.date < $1.date }
        guard loadRequestID == requestID else { return }
        let filtered = loaded.filter { selectedRange.contains($0.date, anchorDate: anchorDate) }
        points = filtered
        selectedTrendPointID = filtered.last?.id
        selectedMissingDate = nil
    }
}

extension View {
    func metricDetailSurface(tint: Color, accent: Color) -> some View {
        self
            .healthDetailSurface()
    }

    func metricBlock(tint: Color) -> some View {
        self
            .padding(18)
            .background(tint, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

@ViewBuilder
func vitalitySectionBadge(_ title: String, tint: Color) -> some View {
    Text(title)
        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
}

@ViewBuilder
func vitalityBodyHabitChartEmptyState(message: String, detail: String) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.58))

        VStack(spacing: 6) {
            Text(message)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
        }
    }
}
