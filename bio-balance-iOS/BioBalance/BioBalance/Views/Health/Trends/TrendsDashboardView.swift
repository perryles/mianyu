/// TrendsDashboardView 作为趋势模块的支撑类型，负责定义趋势时间范围。
/// 负责描述日/周/月三种范围的枚举、标题与展示逻辑。

import SwiftUI
import Charts

/// Trends枚举 作为趋势模块里的状态与分类定义。
/// 负责描述趋势分析展示过程中会用到的状态、分类或分支。
/// nonisolated：纯值类型，供 nonisolated 压力矩阵计算在后台读取（PEN-3 P2-3）。
nonisolated enum TrendsRange: Int, CaseIterable {
    case day = 1
    case week = 7
    case month = 30

    static var allCases: [TrendsRange] {
        [.day, .week, .month]
    }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }

    var windowDays: Int { rawValue }

    var isIntraday: Bool {
        self == .day
    }

    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .day:
            return calendar.startOfDay(for: now)
        case .week, .month:
            return calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
        }
    }

    var dateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .day:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .hour, value: 24, to: start) ?? now
            return start...end
        case .week, .month:
            let start = startDate
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return start...end
        }
    }
}

/// Trends视图 由上级页面或路由调用，作为趋势模块里的界面或内容组件。
/// 负责趋势分析展示。
struct TrendsDashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedRange: TrendsRange = .day
    @State private var trendsVM = TrendsViewModel()
    @Bindable var periodViewModel: PeriodViewModel
    
    var body: some View {
        ZStack {
            trendPageBackground

            AdaptivePageScrollView(topPadding: Theme.Spacing.compact, bottomPadding: 88, showsIndicators: false) {
                VStack(spacing: trendsSectionSpacing) {
                    // AnyView 边界：与 HealthHubView 网格同理，隔断每个板块的泛型类型，
                    // 避免 iOS 27 运行时实例化整页深层嵌套类型时递归爆栈。
                    AnyView(
                        pageHeader
                    )

                    AnyView(
                        rangePicker
                    )

                    AnyView(
                        trendsOverviewPanel
                    )

                    AnyView(
                        PressureDistributionCard(
                            buckets: pressureBuckets,
                            total: pressureDistributionSamples.count,
                            range: selectedRange,
                            isLoading: trendsVM.isLoading
                        )
                        .id(selectedRange)
                    )

                    AnyView(
                        PressureTimeSlotCard(
                            rows: trendsVM.pressureTimeSlotRows,
                            range: selectedRange
                        )
                        .id(selectedRange)
                    )

                    AnyView(
                        categorySection
                            .id(selectedRange)
                    )
                }
            }
        }
        .navigationDestination(item: $trendsVM.selectedCategoryDetail) { detail in
            TrendCategoryDetailView(
                detail: detail,
                range: selectedRange,
                periodViewModel: periodViewModel,
                onPeriodDataChanged: {
                    Task {
                        await trendsVM.loadCategoryCards(range: selectedRange)
                        await trendsVM.loadCategoryDetail(.reproductive, range: selectedRange)
                    }
                }
            )
        }
        .onAppear {
            trendsVM.load(range: selectedRange)
            periodViewModel.reload(days: 90)
        }
        .onChange(of: selectedRange) { _, newValue in
            trendsVM.load(range: newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            trendsVM.load(range: selectedRange)
            periodViewModel.reload(days: 90)
        }
    }


    private var trendsSectionSpacing: CGFloat {
        horizontalSizeClass == .regular ? Theme.Spacing.medium : Theme.Spacing.small
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.compact) {
                HStack(alignment: .top, spacing: Theme.Spacing.compact) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.mintGreen, Color(hex: "5B8CFF").opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: 20)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                        Text("健康指标趋势")
                            .font(Theme.Typography.sectionTitle)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("点击卡片查看对应指标的图表、摘要和数据状态。")
                            .font(Theme.Typography.supporting)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Text("\(displayedCategoryCards.count) 项")
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.mintGreen)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, Theme.Spacing.compact)
                    .background(Theme.Colors.surface, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.Colors.mintGreen.opacity(0.28), lineWidth: 1)
                    )
            }

            unifiedCategoryContent
        }
    }

    private var unifiedCategoryContent: some View {
        LazyVGrid(columns: categoryGridColumns, spacing: Theme.Spacing.small) {
            ForEach(displayedCategoryCards) { card in
                Button {
                    Task { await trendsVM.loadCategoryDetail(card.category, range: selectedRange) }
                } label: {
                    // AnyView 边界：隔断每张信号卡的泛型类型（同 HealthHubView 网格）。
                    if let featured = trendsVM.featuredCategoryCards.first(where: { $0.category == card.category }),
                       card.category == .sleepRecovery {
                        AnyView(SleepTrendSignalCard(featured: featured))
                    } else {
                        AnyView(TrendCategorySignalCard(
                            card: card,
                            metricPoints: trendsVM.featuredCategoryCards
                                .first(where: { $0.category == card.category })
                                .map { previewPoints(for: $0) } ?? []
                        ))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var categoryGridColumns: [GridItem] {
        let columnCount: Int
        if horizontalSizeClass == .regular {
            columnCount = 3
        } else {
            columnCount = 2
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: Theme.Spacing.small, alignment: .top),
            count: columnCount
        )
    }

    private var displayedCategoryCards: [TrendCategoryCardModel] {
        let featuredCategories = Set(trendsVM.featuredCategoryCards.map(\.category))
        let featuredCards = trendsVM.categoryCards.filter { featuredCategories.contains($0.category) }
        let remainingCards = trendsVM.categoryCards.filter {
            !featuredCategories.contains($0.category)
        }
        return featuredCards + remainingCards
    }

    private func previewPoints(for featured: FeaturedTrendCategoryModel) -> [TimeSeriesPointDouble] {
        ([featured.primaryMetric] + featured.supportingMetrics + featured.sleepRecoveryMetrics)
            .first(where: { !$0.points.isEmpty })?
            .points ?? []
    }

    private var trendsOverviewPanel: some View {
        ModernReportMetricsPanel(
            title: String(localized: "活动总览"),
            metrics: displayedCategoryCards.prefix(4).map { card in
                ModernReportMetric(
                    title: card.category.title,
                    value: card.primaryValueText,
                    tint: card.category.accentColor,
                    symbol: card.category.icon
                )
            }
        )
    }

    /// 仪表盘自身不再铺满灰底，交由 TrendsRootView 的柔和渐变背景统一打底。
    private var trendPageBackground: some View {
        Color.clear
            .ignoresSafeArea()
    }

    /// Tab 根页面自绘标题头，与其他 Tab 首页的大标题样式一致。
    private var pageHeader: some View {
        BBPageHeader(
            title: String(localized: "趋势"),
            subtitle: String(localized: "把今天放进更长的时间轴里。")
        )
    }

    private var pressureSamples: [PressureSamplePoint] {
        trendsVM.pressureTimeSlotSamples
    }

    private var pressureDistributionSamples: [PressureSamplePoint] {
        let nonInferredSamples = pressureSamples.filter { !$0.isInferred }
        return nonInferredSamples.isEmpty ? pressureSamples : nonInferredSamples
    }

    private var rangePicker: some View {
        ModernReportSegmentedPicker(
            selection: $selectedRange,
            options: TrendsRange.allCases.map {
                ModernReportPickerOption(value: $0, title: $0.title)
            }
        )
    }

    private var pressureBuckets: [PressureBucket] {
        let samples = pressureDistributionSamples
        let total = Swift.max(1, samples.count)
        return PressureBucket.Kind.allCases.map { kind in
            let count = samples.filter { $0.kind == kind }.count
            return PressureBucket(kind: kind, count: count, percent: Double(count) / Double(total))
        }
    }

}

// 辅助结构体
/// 图表数据结构体 作为趋势模块里的辅助类型。
/// 负责趋势分析展示。

struct PressureBucket: Identifiable {
    /// Kind 枚举，作为内部辅助类型，用于细分外层趋势分析展示中的状态或分支。
    enum Kind: CaseIterable {
        case excellent
        case normal
        case attention
        case overloaded

        init(value: Double) {
            switch value {
            case ..<35:
                self = .excellent
            case 35..<55:
                self = .normal
            case 55..<75:
                self = .attention
            default:
                self = .overloaded
            }
        }

        var title: String {
            switch self {
            case .excellent: return "状态优秀"
            case .normal: return "状态正常"
            case .attention: return "注意压力"
            case .overloaded: return "压力过载"
            }
        }

        var color: Color {
            switch self {
            case .excellent: return Theme.Colors.mintGreen
            case .normal: return Color(hex: "9AA8D8")
            case .attention: return Color(hex: "FFA37A")
            case .overloaded: return Color(hex: "F05275")
            }
        }

        func contains(_ value: Double) -> Bool {
            switch self {
            case .excellent: return value < 35
            case .normal: return value >= 35 && value < 55
            case .attention: return value >= 55 && value < 75
            case .overloaded: return value >= 75
            }
        }
    }

    var id: String { kind.title }
    let kind: Kind
    let count: Int
    let percent: Double
}

private struct PressureDistributionCard: View {
    private let distributionTrackWidth: CGFloat = 136
    private let distributionMinimumVisibleWidth: CGFloat = 8
    private let distributionContrastExponent: CGFloat = 1.18
    private let loadingShimmerWidth: CGFloat = 44
    let buckets: [PressureBucket]
    let total: Int
    let range: TrendsRange
    let isLoading: Bool
    @State private var revealBars = false
    @State private var revealStats = false
    @State private var shimmerOffset: CGFloat = -72

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            pressureDistributionHeader

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    pressureDistributionStats
                    pressureDistributionBars
                }

                VStack(alignment: .leading, spacing: 16) {
                    pressureDistributionStats
                    pressureDistributionBars
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: Theme.Colors.mintGreen, cornerRadius: 28)
        .onAppear {
            revealStats = true
            revealBars = true
        }
        .onChange(of: bucketSignature) { _, _ in
            revealStats = false
            revealBars = false
            withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                revealStats = true
                revealBars = true
            }
        }
        .task(id: isLoading) {
            await runLoadingAnimationLoop()
        }
    }

    private var pressureDistributionHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                pressureDistributionTitle

                Spacer(minLength: 8)

                Image("TrendsPressureDistributionMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 144, height: 88)
                    .padding(.top, -4)
            }

            pressureDistributionTitle
        }
    }

    private var pressureDistributionTitle: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("压力分布")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Text("按压力等级统计有效样本，快速判断这一段时间偏轻松还是偏紧绷。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rangeCaption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(total)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "1E2732"), Color(hex: "3E4C5E")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("格")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private var pressureDistributionStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bucket.kind.color)
                            .frame(width: 8, height: 8)
                        Text(bucket.kind.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bucket.count)次")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(localizedPercentRatio(bucket.percent))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(bucket.kind.color)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bucket.kind.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(revealStats ? 1 : 0)
                .offset(y: revealStats ? 0 : 10)
                .animation(.spring(response: 0.55, dampingFraction: 0.84).delay(Double(index) * 0.06), value: revealStats)
            }
        }
        .frame(minWidth: 178)
    }

    private var pressureDistributionBars: some View {
        VStack(spacing: 14) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(bucket.kind.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 48, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Capsule()
                            .fill(Theme.Colors.secondaryBackground.opacity(0.9))
                            .frame(height: 18)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(bucket.kind.color)
                                    .frame(width: distributionBarWidth(for: bucket), height: 18)
                                    .overlay {
                                        if isLoading {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0),
                                                            Color.white.opacity(0.24),
                                                            Color.white.opacity(0.52),
                                                            Color.white.opacity(0.24),
                                                            Color.white.opacity(0)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: loadingShimmerWidth)
                                                .offset(x: shimmerOffset)
                                                .blendMode(.screen)
                                        }
                                    }
                                    .mask(alignment: .leading) {
                                        Capsule()
                                            .frame(width: distributionBarWidth(for: bucket), height: 18)
                                    }
                                    .animation(.spring(response: 0.65, dampingFraction: 0.82).delay(Double(index) * 0.08), value: revealBars)
                                    .animation(
                                        isLoading
                                            ? .linear(duration: 1.2).delay(Double(index) * 0.06)
                                            : .easeOut(duration: 0.2),
                                        value: shimmerOffset
                                    )
                            }
                    }
                }
            }
        }
        .frame(width: distributionTrackWidth + 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private var rangeCaption: String {
        switch range {
        case .day:
            return "今日压力节律"
        case .week:
            return "近 7 天压力节律"
        case .month:
            return "近 30 天压力节律"
        }
    }

    private func distributionBarWidth(for bucket: PressureBucket) -> CGFloat {
        guard revealBars else { return 0 }
        guard bucket.count > 0 else { return 0 }
        let maxPercent = buckets.map(\.percent).max() ?? 0
        guard maxPercent > 0 else { return 0 }
        let normalized = bucket.percent / maxPercent
        let emphasized = pow(normalized, distributionContrastExponent)
        return max(distributionMinimumVisibleWidth, emphasized * distributionTrackWidth)
    }

    private var bucketSignature: String {
        let counts = buckets.map(\.count).map(String.init).joined(separator: "-")
        return "\(range.rawValue)-\(total)-\(counts)"
    }

    @MainActor
    private func resetLoadingVisuals() {
        shimmerOffset = -72
    }

    private func runLoadingAnimationLoop() async {
        guard isLoading else {
            resetLoadingVisuals()
            return
        }

        resetLoadingVisuals()

        while !Task.isCancelled {
            await MainActor.run {
                shimmerOffset = -72
                withAnimation(.linear(duration: 1.2)) {
                    shimmerOffset = distributionTrackWidth + 24
                }
            }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }

        resetLoadingVisuals()
    }
}

private struct PressureTimeSlotCard: View {
    private struct DisplayRow: Identifiable {
        let id: String
        let cells: [PressureTimeSlotCell]
    }

    private let timelinePlotHeight: CGFloat = 120
    private let timelineMinBarHeight: CGFloat = 20
    private let timelineMaxBarHeight: CGFloat = 84

    let rows: [PressureTimeSlotRow]
    let range: TrendsRange
    @State private var revealHeatmap = false
    @State private var selectedCellID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: range == .day ? 14 : 16) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("压力时段")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(timeSlotCaption)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        legendItem(color: Theme.Colors.mintGreen, title: "优秀")
                        legendItem(color: Color(hex: "9AA8D8"), title: "正常")
                        legendItem(color: Color(hex: "FFA37A"), title: "注意")
                        legendItem(color: Color(hex: "F05275"), title: "过载")
                    }
                    .padding(.vertical, 1)
                }
                .scrollDisabled(true)

            }

            Group {
                if range == .day {
                    intradayTimeline
                } else if range == .week {
                    weeklyTimeline
                } else {
                    monthlyTimeline
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: Theme.Colors.mintGreen, cornerRadius: 28)
        .onAppear {
            revealHeatmap = true
            selectedCellID = defaultSelectedCellID
        }
        .onChange(of: displayRows.map { $0.id }) { _, _ in
            revealHeatmap = false
            selectedCellID = defaultSelectedCellID
            withAnimation(.easeOut(duration: 0.32)) {
                revealHeatmap = true
            }
        }
    }

    private var timeSlotCaption: String {
        switch range {
        case .day:
            return String(localized: "按 3 小时聚合今天的压力变化，越高代表该时段负荷越重。")
        case .week:
            return String(localized: "按天对比本周压力高低，帮助找出最容易紧绷的日期。")
        case .month:
            return String(localized: "压缩展示近 30 天压力走势，适合看连续升高或回落。")
        }
    }

    private var intradayTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    timelineYAxisOverlay(topInset: 0, plotHeight: timelinePlotHeight)

                    ZStack(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(dayCells) { cell in
                                timelineBar(for: cell, minHeight: timelineMinBarHeight, maxHeight: timelineMaxBarHeight)
                                    .frame(width: 18)
                                    .frame(maxWidth: .infinity, alignment: .bottom)
                                    .frame(height: timelinePlotHeight, alignment: .bottom)
                            }
                        }
                    }
                }

                timelineXAxis(hours: dayHourMarkers)
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .bbChartPlotSurface(tint: Theme.Colors.mintGreen, cornerRadius: 22)
    }

    private var weeklyTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    timelineYAxisOverlay(topInset: 0, plotHeight: timelinePlotHeight)

                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(weeklyRows) { row in
                            VStack(alignment: .center, spacing: 0) {
                                HStack(alignment: .bottom, spacing: 3) {
                                    ForEach(row.cells) { cell in
                                        timelineBar(for: cell, minHeight: timelineMinBarHeight, maxHeight: timelineMaxBarHeight)
                                            .frame(maxWidth: .infinity, alignment: .bottom)
                                    }
                                }
                                .frame(height: timelinePlotHeight, alignment: .bottom)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(weeklyRows) { row in
                        Text(weekLabel(for: row))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .bbChartPlotSurface(tint: Theme.Colors.mintGreen, cornerRadius: 22)
    }

    private var monthlyTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    timelineYAxisOverlay(topInset: 0, plotHeight: timelinePlotHeight)

                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(monthBars) { cell in
                            timelineBar(for: cell, minHeight: timelineMinBarHeight, maxHeight: timelineMaxBarHeight)
                                .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(height: timelinePlotHeight, alignment: .bottom)
                }

                timelineAxisLabels(labels: monthAxisLabels)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .bbChartPlotSurface(tint: Theme.Colors.mintGreen, cornerRadius: 22)
    }

    private var slotDuration: Int {
        rows.first?.cells.first?.slotDurationHours ?? (range.isIntraday ? 1 : 3)
    }

    private var displaySlotDuration: Int {
        range == .day ? 3 : slotDuration
    }

    private var displayRows: [DisplayRow] {
        if range == .day {
            return rows.map { row in
                DisplayRow(
                    id: row.id.description,
                    cells: mergeCells(row.cells, chunkSize: displaySlotDuration)
                )
            }
        }

        if range == .week {
            return rows.map { row in
                DisplayRow(
                    id: row.id.description,
                    cells: row.cells
                )
            }
        }

        return monthLinearRows
    }

    private var dayCells: [PressureTimeSlotCell] {
        displayRows.first?.cells ?? []
    }

    private var weeklyRows: [DisplayRow] {
        displayRows
    }

    private var monthBars: [PressureTimeSlotCell] {
        monthLinearRows.flatMap(\.cells)
    }

    private var allDisplayedCells: [PressureTimeSlotCell] {
        range == .month ? monthBars : displayRows.flatMap(\.cells)
    }

    private var dayHourMarkers: [Int] {
        Array(stride(from: 0, through: 24, by: 3))
    }

    private var monthAxisLabels: [String] {
        let cells = monthBars
        guard !cells.isEmpty else { return [] }
        let checkpoints = [0.0, 0.25, 0.5, 0.75, 0.999]
        return checkpoints.map { ratio in
            let index = min(cells.count - 1, Int(Double(cells.count - 1) * ratio))
            return pressureAxisLabel(for: cells[index].date)
        }
    }

    private var defaultSelectedCellID: String? {
        let cells = allDisplayedCells
        guard !cells.isEmpty else { return nil }

        if range == .day {
            let currentHour = Calendar.current.component(.hour, from: Date())
            if let current = cells.first(where: {
                let start = $0.slotStartHour
                let end = start + max(1, $0.slotDurationHours)
                return currentHour >= start && currentHour < end
            }) {
                return current.id
            }
        }

        return cells
            .sorted {
                ($0.value ?? -1) > ($1.value ?? -1)
            }
            .first?
            .id
    }

    private func timelineBar(for cell: PressureTimeSlotCell, minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        let tint = cell.kind?.color ?? Theme.Colors.lightGray.opacity(0.72)
        let height = barHeight(for: cell, minHeight: minHeight, maxHeight: maxHeight)
        let isSelected = range == .day ? false : (selectedCellID == cell.id)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedCellID = cell.id
            }
        } label: {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(cell.isInferred ? 0.58 : 0.8),
                            tint.opacity(cell.value == nil ? 0.34 : 1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: height)
                .overlay {
                    if isSelected {
                        Capsule()
                            .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    }
                }
                .shadow(color: tint.opacity(isSelected ? 0.24 : 0.14), radius: isSelected ? 10 : 5, x: 0, y: 3)
                .scaleEffect(
                    x: isSelected ? 1.07 : 1,
                    y: revealHeatmap ? (isSelected ? 1.04 : 1) : 0.24,
                    anchor: .bottom
                )
                .opacity(revealHeatmap ? 1 : 0.18)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.82).delay(Double(cell.slotStartHour / max(1, displaySlotDuration)) * 0.05),
                    value: revealHeatmap
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func barHeight(for cell: PressureTimeSlotCell, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        guard let value = cell.value else { return minHeight }
        let normalized = min(max(value / 100, 0), 1)
        return minHeight + (normalized * (maxHeight - minHeight))
    }

    private func timelineYAxisOverlay(topInset: CGFloat, plotHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInset)

            VStack(alignment: .leading, spacing: 0) {
                Text("高")
                Spacer()
                Text("中")
                Spacer()
                Text("低")
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary.opacity(0.92))
            .frame(width: 18, height: plotHeight, alignment: .leading)
        }
        .frame(width: 18, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func timelineXAxis(hours: [Int]) -> some View {
        let leadingHours = Array(hours.dropLast())

        return ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                ForEach(leadingHours, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let endHour = hours.last {
                Text("\(endHour)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func timelineAxisLabels(labels: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }

    private var monthLinearRows: [DisplayRow] {
        let flattened = rows.flatMap(\.cells)
        guard !flattened.isEmpty else { return [] }

        let totalBuckets = 56
        let mergedCells = (0..<totalBuckets).compactMap { bucketIndex -> PressureTimeSlotCell? in
            let startIndex = Int(Double(flattened.count) * Double(bucketIndex) / Double(totalBuckets))
            let endIndex = Int(Double(flattened.count) * Double(bucketIndex + 1) / Double(totalBuckets))
            let safeEnd = max(startIndex + 1, endIndex)
            guard startIndex < flattened.count else { return nil }
            return mergeSequentialCells(Array(flattened[startIndex..<min(safeEnd, flattened.count)]))
        }

        return stride(from: 0, to: mergedCells.count, by: 8).map { rowStart in
            DisplayRow(
                id: "month-row-\(rowStart)",
                cells: Array(mergedCells[rowStart..<min(rowStart + 8, mergedCells.count)])
            )
        }
    }

    private func weekLabel(for row: DisplayRow) -> String {
        guard let date = row.cells.first?.date else { return "--" }
        return pressureAxisLabel(for: date)
    }

    private func pressureAxisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let day = calendar.component(.day, from: date)
        let weekdayIndex = max(0, min(6, calendar.component(.weekday, from: date) - 1))
        return "\(day)日\n\(weekdaySymbols[weekdayIndex])"
    }

    private func mergeSequentialCells(_ sourceCells: [PressureTimeSlotCell]) -> PressureTimeSlotCell {
        let measuredValues = sourceCells.filter { $0.source == .measured }.compactMap(\.value)
        let estimatedValues = sourceCells.filter { $0.source == .estimated }.compactMap(\.value)
        let inferredValues = sourceCells.filter { $0.source == .inferred }.compactMap(\.value)

        let source: PressureTimeSlotCell.Source
        let values: [Double]
        if !measuredValues.isEmpty {
            source = .measured
            values = measuredValues
        } else if !estimatedValues.isEmpty {
            source = .estimated
            values = estimatedValues
        } else if !inferredValues.isEmpty {
            source = .inferred
            values = inferredValues
        } else {
            source = .empty
            values = []
        }

        return PressureTimeSlotCell(
            date: sourceCells.first?.date ?? Date(),
            slotStartHour: sourceCells.first?.slotStartHour ?? 0,
            slotDurationHours: max(slotDuration, sourceCells.first?.slotDurationHours ?? slotDuration),
            value: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
            source: source
        )
    }

    private func mergeCells(_ cells: [PressureTimeSlotCell], chunkSize: Int) -> [PressureTimeSlotCell] {
        PressureTimeSlotDayBucketMerger.merge(
            cells,
            chunkSize: chunkSize,
            referenceDate: Date()
        )
    }
}

struct PressureTimeSlotDayBucketMerger {
    static func merge(
        _ cells: [PressureTimeSlotCell],
        chunkSize: Int,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> [PressureTimeSlotCell] {
        guard chunkSize > 1 else { return cells }

        let currentDayStart = calendar.startOfDay(for: referenceDate)
        let currentHourStart = calendar.dateInterval(of: .hour, for: referenceDate)?.start ?? referenceDate
        var merged: [PressureTimeSlotCell] = []
        var index = 0

        while index < cells.count {
            let chunk = Array(cells[index..<min(index + chunkSize, cells.count)])
            let chunkDayStart = calendar.startOfDay(for: chunk.first?.date ?? referenceDate)
            let containsFutureSlot = chunkDayStart == currentDayStart && chunk.contains { cell in
                let slotDate = calendar.date(byAdding: .hour, value: cell.slotStartHour, to: chunkDayStart) ?? chunkDayStart
                return slotDate > currentHourStart
            }

            if containsFutureSlot {
                merged.append(
                    PressureTimeSlotCell(
                        date: chunk.first?.date ?? referenceDate,
                        slotStartHour: chunk.first?.slotStartHour ?? index,
                        slotDurationHours: chunkSize,
                        value: nil,
                        source: .empty
                    )
                )
                index += chunkSize
                continue
            }

            let measuredValues = chunk.filter { $0.source == .measured }.compactMap(\.value)
            let estimatedValues = chunk.filter { $0.source == .estimated }.compactMap(\.value)
            let inferredValues = chunk.filter { $0.source == .inferred }.compactMap(\.value)

            let source: PressureTimeSlotCell.Source
            let values: [Double]
            if !measuredValues.isEmpty {
                source = .measured
                values = measuredValues
            } else if !estimatedValues.isEmpty {
                source = .estimated
                values = estimatedValues
            } else if !inferredValues.isEmpty {
                source = .inferred
                values = inferredValues
            } else {
                source = .empty
                values = []
            }

            merged.append(
                PressureTimeSlotCell(
                    date: chunk.first?.date ?? referenceDate,
                    slotStartHour: chunk.first?.slotStartHour ?? index,
                    slotDurationHours: chunkSize,
                    value: values.max(),
                    source: source
                )
            )

            index += chunkSize
        }

        return merged
    }
}

/// 重点趋势分类卡片组件 作为趋势模块里的内容展示卡片。
/// 负责趋势分析展示。用于趋势页面的“重点分类卡片”。

private struct TrendCategorySignalCard: View {
    let card: TrendCategoryCardModel
    let metricPoints: [TimeSeriesPointDouble]

    var body: some View {
        GeometryReader { proxy in
            let scale = cardScale(for: proxy.size.width)

            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: scaled(12, by: scale)) {
                    HStack(alignment: .center, spacing: scaled(8, by: scale)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: scaled(9, by: scale), style: .continuous)
                                .fill(card.category.accentColor.opacity(0.13))
                                .frame(width: scaled(30, by: scale), height: scaled(30, by: scale))

                            Image(systemName: card.category.icon)
                                .font(.system(size: scaled(14, by: scale), weight: .black))
                                .foregroundColor(card.category.accentColor)
                        }

                        Text(displayTitle)
                            .font(.system(size: scaled(17, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "313843"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 0)

                        Image(systemName: Theme.Icons.chevronRight)
                            .font(.system(size: scaled(13, by: scale), weight: .black))
                            .foregroundColor(Color(hex: "A8AFBA"))
                            .frame(width: scaled(20, by: scale), height: scaled(20, by: scale))
                    }

                    Spacer(minLength: scaled(8, by: scale))

                    VStack(alignment: .leading, spacing: scaled(3, by: scale)) {
                        Text(statusLabelText)
                            .font(.system(size: scaled(12, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "A0A6AE"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(statusValueText)
                            .font(.system(size: scaled(24, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "2F3540"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    .padding(.trailing, scaled(52, by: scale))
                }
                .padding(scaled(18, by: scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                TrendMetricMiniChart(points: metricPoints, tint: card.category.accentColor)
                    .frame(width: scaled(76, by: scale), height: scaled(58, by: scale), alignment: .bottomTrailing)
                    .opacity(0.76)
                    .padding(.trailing, scaled(10, by: scale))
                    .padding(.bottom, scaled(10, by: scale))
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(0.98, contentMode: .fit)
        .bbChartSurface(tint: card.category.accentColor, cornerRadius: 30)
    }

    private var statusLabelText: String {
        card.status.title
    }

    private var displayTitle: String {
        card.category == .heartCardio ? "心率" : card.category.title
    }

    private var statusValueText: String {
        if !card.primaryValueText.isEmpty,
           card.primaryValueText != card.status.title {
            return card.primaryValueText
        }
        switch card.status {
        case .ready:
            return String(localized: "已形成")
        case .partial:
            return String(localized: "可查看")
        case .noData:
            return String(localized: "等待中")
        }
    }

    private func cardScale(for width: CGFloat) -> CGFloat {
        let raw = width / 180
        return min(max(raw, 0.84), 1.08)
    }

    private func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat {
        value * scale
    }
}

private struct SleepTrendSignalCard: View {
    let featured: FeaturedTrendCategoryModel

    private var latestNight: SleepTrendNightSummary? {
        featured.sleepNightSummaries.last
    }

    private var cardTitle: String {
        featured.category.title
    }

    private var durationMinutes: Int? {
        if let minutes = latestNight?.asleepMinutes {
            return max(0, minutes)
        }
        guard let value = featured.primaryMetric.points.last?.value,
              value.isFinite,
              value >= 0 else {
            return nil
        }
        return Int(value.rounded())
    }

    private var durationText: String {
        guard let durationMinutes else { return "--" }
        return "\(durationMinutes / 60):\(String(format: "%02d", durationMinutes % 60))"
    }

    private var miniChartPoints: [TimeSeriesPointDouble] {
        ([featured.primaryMetric] + featured.supportingMetrics + featured.sleepRecoveryMetrics)
            .first(where: { !$0.points.isEmpty })?
            .points ?? []
    }

    private var scoreText: String? {
        guard
            let scoreMetric = featured.supportingMetrics.first(where: { $0.title == "睡眠评分" })
                ?? featured.sleepRecoveryMetrics.first(where: { $0.title == "睡眠评分" }),
            let value = scoreMetric.points.last?.value
        else {
            return nil
        }
        return String(localized: "评分 \(Int(value.rounded()))")
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = cardScale(for: proxy.size.width)

            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: scaled(12, by: scale)) {
                    HStack(alignment: .center, spacing: scaled(8, by: scale)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: scaled(9, by: scale), style: .continuous)
                                .fill(Color(hex: "3FA7E8").opacity(0.13))
                                .frame(width: scaled(30, by: scale), height: scaled(30, by: scale))

                            Image(systemName: featured.category.icon)
                                .font(.system(size: scaled(14, by: scale), weight: .black))
                                .foregroundColor(Color(hex: "3FA7E8"))
                        }

                        Text(cardTitle)
                            .font(.system(size: scaled(17, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "313843"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 0)

                        Image(systemName: Theme.Icons.chevronRight)
                            .font(.system(size: scaled(13, by: scale), weight: .black))
                            .foregroundColor(Color(hex: "A8AFBA"))
                            .frame(width: scaled(20, by: scale), height: scaled(20, by: scale))
                    }

                    Spacer(minLength: scaled(8, by: scale))

                    VStack(alignment: .leading, spacing: scaled(3, by: scale)) {
                        Text(scoreText ?? "昨夜睡眠")
                            .font(.system(size: scaled(12, by: scale), weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "A0A6AE"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(alignment: .firstTextBaseline, spacing: scaled(2, by: scale)) {
                            Text(durationText)
                                .font(.system(size: scaled(24, by: scale), weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "2F3540"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                            if durationMinutes != nil {
                                Text("h")
                                    .font(.system(size: scaled(13, by: scale), weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "A4ABB5"))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.trailing, scaled(52, by: scale))
                }
                .padding(scaled(18, by: scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                TrendMetricMiniChart(points: miniChartPoints, tint: Color(hex: "3FA7E8"))
                    .frame(width: scaled(76, by: scale), height: scaled(58, by: scale), alignment: .bottomTrailing)
                    .opacity(0.76)
                    .padding(.trailing, scaled(10, by: scale))
                    .padding(.bottom, scaled(10, by: scale))
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(0.98, contentMode: .fit)
        .bbChartSurface(tint: Color(hex: "3FA7E8"), cornerRadius: 30)
    }

    private func cardScale(for width: CGFloat) -> CGFloat {
        let raw = width / 180
        return min(max(raw, 0.84), 1.08)
    }

    private func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat {
        value * scale
    }
}

private struct TrendMetricMiniChart: View {
    let points: [TimeSeriesPointDouble]
    let tint: Color

    private var recentPoints: [TimeSeriesPointDouble] {
        Array(
            points
                .filter { $0.value.isFinite }
                .sorted { $0.date < $1.date }
                .suffix(7)
        )
    }

    var body: some View {
        if recentPoints.isEmpty {
            VStack(spacing: 3) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .semibold))
                Text("暂无趋势")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundColor(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(recentPoints) { point in
                AreaMark(
                    x: .value("时间", point.date),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("时间", point.date),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if point.id == recentPoints.last?.id {
                    PointMark(
                        x: .value("时间", point.date),
                        y: .value("数值", point.value)
                    )
                    .foregroundStyle(tint)
                    .symbolSize(28)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.background(Color.clear)
            }
        }
    }
}


@ViewBuilder
func dashboardTrendIcon(
    primary: String,
    badge: String,
    accent: Color,
    secondary: Color,
    size: CGFloat = 48
) -> some View {
    ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.20), secondary.opacity(0.12), Color.white.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                    .stroke(accent.opacity(0.16), lineWidth: 1)
            )
            .overlay(alignment: .center) {
                Image(systemName: primary)
                    .font(.system(size: size * 0.38, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent, secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

        Circle()
            .fill(Color.white.opacity(0.98))
            .frame(width: size * 0.34, height: size * 0.34)
            .overlay(
                Circle()
                    .stroke(accent.opacity(0.16), lineWidth: 1)
            )
            .overlay(
                Image(systemName: badge)
                    .font(.system(size: size * 0.14, weight: .black))
                    .foregroundColor(accent)
            )
            .offset(x: size * 0.08, y: size * 0.08)
    }
    .shadow(color: accent.opacity(0.10), radius: 10, x: 0, y: 6)
}


#Preview {
    ZStack {
        Theme.Colors.pageBackground.ignoresSafeArea()

        TrendsDashboardView(
            periodViewModel: PeriodViewModel()
        )
    }
}
