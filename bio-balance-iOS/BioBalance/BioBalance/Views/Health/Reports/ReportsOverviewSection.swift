/// ReportsOverviewSection 参考新版视觉稿实现的报告总览区。
/// 由报告页顶部承载：周期切换（周报/月报/全部）、综合健康评分环、AI 健康总结、四项指标网格、
/// 本周趋势折线与个性化建议。

import SwiftUI
import Charts

// MARK: - 周期定义

/// 报告总览的聚合周期。
enum ReportsOverviewPeriod: String, CaseIterable, Identifiable {
    case week = "周报"
    case month = "月报"
    case all = "全部"

    var id: String { rawValue }

    /// 本地化标题：rawValue 仅作标识，UI 展示走 String Catalog。
    var displayName: String {
        switch self {
        case .week: return String(localized: "周报")
        case .month: return String(localized: "月报")
        case .all: return String(localized: "全部")
        }
    }
}

/// 一个周期的聚合结果：区间、样本与均值。
struct ReportsOverviewAggregate {
    let period: ReportsOverviewPeriod
    let interval: DateInterval
    /// 有健康样本的天
    let days: [ReportDaySummary]
    /// 有评分的天
    let scoredDays: [ReportDaySummary]
    /// 对比区间（上一个同等长度周期）
    let previousDays: [ReportDaySummary]

    var averageScore: Int? { scoredDays.reportsAverageScore }

    var averageSleepHours: Double? {
        average(of: days.compactMap(\.sleepHours))
    }

    var averageStress: Double? {
        average(of: days.compactMap(\.stress))
    }

    var averageHRV: Double? {
        average(of: days.compactMap(\.hrv))
    }

    var totalSteps: Double? {
        let values = days.compactMap(\.steps)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    /// 平均日步数（活动量按天均值展示更可比）
    var averageSteps: Double? {
        average(of: days.compactMap(\.steps))
    }

    /// 日均心率（bpm）
    var averageHeartRate: Double? {
        average(of: days.compactMap(\.averageHeartRate))
    }

    /// 日均步行/跑步距离（公里）
    var averageDistanceKm: Double? {
        guard let meters = average(of: days.compactMap(\.distanceMeters)) else { return nil }
        return meters / 1000.0
    }

    /// 评分较上一周期的变化；样本不足时为 nil
    var scoreDelta: Int? {
        let current = scoredDays.reportsAverageScore
        let previous = previousDays.filter(\.hasData).reportsAverageScore
        guard let current, let previous else { return nil }
        return current - previous
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - 总览区视图

/// 报告页顶部的总览区：左侧评分环 + 右侧 AI 总结，下方 2×2 指标网格、本周趋势与个性化建议。
/// 参考「健康报告」视觉稿组织信息层级，数据全部来自既有 ReportSummaryViewModel。
struct ReportsOverviewSection: View {
    let viewModel: ReportSummaryViewModel
    var onOpenAlerts: () -> Void = {}
    var onOpenDetail: () -> Void

    @State private var period: ReportsOverviewPeriod = .week
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            periodPicker
            scoreAndSummaryCard
            metricsGrid
            weeklyTrendCard
            personalAdviceCard
        }
    }

    // MARK: 周期切换

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(ReportsOverviewPeriod.allCases) { item in
                let isSelected = item == period
                Button {
                    period = item
                } label: {
                    Text(item.displayName)
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Theme.Colors.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "4E9B8F"), Theme.Colors.mintGreen], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.clear)
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityLabel(item.displayName)
            }

            Spacer(minLength: 0)

            Button {
                onOpenAlerts()
            } label: {
                Image(systemName: "bell.badge.fill")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "F46B5A"))
                    .frame(width: 36, height: 36)
                    .background(Theme.Colors.surface.opacity(0.88), in: Circle())
                    .overlay(Circle().stroke(Theme.Colors.surfaceBorder, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "告警记录"))
            .accessibilityHint(String(localized: "查看异常提醒和处理建议"))
        }
        .padding(4)
        .background(Theme.Colors.background, in: Capsule())
        .overlay(Capsule().stroke(Theme.Colors.surfaceBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "报告周期"))
    }

    // MARK: 综合评分 + AI 总结卡

    private var aggregate: ReportsOverviewAggregate {
        Self.aggregate(for: period, viewModel: viewModel)
    }

    @ViewBuilder
    private var scoreAndSummaryCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    scoreColumn
                    AnyView(aiSummaryCard)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    scoreColumn

                    // AnyView 边界：与页面其他板块一致，隔断深层泛型避免 iOS 27 递归爆栈。
                    AnyView(aiSummaryCard)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: Color(hex: "668C78").opacity(0.07), radius: 14, y: 6)
    }

    private var scoreColumn: some View {
        let score = aggregate.averageScore
        let tint = ReportsScorePalette.tint(for: score)

        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "综合健康评分"))
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(aggregate.intervalText)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)

            ReportsOverviewScoreRing(score: score, tint: tint)

            if let delta = aggregate.scoreDelta {
                HStack(spacing: 3) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.appSystem(size: 10, weight: .black))
                    Text(String(localized: "较上周期 \(delta >= 0 ? "+" : "")\(delta) 分"))
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(delta >= 0 ? Theme.Colors.mintGreen : Color(hex: "F46B5A"))
            } else {
                Text(ReportScoreStatus.shortLabel(for: score))
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var aiSummaryCard: some View {
        Button {
            onOpenDetail()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "9B7BFF"), Color(hex: "7A4CE0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 26, height: 26)

                        Image(systemName: "sparkles")
                            .font(.appSystem(size: 13, weight: .black))
                            .foregroundColor(.white)
                    }

                    Text(String(localized: "AI 健康总结"))
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Text(summaryHeadline)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summaryDetail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [Color(hex: "F5F1FF"), Color(hex: "F7FAFF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(hex: "E9E4F8"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "查看报告详情"))
    }

    private var summaryHeadline: String {
        if let latest = viewModel.latest, period == .week || aggregate.days.isEmpty {
            return latest.scoreBreakdown?.headline
                ?? latest.adviceSummary?.summary
                ?? ReportScoreStatus.headline(for: latest.score)
        }
        return ReportScoreStatus.headline(for: aggregate.averageScore)
    }

    private var summaryDetail: String {
        if viewModel.isLoading && aggregate.days.isEmpty {
            return String(localized: "正在同步健康样本，稍等片刻即可生成总结。")
        }
        if let insight = ReportInterpretationEngine.periodInsight(from: aggregate.days, scope: aggregate.period.displayName) {
            return insight.detail
        }
        return String(localized: "同步睡眠、压力、HRV 与活动样本后，这里会给出更完整的周期总结。")
    }

    // MARK: 指标网格

    private var metricsGrid: some View {
        LazyVGrid(
            columns: metricColumns,
            spacing: 12
        ) {
            ReportsOverviewMetricCard(
                title: String(localized: "睡眠"),
                value: sleepText,
                delta: sleepDeltaText,
                isDeltaPositive: isSleepDeltaPositive,
                tint: ReportMetricKind.sleep.tint,
                systemImage: "moon.fill",
                sparkline: sleepSparkline
            )
            ReportsOverviewMetricCard(
                title: String(localized: "运动"),
                value: activityText,
                delta: activityDeltaText,
                isDeltaPositive: isActivityDeltaPositive,
                tint: ReportMetricKind.activity.tint,
                systemImage: "figure.run",
                sparkline: activitySparkline
            )
            ReportsOverviewMetricCard(
                title: String(localized: "心率"),
                value: heartRateText,
                delta: heartRateDeltaText,
                isDeltaPositive: isHeartRateDeltaPositive,
                tint: Color(hex: "F46B5A"),
                systemImage: "heart.fill",
                sparkline: heartRateSparkline
            )
            ReportsOverviewMetricCard(
                title: String(localized: "压力"),
                value: stressText,
                delta: stressDeltaText,
                isDeltaPositive: isStressDeltaPositive,
                tint: ReportMetricKind.stress.tint,
                systemImage: "leaf.fill",
                sparkline: stressSparkline
            )
        }
    }

    private var metricColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var sleepText: String {
        guard let hours = aggregate.averageSleepHours else { return "--" }
        let wholeHours = Int(hours)
        let minutes = Int((hours - Double(wholeHours)) * 60 + 0.5)
        return String(localized: "\(wholeHours)小时\(minutes)分")
    }

    private var sleepDeltaText: String? {
        guard let delta = percentDelta(\.sleepHours) else { return nil }
        return deltaPercentText(delta)
    }

    private var isSleepDeltaPositive: Bool {
        (percentDelta(\.sleepHours) ?? 0) >= 0
    }

    private var activityText: String {
        guard let km = aggregate.averageDistanceKm ?? aggregate.averageSteps.map({ $0 * 0.0007 }) else { return "--" }
        return String(format: "%.1f km", km)
    }

    private var activityDeltaText: String? {
        guard let delta = percentDelta(\.steps) else { return nil }
        return deltaPercentText(delta)
    }

    private var isActivityDeltaPositive: Bool {
        (percentDelta(\.steps) ?? 0) >= 0
    }

    /// 日均心率；缺样本时回退展示 HRV（同为恢复参考）
    private var heartRateText: String {
        if let bpm = aggregate.averageHeartRate {
            return String(localized: "\(Int(bpm.rounded())) bpm")
        }
        guard let hrv = aggregate.averageHRV else { return "--" }
        return "\(Int(hrv.rounded())) ms"
    }

    private var heartRateDeltaText: String? {
        if aggregate.averageHeartRate != nil {
            guard let delta = percentDelta(\.averageHeartRate) else { return nil }
            return deltaPercentText(delta)
        }
        guard let delta = percentDelta(\.hrv) else { return nil }
        return deltaPercentText(delta)
    }

    private var isHeartRateDeltaPositive: Bool {
        if aggregate.averageHeartRate != nil {
            return (percentDelta(\.averageHeartRate) ?? 0) <= 0
        }
        return (percentDelta(\.hrv) ?? 0) >= 0
    }

    private var stressText: String {
        guard let stress = aggregate.averageStress else { return "--" }
        let value = Int(stress.rounded())
        switch stress {
        case ..<35: return String(localized: "低 \(value)")
        case ..<60: return String(localized: "中 \(value)")
        default: return String(localized: "高 \(value)")
        }
    }

    private var stressDeltaText: String? {
        guard let delta = percentDelta(\.stress) else { return nil }
        return deltaPercentText(delta)
    }

    private var isStressDeltaPositive: Bool {
        // 压力下降才是正向变化
        (percentDelta(\.stress) ?? 0) <= 0
    }

    /// 环比文案：+12% / -5%；0 显示为持平
    private func deltaPercentText(_ delta: Int) -> String {
        if delta == 0 { return String(localized: "持平") }
        return delta > 0 ? "+\(delta)%" : "\(delta)%"
    }

    /// 与上一个同等长度周期对比的百分比变化
    private func percentDelta(_ keyPath: KeyPath<ReportDaySummary, Double?>) -> Int? {
        let current = aggregate.days.compactMap { $0[keyPath: keyPath] }
        let previous = aggregate.previousDays.filter(\.hasData).compactMap { $0[keyPath: keyPath] }
        guard !current.isEmpty, !previous.isEmpty else { return nil }
        let currentAverage = current.reduce(0, +) / Double(current.count)
        let previousAverage = previous.reduce(0, +) / Double(previous.count)
        guard previousAverage > 0 else { return nil }
        return Int(((currentAverage - previousAverage) / previousAverage * 100).rounded())
    }

    // MARK: 迷你趋势

    private var sleepSparkline: [Double] {
        aggregate.days.compactMap(\.sleepHours)
    }

    private var activitySparkline: [Double] {
        aggregate.days.compactMap(\.steps)
    }

    private var heartRateSparkline: [Double] {
        if aggregate.averageHeartRate != nil {
            return aggregate.days.compactMap(\.averageHeartRate)
        }
        return aggregate.days.compactMap(\.hrv)
    }

    private var stressSparkline: [Double] {
        aggregate.days.compactMap(\.stress)
    }

    // MARK: 本周趋势

    /// 「本周趋势」折线卡：展示所选周期的每日评分曲线，点击进入报告详情。
    private var weeklyTrendCard: some View {
        Button {
            onOpenDetail()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.appSystem(size: 13, weight: .black))
                        .foregroundStyle(Color(hex: "5B8CFF"))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "5B8CFF").opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "本周趋势"))
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text(trendCaption)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 3) {
                        Text(String(localized: "查看详情"))
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "5B8CFF"))
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 10, weight: .black))
                            .foregroundStyle(Color(hex: "5B8CFF"))
                    }
                }

                trendChart
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "查看报告详情"))
    }

    /// 趋势副标题：复用周期洞察引擎的一句话解读。
    private var trendCaption: String {
        if viewModel.isLoading && aggregate.days.isEmpty {
            return String(localized: "正在同步健康样本")
        }
        if let insight = ReportInterpretationEngine.periodInsight(from: aggregate.days, scope: aggregate.period.displayName) {
            return insight.headline
        }
        return String(localized: "同步数据后生成周期趋势解读")
    }

    /// 每日评分折线；样本不足时展示内联空态。
    @ViewBuilder
    private var trendChart: some View {
        let points = aggregate.days.filter { $0.score != nil }
        if points.isEmpty {
            ReportsInlineEmptyState(text: viewModel.isLoading ? "正在整理评分样本" : "同步评分数据后查看趋势")
        } else {
            Chart {
                AreaMark(
                    x: .value("日期", points.first?.date ?? Date(), unit: .day),
                    y: .value("评分", 0)
                )
                // 占位不可见：仅保证 Charts 域内有基准序列，视觉由下方 LineMark/AreaMark 承担。

                ForEach(points) { point in
                    AreaMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("评分", point.scoreValue)
                    )
                    .reportsScoreArea(tint: Color(hex: "5B8CFF"))

                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("评分", point.scoreValue)
                    )
                    .reportsScoreLine(tint: Color(hex: "5B8CFF"))

                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("评分", point.scoreValue)
                    )
                    .reportsScorePoint(tint: Color(hex: "5B8CFF"))
                    .symbolSize(30)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(ReportsChartStyle.grid.opacity(0.5))
                    AxisValueLabel(format: .dateTime.weekday(.short))
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [25, 50, 75, 100]) { _ in
                    AxisGridLine().foregroundStyle(ReportsChartStyle.grid.opacity(0.5))
                    AxisValueLabel()
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ReportsChartStyle.axisLabel)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "本周趋势"))
            .accessibilityValue(String(localized: "共 \(points.count) 天评分样本"))
        }
    }

    // MARK: 个性化建议

    /// 「个性化建议」卡：取本周期最弱维度生成 2-3 条可执行建议。
    private var personalAdviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundStyle(Color(hex: "F3A53B"))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: "F3A53B").opacity(0.12), in: Circle())

                Text(String(localized: "个性化建议"))
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 0)

                NavigationLink {
                    ReportDetailView(reportDate: viewModel.latest?.date ?? Date(), initialSummary: viewModel.latest)
                } label: {
                    HStack(spacing: 3) {
                        Text(String(localized: "查看全部"))
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "5B8CFF"))
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 10, weight: .black))
                            .foregroundStyle(Color(hex: "5B8CFF"))
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(adviceItems) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(item.tint)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        Text(item.detail)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "3E4650"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    /// 建议来源：最近一条行动建议 + 本周期最弱维度对应动作，最多 3 条。
    private var adviceItems: [ReportPeriodActionItem] {
        let valid = aggregate.days.filter(\.hasData)
        guard !valid.isEmpty else {
            return [
                ReportPeriodActionItem(
                    title: "先同步健康数据",
                    detail: "补齐睡眠、压力或活动样本后，这里会给出更贴合的建议。",
                    systemImage: "icloud.and.arrow.down",
                    tint: Color(hex: "8AA0B8")
                )
            ]
        }

        var result: [ReportPeriodActionItem] = []
        if let firstAction = valid.reversed().compactMap({ $0.adviceSummary?.actionItems.first }).first {
            result.append(
                ReportPeriodActionItem(
                    title: "下一步",
                    detail: firstAction,
                    systemImage: "sparkles",
                    tint: Color(hex: "34C759")
                )
            )
        }

        if let weakest = ReportMetricFormatter.metricRankItems(from: valid).last {
            result.append(primaryAdvice(for: weakest.kind))
        }

        result.append(
            ReportPeriodActionItem(
                title: "保持可持续",
                detail: "先做一件低负担调整，连续 3 天观察评分变化，不用一次改太多。",
                systemImage: "leaf.fill",
                tint: Color(hex: "5B8CFF")
            )
        )

        return Array(result.prefix(3))
    }

    /// 按最弱维度生成一条可执行建议。
    private func primaryAdvice(for kind: ReportMetricKind) -> ReportPeriodActionItem {
        switch kind {
        case .sleep:
            return ReportPeriodActionItem(
                title: "睡眠",
                detail: "保持规律作息，固定入睡与起床时间，保证充足睡眠。",
                systemImage: "moon.fill",
                tint: ReportMetricKind.sleep.tint
            )
        case .stress:
            return ReportPeriodActionItem(
                title: "压力",
                detail: "睡前尝试放松训练或短时呼吸练习，帮助缓解压力积累。",
                systemImage: "leaf.fill",
                tint: ReportMetricKind.stress.tint
            )
        case .hrv:
            return ReportPeriodActionItem(
                title: "HRV",
                detail: "近恢复弹性偏弱，训练以轻量为主，晚间减少刺激留足恢复窗口。",
                systemImage: "waveform.path.ecg",
                tint: ReportMetricKind.hrv.tint
            )
        case .activity:
            return ReportPeriodActionItem(
                title: "活动",
                detail: "每周至少进行 150 分钟中等强度运动，可从快走或慢跑开始。",
                systemImage: "figure.run",
                tint: ReportMetricKind.activity.tint
            )
        }
    }

    // MARK: 聚合

    static func aggregate(
        for period: ReportsOverviewPeriod,
        viewModel: ReportSummaryViewModel
    ) -> ReportsOverviewAggregate {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        switch period {
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return buildAggregate(period: period, start: start, end: today, calendar: calendar, viewModel: viewModel)
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return buildAggregate(period: period, start: start, end: today, calendar: calendar, viewModel: viewModel)
        case .all:
            let start = viewModel.days.first.map { calendar.startOfDay(for: $0.date) } ?? today
            return buildAggregate(period: period, start: start, end: today, calendar: calendar, viewModel: viewModel)
        }
    }

    private static func buildAggregate(
        period: ReportsOverviewPeriod,
        start: Date,
        end: Date,
        calendar: Calendar,
        viewModel: ReportSummaryViewModel
    ) -> ReportsOverviewAggregate {
        let interval = DateInterval(start: start, duration: end.timeIntervalSince(start) + 24 * 3600)
        let days = viewModel.summaries(for: interval).filter(\.hasData)
        let dayLength = interval.duration
        let previousInterval = DateInterval(start: start.addingTimeInterval(-dayLength), duration: dayLength)
        let previousDays = viewModel.summaries(for: previousInterval).filter(\.hasData)

        return ReportsOverviewAggregate(
            period: period,
            interval: interval,
            days: days,
            scoredDays: days.filter { $0.score != nil },
            previousDays: previousDays
        )
    }
}

// MARK: - 区间文案

extension ReportsOverviewAggregate {
    /// 区间的可读文案，如「5月27日 - 6月2日」
    var intervalText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M月d日"
        let startText = formatter.string(from: interval.start)
        let endText = formatter.string(from: interval.end.addingTimeInterval(-24 * 3600))
        return "\(startText) - \(endText)"
    }
}

// MARK: - 评分环

/// 综合健康评分环：渐变弧 + 中心分数 + 状态标签。
private struct ReportsOverviewScoreRing: View {
    let score: Int?
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.45), tint, tint]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(score.map(String.init) ?? "--")
                    .font(.appSystem(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(String(localized: "/100"))
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)

                Text(ReportScoreStatus.shortLabel(for: score))
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 116, height: 116)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "综合健康评分"))
        .accessibilityValue(score.map { "\($0) 分" } ?? String(localized: "暂无"))
    }

    private var progress: CGFloat {
        CGFloat(min(max(Double(score ?? 0) / 100.0, 0), 1))
    }
}

// MARK: - 指标卡

/// 指标网格中的单卡：标题、主值、环比与迷你柱状趋势。
private struct ReportsOverviewMetricCard: View {
    let title: String
    let value: String
    let delta: String?
    let isDeltaPositive: Bool
    let tint: Color
    let systemImage: String
    let sparkline: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: Circle())

                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Text(value)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: "25282C"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .bottom, spacing: 8) {
                if let delta {
                    Text(delta)
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(isDeltaPositive ? Theme.Colors.mintGreen : Color(hex: "F46B5A"))
                }

                Spacer(minLength: 0)

                miniBars
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// 迷你柱状趋势，最多展示最近 12 个样本
    private var miniBars: some View {
        let values = Array(sparkline.suffix(12))
        let peak = values.max() ?? 0

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { index in
                let ratio = peak > 0 ? values[index] / peak : 0
                Capsule()
                    .fill(tint.opacity(0.35 + 0.45 * ratio))
                    .frame(width: 3, height: max(4, 22 * ratio))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("报告总览") {
    NavigationStack {
        ZStack {
            ReportsSoftBackground()
            AdaptivePageScrollView(topPadding: 14, bottomPadding: 40) {
                ReportsOverviewHostForPreview()
            }
        }
    }
}

@MainActor
private struct ReportsOverviewHostForPreview: View {
    @State private var viewModel = ReportSummaryViewModel()

    var body: some View {
        ReportsOverviewSection(viewModel: viewModel, onOpenAlerts: {}, onOpenDetail: {})
            .task { viewModel.load(days: 30) }
    }
}
#endif
