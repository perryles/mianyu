/// ReportDetailView 作为报告模块的支撑页面，负责展示报告详情子组件。
/// 负责呈现方法论卡片，说明评分口径、趋势覆盖与样本缺失边界。

import SwiftUI
import Charts

private struct ReportDetailMethodologyCard: View {
    let summary: ReportDaySummary?
    let points: [ReportDaySummary]

    private var availableMetricCount: Int {
        guard let summary else { return 0 }
        return ReportMetricKind.allCases.filter {
            ReportMetricFormatter.normalizedValue(for: $0, in: summary) != nil
        }.count
    }

    private var validDayCount: Int {
        Set(points.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("数据口径与边界", subtitle: "说明本页数字如何组合，避免把缺失样本或状态分误读成医学结论。")

            HStack(spacing: 8) {
                ReportsCompactMetricPill(title: "当天维度", value: "\(availableMetricCount)/4", tint: ReportsEditorialStyle.lavenderAccent)
                ReportsCompactMetricPill(title: "趋势样本", value: "\(validDayCount)/7天", tint: Theme.Colors.mintGreen)
                ReportsCompactMetricPill(title: "统一量尺", value: "0-100", tint: ReportsEditorialStyle.warmGold)
            }

            VStack(spacing: 0) {
                methodologyRow(
                    title: "综合评分",
                    detail: "由当天可用的睡眠、压力、HRV 与活动状态共同解释；缺失维度不会按 0 分计入。",
                    systemImage: "gauge.with.dots.needle.67percent",
                    tint: Theme.Colors.mintGreen
                )
                Divider()
                    .overlay(ReportsEditorialStyle.border)
                    .padding(.leading, 42)
                methodologyRow(
                    title: "趋势与关联",
                    detail: "近 7 天图表覆盖报告日及此前 6 天。状态分仅用于同屏比较，其中压力越低，换算后的恢复状态越高。",
                    systemImage: "chart.xyaxis.line",
                    tint: ReportsEditorialStyle.lavenderAccent
                )
                Divider()
                    .overlay(ReportsEditorialStyle.border)
                    .padding(.leading, 42)
                methodologyRow(
                    title: "样本缺失",
                    detail: "“--”表示健康数据尚未授权、尚未同步或当天没有有效样本，不等同于异常或真实值为零。",
                    systemImage: "exclamationmark.circle",
                    tint: Color(hex: "F3A53B")
                )
            }
        }
    }

    private func methodologyRow(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.ink)
                Text(detail)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(ReportsEditorialStyle.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

private struct ReportDetailFooterAction: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundColor(ReportsEditorialStyle.ink)
                .frame(width: 38, height: 38)
                .background(
                    isPrimary ? Color.black.opacity(0.07) : ReportsEditorialStyle.lavender,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.ink)
                Text(subtitle)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(
                        isPrimary
                        ? ReportsEditorialStyle.ink.opacity(0.64)
                        : ReportsEditorialStyle.secondaryInk
                    )
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(ReportsEditorialStyle.ink.opacity(0.56))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 66)
        .background(
            isPrimary ? ReportsEditorialStyle.warmGold : Color.white,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isPrimary ? ReportsEditorialStyle.warmGold : ReportsEditorialStyle.border,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 报告视图 由上级页面或路由调用，作为报告模块里的界面或内容组件。
/// 负责组织日报、周报、月报或报告详情的展示与分享。
struct ReportDetailView: View {
    let reportDate: Date
    let initialSummary: ReportDaySummary?
    @State private var viewModel = ReportSummaryViewModel()
    @State private var timelineReplay: BehaviorTimelineReplay?
    @State private var isTimelineLoading = false
    @State private var sleepEnvironmentInsight: SleepEnvironmentSnoreInsight?
    @State private var isSleepEnvironmentInsightLoading = false
    @State private var sleepNightSummary: SleepTrendNightSummary?
    @State private var dailyWellnessSummary: DailyWellnessSummary = .empty()
    @State private var showingShareSheet = false
    /// 深度分析组是否展开（默认折叠）
    @State private var showDeepAnalysis = false
    /// 生活上下文组是否展开（默认折叠）
    @State private var showLifeContext = false
    /// 说明组是否展开（默认折叠）
    @State private var showNotes = false

    private var summary: ReportDaySummary? {
        viewModel.summary(for: reportDate) ?? initialSummary
    }

    private var subtitle: String {
        reportDate.reportsFullDateString()
    }

    private var dailyWellnessScoreBreakdown: DailyWellnessScoreBreakdown {
        DailyWellnessScoreEngine.evaluate(
            record: dailyWellnessSummary.todayRecord,
            pressureScore: summary?.stress.map { Int($0.rounded()) },
            todayHrv: summary?.hrv,
            recentAverageHrv: recentAverageHrv
        )
    }

    var body: some View {
        ZStack {
            HealthDetailPageBackground()

            AdaptivePageScrollView(style: .reading, topPadding: 10, bottomPadding: 96) {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: 核心摘要组（始终展开）
                    ReportDetailHeroCard(
                        summary: summary,
                        subtitle: subtitle,
                        sleepNightSummary: sleepNightSummary
                    )
                    if let sleepNightSummary, sleepNightSummary.asleepMinutes > 0 {
                        ReportDetailSleepArchitectureCard(night: sleepNightSummary)
                    }
                    ReportsTakeawaysCard(
                        title: "今日重点",
                        subtitle: "把最重要的状态、原因和下一步动作整理成一页摘要。",
                        items: ReportContentComposer.dailyTakeaways(summary: summary, nearbyPoints: nearbyPoints)
                    )
                    ReportDetailBreakdownCard(breakdown: summary?.scoreBreakdown)
                    ReportDetailRecoveryPlanCard(
                        summary: summary,
                        wellnessSummary: dailyWellnessSummary,
                        wellnessScoreBreakdown: dailyWellnessScoreBreakdown
                    )

                    // MARK: 深度分析组（默认折叠）
                    ReportCollapsibleSection(
                        title: "深度分析",
                        subtitle: "趋势、位置对比、关联图与指标结构",
                        systemImage: "chart.xyaxis.line",
                        isExpanded: $showDeepAnalysis
                    ) {
                        ReportDetailTrendCard(reportDate: reportDate, points: nearbyPoints, context: summary?.trendContext)
                        ReportDetailSevenDayPositionCard(
                            reportDate: reportDate,
                            summary: summary,
                            points: nearbyPoints
                        )
                        ReportMetricCompositeTrendCard(
                            title: "近 7 天指标上下文",
                            subtitle: "格子颜色统一表示状态分区：红色承压、黄色波动、蓝色稳定、绿色良好。",
                            points: nearbyPoints,
                            kinds: [.sleep, .stress, .hrv, .activity]
                        )
                        ReportDetailCorrelationChartCard(points: nearbyPoints)
                        ReportDetailSleepStressScatterCard(points: nearbyPoints)
                        metricsOverviewCard
                    }

                    // MARK: 生活上下文组（默认折叠）
                    ReportCollapsibleSection(
                        title: "生活上下文",
                        subtitle: "行为时间线、睡眠环境与轻养生复盘",
                        systemImage: "leaf.fill",
                        isExpanded: $showLifeContext
                    ) {
                        ReportDailyWellnessReviewCard(
                            summary: dailyWellnessSummary,
                            scoreBreakdown: dailyWellnessScoreBreakdown
                        )
                        ReportSleepEnvironmentInsightCard(
                            insight: sleepEnvironmentInsight,
                            isLoading: isSleepEnvironmentInsightLoading
                        )
                        ReportBehaviorTimelineReplayCard(
                            replay: timelineReplay ?? summary?.timelineReplay,
                            isLoading: isTimelineLoading
                        )
                        ReportDailyMetricBalanceCard(summary: summary)
                        ReportDetailMetricShareCard(summary: summary)
                    }

                    // MARK: 说明组（默认折叠）
                    ReportCollapsibleSection(
                        title: "说明与操作",
                        subtitle: "方法论、健康提示与分享",
                        systemImage: "info.circle.fill",
                        isExpanded: $showNotes
                    ) {
                        ReportDetailMethodologyCard(summary: summary, points: nearbyPoints)
                        HealthDisclaimerCard(
                            message: "报告用于帮助理解近期状态与生活节律，不用于疾病诊断、治疗或替代专业医疗建议。若指标持续异常或伴随不适，请及时咨询医生。",
                            title: "健康提示",
                            style: .compact,
                            strokeColor: ReportsEditorialStyle.border,
                            backgroundColor: Color.white
                        )
                        Button {
                            showingShareSheet = true
                        } label: {
                            ReportDetailFooterAction(
                                title: "分享此报告",
                                subtitle: "生成分享卡片并导出",
                                systemImage: "square.and.arrow.up",
                                isPrimary: true
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            AlertHistoryView(focusDate: reportDate)
                        } label: {
                            ReportDetailFooterAction(
                                title: "查看告警历史",
                                subtitle: "回溯异常提醒与建议",
                                systemImage: "bell.badge",
                                isPrimary: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .readingNavigationBarMinimization()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("眠屿")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "171717"))
            }
        }
        .task {
            viewModel.load(days: 30)
            loadDailyWellnessReview()
            await loadTimelineReplay()
            await loadSleepEnvironmentInsight()
        }
        .sheet(isPresented: $showingShareSheet) {
            ReportShareView(reportDate: reportDate, score: summary?.scoreValue ?? 0)
                .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.92), .large], dragIndicator: .hidden)
                .presentationCornerRadius(26)
                .presentationBackground(Color(hex: "F1F1EF"))
        }
    }

    private var nearbyPoints: [ReportDaySummary] {
        viewModel.nearbyPoints(for: reportDate)
    }

    private var recentAverageHrv: Double? {
        viewModel.recentAverageHrv(from: nearbyPoints, excluding: reportDate)
    }

    private var metricsOverviewCard: some View {
        ReportsContentCard(spacing: 10) {
            ReportsSectionHeader("分项概览", subtitle: "把睡眠、活动和压力放在同一个阅读节奏里。")

            VStack(spacing: 10) {
                ReportsSubsectionCard(
                    title: "睡眠",
                    subtitle: "时长与恢复基础",
                    metric: sleepMetric,
                    systemImage: "bed.double.fill",
                    tint: ReportMetricKind.sleep.tint
                )

                ReportsSubsectionCard(
                    title: "活动",
                    subtitle: "步数与身体唤醒",
                    metric: activityMetric,
                    systemImage: "figure.walk",
                    tint: ReportMetricKind.activity.tint
                )

                ReportsSubsectionCard(
                    title: "压力",
                    subtitle: "负荷与恢复空间",
                    metric: stressMetric,
                    systemImage: "brain.head.profile",
                    tint: ReportMetricKind.stress.tint
                )
            }
        }
    }

    private var sleepMetric: String {
        guard let value = summary?.sleepHours else { return String(localized: "暂无") }
        let hours = Int(value)
        let minutes = Int(((value - Double(hours)) * 60).rounded())
        return String(localized: "\(hours)小时\(minutes)分")
    }

    private var activityMetric: String {
        guard let value = summary?.steps else { return String(localized: "暂无") }
        return String(localized: "\(Int(value.rounded())) 步")
    }

    private var stressMetric: String {
        guard let value = summary?.stress else { return String(localized: "暂无") }
        return "\(Int(value.rounded()))"
    }

    @MainActor
    private func loadDailyWellnessReview() {
        let actionRecord = ActionRecordStore.shared.record(for: reportDate)
        let context = DailyWellnessEvaluationContext(
            waterMl: actionRecord.waterMl,
            sunlightMinutes: actionRecord.sunlightMinutes,
            mindfulnessMinutes: actionRecord.mindfulnessMinutes,
            standHours: actionRecord.standHours,
            actionRecord: actionRecord,
            now: Date()
        )
        _ = DailyWellnessStore.shared.refreshFromHealthData(on: reportDate, context: context)
        dailyWellnessSummary = DailyWellnessStore.shared.summary(endingAt: reportDate, days: 7)
    }

    @MainActor
    private func loadTimelineReplay() async {
        isTimelineLoading = true
        timelineReplay = await BehaviorTimelineReplayBuilder().build(for: reportDate)
        isTimelineLoading = false
    }

    @MainActor
    private func loadSleepEnvironmentInsight() async {
        isSleepEnvironmentInsightLoading = true
        let summaries = (try? await HealthKitManager.shared.fetchSleepNightSummaries(days: 2, endDate: reportDate)) ?? []
        let matchedNight = summaries.last(where: { Calendar.current.isDate($0.day, inSameDayAs: reportDate) }) ?? summaries.last
        sleepNightSummary = matchedNight
        sleepEnvironmentInsight = await SleepEnvironmentSnoreInsightBuilder().build(
            for: reportDate,
            snoreSummary: nil,
            sleepSummary: matchedNight
        )
        isSleepEnvironmentInsightLoading = false
    }
}


private struct ReportDetailHeroCard: View {
    let summary: ReportDaySummary?
    let subtitle: String
    let sleepNightSummary: SleepTrendNightSummary?

    private let reportGold = Color(hex: "EFB321")
    private let metricLavender = Color(hex: "F1EFFF")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "moon.stars.fill")
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(reportGold)

                    Text("每日健康分析")
                        .font(.appSystem(size: 27, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "191919"))
                }

            Text("\(subtitle) · 数据来源：Apple 健康")
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "8A8A8F"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 16)

            Divider()
                .overlay(Color(hex: "E9E9E7"))

            VStack(alignment: .leading, spacing: 14) {
                Text("健康概览")
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "7666C7"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(metricLavender, in: Capsule())

                Text(reportHeadline)
                    .font(.appSystem(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "191919"))
                    .fixedSize(horizontal: false, vertical: true)

                Text(reportNarrative)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "69696F"))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 16) {
                    scoreRing

                    VStack(alignment: .leading, spacing: 5) {
                        Text(sleepDurationText)
                            .font(.appSystem(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "151515"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.66)
                        Text("昨夜睡眠时长")
                            .font(Theme.Typography.label)
                            .foregroundColor(Color(hex: "85858A"))
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    metricTile(title: "入睡", value: bedtimeText)
                    metricTile(title: "醒来", value: wakeTimeText)
                    metricTile(title: "睡眠效率", value: efficiencyText)
                    metricTile(title: "夜间清醒", value: awakeText)
                }
            }
            .padding(.top, 16)
        }
        .healthDetailSurface(padding: 18)
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(reportGold.opacity(0.16), lineWidth: 8)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, summary?.score ?? 0))) / 100)
                .stroke(reportGold, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(summary?.score.map(String.init) ?? "--")
                    .font(.appSystem(size: 27, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "191919"))
                Text(statusText)
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "77777C"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("综合评分 \(summary?.score.map(String.init) ?? "暂无")，\(statusText)")
    }

    private var statusText: String {
        ReportScoreStatus.shortLabel(for: summary?.score)
    }

    private var reportHeadline: String {
        if let sleepHours = summary?.sleepHours, sleepHours < 6.5 {
            return String(localized: "睡眠偏短，今天更适合稳住节奏")
        }
        if let stress = summary?.stress, stress >= 65 {
            return String(localized: "压力偏高，恢复窗口需要保护")
        }
        guard let score = summary?.score else {
            return String(localized: "健康数据正在汇总中")
        }
        switch score {
        case 85...: return String(localized: "状态不错，恢复节奏比较完整")
        case 70..<85: return String(localized: "时间基本够，连续性还有提升空间")
        case 50..<70: return String(localized: "今天有些波动，先把恢复放前面")
        default: return String(localized: "身体正在承压，今天不宜继续透支")
        }
    }

    private var reportNarrative: String {
        if let headline = summary?.scoreBreakdown?.headline,
           let advice = summary?.adviceSummary?.summary {
            return "\(headline) \(advice)"
        }
        return summary?.scoreBreakdown?.headline
        ?? "同步更多睡眠、压力、HRV 与活动数据后，这里会生成更完整的恢复解释。"
    }

    private var sleepDurationText: String {
        let minutes: Int?
        if let sleepNightSummary, sleepNightSummary.asleepMinutes > 0 {
            minutes = sleepNightSummary.asleepMinutes
        } else if let hours = summary?.sleepHours {
            minutes = Int((hours * 60).rounded())
        } else {
            minutes = nil
        }
        guard let minutes else { return String(localized: "暂无睡眠数据") }
        return String(localized: "\(minutes / 60)小时\(minutes % 60)分钟")
    }

    private var bedtimeText: String {
        sleepNightSummary.map { timeText($0.startTime) } ?? "--"
    }

    private var wakeTimeText: String {
        sleepNightSummary.map { timeText($0.endTime) } ?? "--"
    }

    private var efficiencyText: String {
        sleepNightSummary?.efficiency.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
    }

    private var awakeText: String {
        sleepNightSummary.map { "\($0.awakeMinutes)分钟" } ?? "--"
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundColor(Color(hex: "85818F"))
            Text(value)
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1D1C22"))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(metricLavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private struct ReportDetailSleepArchitectureCard: View {
    let night: SleepTrendNightSummary

    private var stages: [StageItem] {
        [
            StageItem(title: "深睡", minutes: night.deepMinutes, tint: Color(hex: "3441D4")),
            StageItem(title: "REM", minutes: night.remMinutes, tint: Color(hex: "6D55D9")),
            StageItem(title: "浅睡", minutes: night.coreMinutes, tint: Color(hex: "4CA9D8")),
            StageItem(title: "清醒", minutes: night.awakeMinutes, tint: Color(hex: "D5D5D8"))
        ]
    }

    private var distributionStages: [StageItem] {
        stages.filter { $0.minutes > 0 }
    }

    private var totalMinutes: Int {
        max(1, stages.reduce(0) { $0 + max(0, $1.minutes) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("睡眠结构")
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "7666C7"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "F1EFFF"), in: Capsule())

                Spacer(minLength: 0)

                Text("共 \(durationText(night.asleepMinutes))")
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "88888D"))
            }

            Text("各阶段分布")
                .font(.appSystem(size: 19, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1B1B1D"))

            GeometryReader { geometry in
                let spacing = CGFloat(max(0, distributionStages.count - 1)) * 3
                let availableWidth = max(0, geometry.size.width - spacing)

                HStack(spacing: 3) {
                    ForEach(distributionStages) { stage in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(stage.tint)
                            .frame(width: availableWidth * CGFloat(stage.minutes) / CGFloat(totalMinutes))
                    }
                }
            }
            .frame(height: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stageAccessibilityText)

            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.appSystem(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "7666C7"))
                Text("\(timeText(night.startTime)) 入睡 · \(timeText(night.endTime)) 醒来")
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "77777C"))
            }

            Divider()
                .overlay(Theme.Colors.surfaceBorder)

            VStack(spacing: 10) {
                ForEach(stages) { stage in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(stage.tint)
                            .frame(width: 8, height: 8)

                        Text(stage.title)
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "29292C"))

                        Spacer(minLength: 0)

                        Text(durationText(stage.minutes))
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "55555A"))

                        Text(localizedPercentRatio(Double(stage.minutes) / Double(totalMinutes)))
                            .font(Theme.Typography.label)
                            .foregroundColor(stage.title == "清醒" ? Color(hex: "88888D") : stage.tint)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            Text(structureInsight)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "6E6E73"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 8)
    }

    private var structureInsight: String {
        if let efficiency = night.efficiency, efficiency < 0.85 {
            return String(localized: "总睡眠时间基本可读，但清醒时间占比较高，连续性仍有提升空间。今晚优先减少临睡前刺激，并尽量固定入睡窗口。")
        }
        if let deepRatio = night.deepRatio, deepRatio < 0.13 {
            return String(localized: "睡眠连续性尚可，但深睡占比偏少。恢复不算差，不过身体修复阶段仍可以通过更稳定的作息继续补足。")
        }
        if let remRatio = night.remRatio, remRatio < 0.18 {
            return String(localized: "整体时长较完整，但 REM 占比仍有空间。今天可以保持正常节奏，晚上避免过晚进食或高刺激活动。")
        }
        return String(localized: "睡眠时长与结构整体比较完整，深睡和 REM 都形成了有效恢复。今天可以正常推进安排，同时继续保持当前作息。")
    }

    private var stageAccessibilityText: String {
        stages.map { "\($0.title) \(durationText($0.minutes))" }.joined(separator: "，")
    }

    private func durationText(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        if safeMinutes >= 60 {
            return String(localized: "\(safeMinutes / 60)小时\(safeMinutes % 60)分钟")
        }
        return String(localized: "\(safeMinutes)分钟")
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private struct StageItem: Identifiable {
        var id: String { title }
        let title: String
        let minutes: Int
        let tint: Color
    }
}


private struct ReportDetailBreakdownCard: View {
    let breakdown: ReportScoreBreakdown?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ReportsContentCard {
            ReportsSectionHeader("为什么是这个分数", subtitle: "把睡眠、压力、HRV 和活动拆开看，更容易知道今天的问题主要出在哪。")

            if let breakdown {
                ReportScoreContributionBarChart(items: breakdown.items)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(breakdown.items) { item in
                        ReportContributionTile(item: item)
                    }
                }
            } else {
                ReportsInlineEmptyState(text: "当前还没有足够样本来生成原因拆解。")
            }
        }
    }
}

private struct ReportScoreContributionBarChart: View {
    let items: [ReportScoreContribution]

    private var chartItems: [ReportScoreContribution] {
        items.filter { $0.score != nil }
    }

    var body: some View {
        if chartItems.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("分项贡献")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.ink)
                    Spacer()
                Text("0-100 状态分")
                        .font(Theme.Typography.label)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Chart {
                    ForEach(chartItems) { item in
                        BarMark(
                            x: .value("分数", item.score ?? 0),
                            y: .value("指标", item.kind.title)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [item.kind.tint.opacity(0.58), item.kind.tint.opacity(0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(5)
                    }

                    RuleMark(x: .value("参考线", 70))
                        .reportsStabilityRule()
                }
                .frame(height: CGFloat(max(120, chartItems.count * 34)))
                .chartXScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                        AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(ReportsChartStyle.axisLabel)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(ReportsChartStyle.plotBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(13)
            .background(ReportsEditorialStyle.neutralPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ReportsEditorialStyle.border, lineWidth: 1)
            )
        }
    }
}

private struct ReportContributionTile: View {
    let item: ReportScoreContribution

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.kind.tint.opacity(0.12))
                    Image(systemName: item.kind.systemImage)
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(item.kind.tint)
                }
                .frame(width: 36, height: 36)

                Spacer(minLength: 8)

                Text(item.tone.title)
                    .font(Theme.Typography.label)
                    .foregroundColor(item.kind.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(item.kind.tint.opacity(0.12), in: Capsule())
            }

            Text(item.kind.title)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(ReportsEditorialStyle.ink)

            Text(item.score.map { "\($0)分" } ?? item.valueText)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(item.score == nil ? Theme.Colors.textTertiary : ReportsEditorialStyle.ink)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white)

                    Capsule(style: .continuous)
                        .fill(item.kind.tint.opacity(0.82))
                        .frame(width: item.score.map { geometry.size.width * CGFloat($0) / 100.0 } ?? 0)
                }
            }
            .frame(height: 8)

            Text(item.detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(ReportsEditorialStyle.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReportsEditorialStyle.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReportsEditorialStyle.lavenderAccent.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ReportDetailRecoveryPlanCard: View {
    let summary: ReportDaySummary?
    let wellnessSummary: DailyWellnessSummary
    let wellnessScoreBreakdown: DailyWellnessScoreBreakdown

    private var steps: [RecoveryStep] {
        let adviceItems = summary?.adviceSummary?.actionItems ?? []
        let pendingAction = nextPendingWellnessActionTitle
        return [
            RecoveryStep(
                time: "上午",
                title: morningTitle,
                detail: adviceItems.first ?? "先用低负担方式启动今天，避免一上来就把压力推高。",
                systemImage: "sunrise.fill",
                tint: Color(hex: "F3A53B")
            ),
            RecoveryStep(
                time: "下午",
                title: afternoonTitle,
                detail: adviceItems.dropFirst().first ?? "安排一次轻量补水、短走或站立，把精神状态重新拉回可控区间。",
                systemImage: "figure.walk",
                tint: Theme.Colors.mintGreen
            ),
            RecoveryStep(
                time: "晚上",
                title: eveningTitle,
                detail: pendingAction.map { "把「\($0)」补上，再提前收尾，给睡眠恢复留出空间。" } ?? adviceItems.dropFirst(2).first ?? "今晚重点是提前降刺激，尽量让睡眠窗口完整一些。",
                systemImage: "moon.stars.fill",
                tint: ReportsEditorialStyle.lavenderAccent
            )
        ]
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("今日恢复计划", subtitle: "先明确今天的恢复重点，再按早、中、晚三步执行。")

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(planTitle)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.ink)
                    Text(planSummary)
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(summary?.adviceSummary?.priorityText ?? "轻恢复")
                    .font(Theme.Typography.label)
                    .foregroundColor(ReportsEditorialStyle.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(ReportsEditorialStyle.warmGoldSoft, in: Capsule())
            }
            .padding(14)
            .background(ReportsEditorialStyle.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                ReportsCompactMetricPill(title: "优先项", value: priorityText, tint: priorityTint)
                ReportsCompactMetricPill(title: "轻养生", value: "\(wellnessSummary.todayCompletedCount)/5", tint: Theme.Colors.mintGreen)
                ReportsCompactMetricPill(title: "恢复分", value: "\(wellnessScoreBreakdown.totalScore)", tint: ReportsScorePalette.tint(for: summary?.score))
            }

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    planRow(step)

                    if index < steps.count - 1 {
                        Divider()
                            .overlay(ReportsEditorialStyle.border)
                            .padding(.leading, 50)
                    }
                }
            }
        }
    }

    private var planTitle: String {
        summary?.adviceSummary?.title ?? "先稳住今天的恢复节奏"
    }

    private var planSummary: String {
        summary?.adviceSummary?.summary
        ?? "当前样本还不完整，先用低负担方式安排今天，继续同步后会给出更具体的恢复重点。"
    }

    private var priorityText: String {
        summary?.scoreBreakdown?.leadingNegative?.kind.title
        ?? summary?.adviceSummary?.priorityText
        ?? "轻恢复"
    }

    private var priorityTint: Color {
        summary?.scoreBreakdown?.leadingNegative?.kind.tint
        ?? summary?.adviceSummary?.tint
        ?? Theme.Colors.mintGreen
    }

    private var nextPendingWellnessActionTitle: String? {
        DailyWellnessActionKind.allCases.first { !wellnessSummary.todayRecord.isCompleted($0) }?.definition.title
    }

    private var morningTitle: String {
        switch summary?.scoreBreakdown?.leadingNegativeKind {
        case .some(.sleep): return String(localized: "先保护恢复窗口")
        case .some(.stress): return String(localized: "先降压力启动")
        case .some(.hrv): return String(localized: "先轻量过渡")
        case .some(.activity): return String(localized: "先把身体唤醒")
        case .none: return String(localized: "先稳住节奏")
        }
    }

    private var afternoonTitle: String {
        switch summary?.scoreBreakdown?.leadingNegativeKind {
        case .some(.activity): return String(localized: "补一段轻活动")
        case .some(.stress): return String(localized: "切一次低刺激休息")
        case .some(.sleep), .some(.hrv): return String(localized: "避免继续透支")
        case .none: return String(localized: "做一次状态校准")
        }
    }

    private var eveningTitle: String {
        switch summary?.scoreBreakdown?.leadingNegativeKind {
        case .some(.sleep): return String(localized: "提前收尾入睡")
        case .some(.stress): return String(localized: "把刺激降下来")
        case .some(.hrv): return String(localized: "把恢复窗口留足")
        case .some(.activity): return String(localized: "轻拉伸后收尾")
        case .none: return String(localized: "给明天留余量")
        }
    }

    private func planRow(_ step: RecoveryStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(step.tint.opacity(0.13))
                    Image(systemName: step.systemImage)
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(step.tint)
                }
                .frame(width: 38, height: 38)
                Text(step.time)
                    .font(Theme.Typography.label)
                    .foregroundColor(step.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.ink)
                Text(step.detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private struct RecoveryStep: Identifiable {
        var id: String { time }
        let time: String
        let title: String
        let detail: String
        let systemImage: String
        let tint: Color
    }
}

private struct ReportDailyWellnessReviewCard: View {
    let summary: DailyWellnessSummary
    let scoreBreakdown: DailyWellnessScoreBreakdown

    private var scoreProgress: CGFloat {
        min(1, max(0, CGFloat(scoreBreakdown.totalScore) / 100))
    }

    private var completedKinds: [DailyWellnessActionKind] {
        DailyWellnessActionKind.allCases.filter { summary.todayRecord.isCompleted($0) }
    }

    private var pendingKinds: [DailyWellnessActionKind] {
        DailyWellnessActionKind.allCases.filter { !summary.todayRecord.isCompleted($0) }
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("轻养生复盘", subtitle: "把轻动作、综合压力和 HRV 放在一起看，恢复不是只靠打卡。")

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(ReportsEditorialStyle.warmGoldSoft, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: scoreProgress)
                        .stroke(
                            ReportsEditorialStyle.warmGold,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(scoreBreakdown.totalScore)")
                            .font(.appSystem(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(ReportsEditorialStyle.ink)
                        Text("分")
                            .font(Theme.Typography.label)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(scoreBreakdown.levelTitle) · 连续 \(summary.streak) 天")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.ink)
                    Text(scoreBreakdown.explanation)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                wellnessMetricPill(title: "今日完成", value: "\(summary.todayCompletedCount)/5")
                wellnessMetricPill(title: "压力贡献", value: "\(Int(scoreBreakdown.pressureComponent.rounded()))/25")
                wellnessMetricPill(title: "HRV贡献", value: "\(Int(scoreBreakdown.hrvComponent.rounded()))/15")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("今日动作")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                if completedKinds.isEmpty {
                    ReportsInlineEmptyState(text: "今天还没有目标动作记录，可以从目标页先完成一个最轻的。")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(completedKinds, id: \.self) { kind in
                            wellnessActionChip(kind: kind, isCompleted: true)
                        }
                        ForEach(pendingKinds.prefix(5 - completedKinds.count), id: \.self) { kind in
                            wellnessActionChip(kind: kind, isCompleted: false)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("最近 7 天")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                if summary.weeklyDays.isEmpty {
                    ReportsInlineEmptyState(text: "最近 7 天还没有轻养生图表样本。")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("柱色和底色表示评分状态")
                            .font(Theme.Typography.label)
                            .foregroundColor(Theme.Colors.textTertiary)
                        ReportsScoreBandLegend()
                        BBChartLegendItem(
                            title: "完成动作数（每项折算 20 分）",
                            tint: Color(hex: "8E6CFF"),
                            symbol: .system("diamond.fill")
                        )
                    }

                    Chart {
                        reportsScoreZoneBands()

                        ForEach(summary.weeklyDays) { day in
                            BarMark(
                                x: .value("日期", day.date),
                                y: .value("目标分", day.score)
                            )
                            .reportsScoreBar(tint: dayTint(score: day.score))

                            PointMark(
                                x: .value("日期", day.date),
                                y: .value("完成数", min(100, day.completedCount * 20))
                            )
                            .foregroundStyle(Color(hex: "8E6CFF"))
                            .symbol(.diamond)
                            .symbolSize(38)
                        }

                        RuleMark(y: .value("稳定参考", 70))
                            .reportsStabilityRule()
                    }
                    .reportsScoreChartFrame(height: 150)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                            AxisGridLine().foregroundStyle(ReportsChartStyle.grid)
                            AxisValueLabel(format: .dateTime.day())
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(ReportsChartStyle.axisLabel)
                        }
                    }
                }

                Text(summary.reviewText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(ReportsEditorialStyle.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ReportsEditorialStyle.lavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func wellnessMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(ReportsEditorialStyle.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ReportsEditorialStyle.lavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func wellnessActionChip(kind: DailyWellnessActionKind, isCompleted: Bool) -> some View {
        let definition = kind.definition
        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : definition.symbol)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(isCompleted ? Theme.Colors.mintGreen : Color(hex: definition.tintHex))
            Text(definition.title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(isCompleted ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background((isCompleted ? Theme.Colors.mintGreen : Color(hex: definition.tintHex)).opacity(isCompleted ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dayTint(score: Int) -> Color {
        ReportsScorePalette.tint(for: score)
    }
}

private struct ReportDetailMetricShareCard: View {
    let summary: ReportDaySummary?

    private var items: [MetricShareItem] {
        guard let summary else { return [] }
        return ReportMetricKind.allCases.compactMap { kind in
            guard let value = ReportMetricFormatter.normalizedValue(for: kind, in: summary) else { return nil }
            return MetricShareItem(
                kind: kind,
                value: max(1, value),
                rawValueText: ReportMetricFormatter.rawValueText(for: kind, in: summary)
            )
        }
    }

    private var totalValue: Double {
        max(1, items.map(\.value).reduce(0, +))
    }

    var body: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("当天结构占比", subtitle: "看睡眠、压力、HRV 和活动在今天状态结构里的相对权重。")

            if items.isEmpty {
                ReportsInlineEmptyState(text: "当前还没有足够指标样本生成结构占比图")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(Int(totalValue.rounded()))")
                            .font(.appSystem(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(ReportsEditorialStyle.ink)
                        Text("结构总分")
                            .font(Theme.Typography.label)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Spacer()
                    }

                    GeometryReader { proxy in
                        HStack(spacing: 3) {
                            ForEach(items) { item in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(item.kind.tint)
                                    .frame(width: max(12, proxy.size.width * CGFloat(item.value / totalValue)))
                            }
                        }
                    }
                    .frame(height: 24)
                    .background(ReportsEditorialStyle.neutralPanel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(ReportsEditorialStyle.border, lineWidth: 1)
                    )

                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.kind.tint)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.kind.title)
                                            .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                            .foregroundColor(ReportsEditorialStyle.ink)
                                        Spacer()
                                        Text(shareText(for: item))
                                            .font(Theme.Typography.label)
                                            .foregroundColor(item.kind.tint)
                                    }
                                    Text("\(Int(item.value.rounded())) · \(item.rawValueText)")
                                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.Colors.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func shareText(for item: MetricShareItem) -> String {
        guard totalValue > 0 else { return "--" }
        return "\(Int((item.value / totalValue * 100).rounded()))%"
    }

    private struct MetricShareItem: Identifiable {
        let kind: ReportMetricKind
        let value: Double
        let rawValueText: String

        var id: String { kind.rawValue }
    }
}

private struct ReportSleepEnvironmentInsightCard: View {
    let insight: SleepEnvironmentSnoreInsight?
    let isLoading: Bool

    var body: some View {
        ReportsContentCard {
            ReportsSectionHeader("睡眠环境与鼾声协同", subtitle: "把环境音、鼾声和夜间中断放在一起看，更容易判断昨夜恢复到底被什么拖慢。")

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color(hex: "F28B54"))
                    Text("正在整理睡眠环境与鼾声的联动分析…")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 8)
            } else if let insight {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(insight.headline)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(ReportsEditorialStyle.ink)
                        Spacer(minLength: 0)
                        Text(insight.tone == .elevated ? "重点关注" : (insight.tone == .caution ? "存在干扰" : "可继续观察"))
                            .font(Theme.Typography.label)
                            .foregroundColor(insight.tone.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(insight.tone.tint.opacity(0.12), in: Capsule())
                    }

                    Text(insight.summary)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(ReportsEditorialStyle.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        metricRow(title: "环境音量", value: insight.environmentLabel, tint: Color(hex: "75C7E8"))
                        metricRow(title: "鼾声概览", value: insight.snoreLabel, tint: Color(hex: "F28B54"))
                        metricRow(title: "阶段关联", value: insight.stageLinkText, tint: Color(hex: "57C7B6"))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("建议")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                        ForEach(insight.suggestions, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(insight.tone.tint)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(ReportsEditorialStyle.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !insight.coverageFlags.isEmpty {
                        Text(insight.coverageFlags.joined(separator: " · "))
                            .font(Theme.Typography.supporting)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ReportsInlineEmptyState(text: "暂时还没有足够环境或睡眠样本，无法形成完整协同分析。")
            }
        }
    }

    private func metricRow(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundColor(tint)
            Text(value)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReportsSubsectionCard: View {
    let title: String
    let subtitle: String
    let metric: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.appSystem(size: 18, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(.headline, design: .default))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(.subheadline, design: .default))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            Text(metric)
                .font(.appSystem(.headline, design: .default))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(14)
        .background(ReportsEditorialStyle.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReportsEditorialStyle.border, lineWidth: 1)
        )
    }
}

// MARK: - 可折叠卡片组

/// 报告详情页的可折叠卡片组容器
/// 将多张卡片按逻辑分组，支持展开/折叠，降低信息密度。
private struct ReportCollapsibleSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "7B8794"))
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.appSystem(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(subtitle)
                            .font(Theme.Typography.supporting)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "B0B5BC"))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        ReportDetailView(reportDate: Date(), initialSummary: nil)
    }
}
