/// TrendCategoryDetailView 由趋势首页分类入口调用，作为「趋势分类详情」路由页。
/// 负责按分类分发到不同详情模块，并管理周期数据与运动刷新。

import SwiftUI
import Charts
import UIKit

// 趋势二级详情页的统一路由落点。
// 这里按分类分发到不同详情模块，让首页文件只负责首页布局和入口。
/// 趋势分类视图 由上级页面或路由调用，作为趋势模块里的界面或内容组件。
/// 负责趋势分析展示。
struct TrendCategoryDetailView: View {
    let detail: TrendCategoryDetailModel
    let range: TrendsRange
    @Bindable var periodViewModel: PeriodViewModel
    let onPeriodDataChanged: () -> Void
    @State private var reproductiveSelectedDate: Date?
    @State private var workoutRefreshSecondaryMetrics: [WorkoutRecordDetailPresentation.SecondaryMetric]? = nil
    @State private var workoutRefreshSummary: String? = nil
    @State private var workoutRefreshStatus: TrendCategoryStatus? = nil
    @State private var workoutRequestedSummaries: [WorkoutDaySummary]? = nil
    @State private var workoutRequestedSessions: [WorkoutSessionSummary]? = nil
    @State private var workoutRecentSessionContext: WorkoutSessionSummary?
    @State private var workoutIsLoading = true
    @State private var symptomsMaintenanceTarget: SymptomsIllnessMaintenanceTarget?

    private var rangeTitle: String {
        switch range {
        case .day: return "日趋势"
        case .week: return "周趋势"
        case .month: return "月趋势"
        }
    }

    private var resolvedStatus: TrendCategoryStatus {
        if detail.category == .workoutsTraining, let workoutRefreshStatus {
            return workoutRefreshStatus
        }

        if detail.category == .sleepRecovery {
            let combinedMetrics = detail.sleepCoreMetrics + detail.sleepRecoveryMetrics
            if combinedMetrics.contains(where: { $0.status == .ready || $0.status == .partial || !$0.points.isEmpty }) {
                return combinedMetrics.first(where: { $0.status == .ready || $0.status == .partial || !$0.points.isEmpty })?.status ?? .ready
            }
            return detail.status
        }

        if detail.metrics.contains(where: { $0.status == .ready || $0.status == .partial || !$0.points.isEmpty }) {
            return detail.metrics.first(where: { $0.status == .ready || $0.status == .partial || !$0.points.isEmpty })?.status ?? .ready
        }

        return detail.status
    }

    private var effectiveHeaderSummary: String {
        if detail.category == .workoutsTraining, let workoutRefreshSummary {
            return workoutRefreshSummary
        }
        return detail.headerSummary
    }

    private var effectiveWorkoutSecondaryMetrics: [WorkoutRecordDetailPresentation.SecondaryMetric] {
        workoutRefreshSecondaryMetrics ?? []
    }

    private var showsSharedHero: Bool {
        switch detail.category {
        case .bodyMetrics, .workoutsTraining, .nutritionHydration, .symptomsIllness:
            return false
        default:
            return true
        }
    }

    private var resolvedStatusTitle: String {
        resolvedStatus.title
    }

    private var overviewDisplayStatusTitle: String {
        switch resolvedStatus {
        case .ready:
            return resolvedStatus.title
        case .partial:
            return String(localized: "数据积累中")
        case .noData:
            return String(localized: "暂无记录")
        }
    }

    private var overviewDisplayStatusTint: Color {
        switch resolvedStatus {
        case .ready:
            return resolvedStatus.tint
        case .partial:
            return Color(hex: "FFB340")
        case .noData:
            return Theme.Colors.textTertiary
        }
    }

    private func overviewFallbackMessage(for metric: TrendCategoryMetricModel) -> String {
        switch metric.status {
        case .noData:
            return String(localized: "暂时还没有可展示的趋势数据，继续记录或稍后再看这里会自动更新。")
        case .partial:
            return String(localized: "当前样本还在积累中，继续同步后这里会逐步形成更完整的趋势。")
        case .ready:
            return metric.emptyMessage
        }
    }

    private var detailLayout: some View {
        ZStack {
            HealthDetailPageBackground(
                topGlow: Color(hex: "C4DFF7"),
                lowerGlow: Color(hex: "D5ECE7")
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if showsSharedHero {
                        detailHeroCard
                    }

                    if detail.category == .sleepRecovery {
                        AnyView(Group {
                        exportableDetailSection(
                            title: "核心睡眠趋势",
                            subtitle: "关注时长、规律性、深睡占比、REM 占比与睡眠效率的连续变化。",
                            statusTitle: resolvedStatusTitle,
                            summary: "汇总时长、规律性、深睡占比、REM 占比与睡眠效率等核心指标。",
                            filePrefix: "sleep-core-metrics",
                            showsModuleHeader: false,
                            wrapsInCard: false
                        ) {
                            VStack(spacing: 14) {
                                ForEach(detail.sleepCoreMetrics) { metric in
                                    SleepCoreMetricTrendCard(
                                        metric: metric,
                                        range: range,
                                        nightSummaries: detail.sleepNightSummaries,
                                        sleepStages: detail.sleepStages,
                                        sleepCompositeScores: detail.sleepCompositeScores
                                    )
                                }
                            }
                        } exportContent: {
                            VStack(spacing: 14) {
                                ForEach(detail.sleepCoreMetrics) { metric in
                                    SleepCoreMetricTrendCard(
                                        metric: metric,
                                        range: range,
                                        nightSummaries: detail.sleepNightSummaries,
                                        sleepStages: detail.sleepStages,
                                        sleepCompositeScores: detail.sleepCompositeScores,
                                        isStaticForExport: true
                                    )
                                }
                            }
                        }

                    exportableDetailSection(
                        title: "恢复关联指标",
                        subtitle: "结合睡眠 HRV、夜间心率、呼吸频率与睡眠结构，评估睡眠恢复是否同步改善。",
                        statusTitle: resolvedStatusTitle,
                        summary: "结合睡眠 HRV、夜间心率与呼吸频率等指标，判断睡眠变化是否转化为恢复获益。",
                        filePrefix: "sleep-recovery-metrics",
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        VStack(spacing: 14) {
                            ForEach(detail.sleepRecoveryMetrics) { metric in
                                SleepCoreMetricTrendCard(
                                    metric: metric,
                                    range: range,
                                    nightSummaries: detail.sleepNightSummaries,
                                    sleepStages: detail.sleepStages,
                                    sleepCompositeScores: detail.sleepCompositeScores
                                )
                            }
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            ForEach(detail.sleepRecoveryMetrics) { metric in
                                SleepCoreMetricTrendCard(
                                    metric: metric,
                                    range: range,
                                    nightSummaries: detail.sleepNightSummaries,
                                    sleepStages: detail.sleepStages,
                                    sleepCompositeScores: detail.sleepCompositeScores,
                                    isStaticForExport: true
                                )
                            }
                        }
                    }

                    if !detail.sleepRecoveryMetrics.isEmpty {
                        exportableDetailSection(
                            title: "恢复基线",
                            subtitle: "聚焦睡眠 HRV、夜间心率与呼吸频率的近期趋势，判断恢复储备与夜间负荷是否同步改善。",
                            statusTitle: resolvedStatusTitle,
                            summary: "把睡眠 HRV、夜间心率与呼吸频率放在一起，更适合判断恢复反馈是否真正变好。",
                            filePrefix: "sleep-recovery-baseline",
                            showsModuleHeader: false
                        ) {
                            SleepRecoveryBaselineCard(metrics: detail.sleepRecoveryMetrics)
                        } exportContent: {
                            SleepRecoveryBaselineCard(metrics: detail.sleepRecoveryMetrics, isStaticForExport: true)
                        }
                    }

                        })
                    } else if detail.category == .reproductive, let reproductive = detail.reproductiveDetail {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "周期趋势",
                        subtitle: "把阶段变化、预测窗口和近期主观记录放在一起读，更容易识别最近的周期节律。",
                        statusTitle: resolvedStatusTitle,
                        summary: "该模块联合展示阶段变化、预测窗口与近期记录趋势。",
                        filePrefix: "reproductive-trend"
                    ) {
                        PeriodTrendChartCard(
                            summary: periodViewModel.summary ?? reproductive.summary,
                            range: range,
                            selectedDate: $reproductiveSelectedDate,
                            visualStyle: .airy
                        )
                    } exportContent: {
                        PeriodTrendChartCard(
                            summary: periodViewModel.summary ?? reproductive.summary,
                            range: range,
                            selectedDate: .constant(nil),
                            isStaticForExport: true,
                            visualStyle: .airy
                        )
                    }

                    exportableDetailSection(
                        title: "专项事件",
                        subtitle: "把检测结果、身体信号和行为记录单独拎出来，更适合快速查看这段时间出现过哪些关键周期事件。",
                        statusTitle: periodViewModel.recentLogs.isEmpty ? "暂无记录" : "已整理",
                        summary: "该模块单独汇总妊娠测试、排卵测试、性行为、点滴出血与宫颈黏液等专项事件。",
                        filePrefix: "reproductive-events"
                    ) {
                        ReproductiveEventSummaryCard(viewModel: periodViewModel)
                    } exportContent: {
                        ReproductiveEventSummaryCard(viewModel: periodViewModel)
                    }

                    exportableDetailSection(
                        title: "临床解读",
                        subtitle: "基于当前阶段、窗口提示与近期体感记录，提炼这段时间最值得关注的周期信号。",
                        statusTitle: resolvedStatusTitle,
                        summary: reproductive.cycleStatusText,
                        filePrefix: "reproductive-insights"
                    ) {
                        VStack(spacing: 14) {
                            ReproductiveInsightSummaryCard(detail: reproductive)
                            ForEach(reproductive.insightItems) { item in
                                ReproductiveInsightCard(item: item)
                            }
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            ReproductiveInsightSummaryCard(detail: reproductive)
                            ForEach(reproductive.insightItems) { item in
                                ReproductiveInsightCard(item: item)
                            }
                        }
                    }

                    exportableDetailSection(
                        title: "近期回顾",
                        subtitle: "保留近期记录摘要，方便把阶段变化和最近几次体感体验对照阅读。",
                        statusTitle: periodViewModel.recentLogs.isEmpty ? "暂无记录" : "已记录",
                        summary: "该模块汇总最近几次周期记录、痛经程度与情绪变化。",
                        filePrefix: "reproductive-recent-logs"
                    ) {
                        ReproductiveRecentLogsCard(viewModel: periodViewModel)
                    } exportContent: {
                        ReproductiveRecentLogsCard(viewModel: periodViewModel)
                    }

                    exportableDetailSection(
                        title: "补充记录",
                        subtitle: "可从此进入统一周期健康记录，页面会按进行中的孕期自动展示经期或孕期内容。",
                        statusTitle: "操作入口",
                        summary: "提供统一周期健康记录入口，方便补充当前阶段数据。",
                        filePrefix: "reproductive-entry"
                    ) {
                        NavigationLink {
                            ReproductiveHealthRecordView(
                                periodViewModel: periodViewModel,
                                initialSection: .period
                            )
                            .onDisappear {
                                periodViewModel.reload(days: 90)
                                onPeriodDataChanged()
                            }
                        } label: {
                            ReproductiveReadOnlyEntryCard(
                                predictionHint: periodViewModel.predictionHint,
                                latestLogDate: periodViewModel.recentLogs.first?.date.map(periodViewModel.displayDay)
                            )
                        }
                        .buttonStyle(.plain)
                    } exportContent: {
                        ReproductiveReadOnlyEntryCard(
                            predictionHint: periodViewModel.predictionHint,
                            latestLogDate: periodViewModel.recentLogs.first?.date.map(periodViewModel.displayDay)
                        )
                    }

                        })
                    } else if detail.category == .heartCardio {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "核心心率趋势",
                        subtitle: "继续下钻心率、静息心率、心率变异性与步行平均心率，判断是整体负荷上浮、恢复变差，还是轻活动反应偏高。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "heart-cardio-metrics",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                // 心率健康页详情趋势统一参考睡眠恢复的专项图表结构，保持阅读方式一致。
                                HeartHealthMetricTrendCard(metric: metric, range: range)
                            }
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                // 导出态也保持与页面内一致的心率专项图表结构，避免首页与详情口径割裂。
                                HeartHealthMetricTrendCard(metric: metric, range: range, isStaticForExport: true)
                            }
                        }
                    }

                    // 单指标趋势回答“各自怎么变”，联合分析进一步回答“它们是否同步变化”。
                    // 这里直接复用已加载的心率指标，不额外读取 HealthKit，也不生成模拟数据。
                    exportableDetailSection(
                        title: "联合分析",
                        subtitle: "把 HRV、静息心率与日常心率放到共同的时间和基线尺度中，辅助识别同步变化。",
                        statusTitle: resolvedStatusTitle,
                        summary: "通过配对散点与基线偏离叠图，观察心率负荷和恢复弹性是否在同一时段共同变化。",
                        filePrefix: "heart-cardio-relationships",
                        showsSummary: false,
                        wrapsInCard: false
                    ) {
                        VStack(spacing: 14) {
                            HeartMetricRelationshipChartCard(metrics: detail.metrics, range: range)
                            HeartBaselineDeviationChartCard(metrics: detail.metrics, range: range)
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            HeartMetricRelationshipChartCard(
                                metrics: detail.metrics,
                                range: range,
                                isStaticForExport: true
                            )
                            HeartBaselineDeviationChartCard(
                                metrics: detail.metrics,
                                range: range,
                                isStaticForExport: true
                            )
                        }
                    }

                    if let ecgSummary = detail.heartECGSummary {
                        exportableDetailSection(
                            title: "心电图（ECG）",
                            subtitle: "参考健康 App 的阅读结构，结合最近一次 ECG 结论、关键参数与波形预览理解离散节律记录。",
                            statusTitle: ecgSummary.status.title,
                            summary: ecgSummary.detail,
                            filePrefix: "heart-cardio-ecg",
                            showsModuleHeader: false
                        ) {
                            HeartECGSection(summary: ecgSummary, records: detail.heartECGRecords)
                        } exportContent: {
                            HeartECGSection(summary: ecgSummary, records: detail.heartECGRecords)
                        }
                    }

                    if let monitorSummary = detail.heartClinicalMonitorSummary {
                        exportableDetailSection(
                            title: "监测与告警",
                            subtitle: "把房颤历史、高心率通知、高血压通知、血压和逐搏测量放在一起，更适合做临床监测补充阅读。",
                            statusTitle: resolvedStatusTitle,
                            summary: monitorSummary.detail,
                            filePrefix: "heart-cardio-monitoring",
                            showsModuleHeader: false
                        ) {
                            HeartClinicalMonitoringSection(summary: monitorSummary)
                        } exportContent: {
                            HeartClinicalMonitoringSection(summary: monitorSummary)
                        }
                    }
                        })
                    } else if detail.category == .dailyActivity {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "步速趋势",
                        subtitle: "继续下钻步行速度、步数和步行距离，判断最近移动效率是在回落、改善，还是只是短期波动。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "walking-speed-metrics",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                TrendCategoryMetricCard(
                                    metric: metric,
                                    range: range,
                                    category: detail.category
                                )
                            }
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                TrendCategoryMetricCard(
                                    metric: metric,
                                    range: range,
                                    category: detail.category,
                                    isStaticForExport: true
                                )
                            }
                        }
                    }
                        })
                    } else if detail.category == .bodyMetrics {
                        AnyView(Group {
                    MyWeightDashboardView(metrics: detail.metrics, initialRange: range)
                        })
                    } else if detail.category == .mobilityGait {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "步态行动趋势",
                        subtitle: "继续下钻步幅、速度、平衡、双足支撑、稳定性和负荷几条主线，判断变化是偶发波动还是已经形成连续偏移。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "mobility-gait-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                TrendCategoryMetricCard(
                                    metric: metric,
                                    range: range,
                                    category: detail.category
                                )
                            }
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                TrendCategoryMetricCard(
                                    metric: metric,
                                    range: range,
                                    category: detail.category,
                                    isStaticForExport: true
                                )
                            }
                        }
                    }

                        })
                    } else if detail.category == .vitalsRespiratory {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "生命体征趋势",
                        subtitle: "继续下钻呼吸率、血氧和腕温，判断变化是零星出现还是正在持续偏离个人基线。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "vitals-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                TrendCategoryMetricCard(metric: metric, range: range, category: detail.category)
                            }
                        }
                    } exportContent: {
                        VStack(spacing: 14) {
                            ForEach(detail.metrics) { metric in
                                TrendCategoryMetricCard(metric: metric, range: range, category: detail.category, isStaticForExport: true)
                            }
                        }
                    }
                        })
                    } else if detail.category == .runningDynamics {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "跑步趋势",
                        subtitle: "继续下钻跑量与节奏变化，判断最近是跑量在连续累积，还是配速和输出开始波动。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "running-dynamics-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        RunningDynamicsDetailContent(detail: detail, range: range)
                    } exportContent: {
                        RunningDynamicsDetailContent(detail: detail, range: range, isStaticForExport: true)
                    }
                        })
                    } else if detail.category == .cyclingStats {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "骑行表现",
                        subtitle: "继续下钻骑行量与节奏变化，判断最近是骑行量在连续累积，还是速度和输出开始波动。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "cycling-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        CyclingDetailContent(detail: detail, range: range)
                    } exportContent: {
                        CyclingDetailContent(detail: detail, range: range, isStaticForExport: true)
                    }
                        })
                    } else if detail.category == .swimmingWater {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "游泳趋势",
                        subtitle: "继续下钻游泳量与节奏变化，判断最近是游泳量在连续累积，还是速度和输出开始波动。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "swimming-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        SwimmingDetailContent(detail: detail, range: range)
                    } exportContent: {
                        SwimmingDetailContent(detail: detail, range: range, isStaticForExport: true)
                    }
                        })
                    } else if detail.category == .workoutsTraining {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "健身记录",
                        subtitle: "继续下钻训练总时长和训练次数，判断训练量是稳步堆起来，还是阶段性缺口变大。",
                        statusTitle: resolvedStatusTitle,
                        summary: effectiveHeaderSummary,
                        filePrefix: "workouts-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        WorkoutRecordDetailContent(
                            presentation: workoutRecordPresentation,
                            requestedRange: range,
                            isLoading: workoutIsLoading
                        )
                    } exportContent: {
                        WorkoutRecordDetailContent(
                            presentation: workoutRecordPresentation,
                            requestedRange: range,
                            isStaticForExport: true,
                            isLoading: workoutIsLoading
                        )
                    }
                        })
                    } else if detail.category == .environmentSenses {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "环境感官",
                        subtitle: "继续下钻日照和声音暴露，判断输入是偶发偏高，还是已经形成持续刺激环境。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "environment-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        EnvironmentDetailContent(detail: detail, range: range)
                    } exportContent: {
                        EnvironmentDetailContent(detail: detail, range: range, isStaticForExport: true)
                    }
                        })
                    } else if detail.category == .nutritionHydration {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "营养摄入",
                        subtitle: "继续下钻饮水、达标率和咖啡因残留，判断补水节奏是规律保持，还是出现断续和偏移。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "nutrition-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        NutritionDetailContent(detail: detail, range: range)
                    } exportContent: {
                        NutritionDetailContent(detail: detail, range: range, isStaticForExport: true)
                    }
                        })
                    } else if detail.category == .mindfulnessMental {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "心理正念",
                        subtitle: "继续下钻正念时长和心理状态，判断波动是短时起伏，还是心理节律正在迁移。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "mindfulness-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        MindfulnessDetailContent(detail: detail, range: range)
                    } exportContent: {
                        MindfulnessDetailContent(detail: detail, range: range, isStaticForExport: true)
                    }
                        })
                    } else if detail.category == .symptomsIllness {
                        AnyView(Group {
                    exportableDetailSection(
                        title: "症状病史趋势",
                        subtitle: "读取健康页维护的症状、用药和处方资料；不同时间窗口使用对应的事件或趋势视图。",
                        statusTitle: resolvedStatusTitle,
                        summary: detail.headerSummary,
                        filePrefix: "symptoms-trends",
                        showsSummary: false,
                        showsModuleHeader: false,
                        wrapsInCard: false
                    ) {
                        SymptomsIllnessDetailContent(range: range) { target in
                            symptomsMaintenanceTarget = target
                        }
                    } exportContent: {
                        SymptomsIllnessDetailContent(range: range, isStaticForExport: true)
                    }
                        })
                    }

                    trendDisclaimerCard
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
        }
    }

    private var detailNavigationContent: some View {
        detailLayout
        .navigationTitle(detail.category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $symptomsMaintenanceTarget) { target in
            Group {
                switch target {
                case .symptomObservation:
                    BodySymptomObservationView()
                case .healthRecords:
                    MedicationCenterView()
                }
            }
            .toolbar(.hidden, for: .tabBar)
        }
    }

    var body: some View {
        detailNavigationContent
        .onAppear {
            if detail.category != .workoutsTraining {
                TrendDebugLogger.logDetailPage(detail: detail, range: range)
            }
        }
        .onChange(of: range) { _, _ in
            if detail.category == .workoutsTraining {
                workoutIsLoading = true
            }
        }
        .task(id: range.rawValue) {
            guard detail.category == .workoutsTraining else { return }
            await refreshWorkoutMetrics()
            guard !Task.isCancelled else { return }
            TrendDebugLogger.logWorkoutPresentation(
                detail: detail,
                requestedRange: range,
                presentation: workoutRecordPresentation
            )
        }
    }

    private var detailHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: detail.category.icon)
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(detail.category.accentColor)
                    .frame(width: 48, height: 48)
                    .background(detail.category.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(detail.category.title)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text("核心概览")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(detail.category.subtitle) · \(rangeTitle)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                detailHeroStatusPill(
                    title: "状态",
                    value: overviewDisplayStatusTitle,
                    tint: overviewDisplayStatusTint
                )
                detailHeroStatusPill(
                    title: "窗口",
                    value: rangeTitle,
                    tint: detail.category.accentColor
                )
                Spacer(minLength: 0)
            }

            if !heroSummaryItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("核心摘要")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(heroSummaryItems) { item in
                                heroSummaryChip(item: item)
                            }
                        }
                    }
                }
                .padding(12)
                .background(heroSummaryBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if aiInterpretationSummary != nil || aiInterpretationHighlight != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(detail.category.accentColor)
                        Text("AI 解读")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    if let summary = aiInterpretationSummary {
                        Text(summary)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let item = aiInterpretationHighlight {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(detail.category.accentColor.opacity(0.88))
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)

                            Text(item)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }

                    ForEach(aiInterpretationExtraHighlights, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(detail.category.accentColor.opacity(0.68))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            Text(item)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(detail.category.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .healthDetailSurface(padding: 18)
    }

    private var primaryMetric: TrendCategoryMetricModel? {
        detail.metrics.first(where: { $0.status == .ready && !$0.points.isEmpty }) ?? detail.metrics.first
    }

    private var workoutRecordPresentation: WorkoutRecordDetailPresentation {
        let summaries = workoutRequestedSummaries ?? []
        let sessions = workoutRequestedSessions ?? []
        let startDate = range.startDate
        let endDate = Date()
        let measuredEnergy = sessions.compactMap { session -> Double? in
            guard let energy = session.activeEnergyKilocalories, energy.isFinite, energy >= 0 else {
                return nil
            }
            return energy
        }
        let totalEnergy = !sessions.isEmpty && measuredEnergy.count == sessions.count
            ? Int(measuredEnergy.reduce(0, +).rounded())
            : nil
        let totalMinutes = summaries.reduce(0) { $0 + $1.totalMinutes }
        let totalCount = summaries.reduce(0) { $0 + $1.workoutCount }
        let activeDays = summaries.count
        let calendarDays = buildWorkoutCalendarDays(
            startDate: startDate,
            endDate: endDate,
            summaries: summaries
        )
        let latestWorkout = sessions.last

        return WorkoutRecordDetailPresentation(
            displayStartDate: startDate,
            displayEndDate: endDate,
            totalEnergyKilocalories: totalEnergy,
            totalMinutes: totalMinutes,
            totalWorkoutCount: totalCount,
            activeWorkoutDays: activeDays,
            inactiveDays: max(0, calendarDays.count - activeDays),
            latestWorkoutDate: latestWorkout?.startDate,
            latestWorkoutTitle: latestWorkout?.activityTitle,
            dailyBars: buildWorkoutDailyBars(from: summaries, startDate: startDate, endDate: endDate),
            calendarDays: calendarDays,
            secondaryMetrics: effectiveWorkoutSecondaryMetrics,
            sessions: sessions,
            recentWorkoutContext: range == .day && sessions.isEmpty ? workoutRecentSessionContext : nil
        )
    }

    // Hero 区摘要优先使用分类专属解读，其次再回退到通用指标摘要。
    private var heroSummaryItems: [TrendHeroSummaryItem] {
        if detail.category == .sleepRecovery, let items = detail.sleepClinicalSummary?.heroItems, !items.isEmpty {
            return items
        }
        if detail.category == .reproductive, let reproductive = detail.reproductiveDetail {
            return reproductive.heroItems.map {
                TrendHeroSummaryItem(title: $0.title, value: $0.value, detail: $0.detail)
            }
        }

        let readyMetrics = detail.metrics.filter { $0.status == .ready && !$0.points.isEmpty }
        if !readyMetrics.isEmpty {
            return Array(readyMetrics.prefix(3)).map { metric in
                TrendHeroSummaryItem(
                    title: metric.title,
                    value: metric.summary,
                    detail: metric.status == .ready ? "当前周期已形成可读趋势" : metric.emptyMessage
                )
            }
        }

        if let pendingMetric = detail.metrics.first {
            return [
                TrendHeroSummaryItem(
                    title: pendingMetric.title,
                    value: overviewDisplayStatusTitle,
                    detail: overviewFallbackMessage(for: pendingMetric)
                )
            ]
        }

        return []
    }

    // 阅读提示会混合分类专属建议，以及第一个需要补数据的提醒。
    private var detailHighlights: [String] {
        var items: [String] = []

        if let aiHighlight = aiHeroHighlights?.first, !aiHighlight.isEmpty {
            items.append(aiHighlight)
        } else if detail.category == .sleepRecovery {
            if !detail.sleepStages.isEmpty {
                items.append("先看昨夜结构卡在哪一段，再对照下方趋势判断这是单晚波动还是连续问题。")
            } else {
                items.append("阶段样本还不完整时，先结合时长、节律和恢复评分判断主问题落在哪一层。")
            }
        } else if detail.category == .reproductive, let reproductive = detail.reproductiveDetail {
            items.append(contentsOf: reproductive.highlights)
        } else if let primaryMetric {
            items.append("建议优先阅读 \(primaryMetric.title)，该指标最能代表当前周期内该类趋势的主要变化。")
        }

        if let firstPendingMetric = detail.metrics.first(where: { $0.status != .ready }) {
            items.append(overviewFallbackMessage(for: firstPendingMetric))
        }

        return Array(items.filter { !$0.isEmpty }.prefix(3))
    }

    private var aiInterpretationSummary: String? {
        guard let summary = aiHeroHeadlineText, !summary.isEmpty else { return nil }
        return summary
    }

    private var aiInterpretationHighlight: String? {
        detailHighlights.first
    }

    private var aiInterpretationExtraHighlights: [String] {
        Array(detailHighlights.dropFirst())
    }

    private var aiHeroHeadlineText: String? {
        if let insight = detail.sleepAIInsight {
            return insight.summary
        }
        if let insight = detail.mobilityAIInsight {
            return insight.summary
        }
        if let insight = detail.genericAIInsight {
            return insight.summary
        }
        if detail.category == .reproductive, let reproductive = detail.reproductiveDetail {
            return reproductive.insightItems.first?.detail
        }
        return nil
    }

    private var aiHeroHighlights: [String]? {
        if let insight = detail.sleepAIInsight {
            return [insight.guidance]
        }
        if let insight = detail.mobilityAIInsight {
            return insight.guidance
        }
        if let insight = detail.genericAIInsight {
            return insight.guidance
        }
        if detail.category == .reproductive, let reproductive = detail.reproductiveDetail {
            return reproductive.highlights
        }
        return nil
    }

    private func exportDescriptor(title: String, statusTitle: String, summary: String, filePrefix: String) -> TrendExportModuleDescriptor {
        TrendExportModuleDescriptor(
            category: detail.category,
            moduleTitle: title,
            rangeTitle: rangeTitle,
            statusTitle: statusTitle,
            summary: summary,
            accentColor: detail.category.accentColor,
            exportFilePrefix: "\(detail.category.rawValue)-\(filePrefix)"
        )
    }

    // 统一详情模块的页面展示和导出展示，避免两套内容逐渐分叉。
    @ViewBuilder
    private func exportableDetailSection<Content: View, ExportContent: View>(
        title: String,
        subtitle: String,
        statusTitle: String,
        summary: String,
        filePrefix: String,
        showsSummary: Bool = true,
        showsModuleHeader: Bool = true,
        wrapsInCard: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder exportContent: () -> ExportContent
    ) -> some View {
        TrendExportableSection(
            descriptor: exportDescriptor(
                title: title,
                statusTitle: statusTitle,
                summary: summary,
                filePrefix: filePrefix
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if showsModuleHeader {
                    detailModuleHeader(
                        title: title,
                        subtitle: subtitle,
                        statusTitle: statusTitle,
                        summary: summary,
                        showsSummary: showsSummary
                    )
                }

                content()
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
            }
            .modifier(
                TrendDetailSectionCardModifier(
                    accent: detail.category.accentColor,
                    wrapsInCard: wrapsInCard,
                    prefersPlainWhite: detail.category == .reproductive
                )
            )
        } exportContent: {
            exportContent()
        }
    }

    private func heroSummaryChip(item: TrendHeroSummaryItem) -> some View {
        HStack(spacing: 6) {
            Text(item.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Text(item.value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(heroSummaryChipBackgroundColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(heroChipBorderColor, lineWidth: 1)
        )
    }

    private func detailHeroStatusPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "8C97A5"))
            Text(value)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.10), lineWidth: 1)
        )
    }

    private func detailModuleHeader(
        title: String,
        subtitle: String,
        statusTitle: String,
        summary: String,
        showsSummary: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: detail.category.badgeIcon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(detail.category.accentColor)
                    .frame(width: 32, height: 32)
                    .background(detail.category.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(statusTitle)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(overviewDisplayStatusTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(overviewDisplayStatusTint.opacity(0.10), in: Capsule())
            }

            if showsSummary {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(detail.category.accentColor.opacity(0.70))
                        .frame(width: 4, height: 36)

                    Text(summary)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var trendDisclaimerCard: some View {
        HealthDisclaimerCard(
            message: "本页趋势、AI 洞察与健康解读仅供日常自我管理参考，不构成医疗诊断或治疗建议。做出重要健康决定前，请结合身体感受并咨询专业医生。"
        )
    }

    private var heroSummaryBackgroundColor: Color {
        detail.category == .reproductive ? Color.white : detail.category.accentColor.opacity(0.08)
    }

    private var heroSummaryChipBackgroundColor: Color {
        detail.category == .reproductive ? Color.white : Color.white.opacity(0.76)
    }

    private var heroChipBorderColor: Color {
        detail.category == .reproductive ? Color(hex: "EEE7E1") : Color.clear
    }

    private func refreshWorkoutMetrics() async {
        guard detail.category == .workoutsTraining else { return }

        workoutIsLoading = true
        workoutRequestedSummaries = nil
        workoutRequestedSessions = nil
        workoutRecentSessionContext = nil
        workoutRefreshSecondaryMetrics = nil
        workoutRefreshSummary = nil
        workoutRefreshStatus = nil

        let healthKitManager = HealthKitManager.shared
        let calendar = Calendar.current
        let now = Date()
        let requestedStart = range.startDate
        let sessions: [WorkoutSessionSummary]
        let recentContext: WorkoutSessionSummary?

        if range == .day {
            let recentStart = calendar.date(
                byAdding: .day,
                value: -29,
                to: calendar.startOfDay(for: now)
            ) ?? requestedStart
            async let requestedSessions = try? healthKitManager.fetchWorkoutSessionSummaries(
                startDate: requestedStart,
                endDate: now
            )
            async let recentSessions = try? healthKitManager.fetchWorkoutSessionSummaries(
                startDate: recentStart,
                endDate: now
            )

            sessions = await requestedSessions ?? []
            let recent = await recentSessions ?? []
            recentContext = sessions.isEmpty
                ? recent.last(where: { $0.startDate < requestedStart })
                : nil
        } else {
            sessions = (try? await healthKitManager.fetchWorkoutSessionSummaries(
                startDate: requestedStart,
                endDate: now
            )) ?? []
            recentContext = nil
        }

        guard !Task.isCancelled else { return }

        let summaries = buildWorkoutDaySummaries(from: sessions)
        let dailyBars = summaries.isEmpty
            ? []
            : buildWorkoutDailyBars(from: summaries, startDate: requestedStart, endDate: now)
        let durationPoints = range == .day ? sessions.map {
            TimeSeriesPointDouble(timestamp: Int64($0.startDate.timeIntervalSince1970), value: $0.durationMinutes)
        } : dailyBars.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: Double($0.totalMinutes))
        }
        let countPoints = range == .day ? sessions.map {
            TimeSeriesPointDouble(timestamp: Int64($0.startDate.timeIntervalSince1970), value: 1)
        } : dailyBars.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: Double($0.workoutCount))
        }
        let refreshedMetrics = [
            makeWorkoutMetric(
                title: "训练总时长",
                unit: "分钟",
                points: durationPoints,
                accentHex: "7CD992",
                summaryValue: range == .day ? sessions.reduce(0) { $0 + $1.durationMinutes } : nil
            ),
            makeWorkoutMetric(
                title: "训练次数",
                unit: "次",
                points: countPoints,
                accentHex: "32ADE6",
                summaryValue: range == .day ? Double(sessions.count) : nil
            )
        ]
        let refreshedSecondaryMetrics = refreshedMetrics.map {
            WorkoutRecordDetailPresentation.SecondaryMetric(
                title: $0.title,
                unit: $0.unit,
                accentHex: $0.accentHex,
                status: $0.status,
                summary: $0.summary,
                emptyMessage: $0.emptyMessage,
                points: $0.points
            )
        }

        workoutRequestedSummaries = summaries
        workoutRequestedSessions = sessions
        workoutRecentSessionContext = recentContext
        workoutRefreshSecondaryMetrics = refreshedSecondaryMetrics
        workoutRefreshStatus = resolveWorkoutStatus(metrics: refreshedMetrics)
        workoutRefreshSummary = makeWorkoutSummaryText(
            summaries: summaries,
            sessions: sessions,
            metrics: refreshedMetrics
        )
        workoutIsLoading = false
    }

    private func makeWorkoutMetric(
        title: String,
        unit: String,
        points: [TimeSeriesPointDouble],
        accentHex: String,
        summaryValue: Double? = nil
    ) -> TrendCategoryMetricModel {
        let status: TrendCategoryStatus = points.isEmpty ? .noData : .ready

        let summary = (summaryValue ?? points.last?.value).map {
            workoutMetricSummaryText(for: $0, unit: unit)
        } ?? "暂无记录"

        return TrendCategoryMetricModel(
            title: title,
            unit: unit,
            points: points,
            secondaryPoints: [],
            status: status,
            emptyMessage: "当前区间还没有训练记录，继续记录后这里会显示趋势。",
            accentHex: accentHex,
            summary: summary
        )
    }

    private func resolveWorkoutStatus(metrics: [TrendCategoryMetricModel]) -> TrendCategoryStatus {
        if metrics.contains(where: { !$0.points.isEmpty }) {
            return .ready
        }
        return .noData
    }

    private func makeWorkoutSummaryText(
        summaries: [WorkoutDaySummary],
        sessions: [WorkoutSessionSummary],
        metrics: [TrendCategoryMetricModel]
    ) -> String {
        if metrics.allSatisfy(\.points.isEmpty) {
            return range == .day
                ? "今日还没有训练记录，完成一次训练后这里会显示今天的训练趋势。"
                : "当前区间还没有训练记录，继续记录后这里会形成你的训练节律。"
        }

        if range == .day {
            let totalMinutes = Int(sessions.reduce(0) { $0 + $1.durationMinutes }.rounded())
            let dominantTitle = sessions
                .reduce(into: [String: Double]()) { totals, session in
                    totals[session.activityTitle, default: 0] += session.durationMinutes
                }
                .max(by: { $0.value < $1.value })?
                .key ?? "综合运动"
            return String(localized: "今天记录了 \(sessions.count) 次训练，共 \(totalMinutes) 分钟；主要训练为\(dominantTitle)。")
        }

        if summaries.count <= 1 {
            return String(localized: "当前窗口只记录到少量训练，训练总时长和训练次数会按实际日期保留。")
        }

        let dominantTitle = sessions
            .reduce(into: [String: Double]()) { totals, session in
                totals[session.activityTitle, default: 0] += session.durationMinutes
            }
            .max(by: { $0.value < $1.value })?
            .key ?? "健身训练"

        return String(localized: "已重新同步健康 App 的健身记录，当前主训练类型\(dominantTitle)，可以结合训练总时长和训练次数判断最近节奏是否连续。")
    }

    private func workoutMetricSummaryText(for value: Double, unit: String) -> String {
        let digits: Int
        switch unit {
        case "分钟", "次":
            digits = 0
        default:
            digits = abs(value) >= 100 || value == value.rounded() ? 0 : 1
        }
        let valueText = String(format: "%.\(digits)f", value)
        return unit.isEmpty ? valueText : "\(valueText)\(unit)"
    }

    private func buildWorkoutDaySummaries(from sessions: [WorkoutSessionSummary]) -> [WorkoutDaySummary] {
        let calendar = Calendar.current
        return Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startDate)
        }
        .map { day, daySessions in
            let typeDurations = daySessions.reduce(into: [String: Double]()) { totals, session in
                totals[session.activityTitle, default: 0] += session.durationMinutes
            }
            let measuredEnergy = daySessions.compactMap { session -> Double? in
                guard let energy = session.activeEnergyKilocalories, energy.isFinite, energy >= 0 else {
                    return nil
                }
                return energy
            }
            let measuredDistance = daySessions.compactMap { session -> Double? in
                guard let distance = session.distanceKilometers, distance.isFinite, distance >= 0 else {
                    return nil
                }
                return distance
            }
            // 与 fetchWorkoutDaySummaries 同口径：有测量值就累加，部分缺测时打 hasPartial* 标记。
            return WorkoutDaySummary(
                date: day,
                totalMinutes: Int(daySessions.reduce(0) { $0 + $1.durationMinutes }.rounded()),
                totalEnergyKilocalories: measuredEnergy.isEmpty
                    ? nil
                    : Int(measuredEnergy.reduce(0, +).rounded()),
                totalDistanceKilometers: measuredDistance.isEmpty
                    ? nil
                    : measuredDistance.reduce(0, +),
                dominantWorkoutTitle: typeDurations.max(by: { $0.value < $1.value })?.key,
                durationMinutesByWorkoutTitle: typeDurations,
                workoutCount: daySessions.count,
                hasPartialEnergyData: !measuredEnergy.isEmpty && measuredEnergy.count < daySessions.count,
                hasPartialDistanceData: !measuredDistance.isEmpty && measuredDistance.count < daySessions.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func buildWorkoutDailyBars(
        from summaries: [WorkoutDaySummary],
        startDate: Date,
        endDate: Date
    ) -> [WorkoutRecordDetailPresentation.DailyBar] {
        let calendar = Calendar.current
        let grouped = Dictionary(uniqueKeysWithValues: summaries.map { (calendar.startOfDay(for: $0.date), $0) })
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let dayCount = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let normalized = calendar.startOfDay(for: date)
            let summary = grouped[normalized]
            return WorkoutRecordDetailPresentation.DailyBar(
                date: normalized,
                energyKilocalories: summary?.totalEnergyKilocalories,
                totalMinutes: summary?.totalMinutes ?? 0,
                workoutCount: summary?.workoutCount ?? 0,
                dominantWorkoutTitle: summary?.dominantWorkoutTitle
            )
        }
    }

    private func buildWorkoutCalendarDays(
        startDate: Date,
        endDate: Date,
        summaries: [WorkoutDaySummary]
    ) -> [WorkoutRecordDetailPresentation.CalendarDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(uniqueKeysWithValues: summaries.map { (calendar.startOfDay(for: $0.date), $0) })
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let dayCount = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.autoupdatingCurrent
        weekdayFormatter.dateFormat = "E"
        let numberFormatter = DateFormatter()
        numberFormatter.locale = Locale.autoupdatingCurrent
        numberFormatter.dateFormat = "d"

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let normalized = calendar.startOfDay(for: date)
            let summary = grouped[normalized]
            return WorkoutRecordDetailPresentation.CalendarDay(
                date: normalized,
                weekdayLabel: weekdayFormatter.string(from: normalized),
                dayNumber: numberFormatter.string(from: normalized),
                hasWorkout: summary != nil
            )
        }
    }
}

enum TrendDebugLogger {
    static func logDetailPage(detail: TrendCategoryDetailModel, range: TrendsRange) {
        print("========== [趋势详情] \(detail.category.title) | 范围=\(range.title) ==========")
        print("[页面] 摘要=\(detail.headerSummary)")
        print("[页面] 状态=\(statusText(detail.status))")
        logMetrics(detail.metrics, label: "详情指标")
        logMetrics(detail.sleepCoreMetrics, label: "睡眠核心指标")
        logMetrics(detail.sleepRecoveryMetrics, label: "睡眠恢复指标")
        logCategorySummary(detail)
        logSleepClinicalSummary(detail.sleepClinicalSummary)
        logSleepStages(detail.sleepStages)
        logSleepNightSummaries(detail.sleepNightSummaries)
    }

    static func logWorkoutPresentation(
        detail: TrendCategoryDetailModel,
        requestedRange: TrendsRange,
        presentation: WorkoutRecordDetailPresentation
    ) {
        print("========== [趋势详情] \(detail.category.title) | 请求范围=\(requestedRange.title) ==========")
        print("[页面] 展示窗口=\(format(date: presentation.displayStartDate)) -> \(format(date: presentation.displayEndDate))")
        let energyText = presentation.totalEnergyKilocalories.map { "\($0)kcal" } ?? "未记录"
        print("[页面] 主值=运动消耗 \(energyText)")
        print("[页面] 统计=训练次数 \(presentation.totalWorkoutCount) 次 | 训练总时长 \(presentation.totalMinutes) 分钟 | 有运动 \(presentation.activeWorkoutDays) 天 | 无运动 \(presentation.inactiveDays) 天")
        print("[页面] 当前窗口逐次训练=\(presentation.sessions.count)")
        if let recent = presentation.recentWorkoutContext {
            print("[页面] 独立近期参考=\(format(date: recent.startDate)) | \(recent.activityTitle)")
        }
        if let latestWorkoutDate = presentation.latestWorkoutDate {
            print("[页面] 最近记录=\(format(date: latestWorkoutDate)) | \(presentation.latestWorkoutTitle ?? "综合运动")")
        } else {
            print("[页面] 最近记录=无")
        }
        logWorkoutSecondaryMetrics(presentation.secondaryMetrics)
        logWorkoutCalendar(presentation.calendarDays)
        logWorkoutBars(presentation.dailyBars)
    }

    static func logMetricChart(
        source: String,
        metric: TrendCategoryMetricModel,
        range: TrendsRange,
        rawPoints: [TimeSeriesPointDouble],
        renderedPoints: [TimeSeriesPointDouble],
        renderMode: String? = nil,
        rawPointCount: Int? = nil,
        renderedPointCount: Int? = nil,
        notes: [String] = [],
        xDomain: ClosedRange<Date>,
        xAxisDates: [Date],
        yDomain: ClosedRange<Double>,
        yAxisValues: [Double]
    ) {
        print("------ [趋势图] \(source) | \(metric.title) | 范围=\(range.title) ------")
        print("[指标] 单位=\(metric.unit) 状态=\(statusText(metric.status)) 摘要=\(metric.summary)")
        if let renderMode {
            print("[渲染] 图表模式=\(renderMode)")
        }
        if let rawPointCount, let renderedPointCount {
            print("[渲染] 点位数 原始=\(rawPointCount) 渲染=\(renderedPointCount)")
        }
        if !notes.isEmpty {
            print("[渲染] 备注=\(notes.joined(separator: " | "))")
        }
        print("[数据] 原始点=\(format(points: rawPoints))")
        print("[数据] 渲染点=\(format(points: renderedPoints))")
        print("[坐标轴] X 范围=\(format(date: xDomain.lowerBound)) -> \(format(date: xDomain.upperBound))")
        print("[坐标轴] X 刻度=\(xAxisDates.map(format(date:)).joined(separator: ", "))")
        print("[坐标轴] Y 范围=\(format(number: yDomain.lowerBound)) -> \(format(number: yDomain.upperBound))")
        print("[坐标轴] Y 刻度=\(yAxisValues.map(format(number:)).joined(separator: ", "))")
    }

    static func logSleepTimelineChart(
        source: String,
        metric: TrendCategoryMetricModel,
        range: TrendsRange,
        sleepInterval: SleepInterval,
        axisDates: [Date],
        stages: [SleepStage]
    ) {
        print("------ [趋势图] \(source) | \(metric.title) | 范围=\(range.title) ------")
        print("[指标] 单位=\(metric.unit) 状态=\(statusText(metric.status)) 摘要=\(metric.summary)")
        print("[数据] 主睡眠窗口=\(format(date: sleepInterval.start)) -> \(format(date: sleepInterval.end))")
        print("[坐标轴] X 范围=\(format(date: sleepInterval.start)) -> \(format(date: sleepInterval.end))")
        print("[坐标轴] X 刻度=\(axisDates.map(format(date:)).joined(separator: ", "))")

        let stageLines = stages.compactMap { stage -> String? in
            guard let start = stage.startDate, let end = stage.endDate else { return nil }
            let sourceType = stage.sourceType ?? "未记录"
            return String(localized: "\(stage.stage){原始类型=\(sourceType),时长=\(stage.duration),开始=\(format(date: start)),结束=\(format(date: end))}")
        }

        if !stageLines.isEmpty {
            print("[数据] 阶段段落=\(stageLines.joined(separator: " | "))")
        }
    }

    static func logSleepCompositeScoreChart(
        metric: TrendCategoryMetricModel,
        range: TrendsRange,
        sleepInterval: SleepInterval,
        axisDates: [Date],
        breakdown: SleepCompositeScoreBreakdown
    ) {
        print("------ [趋势图] 睡眠评分雷达图 | \(metric.title) | 范围=\(range.title) ------")
        print("[指标] 单位=\(metric.unit) 状态=\(statusText(metric.status)) 摘要=\(metric.summary)")
        print("[数据] 主睡眠窗口=\(format(date: sleepInterval.start)) -> \(format(date: sleepInterval.end))")
        print("[坐标轴] X 范围=\(format(date: sleepInterval.start)) -> \(format(date: sleepInterval.end))")
        print("[坐标轴] X 刻度=\(axisDates.map(format(date:)).joined(separator: ", "))")
        print("[睡眠评分拆分] 睡眠时长=\(format(number: breakdown.sleepDurationScore))")
        print("[睡眠评分拆分] 睡眠规律性=\(format(number: breakdown.sleepRegularityScore))")
        print("[睡眠评分拆分] 睡眠效率=\(format(number: breakdown.sleepEfficiencyScore))")
        print("[睡眠评分拆分] 深度恢复=\(format(number: breakdown.deepRecoveryScore))")
        print("[睡眠评分拆分] 精神恢复=\(format(number: breakdown.mentalRecoveryScore))")
        print("[睡眠评分拆分] 生理恢复=\(format(number: breakdown.physiologicalRecoveryScore))")
        print("[睡眠评分拆分] 综合评分=\(format(number: breakdown.overallScore))")
        print("[睡眠评分拆分] 评分权重=时长18/规律性16/效率16/深度16/精神16/生理18")
    }

    private static func logMetrics(_ metrics: [TrendCategoryMetricModel], label: String) {
        guard !metrics.isEmpty else { return }
        print("[指标集合] \(label).数量=\(metrics.count)")
        for metric in metrics {
            print("[指标集合] \(label).\(metric.title) 单位=\(metric.unit) 状态=\(statusText(metric.status)) 数据点=\(format(points: metric.points))")
        }
    }

    private static func logSleepStages(_ stages: [SleepStage]) {
        guard !stages.isEmpty else { return }
        let lines = stages.map { stage in
            let start = stage.startDate.map(format(date:)) ?? "无"
            let end = stage.endDate.map(format(date:)) ?? "无"
            let source = stage.sourceType ?? "未记录"
            return String(localized: "\(stage.stage){原始类型=\(source),时长=\(stage.duration),开始=\(start),结束=\(end)}")
        }
        print("[睡眠阶段] \(lines.joined(separator: " | "))")
    }

    private static func logCategorySummary(_ detail: TrendCategoryDetailModel) {
        switch detail.category {
        case .sleepRecovery:
            logSleepAIInsight(detail.sleepAIInsight)
        case .mobilityGait:
            logMobilityAIInsight(detail.mobilityAIInsight)
        case .workoutsTraining:
            logWorkoutSummary(detail)
        case .heartCardio:
            logHeartECGSummary(detail.heartECGSummary)
            logHeartECGRecords(detail.heartECGRecords)
            logHeartClinicalMonitorSummary(detail.heartClinicalMonitorSummary)
        case .environmentSenses:
            print("[环境感官摘要] 状态=\(statusText(detail.status))")
            print("[环境感官摘要] 摘要=\(detail.headerSummary)")
            logMetrics(detail.metrics, label: "环境感官指标")
            logEnvironmentDetail(detail)
        case .reproductive:
            logReproductiveDetail(detail.reproductiveDetail)
        default:
            break
        }
    }

    private static func logSleepClinicalSummary(_ summary: SleepTrendClinicalSummaryModel?) {
        guard let summary else { return }
        print("[主睡眠摘要] 标题=\(summary.headline)")
        print("[主睡眠摘要] 说明=\(summary.explanation)")
        print("[主睡眠摘要] 阶段结论=\(summary.stageHeadline)")

        if !summary.heroItems.isEmpty {
            let heroLines = summary.heroItems.map {
                "\($0.title){数值=\($0.value),说明=\($0.detail)}"
            }
            print("[主睡眠摘要] 核心卡片=\(heroLines.joined(separator: " | "))")
        }

        if !summary.stageHighlights.isEmpty {
            let highlightLines = summary.stageHighlights.map {
                "\($0.title){数值=\($0.value)}"
            }
            print("[主睡眠摘要] 阶段亮点=\(highlightLines.joined(separator: " | "))")
        }
    }

    private static func logSleepAIInsight(_ insight: SleepTrendAIInsightModel?) {
        guard let insight else { return }
        print("[睡眠洞察] 摘要=\(insight.summary)")
        if !insight.observations.isEmpty {
            print("[睡眠洞察] 观察=\(insight.observations.joined(separator: " | "))")
        }
        print("[睡眠洞察] 建议=\(insight.guidance)")
    }

    private static func logMobilityAIInsight(_ insight: MobilityTrendAIInsightModel?) {
        guard let insight else { return }
        print("[步态行动洞察] 状态=\(insight.statusTitle)")
        print("[步态行动洞察] 摘要=\(insight.summary)")
        if !insight.observations.isEmpty {
            print("[步态行动洞察] 观察=\(insight.observations.joined(separator: " | "))")
        }
        if !insight.guidance.isEmpty {
            print("[步态行动洞察] 建议=\(insight.guidance.joined(separator: " | "))")
        }
        print("[步态行动洞察] 来源=\(insight.sourceLabel)")
    }

    private static func logWorkoutSummary(_ detail: TrendCategoryDetailModel) {
        print("[健身记录摘要] 状态=\(statusText(detail.status))")
        print("[健身记录摘要] 摘要=\(detail.headerSummary)")
        if detail.metrics.isEmpty {
            print("[健身记录摘要] 指标=无")
            return
        }
        let lines = detail.metrics.map {
            "\($0.title){状态=\(statusText($0.status)),点数=\($0.points.count),摘要=\($0.summary)}"
        }
        print("[健身记录摘要] 指标=\(lines.joined(separator: " | "))")
        print("[健身记录摘要] 指标标题=\(detail.metrics.map(\.title).joined(separator: ", "))")

        for metric in detail.metrics {
            logWorkoutMetric(metric)
        }
    }

    private static func logWorkoutMetric(_ metric: TrendCategoryMetricModel) {
        let nonZeroPoints = metric.points.filter { $0.value > 0 }
        let latestPoint = metric.points.last
        let peakPoint = metric.points.max(by: { $0.value < $1.value })
        let totalValue = metric.points.reduce(0) { $0 + $1.value }
        let averageValue = metric.points.isEmpty ? 0 : totalValue / Double(metric.points.count)
        let nonZeroAverage = nonZeroPoints.isEmpty ? 0 : nonZeroPoints.reduce(0) { $0 + $1.value } / Double(nonZeroPoints.count)

        print("[健身记录明细] \(metric.title).状态=\(statusText(metric.status))")
        print("[健身记录明细] \(metric.title).单位=\(metric.unit)")
        print("[健身记录明细] \(metric.title).摘要=\(metric.summary)")
        print("[健身记录明细] \(metric.title).总点数=\(metric.points.count) 非零点数=\(nonZeroPoints.count)")
        print("[健身记录明细] \(metric.title).累计=\(format(number: totalValue)) 平均=\(format(number: averageValue)) 非零平均=\(format(number: nonZeroAverage))")

        if let latestPoint {
            print("[健身记录明细] \(metric.title).最新=\(format(date: latestPoint.date)) -> \(format(number: latestPoint.value))")
        } else {
            print("[健身记录明细] \(metric.title).最新=无")
        }

        if let peakPoint {
            print("[健身记录明细] \(metric.title).峰值=\(format(date: peakPoint.date)) -> \(format(number: peakPoint.value))")
        } else {
            print("[健身记录明细] \(metric.title).峰值=无")
        }

        if nonZeroPoints.isEmpty {
            print("[健身记录明细] \(metric.title).非零点列=无")
        } else {
            let nonZeroLines = nonZeroPoints.map {
                "\(format(date: $0.date))=\(format(number: $0.value))"
            }
            print("[健身记录明细] \(metric.title).非零点列=\(nonZeroLines.joined(separator: " | "))")
        }

        print("[健身记录明细] \(metric.title).完整点列=\(format(points: metric.points))")
    }

    private static func logWorkoutCalendar(_ days: [WorkoutRecordDetailPresentation.CalendarDay]) {
        guard !days.isEmpty else {
            print("[健身记录日历] 无")
            return
        }

        let lines = days.map {
            "\($0.weekdayLabel)\($0.dayNumber){有记录=\($0.hasWorkout)}"
        }
        print("[健身记录日历] \(lines.joined(separator: " | "))")
    }

    private static func logWorkoutBars(_ bars: [WorkoutRecordDetailPresentation.DailyBar]) {
        guard !bars.isEmpty else {
            print("[健身记录主图] 无")
            return
        }

        let lines = bars.map {
            let energyText = $0.energyKilocalories.map(String.init) ?? "未记录"
            return "\(format(date: $0.date)){能量=\(energyText),分钟=\($0.totalMinutes),次数=\($0.workoutCount),类型=\($0.dominantWorkoutTitle ?? "无")}"
        }
        print("[健身记录主图] \(lines.joined(separator: " | "))")
    }

    private static func logWorkoutSecondaryMetrics(_ metrics: [WorkoutRecordDetailPresentation.SecondaryMetric]) {
        guard !metrics.isEmpty else {
            print("[健身记录次级指标] 无")
            return
        }
        let lines = metrics.map {
            "\($0.title){状态=\(statusText($0.status)),单位=\($0.unit),摘要=\($0.summary),点数=\($0.points.count)}"
        }
        print("[健身记录次级指标] \(lines.joined(separator: " | "))")
    }

    private static func logSleepNightSummaries(_ summaries: [SleepTrendNightSummary]) {
        guard !summaries.isEmpty else { return }
        if let latest = summaries.last {
            print(
                "[主睡眠夜] 日期=\(format(date: latest.day)) 开始=\(format(date: latest.startTime)) 结束=\(format(date: latest.endTime)) 入睡分钟=\(latest.asleepMinutes) 清醒分钟=\(latest.awakeMinutes) 浅睡分钟=\(latest.coreMinutes) 深睡分钟=\(latest.deepMinutes) REM分钟=\(latest.remMinutes) 在床分钟=\(latest.inBedMinutes.map(String.init) ?? "无")"
            )
        }

        let lines = summaries.map { item in
            "日期=\(format(date: item.day)) 开始=\(format(date: item.startTime)) 结束=\(format(date: item.endTime)) 入睡分钟=\(item.asleepMinutes) 清醒分钟=\(item.awakeMinutes) 浅睡分钟=\(item.coreMinutes) 深睡分钟=\(item.deepMinutes) REM分钟=\(item.remMinutes) 在床分钟=\(item.inBedMinutes.map(String.init) ?? "无")"
        }
        print("[睡眠夜摘要] \(lines.joined(separator: " || "))")
    }

    private static func logHeartECGSummary(_ summary: HeartECGSummaryModel?) {
        guard let summary else { return }
        print("[心电摘要] 状态=\(statusText(summary.status))")
        print("[心电摘要] 标题=\(summary.headline)")
        print("[心电摘要] 说明=\(summary.detail)")
        print("[心电摘要] 记录数=\(summary.recordCountText)")
        if let latest = summary.latestRecord {
            print(
                "[最新心电] 时间=\(format(date: latest.sampledAt)) 分类=\(latest.classificationTitle) 平均心率=\(latest.averageHeartRateText) 采样频率=\(latest.samplingFrequencyText) 时长=\(latest.durationText) 症状=\(latest.symptomsStatusText) 算法版本=\(latest.algorithmVersionText ?? "无") 电压点数=\(latest.voltagePoints.count)"
            )
            print("[最新心电] 分类说明=\(latest.classificationDetail)")
        }
    }

    private static func logEnvironmentDetail(_ detail: TrendCategoryDetailModel) {
        let metricByTitle = Dictionary(uniqueKeysWithValues: detail.metrics.map { ($0.title, $0) })
        let orderedTitles = ["日照时长", "环境音量", "耳机暴露量", "耳机暴露时长"]

        for title in orderedTitles {
            guard let metric = metricByTitle[title] else {
                print("[环境感官原始数据] \(title)=未提供")
                continue
            }
            print("[环境感官原始数据] \(title).状态=\(statusText(metric.status))")
            print("[环境感官原始数据] \(title).摘要=\(metric.summary)")
            print("[环境感官原始数据] \(title).单位=\(metric.unit)")
            print("[环境感官原始数据] \(title).点数=\(metric.points.count)")
            print("[环境感官原始数据] \(title).点列=\(format(points: metric.points))")
        }
    }

    private static func logHeartECGRecords(_ records: [HeartECGRecordModel]) {
        guard !records.isEmpty else { return }
        let lines = records.map { record in
            "时间=\(format(date: record.sampledAt)) 分类=\(record.classificationTitle) 平均心率=\(record.averageHeartRateText) 时长=\(record.durationText) 电压点数=\(record.voltagePoints.count)"
        }
        print("[心电记录] \(lines.joined(separator: " || "))")
    }

    private static func logHeartClinicalMonitorSummary(_ summary: HeartClinicalMonitorSummary?) {
        guard let summary else { return }
        print("[临床监测摘要] 标题=\(summary.headline)")
        print("[临床监测摘要] 说明=\(summary.detail)")
        if !summary.items.isEmpty {
            let itemLines = summary.items.map {
                "\($0.title){数值=\($0.value),状态=\(statusText($0.status)),说明=\($0.detail)}"
            }
            print("[临床监测摘要] 项目=\(itemLines.joined(separator: " | "))")
        }
    }

    private static func logReproductiveDetail(_ detail: ReproductiveTrendDetailModel?) {
        guard let detail else { return }
        print("[生理周期摘要] 周期状态=\(detail.cycleStatusText)")
        print("[生理周期摘要] 状态说明=\(detail.cycleStatusDetail)")
        print("[生理周期摘要] 最近记录=\(detail.latestLogSummary)")
        print("[生理周期摘要] 记录说明=\(detail.latestLogDetail)")
        if !detail.heroItems.isEmpty {
            let heroLines = detail.heroItems.map {
                "\($0.title){数值=\($0.value),说明=\($0.detail)}"
            }
            print("[生理周期摘要] 核心卡片=\(heroLines.joined(separator: " | "))")
        }
        if !detail.insightItems.isEmpty {
            let insightLines = detail.insightItems.map {
                "\($0.title){说明=\($0.detail)}"
            }
            print("[生理周期摘要] 洞察=\(insightLines.joined(separator: " | "))")
        }
        if !detail.highlights.isEmpty {
            print("[生理周期摘要] 亮点=\(detail.highlights.joined(separator: " | "))")
        }
    }

    nonisolated private static func statusText(_ status: TrendCategoryStatus) -> String {
        switch status {
        case .ready: return "已接入"
        case .partial: return "部分接入"
        case .noData: return "暂无记录"
        }
    }

    nonisolated private static func format(points: [TimeSeriesPointDouble]) -> String {
        if points.isEmpty { return "[]" }
        return points.map { "\(format(date: $0.date))=\(format(number: $0.value))" }.joined(separator: ", ")
    }

    nonisolated private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    nonisolated private static func format(number: Double) -> String {
        String(format: "%.2f", number)
    }

}

private struct TrendDetailSectionCardModifier: ViewModifier {
    let accent: Color
    let wrapsInCard: Bool
    var prefersPlainWhite: Bool = false

    func body(content: Content) -> some View {
        if wrapsInCard {
            content
                .healthDetailSurface(padding: 18)
        } else {
            content
        }
    }
}

private struct MyWeightDashboardView: View {
    @Environment(\.displayScale) private var displayScale
    let metrics: [TrendCategoryMetricModel]
    let range: TrendsRange

    @State private var selectedTitle: String
    @State private var selectedPoint: TimeSeriesPointDouble?
    @State private var showingAllData = false
    @State private var showingExportOptions = false
    @State private var exportItem: MyWeightShareItem?
    @State private var exportErrorMessage: String?
    @AppStorage("body_profile_target_weight_kg") private var targetWeightKg: Double = 58.0

    init(metrics: [TrendCategoryMetricModel], initialRange: TrendsRange) {
        self.metrics = metrics
        self.range = initialRange
        let orderedTitles = ["体重", "瘦体重", "身高", "BMI", "体脂率"]
        let firstAvailableTitle = orderedTitles.first { title in
            metrics.contains(where: { $0.title == title && !$0.points.isEmpty })
        }
        _selectedTitle = State(initialValue: firstAvailableTitle ?? "体重")
    }

    private var selectableMetrics: [TrendCategoryMetricModel] {
        let orderedTitles = ["体重", "瘦体重", "身高", "BMI", "体脂率"]
        return orderedTitles.compactMap { title in
            metrics.first(where: { $0.title == title && !$0.points.isEmpty })
        }
    }

    private var selectedMetric: TrendCategoryMetricModel {
        selectableMetrics.first(where: { displayTitle(for: $0) == selectedTitle || $0.title == selectedTitle })
        ?? selectableMetrics.first
        ?? metrics.first(where: { $0.title == "体重" })
        ?? metrics.first
        ?? TrendCategoryMetricModel(
            title: "体重",
            unit: "kg",
            points: [],
            secondaryPoints: [],
            status: .noData,
            emptyMessage: "健康 App 暂无体重记录",
            accentHex: "F0A23A",
            summary: "暂无体重数据"
        )
    }

    private var allPoints: [TimeSeriesPointDouble] {
        selectedMetric.points.sorted { $0.date < $1.date }
    }

    private var visiblePoints: [TimeSeriesPointDouble] {
        let now = Date()
        return allPoints.filter { $0.date >= range.startDate && $0.date <= now }
    }

    private var currentPoint: TimeSeriesPointDouble? {
        selectedPoint ?? visiblePoints.last ?? allPoints.last
    }

    private var averageValue: Double? {
        guard !visiblePoints.isEmpty else { return nil }
        return visiblePoints.map(\.value).reduce(0, +) / Double(visiblePoints.count)
    }

    private var minPoint: TimeSeriesPointDouble? {
        visiblePoints.min { $0.value < $1.value }
    }

    private var maxPoint: TimeSeriesPointDouble? {
        visiblePoints.max { $0.value < $1.value }
    }

    private var changeValue: Double? {
        guard let first = visiblePoints.first?.value, let latest = visiblePoints.last?.value else { return nil }
        return latest - first
    }

    private var targetValue: Double? {
        if selectedMetric.title == "体重", targetWeightKg > 0 {
            return targetWeightKg
        }
        return selectedMetric.title == "身高" ? currentPoint?.value : minPoint?.value
    }

    private var chartAccent: Color {
        Color(hex: selectedMetric.accentHex)
    }

    private var pageTitle: String {
        selectedMetric.title == "体重" ? "身高体重" : "我的\(displayTitle(for: selectedMetric))"
    }

    private var latestHeightCm: Double? {
        latestPoint(for: "身高")?.value
    }

    private var latestWeightKg: Double? {
        latestPoint(for: "体重")?.value
    }

    private var latestBMI: Double? {
        if let bmi = latestPoint(for: "BMI")?.value {
            return bmi
        }
        guard let latestHeightCm, let latestWeightKg, latestHeightCm > 0, latestWeightKg > 0 else {
            return nil
        }
        let heightM = latestHeightCm / 100.0
        return latestWeightKg / (heightM * heightM)
    }

    var body: some View {
        VStack(spacing: 18) {
            metricSelectorBar
            heroSection
            bmiSummaryCard
            rangeHeader
            chartSection
            statsGrid
            allDataEntry
        }
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showingAllData) {
            NavigationStack {
                MyWeightAllDataView(metric: selectedMetric, points: allPoints)
            }
        }
        .sheet(item: $exportItem) { item in
            MyWeightActivityView(items: [item.url])
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .confirmationDialog("导出格式", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("CSV (.csv)") { exportCSV() }
            Button("图片（贾玲版备忘录风格）") { exportImage() }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: selectedTitle) { _, _ in
            selectedPoint = nil
        }
    }

    private var metricSelectorBar: some View {
        HStack {
            Text("查看指标")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            metricMenu
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    private var metricMenu: some View {
        Menu {
            ForEach(menuItems, id: \.self) { title in
                Button {
                    selectedTitle = title
                } label: {
                    if title == selectedTitle {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: selectedMetric))
                    .font(.system(size: 13, weight: .bold))
                Text(displayTitle(for: selectedMetric))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(Color.black.opacity(0.24))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Theme.Colors.surface.opacity(0.78), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var menuItems: [String] {
        let resolved = selectableMetrics.map(displayTitle)
        return resolved.isEmpty ? ["体重"] : resolved
    }

    private func latestPoint(for title: String) -> TimeSeriesPointDouble? {
        metrics.first(where: { $0.title == title })?
            .points
            .sorted { $0.date < $1.date }
            .last
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(targetValue.map { formattedValue($0) } ?? "--")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .shadow(color: .white, radius: 2, x: 0, y: 2)
                    Text(unitText)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }
                Text(primaryHeroLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(changeText)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(changeColor)
                        .shadow(color: .white, radius: 2, x: 0, y: 2)
                    Text(unitText)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(changeColor)
                }
                Text("\(displayTitle(for: selectedMetric))变化")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 22)
    }

    private var primaryHeroLabel: String {
        switch selectedMetric.title {
        case "体重": return "目标体重"
        case "身高": return "当前身高"
        default: return "区间最低"
        }
    }

    private var bmiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BMI 水平")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(bmiSubtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(latestBMI.map { String(format: "%.1f", $0) } ?? "--")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(bmiLevelText)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(bmiLevelColor)
                }
            }

            bmiRangeBar

            HStack(spacing: 10) {
                miniProfilePill(title: "身高", value: latestHeightCm.map { String(format: "%.0f cm", $0) } ?? "--")
                miniProfilePill(title: "体重", value: latestWeightKg.map { String(format: "%.1f kg", $0) } ?? "--")
                miniProfilePill(title: "目标", value: String(format: "%.1f kg", targetWeightKg))
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var bmiRangeBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 5) {
                    Capsule().fill(Color(hex: "33D1C5")).frame(maxWidth: .infinity)
                    Capsule().fill(Color(hex: "4BDD82")).frame(maxWidth: .infinity)
                    Capsule().fill(Color(hex: "A8CC6D")).frame(maxWidth: .infinity)
                    Capsule().fill(Color(hex: "F6D327")).frame(maxWidth: .infinity)
                    Capsule().fill(Color(hex: "FF9446")).frame(maxWidth: .infinity)
                }
                .frame(height: 13)

                if let latestBMI {
                    let clamped = min(max(latestBMI, 15), 36)
                    let x = proxy.size.width * CGFloat((clamped - 15) / 21)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(bmiLevelColor, lineWidth: 6))
                        .offset(x: min(max(0, x - 13), max(0, proxy.size.width - 26)))
                        .shadow(color: bmiLevelColor.opacity(0.22), radius: 6, x: 0, y: 3)
                }
            }
        }
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            HStack {
                Text("18.5")
                Spacer()
                Text("24")
                Spacer()
                Text("28")
                Spacer()
                Text("32")
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary)
            .offset(y: 16)
        }
        .padding(.bottom, 14)
    }

    private func miniProfilePill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var bmiSubtitle: String {
        guard latestBMI != nil else {
            return String(localized: "录入身高和体重后自动生成 BMI 分析")
        }
        return String(localized: "参考 WHO 亚洲成人标准，用于日常体型趋势观察")
    }

    private var bmiLevelText: String {
        guard let latestBMI else { return "待录入" }
        switch latestBMI {
        case ..<18.5: return "偏瘦"
        case ..<24: return "标准"
        case ..<28: return "偏胖"
        case ..<32: return "肥胖"
        default: return "重度肥胖"
        }
    }

    private var bmiLevelColor: Color {
        guard let latestBMI else { return Theme.Colors.textTertiary }
        switch latestBMI {
        case ..<18.5: return Color(hex: "33D1C5")
        case ..<24: return Color(hex: "4BDD82")
        case ..<28: return Color(hex: "A8CC6D")
        case ..<32: return Color(hex: "F6D327")
        default: return Color(hex: "FF9446")
        }
    }

    private var rangeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(rangeTitle, systemImage: "calendar")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "B67A2E"))

            Text(rangeDateText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "7D7D7D"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BBChartHeader(
                title: "\(displayTitle(for: selectedMetric)) \(unitText)",
                subtitle: rangeDateText,
                systemImage: symbol(for: selectedMetric),
                tint: chartAccent
            )

            if visiblePoints.isEmpty {
                TrendMetricEmptyStateView(
                    status: selectedMetric.status,
                    title: selectedMetric.title,
                    message: selectedMetric.emptyMessage,
                    accent: Color(hex: selectedMetric.accentHex)
                )
                .frame(height: 220)
            } else {
                bodyWeightChart
                if let currentPoint {
                    BBChartSelectionReadout(
                        title: ChineseDateText.fullDate(currentPoint.date),
                        value: "\(formattedValue(currentPoint.value))\(unitText)",
                        detail: selectedPoint == nil ? "最新读数" : "当前选择",
                        tint: chartAccent,
                        systemImage: selectedPoint == nil ? "clock.fill" : "scope"
                    )
                }
            }
        }
        .padding(16)
        .bbChartSurface(tint: chartAccent, cornerRadius: 24)
        .padding(.horizontal, 20)
    }

    private var bodyWeightChart: some View {
        Chart {
            if let targetValue {
                RuleMark(y: .value("目标", targetValue))
                    .foregroundStyle(chartAccent.opacity(0.72))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .annotation(position: .trailing, alignment: .center) {
                        Text(formattedValue(targetValue))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(chartAccent)
                    }
            }

            ForEach(visiblePoints) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value(selectedMetric.title, point.value)
                )
                .foregroundStyle(chartAccent.opacity(0.62))
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", point.date),
                    y: .value(selectedMetric.title, point.value)
                )
                .symbolSize(point.id == (selectedPoint ?? visiblePoints.last)?.id ? 72 : 34)
                .foregroundStyle(Theme.Colors.onAccent)
                .annotation(position: .overlay) {
                    Circle()
                        .fill(chartAccent)
                        .frame(width: point.id == (selectedPoint ?? visiblePoints.last)?.id ? 10 : 7,
                               height: point.id == (selectedPoint ?? visiblePoints.last)?.id ? 10 : 7)
                }

                if point.id == maxPoint?.id {
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(selectedMetric.title, point.value)
                    )
                    .symbolSize(1)
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 3) {
                        VStack(spacing: -2) {
                            Text("\(formattedValue(point.value))\(unitText)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            Text("MAX")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "F39B1F"))
                    }
                }

                if point.id == minPoint?.id {
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(selectedMetric.title, point.value)
                    )
                    .symbolSize(1)
                    .foregroundStyle(.clear)
                    .annotation(position: .bottom, spacing: 3) {
                        VStack(spacing: -2) {
                            Text("\(formattedValue(point.value))\(unitText)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            Text("MIN")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "91C783"))
                    }
                }

                if point.id == (selectedPoint ?? visiblePoints.last)?.id {
                    RuleMark(x: .value("选中", point.date))
                        .foregroundStyle(chartAccent.opacity(0.46))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(selectedMetric.title, point.value)
                    )
                    .symbolSize(80)
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 10, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: 5) {
                            Text("\(formattedValue(point.value))\(unitText)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.black)
                            Text(ChineseDateText.fullDate(point.date))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "868686"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .frame(height: 260)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                AxisTick(stroke: StrokeStyle(lineWidth: 0))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisDateText(date))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "8E8E8E"))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                    .foregroundStyle(Color.black.opacity(0.07))
                AxisTick(stroke: StrokeStyle(lineWidth: 0))
                AxisValueLabel {
                    if let y = value.as(Double.self) {
                        Text(String(format: "%.0f", y))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "8E8E8E"))
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.leading, 2)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
                .bbChartPlotSurface(tint: chartAccent, cornerRadius: 18)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard frame.contains(value.location) else { return }
                                    let relativeX = value.location.x - frame.origin.x
                                    guard let date: Date = proxy.value(atX: relativeX) else { return }
                                    selectedPoint = visiblePoints.min {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }
                                }
                        )
                }
            }
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
            statCard(value: "\(visiblePoints.count)", title: "统计天数")
            statCard(value: averageValue.map { "\(formattedValue($0))\(unitText)" } ?? "--", title: "平均\(displayTitle(for: selectedMetric))")
            statCard(value: maxPoint.map { "\(formattedValue($0.value))\(unitText)" } ?? "--", title: maxStatTitle)
            statCard(value: minPoint.map { "\(formattedValue($0.value))\(unitText)" } ?? "--", title: minStatTitle)
        }
        .padding(.horizontal, 20)
    }

    private var maxStatTitle: String {
        switch selectedMetric.title {
        case "体重": return "最重"
        case "身高": return "最高记录"
        default: return "最高值"
        }
    }

    private var minStatTitle: String {
        switch selectedMetric.title {
        case "体重": return "最轻"
        case "身高": return "最低记录"
        default: return "最低值"
        }
    }

    private var allDataEntry: some View {
        Button {
            showingAllData = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("所有\(displayTitle(for: selectedMetric))数据")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(allPoints.isEmpty ? "暂无记录" : "\(allPoints.count) 条记录，可按月份查看和导出")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "B0B0B0"))
            }
            .padding(18)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func statCard(value: String, title: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3B3E41"))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "808080"))
        }
        .frame(maxWidth: .infinity, minHeight: 86)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var yDomain: ClosedRange<Double> {
        let values = visiblePoints.map(\.value) + [targetValue].compactMap { $0 }
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.22, selectedMetric.title == "体重" ? 1.5 : 0.5)
        return Swift.max(0, min - padding)...(max + padding)
    }

    private var yAxisValues: [Double] {
        let lower = yDomain.lowerBound
        let upper = yDomain.upperBound
        guard upper > lower else { return [lower] }
        return (0...5).map { lower + (upper - lower) * Double($0) / 5.0 }
    }

    private var xAxisDates: [Date] {
        guard let first = visiblePoints.first?.date, let last = visiblePoints.last?.date else { return [] }
        if visiblePoints.count <= 3 { return visiblePoints.map(\.date) }
        let middle = visiblePoints[visiblePoints.count / 2].date
        return [first, middle, last]
    }

    private var rangeTitle: String {
        switch range {
        case .day: return "今天"
        case .week: return "最近 7 天"
        case .month: return "最近 30 天"
        }
    }

    private var rangeDateText: String {
        guard let first = visiblePoints.first?.date, let last = visiblePoints.last?.date else { return "等待健康 App 同步" }
        return "\(compactDate(first))-\(compactDate(last))"
    }

    private var unitText: String {
        selectedMetric.unit
    }

    private var changeText: String {
        guard let changeValue else { return "--" }
        let prefix = changeValue > 0 ? "+" : ""
        return "\(prefix)\(formattedValue(changeValue))"
    }

    private var changeColor: Color {
        guard let changeValue else { return Color(hex: "A0A0A0") }
        if selectedMetric.title == "体重" {
            return changeValue <= 0 ? Color(hex: "91C783") : Color(hex: "F0A23A")
        }
        return changeValue >= 0 ? Color(hex: "91C783") : Color(hex: "F0A23A")
    }

    private func formattedValue(_ value: Double) -> String {
        switch selectedMetric.unit {
        case "kg", "km", "L":
            return String(format: "%.1f", value)
        case "cm":
            return String(format: "%.0f", value)
        case "%":
            return String(format: "%.1f", value)
        default:
            return abs(value) >= 100 || value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
    }

    private func compactDate(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(localized: "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日")
    }

    private func axisDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(format: "%02d.%02d", calendar.component(.month, from: date), calendar.component(.day, from: date))
    }

    private func displayTitle(for metric: TrendCategoryMetricModel) -> String {
        metric.title
    }

    private func symbol(for metric: TrendCategoryMetricModel) -> String {
        switch metric.title {
        case "瘦体重": return "figure.strengthtraining.traditional"
        case "身高": return "ruler"
        case "体脂率": return "percent"
        case "BMI": return "scalemass"
        default: return "scalemass.fill"
        }
    }

    private func exportCSV() {
        do {
            let url = try MyWeightExporter.csv(metric: selectedMetric, points: allPoints)
            exportItem = MyWeightShareItem(url: url)
        } catch {
            exportErrorMessage = "CSV 文件生成失败，请稍后再试。"
        }
    }

    @MainActor
    private func exportImage() {
        do {
            let exportView = MyWeightExportSnapshotView(
                metric: selectedMetric,
                points: visiblePoints,
                rangeTitle: rangeTitle,
                changeText: changeText
            )
            let renderer = ImageRenderer(content: exportView)
            renderer.scale = displayScale
            guard let image = renderer.uiImage,
                  let data = image.pngData() else {
                throw MyWeightExportError.renderFailed
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("my-weight-\(MyWeightExporter.timestamp()).png")
            try data.write(to: url)
            exportItem = MyWeightShareItem(url: url)
        } catch {
            exportErrorMessage = "图片生成失败，请稍后再试。"
        }
    }
}

private struct MyWeightAllDataView: View {
    let metric: TrendCategoryMetricModel
    let points: [TimeSeriesPointDouble]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var showingExportOptions = false
    @State private var showingMonthPicker = false
    @State private var exportItem: MyWeightShareItem?
    @State private var exportErrorMessage: String?
    @State private var selectedMonthDate: Date

    init(metric: TrendCategoryMetricModel, points: [TimeSeriesPointDouble]) {
        self.metric = metric
        self.points = points.sorted { $0.date > $1.date }
        let firstDate = points.sorted { $0.date > $1.date }.first?.date ?? Date()
        let calendar = Calendar.current
        let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: firstDate)) ?? firstDate
        _selectedMonthDate = State(initialValue: firstMonth)
    }

    private var displayTitle: String {
        metric.title
    }

    private var monthGroups: [MyWeightMonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { point in
            calendar.date(from: calendar.dateComponents([.year, .month], from: point.date)) ?? calendar.startOfDay(for: point.date)
        }
        return grouped.map { month, values in
            MyWeightMonthGroup(month: month, points: values.sorted { $0.date > $1.date })
        }
        .sorted { $0.month > $1.month }
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(monthGroups) { group in
                        monthSection(group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 46)
            }
        }
        .navigationTitle("所有\(displayTitle)数据")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingExportOptions = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .confirmationDialog("导出格式", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("CSV (.csv)") { exportCSV(points: points) }
            Button("图片（贾玲版备忘录风格）") { showingMonthPicker = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingMonthPicker) {
            MyWeightMonthPickerSheet(
                months: monthGroups.map(\.month),
                selectedMonth: selectedMonthDate
            ) { month in
                selectedMonthDate = month
                showingMonthPicker = false
                let monthPoints = points(in: month)
                exportImage(points: monthPoints.isEmpty ? points : monthPoints)
            } onCancel: {
                showingMonthPicker = false
            }
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $exportItem) { item in
            MyWeightActivityView(items: [item.url])
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func monthSection(_ group: MyWeightMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(monthTitle(group.month))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.black)

                Text(monthChangeText(group.points))
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(monthChangeColor(group.points))
            }
            .padding(.leading, 14)

            VStack(spacing: 0) {
                ForEach(Array(group.points.enumerated()), id: \.element.id) { index, point in
                    allDataRow(point: point, previous: previousPoint(after: point))

                    if index < group.points.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture {
                selectedMonthDate = group.month
            }
        }
    }

    private func allDataRow(point: TimeSeriesPointDouble, previous: TimeSeriesPointDouble?) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayTitle(point.date))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                if Calendar.current.isDateInYesterday(point.date) {
                    Text("昨天")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "8BC27B"))
                Text(formattedValue(point.value))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                Text(metric.unit)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(width: 112, alignment: .trailing)

            Text(deltaText(point: point, previous: previous))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(deltaColor(point: point, previous: previous))
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private func previousPoint(after point: TimeSeriesPointDouble) -> TimeSeriesPointDouble? {
        guard let index = points.firstIndex(where: { $0.id == point.id }),
              index + 1 < points.count else {
            return nil
        }
        return points[index + 1]
    }

    private func points(in month: Date) -> [TimeSeriesPointDouble] {
        let calendar = Calendar.current
        return points.filter {
            calendar.component(.year, from: $0.date) == calendar.component(.year, from: month)
            && calendar.component(.month, from: $0.date) == calendar.component(.month, from: month)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.year, from: date))-\(String(format: "%02d", calendar.component(.month, from: date)))"
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(localized: "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日")
    }

    private func monthChangeText(_ points: [TimeSeriesPointDouble]) -> String {
        guard let latest = points.first?.value, let earliest = points.last?.value else { return "" }
        let delta = latest - earliest
        let arrow = delta >= 0 ? "↑" : "↓"
        return "\(arrow)\(formattedValue(abs(delta)))\(metric.unit)"
    }

    private func monthChangeColor(_ points: [TimeSeriesPointDouble]) -> Color {
        guard let latest = points.first?.value, let earliest = points.last?.value else { return Color(hex: "8A8A8A") }
        let delta = latest - earliest
        if metric.title == "体重" {
            return delta >= 0 ? Color(hex: "E3A045") : Color(hex: "8BC27B")
        }
        return delta >= 0 ? Color(hex: "8BC27B") : Color(hex: "E3A045")
    }

    private func deltaText(point: TimeSeriesPointDouble, previous: TimeSeriesPointDouble?) -> String {
        guard let previous else { return "" }
        let delta = point.value - previous.value
        if abs(delta) < 0.005 { return "-0.00\(metric.unit)" }
        let arrow = delta >= 0 ? "↑" : "↓"
        return "\(arrow)\(formattedValue(abs(delta)))\(metric.unit)"
    }

    private func deltaColor(point: TimeSeriesPointDouble, previous: TimeSeriesPointDouble?) -> Color {
        guard let previous else { return Color.clear }
        let delta = point.value - previous.value
        if abs(delta) < 0.005 { return Color(hex: "7D7D7D") }
        if metric.title == "体重" {
            return delta >= 0 ? Color(hex: "E3A045") : Color(hex: "8BC27B")
        }
        return delta >= 0 ? Color(hex: "8BC27B") : Color(hex: "E3A045")
    }

    private func formattedValue(_ value: Double) -> String {
        switch metric.unit {
        case "kg", "km", "L":
            return String(format: "%.2f", value)
        case "%":
            return String(format: "%.1f", value)
        default:
            return abs(value) >= 100 || value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
    }

    private func exportCSV(points: [TimeSeriesPointDouble]) {
        do {
            exportItem = MyWeightShareItem(url: try MyWeightExporter.csv(metric: metric, points: points))
        } catch {
            exportErrorMessage = "CSV 文件生成失败，请稍后再试。"
        }
    }

    @MainActor
    private func exportImage(points: [TimeSeriesPointDouble]) {
        do {
            let renderer = ImageRenderer(content: MyWeightMemoExportView(metric: metric, points: points))
            renderer.scale = displayScale
            guard let image = renderer.uiImage,
                  let data = image.pngData() else {
                throw MyWeightExportError.renderFailed
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("my-weight-memo-\(MyWeightExporter.timestamp()).png")
            try data.write(to: url)
            exportItem = MyWeightShareItem(url: url)
        } catch {
            exportErrorMessage = "图片生成失败，请稍后再试。"
        }
    }
}

private struct MyWeightMonthGroup: Identifiable {
    let month: Date
    let points: [TimeSeriesPointDouble]

    var id: TimeInterval { month.timeIntervalSince1970 }
}

private struct MyWeightMonthPickerSheet: View {
    let months: [Date]
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var selectedMonth: Date

    init(
        months: [Date],
        selectedMonth: Date,
        onConfirm: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.months = months.isEmpty ? [Date()] : months
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let calendar = Calendar.current
        let normalizedSelection = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        _selectedMonth = State(initialValue: self.months.contains(normalizedSelection) ? normalizedSelection : self.months[0])
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.18))
                        .frame(width: 48, height: 48)
                        .background(Theme.Colors.surface, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("选择需要导出的月份")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.black)

                Spacer()

                Color.clear
                    .frame(width: 48, height: 48)
            }

            Picker("月份", selection: $selectedMonth) {
                ForEach(months, id: \.self) { month in
                    Text(monthTitle(month)).tag(month)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 142)
            .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                onConfirm(selectedMonth)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(Color(hex: "F59B1F"))
                    .frame(width: 78, height: 74)
                    .background(Color(hex: "333638"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(Theme.Colors.secondarySurface)
    }

    private func monthTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(localized: "\(calendar.component(.year, from: date)) 年    \(calendar.component(.month, from: date)) 月")
    }
}

private struct MyWeightExportSnapshotView: View {
    let metric: TrendCategoryMetricModel
    let points: [TimeSeriesPointDouble]
    let rangeTitle: String
    let changeText: String

    var body: some View {
        MyWeightMemoExportView(metric: metric, points: points, headerOverride: "\(rangeTitle) · 变化 \(changeText)")
    }
}

private struct MyWeightMemoExportView: View {
    let metric: TrendCategoryMetricModel
    let points: [TimeSeriesPointDouble]
    var headerOverride: String? = nil

    private var displayTitle: String {
        metric.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("所有\(displayTitle)数据")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                Text(headerOverride ?? exportSubtitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "777777"))
            }

            VStack(spacing: 0) {
                ForEach(Array(points.prefix(12).enumerated()), id: \.element.id) { index, point in
                    HStack {
                        Text(dayText(point.date))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                        Spacer()
                        Text("\(formattedValue(point.value))\(metric.unit)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                    }
                    .padding(.vertical, 12)

                    if index < Swift.min(points.count, 12) - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(24)
        .frame(width: 430, alignment: .topLeading)
        .background(Theme.Colors.secondarySurface)
    }

    private var exportSubtitle: String {
        guard let first = points.last?.date, let last = points.first?.date else { return "暂无记录" }
        return String(localized: "\(dayText(first))-\(dayText(last)) · 共 \(points.count) 条")
    }

    private func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(localized: "\(calendar.component(.year, from: date))年\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日")
    }

    private func formattedValue(_ value: Double) -> String {
        switch metric.unit {
        case "kg", "km", "L":
            return String(format: "%.2f", value)
        case "%":
            return String(format: "%.1f", value)
        default:
            return abs(value) >= 100 || value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
    }
}

private struct MyWeightShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct MyWeightActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum MyWeightExportError: Error {
    case renderFailed
}

private enum MyWeightExporter {
    static func csv(metric: TrendCategoryMetricModel, points: [TimeSeriesPointDouble]) throws -> URL {
        let sorted = points.sorted { $0.date > $1.date }
        var lines = ["date,value,unit"]
        lines.append(contentsOf: sorted.map { point in
            "\(isoDate(point.date)),\(String(format: "%.4f", point.value)),\(metric.unit)"
        })
        let filename = "my-weight-\(timestamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
