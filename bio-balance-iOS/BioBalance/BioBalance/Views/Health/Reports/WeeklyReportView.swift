/// WeeklyReportView 由报告模块入口调用，作为「报告详情」周报页。
/// 负责按周切换展示综合评分、分类 Tab（综合/睡眠/运动/心率/压力）、各项指标与个性化建议。

import SwiftUI
import Charts

/// 报告详情的周期粒度。
enum ReportDetailPeriod: Equatable {
    case week
    case month

    var navigationTitle: String {
        switch self {
        case .week: return String(localized: "报告详情")
        case .month: return String(localized: "月度报告")
        }
    }
}

/// 报告详情的分类 Tab。
/// 「综合」汇总四项指标；其余 Tab 聚焦单一指标在所选周期内的表现。
enum ReportDetailSegment: String, CaseIterable, Identifiable {
    case overall = "综合"
    case sleep = "睡眠"
    case activity = "运动"
    case heartRate = "心率"
    case stress = "压力"

    var id: String { rawValue }

    /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
    var displayName: String {
        switch self {
        case .overall: return String(localized: "综合")
        case .sleep: return String(localized: "睡眠")
        case .activity: return String(localized: "运动")
        case .heartRate: return String(localized: "心率")
        case .stress: return String(localized: "压力")
        }
    }

    var systemImage: String {
        switch self {
        case .overall: return "square.grid.2x2.fill"
        case .sleep: return "moon.fill"
        case .activity: return "figure.run"
        case .heartRate: return "heart.fill"
        case .stress: return "leaf.fill"
        }
    }
}

/// 报告详情页 由报告模块入口调用，作为「报告详情」页。
/// 支持 week / month 两种粒度：按周（或月）切换展示综合评分、
/// 分类 Tab（综合/睡眠/运动/心率/压力）、各项指标与个性化建议。
struct WeeklyReportView: View {
    /// Week Range 枚举，作为内部辅助类型，用于按周箭头切换报告周期。
    enum WeekRange: String, CaseIterable, Identifiable {
        case thisWeek = "本周"
        case lastWeek = "上周"
        case twoWeeksAgo = "两周前"
        case threeWeeksAgo = "三周前"

        var id: String { rawValue }

        /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
        var displayName: String {
            switch self {
            case .thisWeek: return String(localized: "本周")
            case .lastWeek: return String(localized: "上周")
            case .twoWeeksAgo: return String(localized: "两周前")
            case .threeWeeksAgo: return String(localized: "三周前")
            }
        }

        var offsetWeeks: Int {
            switch self {
            case .thisWeek: return 0
            case .lastWeek: return -1
            case .twoWeeksAgo: return -2
            case .threeWeeksAgo: return -3
            }
        }

        func shifted(by offset: Int) -> Self? {
            Self.allCases.first { $0.offsetWeeks == offsetWeeks + offset }
        }
    }

    private let period: ReportDetailPeriod
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var viewModel = ReportSummaryViewModel()
    @State private var selectedRange: WeekRange
    @State private var monthOffset: Int = 0
    @State private var selectedSegment: ReportDetailSegment = .overall
    @State private var hapticSelectionTick = 0
    @State private var showingShareSheet = false
    @State private var inspectedOverallDate: Date?
    @State private var inspectedMetricDate: Date?

    init(initialRange: WeekRange = .thisWeek, period: ReportDetailPeriod = .week) {
        self.period = period
        self.selectedRange = initialRange
    }

    // MARK: - 周期计算

    private var periodInterval: DateInterval {
        let calendar = Calendar.current
        switch period {
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
            let start = calendar.date(byAdding: .weekOfYear, value: selectedRange.offsetWeeks, to: startOfWeek) ?? startOfWeek
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .month:
            let base = calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
            let interval = calendar.dateInterval(of: .month, for: base)
            return interval ?? DateInterval(start: calendar.startOfDay(for: base), duration: 30 * 24 * 3600)
        }
    }

    private var periodTitle: String {
        switch period {
        case .week:
            let calendar = Calendar.current
            let start = periodInterval.start
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(start.reportsMonthDayString()) - \(end.reportsMonthDayString())"
        case .month:
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("yMMMM")
            return formatter.string(from: periodInterval.start)
        }
    }

    /// 当前周期的有效天数上限（周 7 天 / 月按自然日数）。
    private var expectedDayCount: Int {
        switch period {
        case .week:
            guard selectedRange == .thisWeek else { return 7 }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let start = calendar.startOfDay(for: periodInterval.start)
            guard today >= start, today < periodInterval.end else { return 7 }
            let elapsed = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return min(7, max(1, elapsed))
        case .month:
            let calendar = Calendar.current
            let total = calendar.range(of: .day, in: .month, for: periodInterval.start)?.count ?? 30
            let today = calendar.startOfDay(for: Date())
            let start = calendar.startOfDay(for: periodInterval.start)
            guard today >= start, today < periodInterval.end else {
                return total
            }
            let elapsed = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return min(total, max(1, elapsed))
        }
    }

    private var periodSummaries: [ReportDaySummary] {
        viewModel.summaries(for: periodInterval)
    }

    private var points: [ReportDaySummary] {
        periodSummaries.filter { $0.score != nil }
    }

    /// 上一周期的区间，用于计算环比。
    private var previousPeriodInterval: DateInterval {
        let calendar = Calendar.current
        switch period {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: periodInterval.start) ?? periodInterval.start
            let end = selectedRange == .thisWeek
                ? min(calendar.date(byAdding: .day, value: expectedDayCount, to: start) ?? periodInterval.start, periodInterval.start)
                : periodInterval.start
            return DateInterval(start: start, end: end)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: periodInterval.start) ?? periodInterval.start
            let end = monthOffset == 0
                ? min(calendar.date(byAdding: .day, value: expectedDayCount, to: start) ?? periodInterval.start, periodInterval.start)
                : periodInterval.start
            return DateInterval(start: start, end: end)
        }
    }

    /// 周报、月报分别与紧邻的上一完整自然周、自然月比较。
    private var weeklyReview: WeeklyHealthReview {
        WeeklyHealthReviewEngine.make(
            current: periodSummaries,
            previous: viewModel.summaries(for: previousPeriodInterval),
            expectedDays: expectedDayCount,
            scope: periodScopeName
        )
    }

    private var periodScopeName: String {
        switch period {
        case .week: return selectedRange.displayName
        case .month: return monthOffset == 0 ? String(localized: "本月") : periodTitle
        }
    }

    /// 文案里的周期名词（周/月），供各卡片按粒度组句。
    private var cycleNoun: String {
        period == .week ? String(localized: "周") : String(localized: "月")
    }

    private var averageScore: Int? {
        points.reportsAverageScore
    }

    private var scoreDelta: Int? {
        weeklyReview.scoreDelta
    }

    private var canNavigateToPreviousPeriod: Bool {
        switch period {
        case .week:
            return selectedRange.offsetWeeks > WeekRange.allCases.last!.offsetWeeks
        case .month:
            return monthOffset > -3
        }
    }

    private var canNavigateToNextPeriod: Bool {
        switch period {
        case .week:
            return selectedRange.offsetWeeks < WeekRange.allCases.first!.offsetWeeks
        case .month:
            return monthOffset < 0
        }
    }

    /// 需要加载的历史天数（月报模式要覆盖回看 3 个月）。
    private var loadDays: Int {
        period == .month ? 120 : 36
    }

    // MARK: - 主体

    var body: some View {
        ZStack {
            Theme.Colors.surface.ignoresSafeArea()

            AdaptivePageScrollView(style: .reading, topPadding: 20, bottomPadding: 64) {
                VStack(alignment: .leading, spacing: 0) {
                    weekNavigationBar
                    segmentPicker
                        .padding(.top, 16)
                        .padding(.bottom, 28)

                    switch selectedSegment {
                    case .overall:
                        overallScoreCard
                        reportSection { overallTrendCard }
                        reportSection { metricBreakdownCard }
                        reportSection { personalizedAdviceCard }
                    case .sleep:
                        reportSection { singleMetricDetailCard(kind: .sleep) }
                        reportSection { metricTrendCard(kind: .sleep) }
                    case .activity:
                        reportSection { singleMetricDetailCard(kind: .activity) }
                        reportSection { metricTrendCard(kind: .activity) }
                    case .heartRate:
                        reportSection { heartRateDetailCard }
                        reportSection { heartRateTrendCard }
                    case .stress:
                        reportSection { stressDetailCard }
                        reportSection { metricTrendCard(kind: .stress) }
                    }
                }
            }
        }
        .navigationTitle(period.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.appSystem(size: 15, weight: .bold))
                }
                .accessibilityLabel("分享报告")
            }
        }
        .task {
            viewModel.load(days: loadDays)
        }
        .sensoryFeedback(.selection, trigger: hapticSelectionTick)
        .sheet(isPresented: $showingShareSheet) {
            ReportShareView(
                reportDate: points.last?.date ?? periodInterval.start,
                score: averageScore ?? 0
            )
            .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.92), .large], dragIndicator: .hidden)
            .presentationCornerRadius(26)
            .presentationBackground(Color(hex: "F1F1EF"))
        }
    }

    // MARK: - 周期导航

    private func metricStrip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3),
            spacing: 8,
            content: content
        )
    }

    /// 连续报告的统一分区：数据直接呈现在页面上，不嵌套整块装饰卡片。
    private func reportSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.textTertiary.opacity(0.16))
                .frame(height: 1)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
                .padding(.bottom, 28)
        }
    }

    private var weekNavigationBar: some View {
        HStack(spacing: 12) {
            weekArrowButton(systemImage: "chevron.left", isEnabled: canNavigateToPreviousPeriod) {
                switch period {
                case .week:
                    selectedRange = selectedRange.shifted(by: -1) ?? selectedRange
                case .month:
                    monthOffset -= 1
                }
                resetChartSelections()
            }

            Text(periodTitle)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            weekArrowButton(systemImage: "chevron.right", isEnabled: canNavigateToNextPeriod) {
                switch period {
                case .week:
                    selectedRange = selectedRange.shifted(by: 1) ?? selectedRange
                case .month:
                    monthOffset += 1
                }
                resetChartSelections()
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "报告周期 \(periodTitle)"))
    }

    private func weekArrowButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard isEnabled else { return }
            action()
            hapticSelectionTick += 1
        } label: {
            Image(systemName: systemImage)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(isEnabled ? Color(hex: "3C4048") : Color(hex: "C9CCD1"))
                .frame(width: 44, height: 44)
                .background(
                    Color(hex: "F3F4F6"),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "chevron.left" ? String(localized: "上一周") : String(localized: "下一周"))
    }

    // MARK: - 分类 Tab

    private var segmentPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 2 : 5), spacing: 6) {
            ForEach(ReportDetailSegment.allCases) { segment in
                segmentButton(segment)
            }
        }
        .padding(5)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func segmentButton(_ segment: ReportDetailSegment) -> some View {
        let isSelected = segment == selectedSegment
        return Button {
            guard !isSelected else { return }
            selectedSegment = segment
            inspectedMetricDate = nil
            hapticSelectionTick += 1
        } label: {
            Text(segment.displayName)
                .font(.appSystem(size: 13, weight: isSelected ? .black : .bold, design: .rounded))
                .foregroundColor(isSelected ? Color(hex: "17181C") : Color(hex: "878C94"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    isSelected ? Color(hex: "EFF1F4") : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 综合评分卡

    private var overallScoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "综合评分"))
                .font(.appSystem(size: 28, weight: .bold))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(averageScore.map(String.init) ?? "--")
                    .font(.appSystem(size: 84, weight: .heavy))
                    .foregroundColor(averageStatusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(String(localized: "/100"))
                    .font(.appSystem(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Text(averageStatusText)
                .font(.appSystem(size: 15, weight: .semibold))
                .foregroundColor(averageStatusTint)
            deltaBadge
            Text(overallNarrative)
                .font(.appSystem(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 28)
    }

    /// 综合页的周期评分曲线。周报逐日阅读，月报以连续曲线呈现整月走势，
    /// 并支持拖动查看任意一天的具体评分与周期均值差异。
    private var overallTrendCard: some View {
        let scoredPoints = points.sorted { $0.date < $1.date }
        let selectedPoint = nearestSummary(to: inspectedOverallDate, in: scoredPoints)
        let activePoint = inspectedOverallDate == nil ? scoredPoints.last : selectedPoint
        let bestPoint = scoredPoints.max { $0.scoreValue < $1.scoreValue }
        let lowestPoint = scoredPoints.min { $0.scoreValue < $1.scoreValue }
        let average = scoredPoints.reportsAverageScore
        let segments = continuousDaySegments(for: scoredPoints.map(\.date))

        return ReportsContentCard(spacing: 14, isContinuous: true) {
            ReportsSectionHeader(
                String(localized: "综合评分\(cycleNoun)趋势"),
                subtitle: period == .week
                    ? String(localized: "逐日查看综合状态，拖动图表可回看当天表现。")
                    : String(localized: "连续查看整月状态变化，拖动图表可定位具体日期。")
            )

            if scoredPoints.isEmpty {
                reportTrendEmptyState(String(localized: "这个\(cycleNoun)暂无综合评分趋势"))
            } else {
                metricStrip {
                    ReportsCompactMetricPill(
                        title: String(localized: "\(cycleNoun)均"),
                        value: average.map { "\($0) 分" } ?? "--",
                        tint: ReportsScorePalette.tint(for: average)
                    )
                    ReportsCompactMetricPill(
                        title: String(localized: "高点"),
                        value: bestPoint.map { "\($0.scoreValue) · \($0.date.reportsMonthDayString())" } ?? "--",
                        tint: Theme.Colors.mintGreen
                    )
                    ReportsCompactMetricPill(
                        title: String(localized: "波动"),
                        value: scoredPoints.count >= 2
                            ? scoreRangeText(lowest: lowestPoint, highest: bestPoint)
                            : "--",
                        tint: Color(hex: "8E6CFF")
                    )
                }

                HStack(spacing: 18) {
                    trendLegendItem(String(localized: "周期均值"), tint: ReportsChartStyle.averageLine, dashed: true)
                    trendLegendItem(String(localized: "稳定参考"), tint: ReportsChartStyle.stabilityLine, dashed: true)
                }

                Chart {
                    ForEach(scoredPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue),
                            series: .value("连续区间", segments[point.date.reportsDayKey()] ?? 0)
                        )
                        .foregroundStyle(Theme.Colors.mintGreen)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("评分", point.scoreValue)
                        )
                        .foregroundStyle(Theme.Colors.mintGreen)
                        .symbol(.circle)
                        .symbolSize(selectedPoint?.id == point.id ? 82 : (period == .week ? 46 : 28))
                        .accessibilityLabel(point.date.reportsMonthDayString())
                        .accessibilityValue(String(localized: "综合评分 \(point.scoreValue) 分"))
                    }

                    if let average {
                        RuleMark(y: .value("周期均值", average))
                            .reportsAverageRule()
                    }

                    RuleMark(y: .value("稳定参考", 70))
                        .reportsStabilityRule()

                    if let selectedPoint {
                        RuleMark(x: .value("当前选择", selectedPoint.date))
                            .reportsSelectionRule(tint: ReportsScorePalette.tint(for: selectedPoint.score))
                    }
                }
                .frame(height: 220)
                .chartYScale(domain: 0...100)
                .chartYAxis { scoreTrendYAxis }
                .chartLegend(.hidden)
                .chartXScale(domain: chartDateDomain)
                .chartXSelection(value: $inspectedOverallDate)
                .chartXAxis { trendXAxis }
                .onChange(of: selectedPoint?.id) { _, newValue in
                    if newValue != nil {
                        hapticSelectionTick += 1
                    }
                }
                .accessibilityLabel(String(localized: "综合评分\(cycleNoun)趋势图"))

                if let activePoint {
                    reportChartReadout(
                        date: activePoint.date, isSelected: inspectedOverallDate != nil,
                        value: String(localized: "\(activePoint.scoreValue) 分"),
                        comparison: comparisonText(value: Double(activePoint.scoreValue), average: average.map(Double.init)),
                        tint: ReportsScorePalette.tint(for: activePoint.score)
                    )
                } else if let date = inspectedOverallDate {
                    reportMissingDay(date)
                }

                trendExtremes(
                    high: bestPoint.map { String(localized: "\($0.scoreValue) 分") }, highDate: bestPoint?.date,
                    low: lowestPoint.map { String(localized: "\($0.scoreValue) 分") }, lowDate: lowestPoint?.date
                )
                chartCoverageNote(observedDays: scoredPoints.count)
            }
        }
    }

    private var deltaBadge: some View {
        HStack(spacing: 6) {
            if let scoreDelta {
                Image(systemName: scoreDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.appSystem(size: 11, weight: .black))
            } else {
                Image(systemName: "leaf.fill")
                    .font(.appSystem(size: 11, weight: .black))
            }

            Text(deltaBadgeText)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(deltaBadgeTint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(deltaBadgeTint.opacity(0.12), in: Capsule())
    }

    private var deltaBadgeText: String {
        guard let scoreDelta else {
            return String(localized: "等待可比样本")
        }
        if scoreDelta == 0 {
            return String(localized: "与\(comparisonPeriodName)持平")
        }
        return scoreDelta > 0
            ? String(localized: "较\(comparisonPeriodName)提升 \(scoreDelta) 分")
            : String(localized: "较\(comparisonPeriodName)下降 \(abs(scoreDelta)) 分")
    }

    private var comparisonPeriodName: String {
        switch period {
        case .week:
            return selectedRange == .thisWeek ? String(localized: "上周同期") : String(localized: "上周")
        case .month:
            return monthOffset == 0 ? String(localized: "上月同期") : String(localized: "上月")
        }
    }

    private var comparisonPillTitle: String {
        if (period == .week && selectedRange == .thisWeek) || (period == .month && monthOffset == 0) {
            return String(localized: "同期变化")
        }
        return String(localized: "环比变化")
    }

    private var deltaBadgeTint: Color {
        guard let scoreDelta else { return Color(hex: "8A9099") }
        if scoreDelta > 0 { return Theme.Colors.mintGreen }
        if scoreDelta < 0 { return Color(hex: "E0603F") }
        return Color(hex: "5B8CFF")
    }

    private var averageStatusText: String {
        ReportScoreStatus.shortLabel(for: averageScore)
    }

    private var averageStatusTint: Color {
        ReportsScorePalette.tint(for: averageScore)
    }

    private var overallNarrative: String {
        let review = weeklyReview
        if review.observedDays == 0 {
            return String(localized: "这个\(cycleNoun)还没有可解读的健康样本，先完成设备佩戴与数据同步。")
        }
        var parts: [String] = [review.summary]
        if let supportKind = review.supportKind {
            parts.append(String(localized: "\(supportKind.title)表现突出。"))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 各项指标卡

    private var metricBreakdownCard: some View {
        let rows = metricRows
        return VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "各项指标"))
                .font(.appSystem(size: 20, weight: .bold))
                .foregroundColor(Theme.Colors.textPrimary)

            if rows.allSatisfy({ $0.score == nil }) {
                ReportsInlineEmptyState(text: String(localized: "这个\(cycleNoun)暂无可生成报告的数据"))
            } else {
                VStack(spacing: 16) {
                    ForEach(rows) { row in
                        metricRow(row)
                    }
                }
            }
        }
    }

    /// 综合页的指标行：睡眠、运动、心率、压力。
    /// 心率不在 ReportMetricKind 中，改用日均心率单独归一化。
    private var metricRows: [ReportDetailMetricRow] {
        [
            ReportDetailMetricRow(
                title: String(localized: "睡眠"),
                systemImage: ReportMetricKind.sleep.systemImage,
                tint: ReportMetricKind.sleep.tint,
                score: ReportDetailWeekMetric(kind: .sleep, points: periodSummaries).score,
                summary: ReportDetailWeekMetric(kind: .sleep, points: periodSummaries).rawValueSummary,
                segment: .sleep
            ),
            ReportDetailMetricRow(
                title: String(localized: "运动"),
                systemImage: ReportMetricKind.activity.systemImage,
                tint: ReportMetricKind.activity.tint,
                score: ReportDetailWeekMetric(kind: .activity, points: periodSummaries).score,
                summary: ReportDetailWeekMetric(kind: .activity, points: periodSummaries).rawValueSummary,
                segment: .activity
            ),
            heartRateMetricRow,
            ReportDetailMetricRow(
                title: String(localized: "压力"),
                systemImage: ReportMetricKind.stress.systemImage,
                tint: ReportMetricKind.stress.tint,
                score: ReportDetailWeekMetric(kind: .stress, points: periodSummaries).score,
                summary: ReportDetailWeekMetric(kind: .stress, points: periodSummaries).rawValueSummary,
                segment: .stress
            )
        ]
    }

    /// 心率行：由日均心率归一化（静息心率越低状态越好）。
    private var heartRateMetricRow: ReportDetailMetricRow {
        let values = periodSummaries.compactMap(\.averageHeartRate).filter { $0 > 0 }
        let score: Int? = values.isEmpty
            ? nil
            : values.map { max(0, min(100, 100 - ($0 - 55) * 2)) }.average.map { Int($0.rounded()) }
        let summary = values.isEmpty
            ? String(localized: "暂无心率样本")
            : String(localized: "日均心率均值 \(Int((values.reduce(0, +) / Double(values.count)).rounded())) bpm")
        return ReportDetailMetricRow(
            title: String(localized: "心率"),
            systemImage: "heart.fill",
            tint: Color(hex: "E0603F"),
            score: score,
            summary: summary,
            segment: .heartRate
        )
    }

    private func metricRow(_ row: ReportDetailMetricRow) -> some View {
        let gradeTint = row.gradeTint

        return Button {
            selectedSegment = row.segment
            inspectedMetricDate = nil
            hapticSelectionTick += 1
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: row.systemImage)
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(row.tint)
                        .frame(width: 34, height: 34)
                        .background(row.tint.opacity(0.12), in: Circle())

                    Text(row.title)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "23252B"))

                    Spacer(minLength: 8)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(row.score.map(String.init) ?? "--")
                            .font(.appSystem(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(String(localized: "/100"))
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Text(row.gradeText)
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(gradeTint)
                        .frame(width: 44, alignment: .trailing)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Theme.Colors.secondaryBackground)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [row.tint.opacity(0.55), row.tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(Double(row.score ?? 0) / 100.0))
                    }
                }
                .frame(height: 10)

                Text(row.summary)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "878C94"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(row.title) \(row.score.map { "\($0) 分" } ?? "暂无")，\(row.gradeText)，\(row.summary)"))
    }

    // MARK: - 个性化建议卡

    private var personalizedAdviceCard: some View {
        let items = personalizedAdviceItems

        return VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "个性化建议"))
                .font(.appSystem(size: 20, weight: .bold))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(Color(hex: "C9CCD1"))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)

                        Text(item)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "3E4249"))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var personalizedAdviceItems: [String] {
        var items: [String] = []

        if let attentionKind = weeklyReview.attentionKind {
            items.append(adviceForKind(attentionKind))
        }
        if let advice = points.reversed().compactMap({ $0.adviceSummary?.actionItems.first }).first {
            items.append(advice)
        }
        items.append(weeklyReview.nextAction)

        if items.isEmpty {
            items.append(String(localized: "先保持设备佩戴并同步健康数据，样本足够后会生成个性化建议。"))
        }
        var seen: Set<String> = []
        return items.filter { seen.insert($0).inserted }
    }

    private func adviceForKind(_ kind: ReportMetricKind) -> String {
        switch kind {
        case .sleep:
            return String(localized: "保持规律的作息时间，优先固定入睡和起床窗口。")
        case .activity:
            return String(localized: "尝试每周进行 30 分钟中等强度运动，补齐活动短板。")
        case .stress:
            return String(localized: "可以通过冥想或深呼吸来进一步降低压力。")
        case .hrv:
            return String(localized: "优先降低刺激和强度，让身体恢复弹性先回升。")
        }
    }

    // MARK: - 单指标 Tab 详情

    private func reportValue(_ value: String, unit: String, status: String? = nil, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.appSystem(size: 64, weight: .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.appSystem(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status {
                Text(status)
                    .font(.appSystem(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func singleMetricDetailCard(kind: ReportMetricKind) -> some View {
        let metric = ReportDetailWeekMetric(kind: kind, points: periodSummaries)
        let validSummaries = periodSummaries.filter { ReportMetricFormatter.hasMetric(kind, in: $0) }
        let previousMetric = ReportDetailWeekMetric(
            kind: kind,
            points: viewModel.summaries(for: previousPeriodInterval)
        )
        let delta = metric.score.flatMap { current -> Int? in
            guard metric.observedDays >= WeeklyHealthReviewEngine.minimumComparableScoreDays,
                  previousMetric.observedDays >= WeeklyHealthReviewEngine.minimumComparableScoreDays,
                  let previous = previousMetric.score else { return nil }
            return current - previous
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(metric.tint)
                    .frame(width: 36, height: 36)
                    .background(metric.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "\(localizedMetricTitle(for: kind))表现"))
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(periodTitle)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)
            }

            reportValue(metric.score.map(String.init) ?? "--", unit: String(localized: "/100"), status: metric.gradeText, tint: metric.gradeTint)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Theme.Colors.secondaryBackground)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [metric.tint.opacity(0.55), metric.tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(Double(metric.score ?? 0) / 100.0))
                }
            }
            .frame(height: 10)

            metricStrip {
                ReportsCompactMetricPill(
                    title: String(localized: "\(cycleNoun)均值"),
                    value: ReportMetricFormatter.averageRawValueText(for: kind, in: validSummaries),
                    tint: metric.tint
                )
                ReportsCompactMetricPill(
                    title: comparisonPillTitle,
                    value: delta.map { $0 >= 0 ? "+\($0)" : "\($0)" } ?? "--",
                    tint: delta.map { $0 >= 0 ? Theme.Colors.mintGreen : Color(hex: "E0603F") } ?? Color(hex: "8A9099")
                )
                ReportsCompactMetricPill(
                    title: String(localized: "覆盖天数"),
                    value: "\(metric.observedDays)/\(expectedDayCount)",
                    tint: Color(hex: "5B8CFF")
                )
            }

            Text(metricNarrative(metric))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricNarrative(_ metric: ReportDetailWeekMetric) -> String {
        guard let score = metric.score else {
            return String(localized: "这个\(cycleNoun)\(localizedMetricTitle(for: metric.kind))样本不足，先补齐数据再回看趋势。")
        }
        let rankNote = ReportMetricFormatter.metricRankItems(from: periodSummaries).first { $0.kind == metric.kind }?.note
        if let rankNote {
            return String(localized: "\(localizedMetricTitle(for: metric.kind))\(cycleNoun)均状态分 \(score)，\(rankNote)")
        }
        return String(localized: "\(localizedMetricTitle(for: metric.kind))\(cycleNoun)均状态分 \(score)。")
    }

    // MARK: - 心率 Tab 详情

    private var heartRateDetailCard: some View {
        let current = periodSummaries.compactMap(\.averageHeartRate).filter { $0 > 0 }
        let average = current.isEmpty ? nil : current.reduce(0, +) / Double(current.count)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "E0603F"))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "E0603F").opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "心率表现"))
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(periodTitle)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)
            }

            reportValue(average.map { String(format: "%.0f", $0) } ?? "--", unit: String(localized: "bpm \(cycleNoun)均心率"), tint: Color(hex: "E0603F"))

            metricStrip {
                ReportsCompactMetricPill(
                    title: String(localized: "样本天数"),
                    value: "\(current.count)/\(expectedDayCount)",
                    tint: Color(hex: "5B8CFF")
                )
                ReportsCompactMetricPill(
                    title: String(localized: "\(cycleNoun)内最高"),
                    value: current.max().map { "\(Int($0.rounded()))" } ?? "--",
                    tint: Color(hex: "E0603F")
                )
                ReportsCompactMetricPill(
                    title: String(localized: "\(cycleNoun)内最低"),
                    value: current.min().map { "\(Int($0.rounded()))" } ?? "--",
                    tint: Theme.Colors.mintGreen
                )
            }

            Text(current.isEmpty
                 ? String(localized: "心率样本还在同步中，样本足够后会形成更完整的\(cycleNoun)内解读。")
                 : String(localized: "日均心率由 Apple 健康同步；请结合个人基线、活动和 HRV 回看变化。"))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 压力 Tab 详情

    private var stressDetailCard: some View {
        let metric = ReportDetailWeekMetric(kind: .stress, points: periodSummaries)
        let highDays = periodSummaries.filter { ($0.stress ?? 0) >= 65 }.count
        let validSummaries = periodSummaries.filter { ReportMetricFormatter.hasMetric(.stress, in: $0) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(metric.tint)
                    .frame(width: 36, height: 36)
                    .background(metric.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "压力表现"))
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(periodTitle)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)
            }

            reportValue(metric.score.map(String.init) ?? "--", unit: String(localized: "/100 恢复状态分"), status: metric.gradeText, tint: metric.gradeTint)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Theme.Colors.secondaryBackground)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [metric.tint.opacity(0.55), metric.tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(Double(metric.score ?? 0) / 100.0))
                }
            }
            .frame(height: 10)

            metricStrip {
                ReportsCompactMetricPill(
                    title: String(localized: "压力均值"),
                    value: ReportMetricFormatter.averageRawValueText(for: .stress, in: validSummaries),
                    tint: ReportMetricKind.stress.tint
                )
                ReportsCompactMetricPill(
                    title: String(localized: "高峰天数"),
                    value: metric.observedDays == 0 ? "--" : "\(highDays)",
                    tint: highDays > 0 ? Color(hex: "E0603F") : Theme.Colors.mintGreen
                )
                ReportsCompactMetricPill(
                    title: String(localized: "覆盖天数"),
                    value: "\(metric.observedDays)/\(expectedDayCount)",
                    tint: Color(hex: "5B8CFF")
                )
            }

            Text(metric.observedDays == 0
                 ? metricNarrative(metric)
                 : highDays > 0
                     ? String(localized: "这个\(cycleNoun)有 \(highDays) 天压力偏高，建议把高负荷任务分段，并在白天插入短呼吸或轻步行作为缓冲。")
                     : String(localized: "这个\(cycleNoun)没有明显压力高峰，负荷控制比较友好，保持当前节奏即可。"))
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 指标趋势图

    private func metricTrendCard(kind: ReportMetricKind) -> some View {
        let plotPoints = WeeklyReportTrendData.points(for: kind, in: periodSummaries)
        let average = plotPoints.isEmpty ? nil : plotPoints.map(\.value).reduce(0, +) / Double(plotPoints.count)
        let selectedPoint = nearestMetricPoint(to: inspectedMetricDate, in: plotPoints)
        let activePoint = inspectedMetricDate == nil ? plotPoints.last : selectedPoint
        let bestPoint = plotPoints.max { $0.value < $1.value }
        let lowestPoint = plotPoints.min { $0.value < $1.value }
        let segments = continuousDaySegments(for: plotPoints.map(\.date))

        return ReportsContentCard(spacing: 14, isContinuous: true) {
            ReportsSectionHeader(
                String(localized: "\(localizedMetricTitle(for: kind))\(cycleNoun)趋势"),
                subtitle: period == .week
                    ? String(localized: "逐日查看原始数据，拖动图表可读取具体数值。")
                    : String(localized: "查看整月原始数据，虚线为月均值。")
            )

            if plotPoints.isEmpty {
                reportTrendEmptyState(String(localized: "这个\(cycleNoun)暂无该指标的可用样本"))
            } else {
                metricStrip {
                    ReportsCompactMetricPill(
                        title: String(localized: "周期均值"),
                        value: average.map { rawTrendValue($0, kind: kind) } ?? "--",
                        tint: kind.tint
                    )
                    ReportsCompactMetricPill(
                        title: String(localized: "最高"),
                        value: bestPoint.map { $0.rawValueText } ?? "--",
                        tint: kind.tint
                    )
                    ReportsCompactMetricPill(
                        title: String(localized: "覆盖"),
                        value: "\(plotPoints.count)/\(expectedDayCount)",
                        tint: Color(hex: "5B8CFF")
                    )
                }

                rawTrendLegend(kind: kind)

                Chart {
                    if WeeklyReportTrendData.usesBars(for: kind) {
                        ForEach(plotPoints) { point in
                            BarMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("原始值", point.value),
                                width: .ratio(0.58)
                            )
                            .reportsScoreBar(tint: kind.tint)
                            .opacity(selectedPoint == nil || selectedPoint?.id == point.id ? 1 : 0.45)
                            .accessibilityLabel(point.date.reportsMonthDayString())
                            .accessibilityValue(point.rawValueText)

                            // 真实记录的零值可见，仍不为缺失日期创建标记。
                            if point.value == 0 {
                                PointMark(x: .value("日期", point.date, unit: .day), y: .value("原始值", 0))
                                    .foregroundStyle(kind.tint)
                                    .symbolSize(24)
                                    .accessibilityHidden(true)
                            }
                        }
                    } else {
                        ForEach(plotPoints) { point in
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("原始值", point.value),
                                series: .value("连续区间", segments[point.date.reportsDayKey()] ?? 0)
                            )
                            .foregroundStyle(kind.tint)
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("原始值", point.value)
                            )
                            .foregroundStyle(kind.tint)
                            .symbol(.circle)
                            .symbolSize(selectedPoint?.id == point.id ? 76 : (period == .week ? 42 : 20))
                            .accessibilityLabel(point.date.reportsMonthDayString())
                            .accessibilityValue(point.rawValueText)
                        }
                    }

                    if let average {
                        RuleMark(y: .value("均值", average))
                            .reportsAverageRule()
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("当前选择", selectedPoint.date))
                            .reportsSelectionRule(tint: kind.tint)
                    }
                }
                .frame(height: 220)
                .chartYScale(domain: WeeklyReportTrendData.domain(for: kind, values: plotPoints.map(\.value)))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number, format: .number.precision(.fractionLength(0)))
                                    .font(.appSystem(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXScale(domain: chartDateDomain)
                .chartXSelection(value: $inspectedMetricDate)
                .chartXAxis { trendXAxis }
                .onChange(of: selectedPoint?.id) { _, newValue in
                    if newValue != nil {
                        hapticSelectionTick += 1
                    }
                }
                .accessibilityLabel(String(localized: "\(localizedMetricTitle(for: kind))\(cycleNoun)趋势图"))

                if let activePoint {
                    reportChartReadout(
                        date: activePoint.date, isSelected: inspectedMetricDate != nil,
                        value: activePoint.rawValueText,
                        comparison: String(localized: "周期均值") + " · " + (average.map { rawTrendValue($0, kind: kind) } ?? "--"),
                        tint: kind.tint
                    )
                } else if let date = inspectedMetricDate {
                    reportMissingDay(date)
                }

                trendExtremes(high: bestPoint?.rawValueText, highDate: bestPoint?.date,
                              low: lowestPoint?.rawValueText, lowDate: lowestPoint?.date)
                chartCoverageNote(observedDays: plotPoints.count)

                Text(kind == .stress
                     ? String(localized: "压力指数越高表示负荷越高；此图不是恢复状态分。")
                     : String(localized: "图表展示原始数据，不将时长或活动量换算为评分。"))
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 心率页使用真实日均心率，而不是 HRV 的替代曲线。
    private var heartRateTrendCard: some View {
        let heartPoints = periodSummaries.compactMap { summary -> ReportHeartRatePlotPoint? in
            guard let value = summary.averageHeartRate, value > 0 else { return nil }
            return ReportHeartRatePlotPoint(date: summary.date, value: value)
        }
        .sorted { $0.date < $1.date }
        let values = heartPoints.map(\.value)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let selectedPoint = nearestHeartRatePoint(to: inspectedMetricDate, in: heartPoints)
        let activePoint = inspectedMetricDate == nil ? heartPoints.last : selectedPoint
        let highestPoint = heartPoints.max { $0.value < $1.value }
        let lowestPoint = heartPoints.min { $0.value < $1.value }
        let segments = continuousDaySegments(for: heartPoints.map(\.date))

        return ReportsContentCard(spacing: 14, isContinuous: true) {
            ReportsSectionHeader(
                String(localized: "心率\(cycleNoun)趋势"),
                subtitle: period == .week
                    ? String(localized: "逐日查看日均心率，拖动图表可读取具体数值。")
                    : String(localized: "连续查看整月日均心率变化，虚线为月均值。")
            )

            if heartPoints.isEmpty {
                reportTrendEmptyState(String(localized: "这个\(cycleNoun)暂无心率可用样本"))
            } else {
                metricStrip {
                    ReportsCompactMetricPill(
                        title: String(localized: "\(cycleNoun)均心率"),
                        value: average.map { "\(Int($0.rounded())) bpm" } ?? "--",
                        tint: Color(hex: "E0603F")
                    )
                    ReportsCompactMetricPill(
                        title: String(localized: "最低"),
                        value: values.min().map { "\(Int($0.rounded())) bpm" } ?? "--",
                        tint: Theme.Colors.mintGreen
                    )
                    ReportsCompactMetricPill(
                        title: String(localized: "最高"),
                        value: values.max().map { "\(Int($0.rounded())) bpm" } ?? "--",
                        tint: Color(hex: "E0603F")
                    )
                }

                HStack(spacing: 14) {
                    BBChartLegendItem(title: String(localized: "日均心率"), tint: Color(hex: "E0603F"))
                    BBChartLegendItem(title: String(localized: "\(cycleNoun)均值"), tint: ReportsChartStyle.averageLine)
                }
                .accessibilityElement(children: .combine)

                Chart {
                    ForEach(heartPoints) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("心率", point.value),
                            series: .value("连续区间", segments[point.date.reportsDayKey()] ?? 0)
                        )
                        .foregroundStyle(Color(hex: "E0603F"))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("心率", point.value)
                        )
                        .foregroundStyle(Color(hex: "E0603F"))
                        .symbol(.circle)
                        .symbolSize(selectedPoint?.id == point.id ? 76 : (period == .week ? 42 : 20))
                        .accessibilityLabel(point.date.reportsMonthDayString())
                        .accessibilityValue(String(localized: "日均心率 \(Int(point.value.rounded())) bpm"))
                    }

                    if let average {
                        RuleMark(y: .value("均值", average))
                            .reportsAverageRule()
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("当前选择", selectedPoint.date))
                            .reportsSelectionRule(tint: Color(hex: "E0603F"))
                    }
                }
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartXScale(domain: chartDateDomain)
                .chartYScale(domain: heartRateChartDomain(for: values))
                .chartXSelection(value: $inspectedMetricDate)
                .chartXAxis { trendXAxis }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel {
                            if let heartRate = value.as(Double.self) {
                                Text("\(Int(heartRate.rounded()))")
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(ReportsChartStyle.axisLabel)
                            }
                        }
                    }
                }
                .onChange(of: selectedPoint?.id) { _, newValue in
                    if newValue != nil {
                        hapticSelectionTick += 1
                    }
                }
                .accessibilityLabel(String(localized: "心率\(cycleNoun)趋势图"))

                if let activePoint {
                    reportChartReadout(
                        date: activePoint.date, isSelected: inspectedMetricDate != nil,
                        value: String(localized: "\(Int(activePoint.value.rounded())) bpm"),
                        comparison: heartRateComparisonText(value: activePoint.value, average: average),
                        tint: Color(hex: "E0603F")
                    )
                } else if let date = inspectedMetricDate {
                    reportMissingDay(date)
                }

                trendExtremes(high: highestPoint.map { String(format: "%.0f bpm", $0.value) }, highDate: highestPoint?.date,
                              low: lowestPoint.map { String(format: "%.0f bpm", $0.value) }, lowDate: lowestPoint?.date)
                chartCoverageNote(observedDays: heartPoints.count)

                Text(String(localized: "心率图展示日均值，仅用于观察个人节律，不用于医学诊断。"))
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 趋势图 X 轴刻度间隔：周图逐日、月图每周一个刻度，避免标签拥挤。
    private func rawTrendValue(_ value: Double, kind: ReportMetricKind) -> String {
        WeeklyReportTrendData.valueText(value, kind: kind)
    }

    private func reportChartReadout(date: Date, isSelected: Bool, value: String, comparison: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isSelected ? String(localized: "当前选中") : String(localized: "最新记录"))
                .font(.appSystem(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(date.formatted(.dateTime.month().day().weekday()))
                .font(.appSystem(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.appSystem(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(comparison)
                .font(.appSystem(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func reportMissingDay(_ date: Date) -> some View {
        reportChartReadout(date: date, isSelected: true, value: String(localized: "暂无数据"),
                           comparison: String(localized: "这一天没有可用记录，不以相邻日期或 0 代替。"), tint: Theme.Colors.textSecondary)
    }

    private func trendExtremes(high: String?, highDate: Date?, low: String?, lowDate: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let high, let highDate {
                Text(String(localized: "最高记录：\(high) · \(highDate.formatted(.dateTime.month().day()))"))
            }
            if let low, let lowDate {
                Text(String(localized: "最低记录：\(low) · \(lowDate.formatted(.dateTime.month().day()))"))
            }
        }
        .font(.appSystem(size: 12, weight: .medium))
        .foregroundStyle(Theme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func rawTrendLegend(kind: ReportMetricKind) -> some View {
        let unit: String
        switch kind {
        case .sleep: unit = String(localized: "小时")
        case .activity: unit = String(localized: "步数")
        case .stress: unit = String(localized: "压力指数")
        case .hrv: unit = "ms"
        }
        return HStack(spacing: 18) {
            trendLegendItem(unit, tint: kind.tint, dashed: false)
            trendLegendItem(String(localized: "周期均值"), tint: ReportsChartStyle.averageLine, dashed: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func trendLegendItem(_ title: String, tint: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(tint)
                .frame(width: dashed ? 6 : 18, height: 2)
            if dashed {
                Rectangle().fill(tint).frame(width: 6, height: 2)
            }
            Text(title)
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// 无数据时保留阅读提示，不绘制伪造的走势或装饰性渐变卡片。
    private func reportTrendEmptyState(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(.appSystem(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            chartCoverageNote(observedDays: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    @AxisContentBuilder
    private var scoreTrendYAxis: some AxisContent {
        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(ReportsChartStyle.grid)
            AxisValueLabel()
                .font(.appSystem(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var trendAxisDayStride: Int {
        period == .week ? 1 : 7
    }

    private var chartDateDomain: ClosedRange<Date> {
        let end = max(periodInterval.start, periodInterval.end.addingTimeInterval(-1))
        return periodInterval.start...end
    }

    private func heartRateChartDomain(for values: [Double]) -> ClosedRange<Double> {
        let minimum = values.min().map { floor(($0 - 10) / 10) * 10 } ?? 40
        let maximum = values.max().map { ceil(($0 + 10) / 10) * 10 } ?? 120
        return max(0, minimum)...max(minimum + 20, maximum)
    }

    private func chartCoverageNote(observedDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "已记录 \(observedDays)/\(expectedDayCount) 天；空白日期不按 0 计算。"))
            if observedDays > 0 && observedDays < 3 {
                Text(String(localized: "当前记录较少，仅展示已有读数，不据此判断持续趋势。"))
            }
            if observedDays > 0 {
                Text(String(localized: "周期均值仅按有记录的日期计算，不是正常范围或个人目标。"))
            }
        }
            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @AxisContentBuilder
    private var trendXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: trendAxisDayStride)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(chartAxisLabel(for: date))
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
        }
    }

    private func chartAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(period == .week ? "EEE" : "Md")
        return formatter.string(from: date)
    }

    /// 缺样本日期断开曲线，不将跨日空白误绘成持续变化。
    private func continuousDaySegments(for dates: [Date]) -> [Int64: Int] {
        let calendar = Calendar.current
        var segments: [Int64: Int] = [:]
        var previousDay: Date?
        var segment = 0
        for date in dates.sorted() {
            let day = calendar.startOfDay(for: date)
            if let previousDay,
               (calendar.dateComponents([.day], from: previousDay, to: day).day ?? 0) > 1 {
                segment += 1
            }
            segments[date.reportsDayKey(calendar: calendar)] = segment
            previousDay = day
        }
        return segments
    }

    private func localizedMetricTitle(for kind: ReportMetricKind) -> String {
        switch kind {
        case .sleep: return String(localized: "睡眠")
        case .activity: return String(localized: "活动")
        case .stress: return String(localized: "压力")
        case .hrv: return String(localized: "HRV")
        }
    }

    private func nearestSummary(to date: Date?, in summaries: [ReportDaySummary]) -> ReportDaySummary? {
        guard let index = WeeklyReportTrendData.selectedIndex(for: date, dates: summaries.map(\.date)) else { return nil }
        return summaries[index]
    }

    private func nearestMetricPoint(to date: Date?, in plotPoints: [ReportMetricPlotPoint]) -> ReportMetricPlotPoint? {
        guard let index = WeeklyReportTrendData.selectedIndex(for: date, dates: plotPoints.map(\.date)) else { return nil }
        return plotPoints[index]
    }

    private func nearestHeartRatePoint(to date: Date?, in plotPoints: [ReportHeartRatePlotPoint]) -> ReportHeartRatePlotPoint? {
        guard let index = WeeklyReportTrendData.selectedIndex(for: date, dates: plotPoints.map(\.date)) else { return nil }
        return plotPoints[index]
    }

    private func comparisonText(value: Double, average: Double?) -> String {
        guard let average else { return String(localized: "周期均值等待更多样本") }
        let delta = value - average
        if abs(delta) < 0.5 {
            return String(localized: "与\(cycleNoun)均值持平")
        }
        return delta > 0
            ? String(localized: "较\(cycleNoun)均值高 \(Int(delta.rounded())) 分")
            : String(localized: "较\(cycleNoun)均值低 \(Int(abs(delta).rounded())) 分")
    }

    private func heartRateComparisonText(value: Double, average: Double?) -> String {
        guard let average else { return String(localized: "周期均值等待更多样本") }
        let delta = value - average
        if abs(delta) < 0.5 {
            return String(localized: "与\(cycleNoun)均心率持平")
        }
        return delta > 0
            ? String(localized: "较\(cycleNoun)均心率高 \(Int(abs(delta).rounded())) bpm")
            : String(localized: "较\(cycleNoun)均心率低 \(Int(abs(delta).rounded())) bpm")
    }

    private func scoreRangeText(lowest: ReportDaySummary?, highest: ReportDaySummary?) -> String {
        guard let lowest, let highest else { return "--" }
        return String(localized: "\(highest.scoreValue - lowest.scoreValue) 分")
    }

    private func resetChartSelections() {
        inspectedOverallDate = nil
        inspectedMetricDate = nil
    }
}

// MARK: - 周指标聚合辅助

/// 综合评分卡里的一行指标（标题、图标、状态分、实测摘要与对应 Tab）。
struct ReportDetailMetricRow: Identifiable {
    let title: String
    let systemImage: String
    let tint: Color
    let score: Int?
    let summary: String
    let segment: ReportDetailSegment

    var id: String { title }

    /// 等级短文本（优秀/良好/一般/待提升）
    var gradeText: String {
        guard let score else { return String(localized: "待补齐") }
        switch score {
        case 85...: return String(localized: "优秀")
        case 70..<85: return String(localized: "良好")
        case 55..<70: return String(localized: "一般")
        default: return String(localized: "待提升")
        }
    }

    var gradeTint: Color {
        guard let score else { return Color(hex: "8A9099") }
        switch score {
        case 85...: return Theme.Colors.mintGreen
        case 70..<85: return Color(hex: "5B8CFF")
        case 55..<70: return Color(hex: "F3A53B")
        default: return Color(hex: "E0603F")
        }
    }
}

private struct ReportHeartRatePlotPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Int64 { date.reportsDayKey() }
}

/// 聚合一周内某个指标的状态分、等级与实测摘要，供报告详情的指标卡片复用。
struct ReportDetailWeekMetric {
    let kind: ReportMetricKind
    let points: [ReportDaySummary]

    private var values: [Double] {
        points.compactMap { ReportMetricFormatter.normalizedValue(for: kind, in: $0) }
    }

    /// 周均状态分（0-100），无样本时为 nil
    var score: Int? {
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    /// 有该指标样本的天数
    var observedDays: Int {
        values.count
    }

    var tint: Color {
        kind.tint
    }

    /// 等级短文本（优秀/良好/一般/待提升）
    var gradeText: String {
        guard let score else { return String(localized: "待补齐") }
        switch score {
        case 85...: return String(localized: "优秀")
        case 70..<85: return String(localized: "良好")
        case 55..<70: return String(localized: "一般")
        default: return String(localized: "待提升")
        }
    }

    var gradeTint: Color {
        guard let score else { return Color(hex: "8A9099") }
        switch score {
        case 85...: return Theme.Colors.mintGreen
        case 70..<85: return Color(hex: "5B8CFF")
        case 55..<70: return Color(hex: "F3A53B")
        default: return Color(hex: "E0603F")
        }
    }

    /// 周内实测值摘要（原始值范围或均值）
    var rawValueSummary: String {
        switch kind {
        case .sleep:
            let values = points.compactMap(\.sleepHours).filter { $0 > 0 }
            guard let average = values.average else { return String(localized: "暂无睡眠样本") }
            let formattedAverage = average.formatted(.number.precision(.fractionLength(1)))
            return String(localized: "日均睡眠 \(formattedAverage) 小时")
        case .activity:
            let values = points.compactMap(\.steps).filter { $0 > 0 }
            guard let average = values.average else { return String(localized: "暂无活动样本") }
            return String(localized: "日均 \(Int(average.rounded())) 步")
        case .stress:
            let values = points.compactMap(\.stress).filter { $0 > 0 }
            guard let average = values.average else { return String(localized: "暂无压力样本") }
            return String(localized: "压力指数均值 \(Int(average.rounded()))，越低越好")
        case .hrv:
            let values = points.compactMap(\.hrv).filter { $0 > 0 }
            guard let average = values.average else { return String(localized: "暂无 HRV 样本") }
            return String(localized: "HRV 均值 \(Int(average.rounded())) ms")
        }
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

// MARK: - 日期格式化辅助

extension Date {
    /// 供图表摘要使用的本地化月日格式。
    func reportsMonthDayString(locale: Locale = Locale.autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: self)
    }
}

/// 周报预览提供器 作为报告模块里的预览辅助类型。
/// 负责报告展示与分享。
struct WeeklyReportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WeeklyReportView()
        }
    }
}
