/// EnvironmentalAudioSheetView 由习惯模块环境声音入口调用，作为「环境声音」记录弹层。
/// 负责按天/周/月展示环境音量暴露趋势。

import SwiftUI
import Charts
import HealthKit

/// 环境声音视图 由上级页面或路由调用，作为习惯模块里的界面或内容组件。
/// 负责展示行为打卡、日常记录与习惯分析内容。
struct EnvironmentalAudioSheetView: View {
    /// Range 枚举，作为内部辅助类型，用于细分外层习惯记录与分析中的状态或分支。
    enum Range: String, CaseIterable, Identifiable {
        case day = "天"
        case week = "周"
        case month = "月"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return String(localized: "当天")
            case .week: return String(localized: "7 天")
            case .month: return String(localized: "所选月")
            }
        }

        var icon: String {
            switch self {
            case .day: return "clock"
            case .week: return "chart.line.uptrend.xyaxis"
            case .month: return "calendar"
            }
        }
    }

    @State private var viewModel = EnvironmentalAudioSheetViewModel()
    @State private var selectedRange: Range = .day
    @State private var selectedDate: Date
    @State private var selectedPointDate: Date?

    init(initialDate: Date = Date()) {
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HealthDetailPageBackground()

            VStack(spacing: 0) {
                heroBackgroundColor
                    .frame(height: 180)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    pageHeroSection
                    overviewCard
                    chartCard
                    exposureGuideCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .healthDetailNavigation(title: HealthPageName.environmentNoise)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { viewModel.reload(for: selectedDate, range: selectedRange) }
        .onChange(of: selectedDate) { _, newValue in
            selectedPointDate = nil
            viewModel.reload(for: newValue, range: selectedRange)
        }
        .onChange(of: selectedRange) { _, newValue in
            selectedPointDate = nil
            viewModel.reload(for: selectedDate, range: newValue)
        }
        .sensoryFeedback(.selection, trigger: selectedRange)
    }

    private var pageHeroSection: some View {
        VStack(spacing: 13) {
            HStack(spacing: 18) {
                Button { shiftDate(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "查看上一时间范围"))

                Text(dateTitle)
                    .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Color(hex: "586171"))
                    .frame(maxWidth: .infinity)

                Button { shiftDate(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(!canMoveForward)
                .accessibilityLabel(String(localized: "查看下一时间范围"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: "586171"))

            EnvironmentalNoiseHeroMeter(
                valueText: viewModel.primaryValueText,
                unitText: viewModel.primaryUnitText,
                progress: heroProgress,
                accent: heroAccentColor,
                isLoading: viewModel.isLoading
            )
            .frame(width: 210, height: 176)

            VStack(spacing: 7) {
                Text(heroTitle)
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(heroSummary)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            rangePicker
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(
            heroBackgroundColor,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -16)
        .padding(.top, -16)
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(Range.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.title)
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(selectedRange == range ? Color(hex: "1D2635") : Color(hex: "7A8494"))
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(
                            selectedRange == range ? Color.white : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .shadow(
                            color: selectedRange == range ? Color.black.opacity(0.06) : Color.clear,
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(hex: "E9EDF3"), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardLabel(selectedRange == .day ? String(localized: "当日概览") : String(localized: "所选范围概览"))

            HStack(spacing: 0) {
                statItem(
                    value: viewModel.averageText,
                    label: selectedRange == .day ? String(localized: "当日平均 dB") : String(localized: "日均均值 dB"),
                    valueColor: Color(hex: "1A2030")
                )
                if selectedRange != .day {
                    statDivider
                    statItem(
                        value: viewModel.maximumText,
                        label: String(localized: "最高日均 dB"),
                        valueColor: Color(hex: "E57B6F")
                    )
                    statDivider
                    statItem(
                        value: "\(viewModel.points.count)",
                        label: String(localized: "有记录天数"),
                        valueColor: Color(hex: "1A2030")
                    )
                }
            }
        }
        .padding(16)
        .environmentAudioCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardLabel(selectedRange == .day ? String(localized: "当日读数") : String(localized: "每日均值趋势 · 长按查看"))

            if viewModel.isLoading && viewModel.points.isEmpty {
                ProgressView(String(localized: "正在读取环境音量"))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if viewModel.points.isEmpty {
                environmentEmptyState
            } else if selectedRange == .day {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "健康 App 提供的是当天平均环境音量"))
                        .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(String(localized: "没有逐小时读数，无法判断哪个时段更安静或更吵。切换到近 7 天或所选月，可查看每日均值变化。"))
                        .font(.appSystem(.footnote, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            } else {
                selectionSummaryRow

                Chart {
                    ForEach(viewModel.points) { point in
                        audioBarMark(for: point)
                        audioBaseLineMark(for: point)
                        audioHighlightLineMark(for: point)
                        audioPointMark(for: point)
                    }

                    if let selectedPoint {
                        selectedRuleMark(for: selectedPoint)
                        selectedHighlightPointMark(for: selectedPoint)
                    }
                }
                .frame(height: 160)
                .chartLegend(.hidden)
                .chartXScale(domain: viewModel.xAxisDomain)
                .chartYScale(domain: viewModel.yAxisDomain)
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.25)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
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
                .chartYAxis {
                    AxisMarks(position: .leading, values: viewModel.yAxisMarks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.18))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(String(format: "%.0f", amount))
                            }
                        }
                        .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: viewModel.xAxisMarks) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(viewModel.axisLabel(for: date))
                            }
                        }
                        .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                if let selectedPoint {
                    selectedDetailCard(for: selectedPoint)
                }
            }
        }
        .padding(16)
        .environmentAudioCard()
    }

    private var environmentEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "ear.badge.waveform")
                .font(.appSystem(size: 24, weight: .bold))
                .foregroundColor(heroAccentColor)

            Text(String(localized: "暂无环境音量记录"))
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "1E2737"))

            Text(String(localized: "请确认健康 App 中已有环境音量记录，并允许眠屿读取。"))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "758093"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var exposureGuideCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardLabel(String(localized: "读数参考"))
                .padding(.bottom, 4)

            exposureLevelRow(
                title: "安静",
                range: "< 55 dB",
                tint: Color(hex: "55B88B"),
                matches: viewModel.latestValue.map { $0 < 55 } ?? false
            )
            exposureDivider
            exposureLevelRow(
                title: "常见",
                range: "55 - 74 dB",
                tint: Color(hex: "E2B24C"),
                matches: viewModel.latestValue.map { $0 >= 55 && $0 < 75 } ?? false
            )
            exposureDivider
            exposureLevelRow(
                title: "偏高",
                range: "≥ 75 dB",
                tint: Color(hex: "E57B6F"),
                matches: viewModel.latestValue.map { $0 >= 75 } ?? false
            )
            Text(String(localized: "仅用于阅读平均读数，不能据此判断听力风险；持续时间和个体情况也需要考虑。"))
                .font(.appSystem(.caption2, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(16)
        .environmentAudioCard()
    }

    private func exposureLevelRow(
        title: String,
        range: String,
        tint: Color,
        matches: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer(minLength: 0)

            Text(range)
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            if matches {
                Image(systemName: "checkmark")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundColor(tint)
            }
        }
        .padding(.vertical, 10)
    }

    private var exposureDivider: some View {
        Divider()
            .overlay(Theme.Colors.surfaceBorder)
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
    }

    private func statItem(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.Colors.secondaryBackground)
            .frame(width: 1, height: 32)
    }

    private var statusBubble: some View {
        HStack(spacing: 7) {
            Image(systemName: statusIcon)
                .font(.appSystem(size: 12, weight: .black))
            Text("当前状态 · \(viewModel.statusText)")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
        }
        .foregroundColor(Theme.Colors.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private var heroProgress: CGFloat {
        guard let value = viewModel.latestValue else { return 0 }
        return CGFloat(min(max((value - 40) / 60, 0.08), 1))
    }

    private var heroAccentColor: Color {
        guard let value = viewModel.latestValue else { return Color(hex: "6C8FAE") }
        switch value {
        case ..<55: return Color(hex: "27A879")
        case 55..<75: return Color(hex: "3478C9")
        default: return Color(hex: "DE6A55")
        }
    }

    private var heroBackgroundColor: Color {
        guard let value = viewModel.latestValue else { return Color(hex: "EAF1F6") }
        switch value {
        case ..<55: return Color(hex: "E2F7EF")
        case 55..<75: return Color(hex: "E7F1FD")
        default: return Color(hex: "FDECE7")
        }
    }

    private var statusIcon: String {
        guard let value = viewModel.latestValue else { return "ear.badge.waveform" }
        switch value {
        case ..<55: return "leaf.fill"
        case 55..<75: return "waveform"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var heroTitle: String {
        guard let value = viewModel.latestValue else {
            return viewModel.isLoading ? String(localized: "正在读取环境音量") : String(localized: "等待环境音量")
        }
        switch value {
        case ..<55: return String(localized: "环境整体安静")
        case 55..<75: return String(localized: "音量处于常见范围")
        default: return String(localized: "环境有些偏吵")
        }
    }

    private var heroSummary: String {
        guard let value = viewModel.latestValue else {
            return String(localized: "读取健康 App 的环境音量记录后，这里会显示所选日期的平均读数。")
        }
        switch value {
        case ..<55:
            return String(localized: "所选范围的平均读数较低，可结合持续时间观察环境变化。")
        case 55..<75:
            return String(localized: "所选范围的平均读数处于常见区间，仍可留意持续时间。")
        default:
            return String(localized: "所选范围的平均读数偏高，留意是否有长时间的高音量暴露。")
        }
    }

    private var rangeDescription: String {
        switch selectedRange {
        case .day: return String(localized: "查看当天环境音量变化")
        case .week: return String(localized: "查看本周环境音量均值")
        case .month: return String(localized: "查看本月环境音量均值")
        }
    }

    private var dateTitle: String {
        switch selectedRange {
        case .day:
            return ChineseDateText.fullDate(selectedDate)
        case .week:
            let start = Calendar.current.date(byAdding: .day, value: -6, to: selectedDate) ?? selectedDate
            return "\(ChineseDateText.compactMonthDay(start)) - \(ChineseDateText.compactMonthDay(selectedDate))"
        case .month:
            return ChineseDateText.compactMonth(selectedDate)
        }
    }

    private var trendTitle: String {
        switch selectedRange {
        case .day: return String(localized: "当日均值")
        case .week: return String(localized: "当周趋势")
        case .month: return String(localized: "当月趋势")
        }
    }

    private var selectionSummaryRow: some View {
        HStack(spacing: 8) {
            Text(selectedPoint == nil ? String(localized: "每日趋势") : String(localized: "已选日期"))
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Self.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Self.tint.opacity(0.12), in: Capsule())

            Text(shortSelectedSummary)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private var shortSelectedSummary: String {
        guard let selectedPoint else {
            return viewModel.points.isEmpty
                ? String(localized: "等待有效记录")
                : String(localized: "共 \(viewModel.points.count) 天有记录")
        }
        return "\(viewModel.axisLabel(for: selectedPoint.date)) · \(Int(selectedPoint.value.rounded())) dB"
    }

    private var selectedPoint: EnvironmentalAudioSheetViewModel.Point? {
        guard let selectedPointDate else { return nil }
        return viewModel.points.first(where: {
            abs($0.date.timeIntervalSince(selectedPointDate)) < 1
        })
    }

    private func updateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else {
            selectedPointDate = nil
            return
        }
        let xPosition = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedPointDate = nearestPoint(to: date)?.date
    }

    private func nearestPoint(to date: Date) -> EnvironmentalAudioSheetViewModel.Point? {
        viewModel.points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private func selectedDetailCard(for point: EnvironmentalAudioSheetViewModel.Point) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.axisLabel(for: point.date))
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(Int(point.value.rounded())) dB")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Self.tint)
            }

            Text(selectedDescription(for: point))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [Self.tint.opacity(0.12), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func selectedDescription(for point: EnvironmentalAudioSheetViewModel.Point) -> String {
        switch point.value {
        case ..<55:
            return String(localized: "这一天的平均环境音量较低。")
        case 55..<75:
            return String(localized: "这一天的平均环境音量处于常见区间。")
        default:
            return String(localized: "这一天的平均环境音量偏高，留意高音量持续的时间。")
        }
    }

    private func shiftDate(by value: Int) {
        let component: Calendar.Component
        switch selectedRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        let candidate = Calendar.current.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
        selectedDate = min(candidate, Calendar.current.startOfDay(for: Date()))
    }

    private var canMoveForward: Bool {
        let calendar = Calendar.current
        switch selectedRange {
        case .day:
            return !calendar.isDateInToday(selectedDate)
        case .week:
            return selectedDate < calendar.startOfDay(for: Date())
        case .month:
            return !calendar.isDate(selectedDate, equalTo: Date(), toGranularity: .month)
        }
    }

    private static let tint = Color(hex: "3478C9")

    @ChartContentBuilder
    private func audioBarMark(for point: EnvironmentalAudioSheetViewModel.Point) -> some ChartContent {
        BarMark(
            x: .value("时间", point.date),
            y: .value("分贝", point.value)
        )
        .foregroundStyle(barGradient(for: point))
        .cornerRadius(6)
    }

    @ChartContentBuilder
    private func audioBaseLineMark(for point: EnvironmentalAudioSheetViewModel.Point) -> some ChartContent {
        LineMark(
            x: .value("时间", point.date),
            y: .value("分贝", point.value)
        )
        .foregroundStyle(Self.tint.opacity(0.22))
        .interpolationMethod(.catmullRom)
        .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
    }

    @ChartContentBuilder
    private func audioHighlightLineMark(for point: EnvironmentalAudioSheetViewModel.Point) -> some ChartContent {
        LineMark(
            x: .value("时间", point.date),
            y: .value("分贝", point.value)
        )
        .foregroundStyle(Self.tint.opacity(highlightLineOpacity(for: point)))
        .interpolationMethod(.catmullRom)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    @ChartContentBuilder
    private func audioPointMark(for point: EnvironmentalAudioSheetViewModel.Point) -> some ChartContent {
        PointMark(
            x: .value("时间", point.date),
            y: .value("分贝", point.value)
        )
        .foregroundStyle(Self.tint)
        .symbolSize(pointSize(for: point))
        .opacity(pointOpacity(for: point))
    }

    @ChartContentBuilder
    private func selectedRuleMark(for point: EnvironmentalAudioSheetViewModel.Point) -> some ChartContent {
        RuleMark(x: .value("选中", point.date))
            .foregroundStyle(Self.tint.opacity(0.24))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ChartContentBuilder
    private func selectedHighlightPointMark(for point: EnvironmentalAudioSheetViewModel.Point) -> some ChartContent {
        PointMark(
            x: .value("时间", point.date),
            y: .value("分贝", point.value)
        )
        .symbolSize(88)
        .foregroundStyle(Theme.Colors.onAccent)
        .annotation(position: .overlay, alignment: .center) {
            Circle()
                .fill(Self.tint)
                .frame(width: 13, height: 13)
        }
    }

    private func isSelected(_ point: EnvironmentalAudioSheetViewModel.Point) -> Bool {
        selectedPoint?.id == point.id
    }

    private func hasSelection() -> Bool {
        selectedPoint != nil
    }

    private func primaryBarOpacity(for point: EnvironmentalAudioSheetViewModel.Point) -> Double {
        !hasSelection() || isSelected(point) ? 0.96 : 0.42
    }

    private func secondaryBarOpacity(for point: EnvironmentalAudioSheetViewModel.Point) -> Double {
        !hasSelection() || isSelected(point) ? 0.42 : 0.18
    }

    private func highlightLineOpacity(for point: EnvironmentalAudioSheetViewModel.Point) -> Double {
        !hasSelection() || isSelected(point) ? 0.9 : 0.54
    }

    private func pointOpacity(for point: EnvironmentalAudioSheetViewModel.Point) -> Double {
        !hasSelection() || isSelected(point) ? 1 : 0.32
    }

    private func pointSize(for point: EnvironmentalAudioSheetViewModel.Point) -> Double {
        isSelected(point) ? 56 : 28
    }

    private func barGradient(for point: EnvironmentalAudioSheetViewModel.Point) -> LinearGradient {
        LinearGradient(
            colors: [
                Self.tint.opacity(primaryBarOpacity(for: point)),
                Self.tint.opacity(secondaryBarOpacity(for: point))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct EnvironmentalNoiseHeroMeter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let valueText: String
    let unitText: String
    let progress: CGFloat
    let accent: Color
    let isLoading: Bool

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.10), lineWidth: 1)
                .frame(width: 174, height: 174)
                .scaleEffect(isPulsing ? 1.04 : 0.96)

            Circle()
                .fill(Color.white.opacity(0.62))
                .frame(width: 154, height: 154)

            Circle()
                .stroke(accent.opacity(0.13), lineWidth: 12)
                .frame(width: 132, height: 132)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 132, height: 132)
                .animation(.easeInOut(duration: 0.35), value: progress)

            VStack(spacing: 3) {
                Image(systemName: "waveform")
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(accent)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(valueText)
                        .font(.appSystem(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    if !unitText.isEmpty {
                        Text(unitText)
                            .font(.appSystem(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            if isLoading {
                ProgressView()
                    .tint(accent)
                    .offset(y: 58)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unitText.isEmpty ? "环境音量等待读取" : "环境音量 \(valueText) \(unitText)")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct EnvironmentAudioCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "DDEDE6"), lineWidth: 1)
            }
    }
}

private extension View {
    func environmentAudioCard() -> some View {
        modifier(EnvironmentAudioCardModifier())
    }
}

/// 环境声音Sheet视图模型 作为习惯模块里的界面状态管理入口。
/// 负责习惯记录与分析。
@MainActor
@Observable
final class EnvironmentalAudioSheetViewModel {
    /// Point 结构体，作为内部辅助类型，用于配合外层习惯记录与分析。
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    var isLoading = false
    var points: [Point] = []
    private(set) var currentRange: EnvironmentalAudioSheetView.Range = .day
    private(set) var selectedDate = Calendar.current.startOfDay(for: Date())
    /// 加载代际：快速切换范围/日期时只允许最新一次加载写入结果。
    private var loadGeneration = 0

    var latestValue: Double? {
        representativeValue
    }

    var primaryValueText: String {
        guard let value = representativeValue else { return "—" }
        return String(format: "%.0f", value)
    }

    var primaryUnitText: String {
        points.isEmpty ? "" : "dB"
    }

    var averageText: String {
        guard !points.isEmpty else { return "—" }
        let avg = points.map(\.value).reduce(0, +) / Double(points.count)
        return String(format: "%.0f", avg)
    }

    var maximumText: String {
        guard let max = points.map(\.value).max() else { return "—" }
        return String(format: "%.0f", max)
    }

    var statusText: String {
        guard let value = representativeValue else { return String(localized: "待读取") }
        switch value {
        case ..<55: return String(localized: "安静")
        case 55..<75: return String(localized: "正常")
        default: return String(localized: "偏高")
        }
    }

    var summaryText: String {
        guard let value = representativeValue else {
            return String(localized: "还没有读取到环境音量记录。等健康权限同步后，这里会提示你哪些时段更安静、哪些时段偏吵。")
        }
        if value >= 75 {
            return String(localized: "当前环境音量偏高，持续暴露在较高噪音下会影响专注和恢复，适合找更安静的环境稍微缓一下。")
        }
        return String(localized: "当前环境音量整体稳定，继续把高噪声时段压短一点，会更有利于专注和恢复。")
    }

    private var representativeValue: Double? {
        guard !points.isEmpty else { return nil }
        if currentRange == .day { return points.last?.value }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    var yAxisMarks: [Double] {
        Array(stride(from: yAxisDomain.lowerBound, through: yAxisDomain.upperBound, by: 20))
    }

    var yAxisDomain: ClosedRange<Double> {
        let minimum = points.map(\.value).min() ?? 40
        let maximum = points.map(\.value).max() ?? 100
        let lower = max(0, floor(min(minimum, 40) / 20) * 20)
        let upper = max(100, ceil((maximum + 5) / 20) * 20)
        return lower...upper
    }

    var xAxisDomain: ClosedRange<Date> {
        let window = Self.dateWindow(for: selectedDate, range: currentRange)
        return window.start...window.end
    }

    var xAxisMarks: [Date] {
        let calendar = Calendar.current
        let window = Self.dateWindow(for: selectedDate, range: currentRange)
        switch currentRange {
        case .month:
            let dayCount = calendar.dateComponents([.day], from: window.start, to: window.end).day ?? 30
            return [0, 7, 14, 21, max(0, dayCount - 1)]
                .compactMap { calendar.date(byAdding: .day, value: $0, to: window.start) }
        case .week:
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: window.start) }
        case .day:
            return []
        }
    }

    func axisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        switch currentRange {
        case .month:
            formatter.dateFormat = "M/d"
        case .week:
            formatter.dateFormat = "E"
        case .day:
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }

    func reload(for selectedDate: Date, range: EnvironmentalAudioSheetView.Range) {
        currentRange = range
        self.selectedDate = Calendar.current.startOfDay(for: selectedDate)
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        points = []
        Task {
            let data = await loadPoints(for: selectedDate, range: range)
            await MainActor.run {
                // 已切换范围/日期或任务被取代时丢弃过期结果。
                guard !Task.isCancelled, generation == self.loadGeneration else { return }
                self.points = data
                self.isLoading = false
            }
        }
    }

    private func loadPoints(for selectedDate: Date, range: EnvironmentalAudioSheetView.Range) async -> [Point] {
        let calendar = Calendar.current
        switch range {
        case .day:
            let fetchedValue = try? await HealthKitManager.shared.fetchEnvironmentalAudioExposure(on: selectedDate)
            guard let value = fetchedValue, value > 0 else { return [] }
            let start = calendar.startOfDay(for: selectedDate)
            return [Point(date: start, value: value)]

        case .week:
            let window = Self.dateWindow(for: selectedDate, range: range)
            let days = (try? await HealthKitManager.shared.fetchDailyEnvironmentalAudioExposureAverages(days: Self.lookbackDays(for: window))) ?? []
            return filteredPoints(days, in: window)

        case .month:
            let window = Self.dateWindow(for: selectedDate, range: range)
            let days = (try? await HealthKitManager.shared.fetchDailyEnvironmentalAudioExposureAverages(days: Self.lookbackDays(for: window))) ?? []
            return filteredPoints(days, in: window)
        }
    }

    static func dateWindow(for date: Date, range: EnvironmentalAudioSheetView.Range, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        switch range {
        case .day:
            return calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: day) ?? day
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return DateInterval(start: start, end: end)
        case .month:
            return calendar.dateInterval(of: .month, for: day) ?? DateInterval(start: day, duration: 86_400)
        }
    }

    static func lookbackDays(for window: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        return max(1, (calendar.dateComponents([.day], from: window.start, to: today).day ?? 0) + 1)
    }

    private func filteredPoints(_ points: [TimeSeriesPointDouble], in window: DateInterval) -> [Point] {
        return points
            .filter { $0.date >= window.start && $0.date < window.end && $0.value > 0 }
            .map { Point(date: $0.date, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

#Preview {
    EnvironmentalAudioSheetView()
}
