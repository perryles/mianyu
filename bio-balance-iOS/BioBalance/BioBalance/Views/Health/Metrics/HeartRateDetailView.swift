/// HeartRateDetailView 由健康首页与今日页调用，作为「心率」详情页。
/// 负责展示心率趋势、静息心率、按日/周/月切换及采样点详情与提醒设置。

import SwiftUI
import Charts

/// 心率视图 由上级页面或路由调用，作为健康模块里的界面或内容组件。
/// 负责解释具体指标含义，并展示对应的趋势、影响因素或分析结果。
struct HeartRateDetailView: View {
    let history: HealthHistory?
    var showsDismissButton: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var healthKitPoints: [TimeSeriesPoint] = []
    @State private var dailyTrendPoints: [TimeSeriesPointDouble] = []
    @State private var restingHeartRate: Double?
    @State private var isLoading = false
    @State private var selectedHeartRateTimestamp: Int64?
    @State private var selectedRange: MetricDetailRange = .day
    @State private var selectedDate: Date
    @State private var showingReminderSettings = false
    @State private var loadRequestID = UUID()
    @AppStorage("app_font_scale_level") private var appFontScaleLevelRaw: Int = 2

    private static let tint = Color(hex: "EF5350")
    private static let accent = Color(hex: "FFB3C1")

    private var appFontScaleLevel: AppFontScaleLevel {
        AppFontScaleLevel(rawValue: appFontScaleLevelRaw) ?? .two
    }

    init(history: HealthHistory?, initialDate: Date = Date(), showsDismissButton: Bool = false) {
        self.history = history
        self.showsDismissButton = showsDismissButton
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    private var canMoveForward: Bool {
        selectedRange.canShiftForward(from: selectedDate)
    }
    
    private var chartData: [TimeSeriesPoint] {
        if selectedRange == .day, !healthKitPoints.isEmpty {
            return healthKitPoints
        }
        if selectedRange == .day, let history, !history.hrPoints.isEmpty {
            return history.hrPoints.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
        }
        if selectedRange != .day {
            return dailyTrendPoints.map { TimeSeriesPoint(timestamp: $0.timestamp, value: Int($0.value.rounded())) }
        }
        return []
    }
    
    var body: some View {
        ZStack {
            HealthDetailPageBackground(
                topGlow: Color(hex: "FFBFCB"),
                lowerGlow: Color(hex: "FFE5EA")
            )
            ambientBackground
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    heroCard
                    overviewCard
                    rhythmCard
                    trendCard
                    guideCard
                    noteCard
                    metricDisclaimerCard
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, HealthDetailDesignSystem.pageBottomPadding)
            }
        }
        .healthDetailNavigation(title: HealthPageName.restingHeartRate)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    HealthNavigationDismissButton {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("设置") { showingReminderSettings = true }
            }
        }
        .sheet(isPresented: $showingReminderSettings) {
            NavigationStack {
                MetricReminderSettingsView(metricKey: "resting_heart_rate", metricTitle: "静息心率")
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .task {
            await loadHealthKitHeartRate()
        }
        .onChange(of: selectedRange) { _, _ in
            Task { await loadHealthKitHeartRate() }
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await loadHealthKitHeartRate() }
        }
        .onChange(of: chartData.map(\.timestamp)) { _, timestamps in
            guard !timestamps.isEmpty else {
                selectedHeartRateTimestamp = nil
                return
            }
            if let selectedHeartRateTimestamp, timestamps.contains(selectedHeartRateTimestamp) {
                return
            }
            selectedHeartRateTimestamp = timestamps.last
        }
    }

    private var metricDisclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页静息心率数据、趋势和解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。若身体不适或需要做出重要健康决定，请咨询专业医生。"
        )
    }

    private var ambientBackground: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Self.tint.opacity(0.16))
                    .frame(width: 190, height: 190)
                    .blur(radius: 30)
                    .offset(x: -42, y: -38)
                Spacer()
                Circle()
                    .fill(Self.accent.opacity(0.20))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                    .offset(x: 30, y: -22)
            }
            Spacer()
        }
        .ignoresSafeArea()
    }

    private var latestBPM: Int {
        chartData.last?.value ?? 0
    }
    
    private var averageBPM: Int {
        guard !chartData.isEmpty else { return 0 }
        return Int(Double(chartData.map(\.value).reduce(0, +)) / Double(chartData.count))
    }
    
    private var peakBPM: Int {
        chartData.map(\.value).max() ?? 0
    }
    
    private var restingHeartRateText: String {
        guard let restingHeartRate, restingHeartRate > 0 else { return "暂无记录" }
        return String(localized: "\(Int(restingHeartRate.rounded())) 次/分")
    }

    private var statusText: String {
        guard let restingHeartRate, restingHeartRate > 0 else { return "等待健康 App 同步静息心率样本。" }
        if selectedRange != .day {
            return String(localized: "当前已切到\(selectedRange.rawValue)范围，优先看静息底线在这段时间里有没有持续抬高或回落。")
        }
        if peakBPM > 0, Double(peakBPM) >= restingHeartRate + 35 {
            return String(localized: "今天活动负荷比较明显，静息心率更适合和这条日内曲线一起看恢复底线。")
        }
        if averageBPM > 0, Double(averageBPM) <= restingHeartRate + 8 {
            return String(localized: "静息心率和今天整体节奏比较接近，通常说明身体负荷还在相对平稳的范围里。")
        }
        return String(localized: "静息心率已经更新，接下来更适合结合睡眠、HRV 和日内心率判断恢复情况。")
    }

    private var trendSummaryText: String {
        guard !chartData.isEmpty else { return selectedRange == .day ? "等待健康 App 同步当天的心率参考曲线。" : "等待健康 App 同步这段时间的静息心率趋势。" }
        if selectedRange == .day {
            return "静息 \(restingHeartRate.map { String(Int($0.rounded())) } ?? "—") 次/分，当天平均 \(averageBPM) 次/分。"
        }
        return "静息 \(restingHeartRate.map { String(Int($0.rounded())) } ?? "—") 次/分，这段时间平均 \(averageBPM) 次/分。"
    }

    private var chartInsightText: String {
        guard !chartData.isEmpty, let restingHeartRate, restingHeartRate > 0 else { return "" }
        if selectedRange != .day {
            return String(localized: "这条趋势更适合看静息底线有没有连续上移，而不是只盯某一天的高低。")
        }
        if peakBPM - averageBPM >= 30 {
            return String(localized: "白天波动偏明显并不等于静息心率异常，更重要的是看静息底线有没有持续抬高。")
        }
        if Double(averageBPM) <= restingHeartRate + 8 {
            return String(localized: "整体曲线离静息心率不远，说明今天多数时段都处在比较轻的身体负荷里。")
        }
        return String(localized: "可以把这条曲线当作静息心率的背景参考，用来理解今天的活动负荷和恢复状态。")
    }

    private var heartRateDomain: ClosedRange<Int> {
        let resting = restingHeartRate.map { Int($0.rounded()) } ?? 0
        let minSample = chartData.map(\.value).min() ?? max(40, resting - 8)
        let maxSample = chartData.map(\.value).max() ?? max(85, resting + 18)
        let lowerAnchor = resting > 0 ? min(resting, minSample) : minSample
        let upperAnchor = resting > 0 ? max(resting, maxSample) : maxSample
        let minValue = max(35, lowerAnchor - 10)
        let maxValue = min(190, upperAnchor + 10)
        return minValue...max(maxValue, minValue + 20)
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    private var dayEnd: Date {
        if selectedRange == .day {
            return Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        }
        return chartData.last?.date ?? (Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60))
    }

    private var chartDomain: ClosedRange<Date> {
        if selectedRange == .day {
            return dayStart...dayEnd
        }
        let interval = selectedRange.visibleDateInterval(anchorDate: selectedDate)
        return interval.start...interval.end
    }

    private var axisDates: [Date] {
        if selectedRange == .day {
            return [0, 6, 12, 18, 24].compactMap { hour in
                Calendar.current.date(byAdding: .hour, value: hour, to: dayStart)
            }
        }
        let calendar = Calendar.current
        let interval = selectedRange.visibleDateInterval(anchorDate: selectedDate)
        if selectedRange == .week {
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        }
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30)
        return [0, 7, 14, 21, days - 1].compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var emptyTrendChart: some View {
        ZStack {
            Chart(chartData) { item in
                PointMark(x: .value("时间", item.date), y: .value("心率", item.value))
            }
            .frame(height: 204)
            .chartLegend(.hidden)
            .chartYScale(domain: heartRateDomain)
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                                .font(.appSystem(size: 10, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                        .foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel()
                        .font(.appSystem(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            HeartRateEmptyState()
                .padding(.horizontal, 24)
                .frame(height: 118)
        }
    }

    private func axisLabel(for date: Date) -> String {
        if selectedRange != .day {
            return selectedRange == .week ? ChineseDateText.compactMonthDay(date) : ChineseDateText.compactDay(date)
        }
        if abs(date.timeIntervalSince(dayEnd)) < 1 {
            return "24:00"
        }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var selectedHeartRatePoint: TimeSeriesPoint? {
        guard let selectedHeartRateTimestamp else { return nil }
        return chartData.first(where: { $0.timestamp == selectedHeartRateTimestamp })
    }

    private func loadHealthKitHeartRate() async {
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        defer {
            if loadRequestID == requestID {
                isLoading = false
            }
        }
        do {
            if selectedRange == .day {
                let start = Calendar.current.startOfDay(for: selectedDate)
                let end = min(Date(), Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date())
                async let points = HealthKitManager.shared.fetchHeartRateSeries(start: start, end: end, maxPoints: 180)
                async let resting = try? HealthKitManager.shared.fetchRestingHeartRate(on: selectedDate)
                let loadedPoints = try await points
                let loadedResting = await resting
                guard loadRequestID == requestID else { return }
                healthKitPoints = loadedPoints
                dailyTrendPoints = []
                restingHeartRate = loadedResting
            } else {
                let days = selectedRange == .week ? 7 : 31
                let queryEnd = selectedRange.queryEndDate(anchorDate: selectedDate)
                let loadedTrend = try await HealthKitManager.shared.fetchDailyHeartRateAverages(days: days, endDate: queryEnd)
                let loadedResting = try? await HealthKitManager.shared.fetchRestingHeartRate(on: selectedDate)
                guard loadRequestID == requestID else { return }
                dailyTrendPoints = loadedTrend.filter { selectedRange.contains($0.date, anchorDate: selectedDate) }
                healthKitPoints = []
                restingHeartRate = loadedResting
            }
        } catch {
            let loadedResting = try? await HealthKitManager.shared.fetchRestingHeartRate(on: selectedDate)
            guard loadRequestID == requestID else { return }
            restingHeartRate = loadedResting
        }
        selectedHeartRateTimestamp = chartData.last?.timestamp
    }

    private var overviewCard: some View {
            HStack(spacing: 10) {
            overviewPill(title: "静息", value: restingHeartRateText, tint: Self.tint)
            overviewPill(title: "均值", value: averageBPM > 0 ? "\(averageBPM) 次/分" : "暂无", tint: Color(hex: "FF9AA2"))
            overviewPill(title: "峰值", value: peakBPM > 0 ? "\(peakBPM) 次/分" : "暂无", tint: Color(hex: "7D8BFF"))
        }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            ModernReportHero(
                eyebrow: String(localized: "心率"),
                title: selectedRange == .day
                    ? String(localized: "静息心率")
                    : selectedRange == .week
                        ? String(localized: "本周静息心率")
                        : String(localized: "本月静息心率"),
                value: restingHeartRate.map { "\(Int($0.rounded()))" } ?? "--",
                unit: "BPM",
                ghostUnit: "BPM",
                captions: [
                    ModernReportCaption(symbol: "calendar", text: selectedRange.title(for: selectedDate)),
                    ModernReportCaption(symbol: "heart.text.square.fill", text: String(localized: "健康 App"))
                ],
                badge: ModernReportBadge(
                    symbol: "waveform.path.ecg",
                    text: rhythmBadgeText,
                    tint: rhythmBadgeTint
                ),
                accent: Self.tint,
                symbol: "heart.fill"
            )

            ModernReportSegmentedPicker(
                selection: $selectedRange,
                options: MetricDetailRange.allCases.map {
                    ModernReportPickerOption(value: $0, title: $0.rawValue)
                }
            )

            ModernReportDateStepper(
                title: selectedRange.title(for: selectedDate),
                canMoveForward: canMoveForward,
                onPrevious: { selectedDate = selectedRange.shiftClampedToToday(selectedDate, by: -1) },
                onNext: { selectedDate = selectedRange.shiftClampedToToday(selectedDate, by: 1) }
            )

            ModernReportMetricsPanel(
                title: String(localized: "心率数据"),
                metrics: [
                    ModernReportMetric(
                        title: String(localized: "静息心率"),
                        value: restingHeartRateText,
                        tint: Self.tint,
                        symbol: "heart.fill"
                    ),
                    ModernReportMetric(
                        title: String(localized: "平均心率"),
                        value: averageBPM > 0 ? String(localized: "\(averageBPM) BPM") : String(localized: "暂无"),
                        tint: Color(hex: "FF9AA2"),
                        symbol: "chart.line.uptrend.xyaxis"
                    ),
                    ModernReportMetric(
                        title: String(localized: "峰值心率"),
                        value: peakBPM > 0 ? String(localized: "\(peakBPM) BPM") : String(localized: "暂无"),
                        tint: Color(hex: "7D8BFF"),
                        symbol: "arrow.up.right"
                    ),
                    ModernReportMetric(
                        title: String(localized: "样本数"),
                        value: "\(chartData.count)",
                        tint: Theme.Colors.mintGreen,
                        symbol: "list.bullet.rectangle.fill"
                    )
                ]
            )

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(verbatim: statusText)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                }
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .modernReportPanelSurface()
        }
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("静息节律")
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(selectedRange == .day ? "先看静息心率本身，再看它和当天整体心率节奏之间有没有明显偏离。" : "先看静息底线在这段时间里是否平稳，再判断恢复有没有持续抬高。")
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge(restingBadgeText, tint: Color(hex: "7D8BFF"))
            }

            HStack(spacing: 10) {
                insightTag(title: "日内均值", value: averageBPM > 0 ? "\(averageBPM) 次/分" : "暂无")
                insightTag(title: "静息差值", value: peakSpreadText)
            }

            Text(chartInsightText)
                .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .detailCardSurface(tint: Self.accent)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedRange == .day ? "日内心率参考" : (selectedRange == .week ? "周内静息趋势" : "月内静息趋势"))
                        .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(trendSummaryText)
                        .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                sectionBadge(chartData.isEmpty ? "暂无数据" : "静息基线", tint: Self.tint)
            }

            if !chartData.isEmpty {
                HStack(spacing: 8) {
                    chartMetricChip(title: selectedRange == .day ? "静息" : "当前", value: restingHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
                    chartMetricChip(title: "均值", value: "\(averageBPM)")
                    chartMetricChip(title: "高点", value: "\(peakBPM)")
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 204)
            } else if chartData.isEmpty {
                emptyTrendChart
            } else {
                Chart(chartData) { item in
                    LineMark(
                        x: .value("时间", item.date),
                        y: .value("心率", item.value)
                    )
                    .foregroundStyle(Self.tint.opacity(selectedHeartRatePoint == nil || selectedHeartRatePoint?.timestamp == item.timestamp ? 0.94 : 0.52))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    if let restingHeartRate, restingHeartRate > 0 {
                        RuleMark(y: .value("静息基线", restingHeartRate))
                            .foregroundStyle(Self.tint.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("静息 \(Int(restingHeartRate.rounded()))")
                                    .font(.appSystem(size: 10, weight: .bold))
                                    .foregroundColor(Self.tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                            }
                    }

                    if let selectedHeartRatePoint {
                        RuleMark(x: .value("选中", selectedHeartRatePoint.date))
                            .foregroundStyle(Self.tint.opacity(0.24))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 216)
                .chartLegend(.hidden)
                .chartYScale(domain: heartRateDomain)
                .chartXScale(domain: chartDomain)
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
                                                updateHeartRateSelection(at: drag.location, frame: frame, proxy: proxy)
                                            default:
                                                break
                                            }
                                        }
                                        .onEnded { value in
                                            switch value {
                                            case .second(true, let drag):
                                                if let drag {
                                                    updateHeartRateSelection(at: drag.location, frame: frame, proxy: proxy)
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
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                                    .font(.appSystem(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                        .padding(.bottom, 10)
                }
            }

            if let selectedHeartRatePoint {
                selectedHeartRateDetailCard(for: selectedHeartRatePoint)
            }

            if !chartData.isEmpty {
                Text(chartInsightText)
                    .font(Theme.Typography.scaled(size: 12, weight: .medium, design: .rounded, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .detailCardSurface(tint: Self.tint)
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("建议")
                    .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                sectionBadge("恢复判断", tint: Self.tint)
            }

            summaryRow(title: "当前状态", value: statusText)
            summaryRow(title: "基线参考", value: chartInsightText)
            summaryRow(title: "推荐安排", value: guideSummaryText)
        }
        .detailCardSurface(tint: Color(hex: "7D8BFF"))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明")
                .font(Theme.Typography.scaled(size: 20, weight: .bold, design: .serif, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(selectedRange == .day ? "这里优先读取健康 App 的静息心率，并用当天心率曲线帮助理解这条恢复底线放在什么背景里。" : "这里优先读取健康 App 的静息心率，并按所选范围展示每天的平均变化。")
            Text(selectedRange == .day ? "静息心率更适合按天或按周看变化，单次日内波动不代表静息水平本身发生了改变。" : "静息心率更适合看连续几天有没有整体上移，而不是只看某一天高一点还是低一点。")
        }
        .font(Theme.Typography.scaled(size: 13, weight: .medium, design: .rounded, level: appFontScaleLevel))
        .foregroundColor(Theme.Colors.textSecondary)
        .detailCardSurface()
    }

    private func overviewPill(title: String, value: String, tint: Color) -> some View {
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

    private func chartMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.scaled(size: 10, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 15, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Typography.scaled(size: 10, weight: .heavy, design: .rounded, level: appFontScaleLevel))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func insightTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.scaled(size: 11, weight: .bold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.scaled(size: 15, weight: .black, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.scaled(size: 13, weight: .semibold, design: .rounded, level: appFontScaleLevel))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var rhythmBadgeText: String {
        if restingHeartRate == nil { return "等待同步" }
        if peakBPM - averageBPM >= 32 { return "负荷偏高" }
        if let restingHeartRate, restingHeartRate > 0, averageBPM > 0, Double(averageBPM) <= restingHeartRate + 8 {
            return "底线平稳"
        }
        return "恢复观察"
    }

    private var rhythmBadgeTint: Color {
        switch rhythmBadgeText {
        case "底线平稳":
            return Self.tint
        case "负荷偏高":
            return Color(hex: "FF7A59")
        default:
            return Self.tint
        }
    }

    private var peakSpreadText: String {
        guard peakBPM > 0, averageBPM > 0 else { return "等待样本" }
        if let restingHeartRate, restingHeartRate > 0, peakBPM > 0 {
            return String(localized: "\(max(0, peakBPM - Int(restingHeartRate.rounded()))) 次/分")
        }
        return String(localized: "等待样本")
    }

    private var restingBadgeText: String {
        guard let restingHeartRate, restingHeartRate > 0 else { return "暂无静息" }
        return String(localized: "静息 \(Int(restingHeartRate.rounded()))")
    }

    private var suggestedActionText: String {
        guard restingHeartRate != nil else { return "先等样本同步" }
        if peakBPM - averageBPM >= 32 { return "结合活动一起看" }
        if let restingHeartRate, restingHeartRate > 0, averageBPM > 0, Double(averageBPM) <= restingHeartRate + 8 {
            return "维持当前恢复"
        }
        return "继续观察恢复"
    }

    private var guideSummaryText: String {
        if let restingHeartRate, restingHeartRate > 0, averageBPM > 0, Double(averageBPM) > restingHeartRate + 12 {
            return String(localized: "今天负荷比静息底线更高，适合一起对照睡眠和压力页面。")
        }
        return selectedRange == .day ? "先用静息心率判断恢复底线，再用日内曲线辅助理解今天的身体负荷。" : "先看这段时间的静息底线是否稳定，再判断最近恢复有没有被活动和睡眠打断。"
    }

    private func updateHeartRateSelection(at location: CGPoint, frame: CGRect, proxy: ChartProxy) {
        guard frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else { return }
        selectedHeartRateTimestamp = nearestHeartRatePoint(to: date)?.timestamp
    }

    private func nearestHeartRatePoint(to date: Date) -> TimeSeriesPoint? {
        chartData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func selectedHeartRateDetailCard(for point: TimeSeriesPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selectedRange == .day ? point.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ChineseDateText.compactMonthDay(point.date))
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(heartRateTimePeriodText(for: point.date))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text("\(point.value) 次/分")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Self.tint)
            }

            Text(selectedHeartRateDescription(for: point))
                .font(Theme.Typography.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Self.tint.opacity(0.12), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func heartRateTimePeriodText(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<6:
            return String(localized: "凌晨")
        case 6..<12:
            return String(localized: "上午")
        case 12..<18:
            return "下午"
        default:
            return "晚上"
        }
    }

    private func selectedHeartRateDescription(for point: TimeSeriesPoint) -> String {
        if let restingHeartRate, restingHeartRate > 0 {
            let delta = point.value - Int(restingHeartRate.rounded())
            if delta >= 30 {
                return String(localized: "\(heartRateTimePeriodText(for: point.date))这段心率比静息基线高 \(delta) 次/分，更像是活动、通勤或情绪波动带来的正常抬升。")
            }
            if delta <= 8 {
                return String(localized: "\(heartRateTimePeriodText(for: point.date))这段心率离静息基线不远，身体负荷相对平稳，更适合当作恢复背景来读。")
            }
            return String(localized: "\(heartRateTimePeriodText(for: point.date))这段心率比静息基线高 \(delta) 次/分，可以结合压力和活动页面一起判断当时负荷。")
        }
        return String(localized: "\(heartRateTimePeriodText(for: point.date))记录到 \(point.value) 次/分，等静息心率样本同步后，这条曲线会更容易读出恢复含义。")
    }
}

private struct HeartRateEmptyState: View {
    var body: some View {
        BBInlineEmptyState(systemImage: "heart.text.square", title: String(localized: "健康 App 暂无静息心率"), message: String(localized: "请确认已授权读取静息心率，或在设备完成同步后再回来查看。"))
    }
}

#if DEBUG
private func heartRatePreviewPoint(hour: Int, value: Int) -> TimeSeriesPoint {
        let start = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .hour, value: hour, to: start) ?? start
        return TimeSeriesPoint(timestamp: Int64(date.timeIntervalSince1970), value: value)
}
#endif

private extension View {
    func detailCardSurface(tint: Color? = nil) -> some View {
        self
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), tint?.opacity(0.05) ?? Color.white.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
    }
}
