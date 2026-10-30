/// DashboardView 由 MainTabView 今日 Tab 调用，作为「今日」首页容器。
/// 负责展示当日健康概览、模块网格、身体信号、睡眠恢复、趋势入口及权限引导。

import SwiftUI
import Charts
import UserNotifications
import Combine
import HealthKit
import OSLog
import UIKit

enum TodayVisualTokens {
    static let cardCornerRadius: CGFloat = Theme.Radius.card
    static let compactCornerRadius: CGFloat = Theme.Radius.inset
    static let canvasTop = Color(hex: "FBFDFF")
    static let canvasBottom = Color(hex: "EDF3F7")
    static let canvas = LinearGradient(
        colors: [canvasTop, canvasBottom],
        startPoint: .top,
        endPoint: .bottom
    )
    static let mistBlue = Theme.Colors.pastelCyan
    static let mistGreen = Theme.Colors.pastelGreen
    static let softYellow = Theme.Colors.pastelYellow
    static let surface = Theme.Colors.surface.opacity(0.94)
    static let surfaceStroke = Color.white.opacity(0.82)
}

nonisolated enum TodayDashboardInitialLoadPolicy {
    static let heavyDataDelayNanoseconds: UInt64 = 450_000_000
}

private struct TodayCardPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var todayCardPressed: Bool {
        get { self[TodayCardPressedKey.self] }
        set { self[TodayCardPressedKey.self] = newValue }
    }
}

private struct TodayCardSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todayCardPressed) private var isPressed
    let tint: Color
    let cornerRadius: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let surfaceScale = reduceMotion || !isPressed ? 1.0 : 0.986

        content
            .background {
                TodayVisualTokens.surface
                    .overlay(alignment: .topLeading) {
                        LinearGradient(
                            colors: [
                                tint.opacity(emphasized ? 0.085 : 0.035),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(shape)
                    .shadow(
                        color: tint.opacity(emphasized ? 0.10 : 0.045),
                        radius: emphasized ? 16 : 10,
                        x: 0,
                        y: emphasized ? 8 : 4
                    )
            }
            .overlay {
                shape.stroke(
                    TodayVisualTokens.surfaceStroke.opacity(0.64),
                    lineWidth: 1
                )
            }
            .scaleEffect(surfaceScale)
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.74),
                value: isPressed
            )
    }
}

private struct TodayCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.todayCardPressed, configuration.isPressed)
    }
}

extension View {
    func todayCardSurface(
        tint: Color = TodayVisualTokens.surfaceStroke,
        cornerRadius: CGFloat = TodayVisualTokens.cardCornerRadius,
        emphasized: Bool = false
    ) -> some View {
        modifier(
            TodayCardSurfaceModifier(
                tint: tint,
                cornerRadius: cornerRadius,
                emphasized: emphasized
            )
        )
    }

    func todayCardButtonStyle() -> some View {
        buttonStyle(TodayCardButtonStyle())
    }
}

private enum TodayHealthPermissionGuideMode {
    case unsupported
    case needsAuthorization
    case refreshAfterSettings

    var buttonTitle: String {
        switch self {
        case .unsupported:
            return String(localized: "我知道了")
        case .needsAuthorization:
            return String(localized: "授权读取健康数据")
        case .refreshAfterSettings:
            return String(localized: "已开启，点击刷新")
        }
    }

    var footnote: String {
        switch self {
        case .unsupported:
            return String(localized: "当前设备暂不支持 Apple Health 数据读取。")
        case .needsAuthorization:
            return String(localized: "系统会弹出 Apple Health 权限请求，请打开心率、HRV 和静息心率。")
        case .refreshAfterSettings:
            return String(localized: "如果已经在系统设置里打开权限，刷新后会重新读取 HealthKit 数据。")
        }
    }
}

/// 仪表盘视图 由上级页面或路由调用，作为今日页里的界面或内容组件。
/// 负责展示当日健康概览、趋势变化和可操作入口。
struct DashboardView: View {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "Today")
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HealthAuthorizationPreferences.flowCompletedKey) private var healthAuthorizationFlowCompleted = false
    @AppStorage("dashboard_module_visible_hero") private var showHeroModule: Bool = true
    @AppStorage("dashboard_module_visible_healthGuide") private var showHealthGuideModule: Bool = true
    @AppStorage("dashboard_module_visible_notificationGuide") private var showNotificationGuideModule: Bool = true
    @AppStorage("dashboard_module_visible_sedentaryReminder") private var showSedentaryReminderModule: Bool = true
    @AppStorage("dashboard_module_visible_bodySignals") private var showBodySignalsModule: Bool = true
    @AppStorage("dashboard_module_visible_trends") private var showTrendsModule: Bool = true
    @AppStorage("dashboard_module_visible_sleepRecovery") private var showSleepRecoveryModule: Bool = true
    @AppStorage("dashboard_module_visible_otherMetrics") private var showOtherMetricsModule: Bool = true
    @AppStorage("dashboard_module_visible_faq") private var showFAQModule: Bool = true
    @State private var dashboardViewModel = DashboardViewModel.shared
    @State private var habitViewModel = HabitViewModel()
    @State private var sleepViewModel = SleepViewModel()
    @State private var reportSummaryViewModel = ReportSummaryViewModel()
    @Bindable var periodViewModel: PeriodViewModel
    let openReproductiveRecord: () -> Void
    @State private var showingPressureDetailSheet = false
    @State private var showingSleepSheet = false
    @State private var showingSedentaryDetail = false
    @State private var showingSnoreAnalysis = false
    @State private var selectedBodySignalDetail: TodayBodySignalDetail?
    @State private var showingPageCustomization = false
    @State private var selectedOtherMetricDestination: DashboardOtherMetricDestination?
    @State private var selectedFAQQuestion: DashboardFAQQuestion?
    @State private var selectedInfoTopic: TodayInfoTopic?
    @State private var didAppear = false
    /// 习惯/睡眠/周期加载冷却：避免 Tab 反复切换/回前台时重复触发全量 HealthKit 查询。
    @State private var lastHeavyTabLoadAt: Date?
    @State private var healthGuideState: HealthGuideState = .needsAuthorization
    @State private var shouldShowNotificationGuide = false
    @State private var showingAIInsightSheet = false
    @State private var aiInitialPrompt: String?
    @State private var healthProfileSummary: HealthProfileSummary?
    @State private var isHealthProfileLoading = false
    @State private var showingTodayHealthPermissionGuide = false
    @State private var todayHealthPermissionGuideMode: TodayHealthPermissionGuideMode = .refreshAfterSettings
    @State private var notificationSettingsTask: Task<Void, Never>?
    @State private var heavyDataLoadTask: Task<Void, Never>?
    @State private var isCheckingTodayHealthPermission = false
    private let sedentaryRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private struct BodySignalSnapshot {
        let recoveryScore: Int?
        let recoveryInput: StressBodyBatteryRecoveryInput
        let bodyBatteryValue: Int?
        let bodyBatteryTrendPoints: [TimeSeriesPoint]
        let focusCapacity: StressFocusCapacityAssessment
        let focusCapacityTrend: StressFocusCapacityTrendSnapshot
    }

    init(
        periodViewModel: PeriodViewModel,
        openReproductiveRecord: @escaping () -> Void
    ) {
        self.periodViewModel = periodViewModel
        self.openReproductiveRecord = openReproductiveRecord
    }

    private var hasAnyVisibleContentModule: Bool {
        [
            showHeroModule,
            showHealthGuideModule && healthGuideState != .authorized,
            showNotificationGuideModule && shouldShowNotificationGuide,
            showSedentaryReminderModule,
            showBodySignalsModule,
            showTrendsModule,
            showSleepRecoveryModule,
            showOtherMetricsModule,
            showFAQModule
        ].contains(true)
    }

    private var dashboardSectionSpacing: CGFloat {
        max(Theme.Spacing.large, adaptiveLayout.sectionSpacing)
    }

    private func dashboardLayout(bodySignalSnapshot: BodySignalSnapshot) -> some View {
        GeometryReader { proxy in
            ZStack {
                background

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: dashboardSectionSpacing) {
                        if showHeroModule {
                            todayHeroPanel(topSafeAreaInset: proxy.safeAreaInsets.top)
                                .padding(.horizontal, -adaptiveLayout.outerPadding)
                        } else {
                            DashboardHeaderBar(
                                prefersTwoPaneLayout: adaptiveLayout.prefersTwoPaneLayout,
                                openAI: {
                                    aiInitialPrompt = nil
                                    showingAIInsightSheet = true
                                }
                            )
                        }

                        if !hasAnyVisibleContentModule {
                            emptyDashboardModulesCard
                        }

                        if showHealthGuideModule && healthGuideState != .authorized {
                            HealthKitAuthorizationCard(mode: healthGuideState) {
                                healthAuthorizationFlowCompleted = true
                                refreshHealthGuideState()
                                dashboardViewModel.loadData()
                            }
                        }

                        if showNotificationGuideModule && shouldShowNotificationGuide {
                            NotificationGuideCard()
                        }

                        if showHeroModule {
                            todayAIInsightSection
                        }

                        if showBodySignalsModule {
                            bodySignalsSection(snapshot: bodySignalSnapshot)
                        }

                        if showTrendsModule {
                            dashboardSection(
                                title: "今日趋势",
                                subtitle: "查看今天的压力与 HRV 变化"
                            ) {
                                TodayChartsCard(
                                    assessment: dashboardViewModel.cardStressAssessment,
                                    realtimeHealth: dashboardViewModel.realtimeHealth,
                                    history: dashboardViewModel.history,
                                    sevenMinuteStressPoints: dashboardViewModel.todaySevenMinuteStressPoints,
                                    avgHrvToday: dashboardViewModel.avgHrvToday,
                                    recentAvgHrv: dashboardViewModel.recentAvgHrv,
                                    restingHeartRate: dashboardViewModel.restingHeartRate,
                                    onShowInfo: { selectedInfoTopic = $0 }
                                )
                            }
                        }

                        if showSleepRecoveryModule {
                            sleepRecoverySection
                        }

                        if showSedentaryReminderModule {
                            activityRecoverySection
                        }

                        if showOtherMetricsModule {
                            otherMetricsSection
                        }

                        if showFAQModule {
                            FAQSection { question in
                                selectedFAQQuestion = DashboardFAQQuestion(question: question)
                            }
                        }

                        PageCustomizationFooterLink(title: PageCustomizationKind.today.footerPrompt) {
                            showingPageCustomization = true
                        }
                    }
                    .padding(.top, showHeroModule ? 0 : proxy.safeAreaInsets.top)
                    .frame(maxWidth: adaptiveLayout.contentMaxWidth(for: .page), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, adaptiveLayout.outerPadding)
                    .padding(.bottom, 88)
                    .background(todayScrollCanvas)
                }
                .ignoresSafeArea(.container, edges: .top)

                statusBarReadabilityScrim(topInset: proxy.safeAreaInsets.top)
                    .zIndex(10)
            }
        }
    }

    private var dashboardPresentedContent: some View {
        // PEN-3 P1-1：body 内只计算一次身体信号快照，避免 dashboardLayout 内重复重算。
        let bodySignalSnapshot = makeBodySignalSnapshot()

        return dashboardLayout(bodySignalSnapshot: bodySignalSnapshot)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingTodayHealthPermissionGuide) {
            TodayHealthPermissionGuidePopup(
                mode: todayHealthPermissionGuideMode,
                isChecking: isCheckingTodayHealthPermission,
                primaryAction: {
                    Task {
                        await handleTodayHealthPermissionGuidePrimaryAction()
                    }
                },
                settingsAction: {
                    openSystemSettings()
                },
                closeAction: {
                    showingTodayHealthPermissionGuide = false
                }
            )
            .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.82), .large], dragIndicator: .visible)
        }
        .sheet(isPresented: $showingPressureDetailSheet) {
            PressureDetailView(
                history: dashboardViewModel.history,
                preferredAssessment: dashboardViewModel.cardStressAssessment,
                preferredRealtimeHealth: dashboardViewModel.realtimeHealth,
                preferredAvgHrvToday: dashboardViewModel.avgHrvToday,
                preferredRecentAvgHrv: dashboardViewModel.recentAvgHrv,
                preferredRestingHeartRate: dashboardViewModel.restingHeartRate,
                preferredRecentAvgRestingHeartRate: dashboardViewModel.recentAvgRestingHeartRate,
                preferredSevenMinuteStressPoints: dashboardViewModel.todaySevenMinuteStressPoints,
                isModalPresentation: true
            )
            .onAppear {
                logBodySignalDetailOpen("pressure")
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .hidden)
        }
        .sheet(isPresented: $showingSleepSheet) {
            SleepDetailSheetView(viewModel: sleepViewModel, showsDismissButton: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingSnoreAnalysis) {
            SnoreAnalysisPage(viewModel: sleepViewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingSedentaryDetail) {
            NavigationStack {
                SedentaryView(viewModel: dashboardViewModel, showsDismissButtons: true)
            }
            .tint(Theme.Colors.textPrimary)
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(item: $selectedBodySignalDetail) { detail in
            NavigationStack {
                switch detail {
                case .bodyBattery:
                    BodyBatteryDetailView(
                        assessment: dashboardViewModel.cardStressAssessment,
                        history: dashboardViewModel.history,
                        recentAvgHrv: dashboardViewModel.recentAvgHrv,
                        restingHeartRate: dashboardViewModel.restingHeartRate,
                        recentAvgRestingHeartRate: dashboardViewModel.recentAvgRestingHeartRate,
                        recoveryScore: bodySignalSnapshot.recoveryScore,
                        recoveryInput: bodySignalSnapshot.recoveryInput,
                        wakeDate: sleepViewModel.sleepInterval?.end,
                        currentValue: bodySignalSnapshot.bodyBatteryValue,
                        loadInput: dashboardViewModel.bodyBatteryLoadInput,
                        trendPoints: bodySignalSnapshot.bodyBatteryTrendPoints,
                        heartRhythmResult: dashboardViewModel.heartRhythmResult,
                        initialDate: dashboardViewModel.selectedDate,
                        showsDismissButton: true
                    )
                case .focusCapacity:
                    FocusCapacityDetailView(
                        assessment: dashboardViewModel.cardStressAssessment,
                        focusAssessment: bodySignalSnapshot.focusCapacity,
                        history: dashboardViewModel.history,
                        recentAvgHrv: dashboardViewModel.recentAvgHrv,
                        restingHeartRate: dashboardViewModel.restingHeartRate,
                        recentAvgRestingHeartRate: dashboardViewModel.recentAvgRestingHeartRate,
                        bodyBatteryValue: bodySignalSnapshot.bodyBatteryValue,
                        trendSnapshot: bodySignalSnapshot.focusCapacityTrend,
                        initialDate: dashboardViewModel.selectedDate,
                        showsDismissButton: true
                    )
                }
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .hidden)
        }
        .sheet(item: $selectedOtherMetricDestination) { destination in
            otherMetricSheet(for: destination)
                .onAppear {
                    if destination == .vo2Max {
                        logBodySignalDetailOpen("vo2Max")
                    } else {
                        logBodyIndexDetailOpen(destination.rawValue)
                    }
                }
        }
        .sheet(item: $selectedFAQQuestion) { item in
            NavigationStack {
                FAQDetailView(question: item.question)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .hidden)
        }
        .sheet(item: $selectedInfoTopic) { topic in
            TodayInfoSheet(topic: topic)
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .fullScreenCover(isPresented: $showingPageCustomization) {
            PageCustomizationSheet()
        }
        .sheet(isPresented: $showingAIInsightSheet, onDismiss: {
            aiInitialPrompt = nil
        }) {
            HealthAIView(context: healthAIContext, initialPrompt: aiInitialPrompt)
            .adaptiveSheetChrome(style: .reading, detents: [.large], dragIndicator: .visible)
        }
    }

    var body: some View {
        dashboardPresentedContent
        .onAppear {
            Self.logger.info("[Today][Signals] operation=pageEnter")
            HealthDataManager.shared.syncAllDataIfNeeded()
            dashboardViewModel.loadData()
            scheduleTabHeavyDataLoad()
            refreshHealthGuideState()
            refreshNotificationGuideVisibility()
            Task { await loadHealthProfileSummary() }
            if didAppear { return }
            didAppear = true
            #if DEBUG
            HealthKitDebugDump.logAuthorizationReadinessIfNeeded()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // 回到前台时消费小组件端的行动完成变更，保持 App 内计划状态一致
            RecoveryPlanWidgetSyncCoordinator.synchronize()
            refreshHealthGuideState()
            refreshNotificationGuideVisibility()
            HealthDataManager.shared.syncAllDataIfNeeded()
            dashboardViewModel.loadData()
            scheduleTabHeavyDataLoad()
            Task {
                await dashboardViewModel.refreshSedentaryState()
                await loadHealthProfileSummary()
            }
        }
        .onReceive(sedentaryRefreshTimer) { _ in
            Task {
                await dashboardViewModel.refreshSedentaryState()
            }
        }
        .onChange(of: healthAuthorizationFlowCompleted) { _, _ in
            refreshHealthGuideState()
        }
        .onChange(of: HealthAuthorizationCoordinator.shared.phase) { _, _ in
            // 启动/回前台的异步评估完成后，同步刷新页面上的授权引导卡片。
            refreshHealthGuideState()
        }
        .onDisappear {
            notificationSettingsTask?.cancel()
            heavyDataLoadTask?.cancel()
            dashboardViewModel.cancelLoading()
        }
    }

    private var emptyDashboardModulesCard: some View {
        PageCustomizationEmptyCard()
    }

    /// 习惯/睡眠/周期数据在 30 秒冷却窗口内不重复加载（DashboardViewModel 自身已有刷新策略）。
    private func scheduleTabHeavyDataLoad() {
        heavyDataLoadTask?.cancel()
        heavyDataLoadTask = Task {
            try? await Task.sleep(
                nanoseconds: TodayDashboardInitialLoadPolicy.heavyDataDelayNanoseconds
            )
            guard !Task.isCancelled else { return }
            loadTabHeavyData()
        }
    }

    private func loadTabHeavyData() {
        let now = Date()
        if let lastHeavyTabLoadAt, now.timeIntervalSince(lastHeavyTabLoadAt) < 30 { return }
        lastHeavyTabLoadAt = now
        habitViewModel.loadData(for: Date())
        sleepViewModel.loadData()
        reportSummaryViewModel.load(days: 35)
        periodViewModel.reload(days: 90)
    }

    private func refreshHealthGuideState() {
        let newState: HealthGuideState

        if !HealthKitManager.shared.isHealthDataSupported() {
            newState = .unsupported
        } else {
            switch HealthAuthorizationCoordinator.shared.phase {
            case .authorizedFresh, .authorizedNeedsRefresh, .authorizedNoData:
                newState = .authorized
                if !healthAuthorizationFlowCompleted {
                    healthAuthorizationFlowCompleted = true
                }
            case .promptAvailable:
                newState = .needsAuthorization
            case .unknown:
                // 协调器尚未完成首次评估时，用已完成流程标记和写入权限旁证避免引导卡闪烁。
                if healthAuthorizationFlowCompleted || HealthKitManager.shared.isLikelyAuthorized() {
                    newState = .authorized
                    if !healthAuthorizationFlowCompleted {
                        healthAuthorizationFlowCompleted = true
                    }
                } else {
                    newState = .needsAuthorization
                }
            case .unavailable:
                newState = .unsupported
            }
        }

        healthGuideState = newState
    }

    private func refreshNotificationGuideVisibility() {
        notificationSettingsTask?.cancel()
        notificationSettingsTask = Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard !Task.isCancelled else { return }
            let shouldShow = !settings.authorizationStatus.allowsDashboardNotifications
            shouldShowNotificationGuide = shouldShow
        }
    }

    private var healthAIContext: HealthAIContext {
        HealthAIContextBuilder().makeContext(
            assessment: dashboardViewModel.cardStressAssessment,
            realtimeHealth: dashboardViewModel.realtimeHealth,
            restingHeartRate: dashboardViewModel.restingHeartRate,
            avgHrvToday: dashboardViewModel.avgHrvToday,
            recentAvgHrv: dashboardViewModel.recentAvgHrv,
            recentAvgRestingHeartRate: dashboardViewModel.recentAvgRestingHeartRate,
            sleepData: sleepViewModel.sleepData,
            sleepInterval: sleepViewModel.sleepInterval,
            nightlyHrv: sleepViewModel.nightlyHrv,
            nightlyRespiratoryRate: sleepViewModel.nightlyRespirationRate,
            sleepingWristTemperature: sleepViewModel.sleepingWristTemperature,
            sedentaryState: dashboardViewModel.sedentaryState,
            sedentarySummary: dashboardViewModel.sedentaryTodaySummary,
            activityPoints: dashboardViewModel.todayActivityPoints,
            walkingSpeedMpsToday: dashboardViewModel.todayWalkingSpeedMps,
            waterMlToday: habitViewModel.waterAmount,
            caffeineConsumedTodayMg: habitViewModel.caffeineAmount,
            daylightMinutesToday: habitViewModel.sunlightMinutes,
            healthProfileSummary: healthProfileSummary?.aiDigest
        )
    }

    private func makeBodySignalSnapshot() -> BodySignalSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let input = StressBodyBatteryHealthKitAdapter.makeBodyBatteryRecoveryInput(
            sleepData: sleepViewModel.sleepData,
            recentNightSummaries: sleepViewModel.recentNightSummaries,
            sleepGoalMinutes: sleepViewModel.sleepGoalMinutes,
            nightlyHrv: sleepViewModel.nightlyHrv,
            baselineHrv: sleepViewModel.baselineNightlyHrv ?? dashboardViewModel.recentAvgHrv,
            overnightHeartRate: sleepViewModel.overnightAverageHeartRate,
            baselineOvernightHeartRate: sleepViewModel.baselineOvernightHeartRate,
            restingHeartRate: dashboardViewModel.restingHeartRate,
            baselineRestingHeartRate: dashboardViewModel.recentAvgRestingHeartRate,
            nightlyRespiratoryRate: sleepViewModel.nightlyRespirationRate,
            baselineNightlyRespiratoryRate: sleepViewModel.baselineNightlyRespirationRate,
            sleepingWristTemperature: sleepViewModel.sleepingWristTemperature,
            baselineSleepingWristTemperature: sleepViewModel.baselineSleepingWristTemperature,
            sleepingBreathingDisturbances: sleepViewModel.sleepingBreathingDisturbances,
            baselineSleepingBreathingDisturbances: sleepViewModel.baselineSleepingBreathingDisturbances,
            referenceDate: now,
            calendar: calendar
        )
        let recoveryScore = StressBodyBatteryEngine.recoveryScore(input: input)
        let stressPoints = (dashboardViewModel.history?.stressPoints ?? [])
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
        let rawBodyBatteryTrendPoints = StressBodyBatteryEngine.trajectory(
            stressPoints: stressPoints,
            fallbackStress: dashboardViewModel.cardStressAssessment.score,
            recoveryScore: recoveryScore,
            wakeDate: sleepViewModel.sleepInterval?.end,
            endDate: now,
            calendar: calendar,
            load: dashboardViewModel.bodyBatteryLoadInput
        )
        // 整条轨迹使用同一有界心律修正，卡片读数即为详情曲线末点。
        let bodyBatteryTrendPoints = HeartRhythmStabilityEngine.applyPenalty(
            trajectory: rawBodyBatteryTrendPoints,
            result: dashboardViewModel.heartRhythmResult
        )
        let bodyBatteryValue = bodyBatteryTrendPoints.last?.value
        let stress = dashboardViewModel.cardStressAssessment
        let sleepEvidence = StressFocusCapacitySleepAdapter.evidence(
            durationMinutes: sleepViewModel.sleepData?.duration_minutes,
            score: sleepViewModel.sleepData?.sleep_score
        )
        let wakeDate: Date?
        if let candidateWakeDate = sleepViewModel.sleepInterval?.end,
           calendar.isDate(candidateWakeDate, inSameDayAs: now) {
            wakeDate = candidateWakeDate
        } else {
            wakeDate = nil
        }
        let focusCapacity = StressFocusCapacityEngine.evaluate(input: StressFocusCapacityInput(
            now: now,
            stressScore: stress.score,
            bodyBatteryScore: bodyBatteryValue,
            stressConfidence: stress.confidence,
            stressQuality: stress.quality,
            sleepMinutes: sleepEvidence.minutes,
            sleepGoalMinutes: sleepViewModel.sleepGoalMinutes,
            sleepScore: sleepEvidence.score,
            wakeDate: wakeDate,
            sedentaryMinutes: focusCapacitySedentaryMinutes,
            waterIntakeMl: habitViewModel.waterAmount > 0 ? habitViewModel.waterAmount : nil,
            waterTargetMl: habitViewModel.waterTarget > 0 ? habitViewModel.waterTarget : nil
        ))
        let focusCapacityTrend = StressFocusCapacityTrendSnapshot(
            assessment: focusCapacity,
            stressPoints: stressPoints,
            now: now,
            calendar: calendar
        )
        return BodySignalSnapshot(
            recoveryScore: recoveryScore,
            recoveryInput: input,
            bodyBatteryValue: bodyBatteryValue,
            bodyBatteryTrendPoints: bodyBatteryTrendPoints,
            focusCapacity: focusCapacity,
            focusCapacityTrend: focusCapacityTrend
        )
    }

    private var focusCapacitySedentaryMinutes: Int? {
        let state = dashboardViewModel.sedentaryState
        guard state.sourceStatus == .ready, !state.pausedBySleep else { return nil }
        guard state.isCounting || state.lastActivityAt != nil || state.seatedStartAt != nil else { return nil }
        return state.isCounting ? max(0, state.elapsedMinutes) : 0
    }

    @MainActor
    private func loadHealthProfileSummary() async {
        guard !isHealthProfileLoading else { return }
        isHealthProfileLoading = true
        let summary = await HealthProfileSummaryStore.shared.summary(range: .thirtyDays)
        healthProfileSummary = summary
        isHealthProfileLoading = false
    }

    @MainActor
    private func handleTodayHealthPermissionGuidePrimaryAction() async {
        switch todayHealthPermissionGuideMode {
        case .unsupported:
            showingTodayHealthPermissionGuide = false
        case .needsAuthorization:
            await requestTodayHealthPermissionAndRefresh()
        case .refreshAfterSettings:
            await refreshTodayHealthDataAndOpenIfReady()
        }
    }

    @MainActor
    private func requestTodayHealthPermissionAndRefresh() async {
        guard !isCheckingTodayHealthPermission else { return }
        isCheckingTodayHealthPermission = true
        let phase = await HealthAuthorizationCoordinator.shared.requestAuthorizationIfNeeded()
        switch phase {
        case .authorizedFresh, .authorizedNeedsRefresh, .authorizedNoData:
            healthAuthorizationFlowCompleted = true
        case .unknown, .unavailable, .promptAvailable:
            todayHealthPermissionGuideMode = .refreshAfterSettings
        }
        await refreshTodayHealthDataAndOpenIfReady(keepsCheckingFlag: true)
    }

    @MainActor
    private func refreshTodayHealthDataAndOpenIfReady(keepsCheckingFlag: Bool = false) async {
        if !keepsCheckingFlag {
            guard !isCheckingTodayHealthPermission else { return }
            isCheckingTodayHealthPermission = true
        }

        refreshHealthGuideState()
        dashboardViewModel.loadData()
        habitViewModel.loadData(for: Date())
        HealthDataManager.shared.syncAllDataIfNeeded(force: true)
        try? await Task.sleep(nanoseconds: 900_000_000)

        isCheckingTodayHealthPermission = false

        if hasStressSelfTestSignals {
            showingTodayHealthPermissionGuide = false
            showingPressureDetailSheet = true
        } else {
            todayHealthPermissionGuideMode = .refreshAfterSettings
            showingTodayHealthPermissionGuide = true
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { await UIApplication.shared.open(url) }
    }

    private func logBodySignalDetailOpen(_ signal: String) {
        Self.logger.info(
            "[Today][BodySignals] operation=detailPageEnter signal=\(signal, privacy: .public)"
        )
    }

    private func logBodyIndexDetailOpen(_ metric: String) {
        Self.logger.info(
            "[Today][BodyIndexes] operation=detailPageEnter metric=\(metric, privacy: .public)"
        )
    }

    private func todayHeroPanel(topSafeAreaInset: CGFloat) -> some View {
        // 日级压力需要累积足够时段样本；样本尚未覆盖时应立即展示已有的实时压力，
        // 与下方“综合压力”卡保持同一数据口径，避免首屏误显示“等待同步”。
        let assessment = dashboardViewModel.cardStressAssessment

        return TodayEnergyHero(
            assessment: assessment,
            prefersWideLayout: adaptiveLayout.prefersTwoPaneLayout,
            topSafeAreaInset: topSafeAreaInset,
            openAI: {
                aiInitialPrompt = nil
                showingAIInsightSheet = true
            }
        )
    }

    private var todayAIInsightSection: some View {
        Button {
            aiInitialPrompt = "请基于今天的压力、HRV、睡眠和活动状态，解释我现在最需要优先关注什么。"
            showingAIInsightSheet = true
        } label: {
            TodayAIInsightSection(
                assessment: dashboardViewModel.cardStressAssessment,
                avgHrvToday: dashboardViewModel.avgHrvToday,
                recentAvgHrv: dashboardViewModel.recentAvgHrv,
                restingHeartRate: dashboardViewModel.restingHeartRate,
                recentAvgRestingHeartRate: dashboardViewModel.recentAvgRestingHeartRate,
                currentBpm: dashboardViewModel.realtimeHealth.map { Double($0.bpm) },
                realtimeHealth: dashboardViewModel.realtimeHealth
            )
        }
        .todayCardButtonStyle()
    }

    private func bodySignalsSection(snapshot: BodySignalSnapshot) -> some View {
        dashboardSection(
            title: "身体信号",
            subtitle: "把压力、恢复、专注和心肺放在同一视角"
        ) {
            TodayDashboardCoreGridSection(
                dashboardViewModel: dashboardViewModel,
                bodyBatteryValue: snapshot.bodyBatteryValue,
                focusCapacityValue: snapshot.focusCapacity.score,
                bodyBatteryTrendPoints: snapshot.bodyBatteryTrendPoints,
                focusCapacityTrendPoints: snapshot.focusCapacityTrend.points,
                vo2MaxText: vo2MaxText,
                pressureSignalHintText: pressureSignalHintText,
                vo2MaxSignalHintText: vo2MaxSignalHintText,
                onTapPressure: {
                    showingPressureDetailSheet = true
                },
                onTapBodyBattery: {
                    selectedBodySignalDetail = .bodyBattery
                },
                onTapFocusCapacity: {
                    selectedBodySignalDetail = .focusCapacity
                },
                onTapVO2Max: {
                    selectedOtherMetricDestination = .vo2Max
                }
            )
        }
    }

    private var todayHealthPatternsAndWeekSection: some View {
        let digest = TodayDashboardDigestBuilder.make(summaries: reportSummaryViewModel.days)

        return dashboardSection(
            title: "健康回顾",
            subtitle: "从近 30 天规律回看上周表现"
        ) {
            VStack(spacing: Theme.Spacing.small) {
                TodayHealthPatternsCard(
                    patterns: digest.patterns,
                    isLoading: reportSummaryViewModel.isLoading
                )

                NavigationLink {
                    WeeklyReportView(initialRange: .lastWeek)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    TodayPreviousWeekSummaryCard(
                        review: digest.previousWeekReview,
                        rangeText: digest.previousWeekRangeText
                    )
                }
                .buttonStyle(TodaySummaryCardButtonStyle())
            }
        }
    }

    private var sleepRecoverySection: some View {
        VStack(alignment: .leading, spacing: dashboardSectionSpacing) {
            dashboardSection(
                title: "夜间恢复",
                subtitle: "查看睡眠质量、节律与鼾声线索"
            ) {
                VStack(spacing: Theme.Spacing.small) {
                    Button {
                        showingSleepSheet = true
                    } label: {
                        SleepSummaryCard(viewModel: sleepViewModel)
                    }
                    .buttonStyle(TodaySummaryCardButtonStyle())
                    .accessibilityHint("打开睡眠详情")

                    Button {
                        showingSnoreAnalysis = true
                    } label: {
                        TodaySnoreAnalysisEntryCard()
                    }
                    .buttonStyle(TodaySummaryCardButtonStyle())
                    .accessibilityHint("打开鼾声分析")
                }
            }

            todayHealthPatternsAndWeekSection
        }
    }

    private var activityRecoverySection: some View {
        dashboardSection(
            title: "活动恢复",
            subtitle: "关注久坐时长与主动打断情况"
        ) {
            TodaySedentarySummaryCard(viewModel: dashboardViewModel) {
                showingSedentaryDetail = true
            }
        }
    }

    private func dashboardSection<Content: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.supporting)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .accessibilityElement(children: .contain)
    }

    private var otherMetricsSection: some View {
        dashboardSection(
            title: "身体指数",
            subtitle: "查看关键身体数据和近期变化"
        ) {
            if dashboardViewModel.otherMetrics.isEmpty {
                emptyOtherMetricsPreview
            } else {
                LazyVGrid(columns: otherMetricsGridColumns, spacing: Theme.Spacing.small) {
                    ForEach(dashboardViewModel.otherMetrics) { metric in
                        Button {
                            guard metric.isInteractive, let destination = metric.destination else { return }
                            selectedOtherMetricDestination = destination
                        } label: {
                            TodayOtherMetricCard(metric: metric)
                        }
                        .todayCardButtonStyle()
                        .disabled(!metric.isInteractive)
                    }
                }
            }
        }
    }

    private var emptyOtherMetricsPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "3E7E73"))
                    .frame(width: 42, height: 42)
                    .bbTintedChip(tint: Color(hex: "3E7E73"), in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintOpacity: 0.10)

                VStack(alignment: .leading, spacing: 5) {
                    Text("等待更多身体信号")
                        .font(Theme.Typography.cardTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("同步后会显示 HRV、静息心率、日照、手腕温度和步态等指标。")
                        .font(Theme.Typography.supporting)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricSignalPill(title: "HRV", symbol: "waveform.path.ecg", tint: Color(hex: "3E7E73"))
                metricSignalPill(title: "静息心率", symbol: "heart.fill", tint: Color(hex: "B93A3A"))
                metricSignalPill(title: "日照", symbol: "sun.max.fill", tint: Color(hex: "A56A24"))
                metricSignalPill(title: "步态", symbol: "figure.walk", tint: Color(hex: "2B79A0"))
            }
        }
        .padding(16)
        .todayCardSurface(tint: Theme.Colors.mintGreen)
    }

    private func metricSignalPill(title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .bbTintedChip(tint: tint, in: Circle(), tintOpacity: 0.08)
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tint.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var otherMetricsGridColumns: [GridItem] {
        return [GridItem(.flexible(), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    private func otherMetricSheet(for destination: DashboardOtherMetricDestination) -> some View {
        NavigationStack {
            switch destination {
            case .hrv:
                TodayHRVDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            case .restingHeartRate:
                TodayRestingHeartRateDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            case .vo2Max:
                CardioFitnessDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            case .wristTemperature:
                TodayWristTemperatureDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            case .sunlight:
                TodaySunlightDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            case .walkingAsymmetry:
                TodayWalkingAsymmetryDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            case .heartRhythm:
                TodayHeartRhythmDetailView(
                    summary: otherMetricDetailSummary(for: destination),
                    heartRhythmResult: dashboardViewModel.heartRhythmResult,
                    personalizationContext: bodyIndexPersonalizationContext,
                    initialDate: dashboardViewModel.selectedDate
                )
            }
        }
        .adaptiveSheetChrome(style: .reading, dragIndicator: .hidden)
    }

    private var bodyIndexPersonalizationContext: BodyIndexPersonalizationContext {
        let sleep = HealthDataManager.shared.currentSleep
        return BodyIndexPersonalizationContext(
            hrvBaseline: dashboardViewModel.recentAvgHrv,
            restingHeartRateBaseline: dashboardViewModel.recentAvgRestingHeartRate,
            stressScore: dashboardViewModel.cardStressAssessment.score,
            sleepMinutes: sleep?.duration_minutes,
            sleepScore: sleep?.sleep_score,
            recentVO2Max: dashboardViewModel.recentAvgVo2Max,
            vo2SourceText: dashboardViewModel.vo2MaxAssessment.map {
                $0.source == .engineEstimated ? "眠屿估算" : "Apple 健康样本"
            },
            walkingSpeedMps: dashboardViewModel.todayWalkingSpeedMps
        )
    }

    private func otherMetricDetailSummary(for destination: DashboardOtherMetricDestination) -> TodayOtherMetricDetailSummary {
        if let metric = dashboardViewModel.otherMetrics.first(where: { $0.destination == destination }) {
            return TodayOtherMetricDetailSummary(
                title: metric.title,
                valueText: metric.valueText,
                unitText: metric.unitText,
                statusText: metric.statusText,
                deltaText: metric.deltaText,
                lastUpdatedText: metric.lastUpdatedText,
                summaryText: destination.detailSummaryText,
                symbol: destination.detailSymbol,
                tint: destination.detailTint,
                statusTone: metric.statusTone,
                trendPoints: metric.trendPoints
            )
        }

        let weeklyVO2Assessments = VO2MaxRules.assessmentsInDashboardRollingWeek(
            onOrBefore: dashboardViewModel.selectedDate,
            in: dashboardViewModel.vo2MaxHistory
        )
        let vo2TrendPoints = weeklyVO2Assessments.map {
            TimeSeriesPointDouble(timestamp: Int64($0.date.timeIntervalSince1970), value: $0.value)
        }
        let vo2Status = dashboardViewModel.vo2MaxAssessment?.fitnessLevel.localizedTitle ?? "等待样本"

        return TodayOtherMetricDetailSummary(
            title: "心肺耐力",
            valueText: vo2MaxText,
            unitText: vo2MaxText == "—" ? "" : "ml/kg/min",
            statusText: vo2Status,
            deltaText: vo2MaxSignalHintText,
            lastUpdatedText: vo2TrendPoints.isEmpty ? "等待同步" : "最近 7 天",
            summaryText: destination.detailSummaryText,
            symbol: destination.detailSymbol,
            tint: destination.detailTint,
            statusTone: dashboardViewModel.vo2MaxAssessment == nil ? .muted : .normal,
            trendPoints: vo2TrendPoints
        )
    }

    private var vo2MaxText: String {
        guard let value = dashboardViewModel.vo2MaxAssessment?.value, value > 0 else { return "—" }
        return String(format: "%.1f", value)
    }

    private var pressureSignalHintText: String {
        let assessment = dashboardViewModel.cardStressAssessment
        guard assessment.hasData else {
            return "等待 HRV 与心率完成估算"
        }
        if let score = assessment.score {
            return String(localized: "分数 \(score)，\(assessment.adviceTitle)")
        }
        return assessment.adviceTitle
    }

    private var vo2MaxSignalHintText: String {
        guard let assessment = dashboardViewModel.vo2MaxAssessment, assessment.value > 0 else {
            return String(localized: "等待有效估算")
        }
        let current = assessment.value
        switch assessment.source {
        case .healthKitActual:
            if let baseline = dashboardViewModel.recentAvgVo2Max, baseline > 0 {
                let delta = current - baseline
                if delta >= 0.8 {
                    return String(format: String(localized: "高于近期 %.1f"), delta)
                }
                if delta <= -0.8 {
                    return String(format: String(localized: "低于近期 %.1f"), abs(delta))
                }
                return String(localized: "Apple Health · 接近近期基线")
            }
            return String(localized: "Apple Health 真实样本")
        case .engineEstimated:
            return String(localized: "3.1 本地估算 · 可信度 \(localizedPercent(assessment.confidence))")
        case .engineBlended:
            return String(localized: "Apple Health 真实样本 + 本地解释")
        }
    }

    private var hasStressSelfTestSignals: Bool {
        if let avgHrv = dashboardViewModel.avgHrvToday, avgHrv > 0 { return true }
        if let hrv = dashboardViewModel.realtimeHealth?.hrv, hrv > 0 { return true }
        if let resting = dashboardViewModel.restingHeartRate, resting > 0 { return true }
        if let bpm = dashboardViewModel.realtimeHealth?.bpm, bpm > 0 { return true }
        if let history = dashboardViewModel.history, !history.stressPoints.isEmpty { return true }
        return false
    }

    private var background: some View {
        TodayVisualTokens.canvas
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func statusBarReadabilityScrim(topInset: CGFloat) -> some View {
        if topInset > 0 {
            let fadeTail: CGFloat = 12
            let totalHeight = topInset + fadeTail
            let opaqueEnd = topInset / totalHeight

            Rectangle()
                .fill(.regularMaterial)
                .overlay(TodayVisualTokens.canvasTop.opacity(0.18))
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: opaqueEnd),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: totalHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var todayScrollCanvas: some View {
        LinearGradient(
            colors: [
                TodayVisualTokens.canvasTop,
                TodayVisualTokens.canvasBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct TodayHealthPermissionGuidePopup: View {
    let mode: TodayHealthPermissionGuideMode
    let isChecking: Bool
    let primaryAction: () -> Void
    let settingsAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(hex: "ECFFF4"))
                        Image(systemName: "heart.text.square.fill")
                            .font(.appSystem(size: 28, weight: .black))
                            .foregroundColor(Color(hex: "1FA860"))
                    }
                    .frame(width: 58, height: 58)
                    .overlay(alignment: .topLeading) {
                        Text("小助手")
                            .font(.appSystem(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "17202B"))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(hex: "EEFFF5"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: "B9F4CF"), lineWidth: 1)
                            )
                            .offset(x: -14, y: -12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode == .unsupported ? "当前设备无法读取健康数据" : "无法读取到您的健康相关数据")
                            .font(.appSystem(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "171923"))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("App 会通过 HealthKit 读取手机上的心率、心率变异性、静息心率等数据，用于生成 HRV 压力自测和今日趋势判断。")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "30313A"))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 12, weight: .black))
                            .foregroundColor(Color(hex: "667085"))
                            .frame(width: 34, height: 34)
                            .background(Theme.Colors.secondarySurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("包括：心率、心率变异性、静息心率等，并利用这些数据分析出您的压力在各种场景下的趋势。")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "D8845F"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(hex: "F3D8B9"), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.appSystem(size: 20, weight: .black))
                        .foregroundColor(Color(hex: "1FA860"))
                    Text("请检查是否授权访问 Apple Health 数据：")
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "252832"))
                }

                VStack(spacing: 12) {
                    instructionCard(
                        title: "手机端：",
                        detail: "iOS 设置 - 健康 - 数据访问权限与设备 - 眠屿中点击【全部打开】"
                    )

                    instructionCard(
                        title: "手表端：",
                        detail: "Watch 设置 - 健康 - App - 眠屿中点击【全部打开】"
                    )
                }

                Text(mode.footnote)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "8A8F9B"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button(action: primaryAction) {
                        HStack(spacing: 10) {
                            if isChecking {
                                ProgressView()
                                    .tint(Color(hex: "17202B"))
                            }
                            Text(isChecking ? "正在检查..." : mode.buttonTitle)
                                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "17202B"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(hex: "B8F726"),
                                    Color(hex: "31E887")
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isChecking)

                    Button(action: settingsAction) {
                        Text("打开系统设置")
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "5F6B7A"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.Colors.secondarySurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .background(
                Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 22, x: 0, y: 10)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(
            Theme.Colors.pageBackground
            .ignoresSafeArea()
        )
    }

    private func instructionCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "20232D"))

            Text(detail)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "80858F"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: "D3F1E5"), lineWidth: 1)
        )
        .shadow(color: Color(hex: "1FA860").opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

private func makeHealthAIContext(
    assessment: StressPresentationAssessment,
    realtimeHealth: RealtimeHealth?,
    restingHeartRate: Double?,
    avgHrvToday: Double?,
    recentAvgHrv: Double?,
    recentAvgRestingHeartRate: Double?,
    sleepData: SleepData?,
    sleepInterval: SleepInterval?,
    nightlyHrv: Double?,
    nightlyRespiratoryRate: Double?,
    sleepingWristTemperature: Double?,
    sedentaryState: DashboardSedentaryState? = nil,
    sedentarySummary: SedentaryDaySummary? = nil,
    activityPoints: [TimeSeriesPointDouble] = [],
    walkingSpeedMpsToday: Double? = nil
) -> HealthAIContext {
    HealthAIContextBuilder().makeContext(
        assessment: assessment,
        realtimeHealth: realtimeHealth,
        restingHeartRate: restingHeartRate,
        avgHrvToday: avgHrvToday,
        recentAvgHrv: recentAvgHrv,
        recentAvgRestingHeartRate: recentAvgRestingHeartRate,
        sleepData: sleepData,
        sleepInterval: sleepInterval,
        nightlyHrv: nightlyHrv,
        nightlyRespiratoryRate: nightlyRespiratoryRate,
        sleepingWristTemperature: sleepingWristTemperature,
        sedentaryState: sedentaryState,
        sedentarySummary: sedentarySummary,
        activityPoints: activityPoints,
        walkingSpeedMpsToday: walkingSpeedMpsToday
    )
}

private enum TodayInfoTopic: String, Identifiable {
    case hrvTrend
    case dailyStress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrvTrend:
            return String(localized: "今日 HRV 趋势")
        case .dailyStress:
            return String(localized: "综合压力")
        }
    }

    var summary: String {
        switch self {
        case .hrvTrend:
            return String(localized: "这张图把今天的 HRV 采样和近期基线放在一起看，更容易判断恢复节律有没有变紧。")
        case .dailyStress:
            return String(localized: "这张图会把今天的综合压力估算展示为日内柱状图，帮助你找到综合压力开始抬升的时间段。")
        }
    }

    var bullets: [String] {
        switch self {
        case .hrvTrend:
            return [
                "HRV 越接近或高于近期基线，通常代表恢复状态更从容。",
                "如果某一段持续低于日内均值，往往说明那段时间更紧绷或更疲劳。",
                "没有数据时通常是今天样本还不够，或健康同步还没完成。"
            ]
        case .dailyStress:
            return [
                "综合压力值会结合 HRV、心率、静息心率和当天变化一起判断，不是单一心率读数。",
                "柱状图突然抬升时，可以结合当时的工作、运动、咖啡因或情绪事件一起看。",
                "如果今天数据很少，柱体会更稀疏或暂时为空，这是正常的同步状态。"
            ]
        }
    }
}

enum TodayBodySignalDetail: String, Identifiable {
    case bodyBattery
    case focusCapacity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyBattery:
            return String(localized: "身体电量")
        case .focusCapacity:
            return String(localized: "专注能力")
        }
    }

    var subtitle: String {
        switch self {
        case .bodyBattery:
            return String(localized: "结合夜间恢复与日内压力消耗，查看今天还剩多少可用余量。")
        case .focusCapacity:
            return StressFocusCapacityPresentation.subtitle
        }
    }

    var symbol: String {
        switch self {
        case .bodyBattery:
            return "battery.75"
        case .focusCapacity:
            return "scope"
        }
    }

    var tint: Color {
        switch self {
        case .bodyBattery:
            return Color(hex: "7597B6")
        case .focusCapacity:
            return Color(hex: "8B82B5")
        }
    }

    func value(from assessment: StressPresentationAssessment) -> Int? {
        guard let score = assessment.score else { return nil }
        return value(fromStressScore: score)
    }

    func value(fromStressScore score: Int) -> Int {
        switch self {
        case .bodyBattery:
            return StressBodyBatteryEngine.estimatedDailyLevel(averageStress: score)
        case .focusCapacity:
            return StressFocusCapacityEngine.estimatedScore(stressScore: score)
        }
    }

    func statusText(for value: Int?) -> String {
        guard let value else { return String(localized: "等待数据") }
        switch self {
        case .bodyBattery:
            switch value {
            case 80...:
                return String(localized: "电量充足")
            case 55..<80:
                return String(localized: "状态可用")
            case 30..<55:
                return String(localized: "需要省电")
            default:
                return String(localized: "优先恢复")
            }
        case .focusCapacity:
            return StressFocusCapacityPresentation.statusText(forScore: value)
        }
    }

    func summary(for value: Int?) -> String {
        guard let value else {
            return String(localized: "继续保持佩戴并同步 HRV、心率和静息心率后，这里会显示更完整的今日判断。")
        }
        switch self {
        case .bodyBattery:
            if value >= 70 {
                return String(localized: "当前身体电量相对充足，可以保持正常节奏，但仍建议给高强度任务留出恢复间隙。")
            }
            if value >= 45 {
                return String(localized: "身体电量处在中段，适合把任务分段推进，避免连续叠加强刺激。")
            }
            return String(localized: "身体电量偏低，今天更适合减少额外消耗，把恢复、补水和轻活动放到前面。")
        case .focusCapacity:
            return StressFocusCapacityPresentation.summary(forScore: value)
        }
    }

    var bullets: [String] {
        switch self {
        case .bodyBattery:
            return [
                "醒来电量由睡眠时长与评分、夜间 HRV 和静息心率相对个人基线共同确定。",
                "白天会按压力持续时间累计消耗，高压力耗电更快，低压力时允许缓慢恢复。",
                "它更适合看今天的节奏余量，不建议当作医学意义上的能量储备。",
                "周、月、年缺少逐日完整恢复数据时显示日级估算，不等同于精确储能测量。"
            ]
        case .focusCapacity:
            return StressFocusCapacityPresentation.methodBullets
        }
    }
}

private struct BodySignalScaleLegendItem {
    let range: String
    let meaning: String
    let color: Color
}

private struct BodySignalInsightItem {
    let symbol: String
    let title: String
    let detail: String
}

private struct BodyBatteryBudgetItem {
    let symbol: String
    let title: String
    let detail: String
    let tone: Color
}

/// 身体指数统一详情页：趋势、分布与完整解读都在同一阅读层级完成。
struct BodyIndexReferenceDetailContentView: View {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "TodayBodyIndexes")
    let summary: TodayOtherMetricDetailSummary
    let destination: DashboardOtherMetricDestination
    let heartRhythmResult: HeartRhythmStabilityResult
    let personalizationContext: BodyIndexPersonalizationContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPeriod: BodyBatteryDetailPeriod = .day
    @State private var referenceDate: Date
    @State private var loadedPoints: [TimeSeriesPointDouble] = []
    @State private var isLoadingPoints = false
    @State private var showingDeepAnalysis = false
    @State private var selectedChartDate: Date?
    @State private var sunlightOutdoorContext = SunlightOutdoorContext.placeholder
    @State private var personalizedMotionActive = false
    @State private var showingSharePreview = false

    init(
        summary: TodayOtherMetricDetailSummary,
        destination: DashboardOtherMetricDestination,
        heartRhythmResult: HeartRhythmStabilityResult = .unavailable,
        personalizationContext: BodyIndexPersonalizationContext = .empty,
        initialDate: Date = Date()
    ) {
        self.summary = summary
        self.destination = destination
        self.heartRhythmResult = heartRhythmResult
        self.personalizationContext = personalizationContext
        _referenceDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    private var interval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        switch selectedPeriod {
        case .day:
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: referenceDate) ?? DateInterval(start: start, duration: 7 * 86_400)
        case .month:
            return calendar.dateInterval(of: .month, for: referenceDate) ?? DateInterval(start: start, duration: 31 * 86_400)
        case .year:
            return calendar.dateInterval(of: .year, for: referenceDate) ?? DateInterval(start: start, duration: 365 * 86_400)
        }
    }

    private var points: [TimeSeriesPointDouble] {
        let healthKitPoints = loadedPoints
            .filter { interval.contains($0.date) }
            .map(bodyIndexDisplayPoint)
            .sorted { $0.date < $1.date }
        let cachedPoints = summary.trendPoints
            .filter { $0.value.isFinite && $0.value >= 0 && interval.contains($0.date) }
            .map(bodyIndexDisplayPoint)
            .sorted { $0.date < $1.date }

        var filtered = healthKitPoints.isEmpty ? cachedPoints : healthKitPoints
        if filtered.isEmpty,
           interval.contains(Date()),
           let currentValue = Double(summary.valueText) {
            filtered = [
                TimeSeriesPointDouble(
                    timestamp: Int64(Date().timeIntervalSince1970),
                    value: destination == .walkingAsymmetry ? currentValue * 100 : currentValue
                )
            ]
        }

        if destination != .walkingAsymmetry,
           selectedPeriod == .day,
           filtered.count == 1,
           let point = filtered.first,
           point.date == Calendar.current.startOfDay(for: point.date),
           let midday = Calendar.current.date(byAdding: .hour, value: 12, to: point.date) {
            filtered = [TimeSeriesPointDouble(timestamp: Int64(midday.timeIntervalSince1970), value: point.value)]
        }

        guard selectedPeriod == .year else { return filtered }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.compactMap { date, values in
            guard !values.isEmpty else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: values.map(\.value).reduce(0, +) / Double(values.count))
        }.sorted { $0.date < $1.date }
    }

    private func bodyIndexDisplayPoint(_ point: TimeSeriesPointDouble) -> TimeSeriesPointDouble {
        guard destination == .walkingAsymmetry else { return point }
        // HealthKit 的百分比单位以 0...1 的小数表示，趋势步态图则展示面向用户的 0...100 百分数。
        return TimeSeriesPointDouble(timestamp: point.timestamp, value: point.value * 100)
    }

    private var averageText: String {
        guard !points.isEmpty else { return "暂无" }
        return formatValue(points.map(\.value).reduce(0, +) / Double(points.count))
    }

    private var highText: String { points.map(\.value).max().map(formatValue) ?? "暂无" }
    private var lowText: String { points.map(\.value).min().map(formatValue) ?? "暂无" }

    private var averageValue: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private var selectedPoint: TimeSeriesPointDouble? {
        guard !points.isEmpty else { return nil }
        guard let selectedChartDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedChartDate)) < abs($1.date.timeIntervalSince(selectedChartDate))
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            switch destination {
            case .hrv: return 0...100
            case .restingHeartRate: return 40...100
            case .vo2Max: return 15...60
            case .wristTemperature: return 34...38
            case .sunlight: return 0...60
            case .walkingAsymmetry: return 0...20
            case .heartRhythm: return 0...100
            }
        }
        let spread = max(maximum - minimum, minimumYDomainPadding * 2)
        let padding = max(spread * 0.18, minimumYDomainPadding)

        switch destination {
        case .sunlight, .walkingAsymmetry:
            return 0...max(maximum + padding, destination == .sunlight ? 30 : 20)
        case .hrv:
            return max(0, minimum - padding)...(maximum + padding)
        case .restingHeartRate:
            return min(40, minimum - padding)...max(100, maximum + padding)
        case .vo2Max, .wristTemperature, .heartRhythm:
            return (minimum - padding)...(maximum + padding)
        }
    }

    private var minimumYDomainPadding: Double {
        switch destination {
        case .hrv: return 5
        case .restingHeartRate: return 3
        case .vo2Max: return 1.5
        case .wristTemperature: return 0.2
        case .sunlight: return 5
        case .walkingAsymmetry: return 1.5
        case .heartRhythm: return 5
        }
    }

    private var currentText: String {
        if let selectedPoint {
            return formatValue(selectedPoint.value)
        }
        return Calendar.current.isDateInToday(referenceDate) && selectedPeriod == .day ? summary.valueText : "暂无"
    }

    private var statusColor: Color {
        guard let representativeValue else { return Color(hex: "87928D") }
        switch destination {
        case .hrv, .wristTemperature:
            return summary.tint
        case .restingHeartRate:
            return (50...80).contains(representativeValue) ? Color(hex: "1B9266") : Color(hex: "E26B4F")
        case .vo2Max:
            return representativeValue >= 36 ? Color(hex: "1B9266") : Color(hex: "A56A24")
        case .sunlight:
            return representativeValue >= 20 ? Color(hex: "1B9266") : Color(hex: "A56A24")
        case .walkingAsymmetry:
            return representativeValue <= 10 ? Color(hex: "1B9266") : Color(hex: "E26B4F")
        case .heartRhythm:
            return summary.tint
        }
    }

    private var representativeValue: Double? {
        selectedChartDate == nil ? averageValue : selectedPoint?.value
    }

    private var activeStatusText: String {
        guard let representativeValue else { return "等待数据" }
        switch destination {
        case .hrv:
            return String(localized: "已记录")
        case .restingHeartRate:
            if representativeValue < 50 { return "偏低参考" }
            if representativeValue <= 80 { return "相对平稳" }
            return String(localized: "偏高参考")
        case .vo2Max:
            if representativeValue < 28 { return "打底期" }
            if representativeValue < 36 { return "建立期" }
            if representativeValue < 44 { return "稳态期" }
            return String(localized: "高表现")
        case .wristTemperature:
            return String(localized: "节律参考")
        case .sunlight:
            return representativeValue >= 20 ? "达到目标" : "仍可补充"
        case .walkingAsymmetry:
            if representativeValue <= 10 { return "较稳定" }
            if representativeValue <= 15 { return "需要留意" }
            return String(localized: "偏高参考")
        case .heartRhythm:
            return String(localized: "参考")
        }
    }

    private var activeInterpretationText: String {
        guard !points.isEmpty else {
            return String(localized: "继续保持健康 App 授权与同步，当前周期出现有效样本后会自动补齐趋势。")
        }
        let range = "\(lowText) - \(highText)"
        let metricNote: String
        switch destination {
        case .hrv:
            metricNote = "HRV 更适合结合个人基线和连续变化阅读，不建议只凭单个高低点判断恢复状态。"
        case .restingHeartRate:
            metricNote = "静息心率要结合睡眠、训练负荷和个人长期水平一起看。"
        case .vo2Max:
            metricNote = "心肺能力更新较慢，连续数周的方向比单日变化更有参考价值。"
        case .wristTemperature:
            metricNote = "手腕温度更适合观察连续偏移，并结合睡眠环境和身体状态理解。"
        case .sunlight:
            metricNote = "自然光暴露重点看是否连续接近日常目标，以及暴露是否更多落在白天前半段。"
        case .walkingAsymmetry:
            metricNote = "步态不对称偶发波动常见，连续多日偏高时再结合疲劳和活动负荷观察。"
        case .heartRhythm:
            metricNote = "心律稳定性为事件聚合的参考估算，异常线索较多时建议就医核实。"
        }
        return String(localized: "\(periodTitle)读取到 \(points.count) 个有效样本，均值 \(averageText)，范围 \(range)。\(metricNote)")
    }

    private var activeDataCaption: String {
        guard let last = points.last else { return "当前周期暂无有效样本" }
        return String(localized: "最近样本 \(selectionDateText(for: last.date)) · 共 \(points.count) 个有效样本")
    }

    private var chartUnitText: String {
        switch destination {
        case .hrv: return "单位 ms"
        case .restingHeartRate: return "单位 bpm"
        case .vo2Max: return "单位 ml/kg/min"
        case .wristTemperature: return "单位 ℃"
        case .sunlight: return "单位 分钟"
        case .walkingAsymmetry: return "单位 %"
        case .heartRhythm: return "单位 分"
        }
    }

    private var periodTitle: String {
        switch selectedPeriod {
        case .day: return Calendar.current.isDateInToday(referenceDate) ? "今天" : ChineseDateText.fullDate(referenceDate)
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? referenceDate
            return "\(ChineseDateText.compactMonthDay(interval.start)) - \(ChineseDateText.compactMonthDay(end))"
        case .month: return ChineseDateText.compactMonth(referenceDate)
        case .year: return referenceDate.formatted(.dateTime.year())
        }
    }

    private var chartDomain: ClosedRange<Date> {
        interval.start...interval.end
    }

    private var xAxisDates: [Date] {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .day:
            return stride(from: 0, through: 24, by: 3).compactMap { calendar.date(byAdding: .hour, value: $0, to: interval.start) }
        case .week:
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        case .month:
            let days = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30)
            return [0, 7, 14, 21, days - 1].compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        case .year:
            return [0, 3, 6, 9, 11].compactMap { calendar.date(byAdding: .month, value: $0, to: interval.start) }
        }
    }

    private var canMoveForward: Bool {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: selectedPeriod.calendarComponent, value: 1, to: referenceDate) ?? referenceDate
        let nextIntervalStart: Date
        switch selectedPeriod {
        case .day:
            nextIntervalStart = calendar.startOfDay(for: next)
        case .week:
            nextIntervalStart = calendar.dateInterval(of: .weekOfYear, for: next)?.start ?? next
        case .month:
            nextIntervalStart = calendar.dateInterval(of: .month, for: next)?.start ?? next
        case .year:
            nextIntervalStart = calendar.dateInterval(of: .year, for: next)?.start ?? next
        }
        return nextIntervalStart <= calendar.startOfDay(for: Date())
    }

    var body: some View {
        ZStack {
            TodayVisualTokens.canvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    bodyIndexSignalHero
                    periodPicker
                    curveSection
                    metricSignalSection
                    bodyIndexSignalAdvice

                    HealthDisclaimerCard(
                        message: "\(summary.title)基于已授权健康数据做日常自我管理估算，仅供参考，不构成医疗诊断或治疗建议。"
                    )
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 0)
                .padding(.bottom, HealthDetailDesignSystem.pageBottomPadding)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSharePreview) {
            BodyIndexSharePreviewSheet(
                content: shareContent,
                symbol: summary.symbol,
                tint: summary.tint,
                trendValues: points.map(\.value)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .task {
            await reloadPoints()
            await reloadSunlightOutdoorContext()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await reloadPoints() }
        }
        .onChange(of: referenceDate) { _, _ in
            Task {
                await reloadPoints()
                await reloadSunlightOutdoorContext()
            }
        }
        .onChange(of: selectedChartDate) { _, newValue in
            logWalkingAsymmetrySelection(newValue)
        }
        .onAppear {
            startPersonalizedMotionIfNeeded()
        }
        .onChange(of: reduceMotion) { _, _ in
            startPersonalizedMotionIfNeeded()
        }
    }

    private var bodyIndexSignalHero: some View {
        ModernSignalSheetHero(
            eyebrow: String(localized: "今日身体指数"),
            title: bodyIndexHeroTitle,
            value: bodyIndexHeroValue,
            unit: bodyIndexHeroUnit,
            state: points.isEmpty ? String(localized: "等待数据") : activeStatusText,
            description: summary.summaryText,
            progress: 0,
            tint: summary.tint,
            symbol: summary.symbol,
            pills: bodyIndexHeroPills,
            onClose: { dismiss() }
        )
    }

    private var bodyIndexHeroTitle: String {
        destination == .vo2Max ? String(localized: "心肺能力") : summary.title
    }

    private var bodyIndexHeroValue: String {
        ["—", "-", "", "暂无"].contains(summary.valueText) ? "--" : summary.valueText
    }

    private var bodyIndexHeroUnit: String {
        bodyIndexHeroValue == "--" ? "" : summary.unitText
    }

    private var bodyIndexHeroPills: [ModernSignalHeroPill] {
        switch destination {
        case .hrv:
            return [
                ModernSignalHeroPill(symbol: "scope", text: String(localized: "基线对照")),
                ModernSignalHeroPill(symbol: "bed.double.fill", text: String(localized: "恢复趋势")),
                ModernSignalHeroPill(symbol: "waveform.path.ecg", text: String(localized: "压力联动"))
            ]
        case .restingHeartRate:
            return [
                ModernSignalHeroPill(symbol: "heart.fill", text: String(localized: "静息参考")),
                ModernSignalHeroPill(symbol: "arrow.up.right", text: String(localized: "恢复趋势")),
                ModernSignalHeroPill(symbol: "figure.run", text: String(localized: "负荷联动"))
            ]
        case .vo2Max:
            return [
                ModernSignalHeroPill(symbol: "lungs.fill", text: "VO₂ Max"),
                ModernSignalHeroPill(symbol: "heart.fill", text: String(localized: "恢复参考")),
                ModernSignalHeroPill(symbol: "figure.run", text: personalizationContext.vo2SourceText ?? String(localized: "训练记录"))
            ]
        case .wristTemperature:
            return [
                ModernSignalHeroPill(symbol: "moon.stars.fill", text: String(localized: "夜间样本")),
                ModernSignalHeroPill(symbol: "scope", text: String(localized: "基线偏移")),
                ModernSignalHeroPill(symbol: "clock.fill", text: String(localized: "节律线索"))
            ]
        case .sunlight:
            return [
                ModernSignalHeroPill(symbol: "clock.fill", text: String(localized: "累计时长")),
                ModernSignalHeroPill(symbol: "sunrise.fill", text: String(localized: "昼夜节律")),
                ModernSignalHeroPill(symbol: "figure.walk", text: String(localized: "户外记录"))
            ]
        case .walkingAsymmetry:
            return [
                ModernSignalHeroPill(symbol: "figure.walk", text: String(localized: "左右平衡")),
                ModernSignalHeroPill(symbol: "chart.line.uptrend.xyaxis", text: String(localized: "连续趋势")),
                ModernSignalHeroPill(symbol: "figure.run", text: String(localized: "负荷观察"))
            ]
        case .heartRhythm:
            return [
                ModernSignalHeroPill(symbol: "waveform.path.ecg.rectangle", text: String(localized: "事件汇总")),
                ModernSignalHeroPill(symbol: "chart.line.uptrend.xyaxis", text: String(localized: "趋势参考")),
                ModernSignalHeroPill(symbol: "applewatch", text: String(localized: "持续监测"))
            ]
        }
    }

    private var bodyIndexSignalAdvice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.appSystem(size: 16, weight: .black))
                .foregroundColor(summary.tint)
                .frame(width: 38, height: 38)
                .background(Theme.Colors.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(personalizedContent.headline)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(personalizedContent.actions.first ?? personalizedContent.detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(summary.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(summary.tint.opacity(0.12), lineWidth: 1)
        }
    }

    private var periodPicker: some View {
        ModernReportSegmentedPicker(
            selection: Binding(
                get: { selectedPeriod },
                set: {
                    selectedPeriod = $0
                    selectedChartDate = nil
                }
            ),
            options: BodyBatteryDetailPeriod.allCases.map {
                ModernReportPickerOption(value: $0, title: $0.title)
            }
        )
    }

    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            dateRow

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(destination == .vo2Max ? "样本趋势" : "\(summary.title)曲线")
                    .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(chartUnitText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text(
                    destination == .vo2Max
                        ? (points.isEmpty ? "等待样本" : "\(points.count) 个离散样本")
                        : (points.isEmpty ? "等待样本" : "均值 \(averageText)")
                )
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }

            ZStack {
                alignedMetricTrendChart
                    .opacity(points.isEmpty ? 0 : 1)

                if isLoadingPoints && points.isEmpty {
                    ModernReportChartLoadingState(
                        title: "正在读取健康数据",
                        tint: statusColor
                    )
                } else if points.isEmpty {
                    ModernReportChartEmptyState(
                        symbol: summary.symbol,
                        title: bodyIndexEmptyStateTitle,
                        message: bodyIndexEmptyStateMessage,
                        tint: summary.tint
                    )
                }
            }
        }
        .padding(16)
        .background(TodayVisualTokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(TodayVisualTokens.surfaceStroke.opacity(0.6), lineWidth: 0.5))

    }

    private var bodyIndexEmptyStateTitle: String {
        destination == .vo2Max ? "等待心肺能力样本" : "等待\(summary.title)趋势"
    }

    private var bodyIndexEmptyStateMessage: String {
        switch destination {
        case .vo2Max:
            return "佩戴 Apple Watch 完成符合条件的户外步行或跑步后，健康 App 会生成心肺能力估算。"
        case .hrv:
            return "保持手表佩戴并完成同步，出现有效 HRV 样本后会自动生成趋势。"
        case .restingHeartRate:
            return "持续佩戴手表，健康 App 建立静息心率样本后会自动补齐趋势。"
        case .wristTemperature:
            return "夜间持续佩戴支持的 Apple Watch，建立基线后会显示温度变化。"
        case .sunlight:
            return "允许健康数据同步后，户外自然光暴露记录会显示在这里。"
        case .walkingAsymmetry:
            return "携带 iPhone 行走并完成健康数据同步后，会显示步态平衡趋势。"
        case .heartRhythm:
            return "出现可用的心律事件或相关健康样本后，会在这里形成趋势。"
        }
    }

    private var metricTrendChart: some View {
        VStack(spacing: 10) {
            Chart {
                if destination == .walkingAsymmetry {
                    RectangleMark(
                        xStart: .value("开始", chartDomain.lowerBound),
                        xEnd: .value("结束", chartDomain.upperBound),
                        yStart: .value("稳定下界", 0),
                        yEnd: .value("稳定上界", 10)
                    )
                    .foregroundStyle(Color(hex: "1B9266").opacity(0.08))

                    RectangleMark(
                        xStart: .value("开始", chartDomain.lowerBound),
                        xEnd: .value("结束", chartDomain.upperBound),
                        yStart: .value("留意下界", 10),
                        yEnd: .value("留意上界", 15)
                    )
                    .foregroundStyle(Color(hex: "F3A53B").opacity(0.08))

                    RectangleMark(
                        xStart: .value("开始", chartDomain.lowerBound),
                        xEnd: .value("结束", chartDomain.upperBound),
                        yStart: .value("偏高下界", 15),
                        yEnd: .value("偏高上界", chartYDomain.upperBound)
                    )
                    .foregroundStyle(Color(hex: "E26B4F").opacity(0.07))

                    RuleMark(y: .value("留意阈值", 10))
                        .foregroundStyle(Color(hex: "F3A53B").opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    RuleMark(y: .value("偏高阈值", 15))
                        .foregroundStyle(Color(hex: "E26B4F").opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(points) { point in
                        LineMark(x: .value("时间", point.date), y: .value("不对称", point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color(hex: "245E78"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        PointMark(x: .value("时间", point.date), y: .value("不对称", point.value))
                            .foregroundStyle(walkingAsymmetryColor(for: point.value))
                            .symbolSize(point.id == selectedPoint?.id ? 64 : (points.count > 20 ? 18 : 34))
                    }
                } else if destination == .sunlight {
                    if selectedPeriod != .day {
                        RuleMark(y: .value("日常目标", 20))
                            .foregroundStyle(Color(hex: "A56A24").opacity(0.65))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    }

                    ForEach(points) { point in
                        BarMark(
                            x: .value("时间", point.date),
                            y: .value("日照分钟", point.value),
                            width: .ratio(selectedPeriod == .day ? 0.72 : 0.62)
                        )
                        .foregroundStyle(point.value >= 20 ? Color(hex: "A56A24") : Color(hex: "F4C875"))
                        .cornerRadius(4)
                    }
                } else if destination == .vo2Max {
                    if let averageValue {
                        RuleMark(y: .value("周期均值", averageValue))
                            .foregroundStyle(summary.tint.opacity(0.34))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }

                    ForEach(points) { point in
                        if points.count > 1 {
                            LineMark(x: .value("时间", point.date), y: .value("心肺耐力", point.value))
                                .interpolationMethod(.linear)
                                .foregroundStyle(summary.tint.opacity(0.72))
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }

                        PointMark(x: .value("时间", point.date), y: .value("心肺耐力", point.value))
                            .foregroundStyle(Theme.Colors.surface)
                            .symbolSize(point.id == selectedPoint?.id ? 92 : 48)
                            .annotation(position: .overlay) {
                                Circle()
                                    .fill(summary.tint)
                                    .frame(width: point.id == selectedPoint?.id ? 12 : 8)
                            }
                    }
                } else if destination == .restingHeartRate {
                    RectangleMark(
                        xStart: .value("开始", chartDomain.lowerBound),
                        xEnd: .value("结束", chartDomain.upperBound),
                        yStart: .value("参考下界", 50),
                        yEnd: .value("参考上界", 80)
                    )
                    .foregroundStyle(Color(hex: "1B9266").opacity(0.08))

                    RuleMark(y: .value("参考下界", 50))
                        .foregroundStyle(Color(hex: "1B9266").opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("参考上界", 80))
                        .foregroundStyle(Color(hex: "E26B4F").opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(points) { point in
                        LineMark(x: .value("时间", point.date), y: .value("静息心率", point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color(hex: "A94444"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("时间", point.date), y: .value("静息心率", point.value))
                            .foregroundStyle(restingHeartRateColor(for: point.value))
                            .symbolSize(point.id == selectedPoint?.id ? 64 : 34)
                    }
                } else if destination == .wristTemperature {
                    if let averageValue {
                        RectangleMark(
                            xStart: .value("开始", chartDomain.lowerBound),
                            xEnd: .value("结束", chartDomain.upperBound),
                            yStart: .value("基线下界", averageValue - 0.3),
                            yEnd: .value("基线上界", averageValue + 0.3)
                        )
                        .foregroundStyle(Color(hex: "8266C6").opacity(0.08))

                        RuleMark(y: .value("周期基线", averageValue))
                            .foregroundStyle(Color(hex: "8266C6").opacity(0.48))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }

                    ForEach(points) { point in
                        LineMark(x: .value("时间", point.date), y: .value("手腕温度", point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color(hex: "6750A4"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("时间", point.date), y: .value("手腕温度", point.value))
                            .foregroundStyle(Color(hex: "9A82D8"))
                            .symbolSize(point.id == selectedPoint?.id ? 64 : 34)
                    }
                } else {
                    if let averageValue {
                        RuleMark(y: .value("均值", averageValue))
                            .foregroundStyle(statusColor.opacity(0.32))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }

                    ForEach(points) { point in
                        AreaMark(
                            x: .value("时间", point.date),
                            yStart: .value("下界", chartYDomain.lowerBound),
                            yEnd: .value("数值", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.Colors.pastelCyan.opacity(0.55), Theme.Colors.pastelCyan.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(x: .value("时间", point.date), y: .value("数值", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(statusColor)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(x: .value("时间", point.date), y: .value("数值", point.value))
                            .foregroundStyle(statusColor)
                            .symbolSize(point.id == selectedPoint?.id ? 52 : (points.count > 20 ? 10 : 24))
                    }
                }

                if let selectedPoint, selectedChartDate != nil {
                    RuleMark(x: .value("选中", selectedPoint.date))
                        .foregroundStyle(statusColor.opacity(0.26))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: chartYDomain)
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine().foregroundStyle(Color.clear)
                    AxisTick().foregroundStyle(Color(hex: "A8AFB2"))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "747C80"))
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
                        .foregroundStyle(summary.tint.opacity(0.12))
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(yAxisLabel(for: number))
                                .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "747C80"))
                                .padding(.leading, 4)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedChartDate)
            .chartPlotStyle { plotArea in
                plotArea
                    .clipped()
                    .modernReportChartPlotSurface(tint: summary.tint, cornerRadius: 20)
            }
            .chartLegend(.hidden)
            .frame(height: 218)
            .accessibilityLabel("\(summary.title)趋势图")
            .accessibilityValue(
                selectedPoint.map { "\(selectionDateText(for: $0.date))，\(formatValue($0.value))" }
                ?? "暂无数据"
            )

            if destination == .walkingAsymmetry {
                HStack(spacing: 12) {
                    chartZoneLegend(title: "较稳定 ≤10%", tint: Color(hex: "1B9266"))
                    chartZoneLegend(title: "留意 10–15%", tint: Color(hex: "F3A53B"))
                    chartZoneLegend(title: "偏高 ≥15%", tint: Color(hex: "E26B4F"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if destination == .restingHeartRate {
                chartZoneLegend(title: "常见参考 50–80 bpm", tint: Color(hex: "1B9266"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if destination == .sunlight {
                chartZoneLegend(
                    title: selectedPeriod == .day ? "按小时展示自然光时长" : "虚线为 20 分钟日常参考",
                    tint: Color(hex: "A56A24")
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if destination == .wristTemperature {
                chartZoneLegend(title: "阴影为本周期均值 ±0.3℃", tint: Color(hex: "8266C6"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if destination == .vo2Max {
                chartZoneLegend(title: "圆点代表真实估算样本，细线仅辅助观察方向", tint: summary.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let selectedPoint {
                chartSelectionRow(point: selectedPoint)
            }
        }
    }

    @ViewBuilder
    private var alignedMetricTrendChart: some View {
        if destination == .walkingAsymmetry {
            walkingAsymmetryTimelineChart
        } else {
            metricTrendChart
        }
    }

    private var walkingAsymmetryTimelineChart: some View {
        Chart {
            RectangleMark(
                xStart: .value("开始", chartDomain.lowerBound),
                xEnd: .value("结束", chartDomain.upperBound),
                yStart: .value("稳定下界", 0),
                yEnd: .value("稳定上界", 10)
            )
            .foregroundStyle(Color(hex: "DDEEDF").opacity(0.48))

            RectangleMark(
                xStart: .value("开始", chartDomain.lowerBound),
                xEnd: .value("结束", chartDomain.upperBound),
                yStart: .value("留意下界", 10),
                yEnd: .value("留意上界", 15)
            )
            .foregroundStyle(Color(hex: "FFF0C9").opacity(0.48))

            RectangleMark(
                xStart: .value("开始", chartDomain.lowerBound),
                xEnd: .value("结束", chartDomain.upperBound),
                yStart: .value("偏高下界", 15),
                yEnd: .value("偏高上界", walkingAsymmetryUpperBound)
            )
            .foregroundStyle(Color(hex: "F8DEDA").opacity(0.46))

            ForEach([10.0, 15.0], id: \.self) { threshold in
                RuleMark(y: .value("参考阈值", threshold))
                    .foregroundStyle(Color(hex: "FFB340").opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("步态不对称", point.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color(hex: "FFB340"))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("时间", point.date),
                    y: .value("步态不对称", point.value)
                )
                .foregroundStyle(walkingAsymmetryColor(for: point.value))
                .symbolSize(point.id == selectedPoint?.id ? 78 : 42)
            }

            if let selectedPoint, selectedChartDate != nil {
                RuleMark(x: .value("选中时间", selectedPoint.date))
                    .foregroundStyle(Color(hex: "FFB340").opacity(0.38))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: 0...walkingAsymmetryUpperBound)
        .chartXAxis {
            AxisMarks(values: walkingAsymmetryXAxisDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.14))
                AxisTick(length: 3)
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.34))
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(walkingAsymmetryXAxisLabel(for: date))
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 10, 15, walkingAsymmetryUpperBound]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number.rounded()))%")
                            .padding(.leading, 4)
                    }
                }
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartXSelection(value: $selectedChartDate)
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
        }
        .frame(height: 196)
        .padding(10)
        .bbChartPlotSurface(tint: Color(hex: "C99A47"), cornerRadius: 18)
        .accessibilityLabel("步态不对称真实时间趋势图")
        .accessibilityValue(
            selectedPoint.map { "\(selectionDateText(for: $0.date))，\(formatValue($0.value))" }
            ?? "共 \(points.count) 个真实时间样本"
        )
    }

    private var walkingAsymmetryUpperBound: Double {
        let maximum = points.map(\.value).max() ?? 0
        if maximum <= 10 { return 16 }
        if maximum <= 15 { return 18 }
        return max(20, ceil((maximum + 1.5) / 5) * 5)
    }

    private var walkingAsymmetryXAxisDates: [Date] {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .day:
            return stride(from: 0, through: 24, by: 3).compactMap {
                calendar.date(byAdding: .hour, value: $0, to: interval.start)
            }
        case .week:
            return (0..<7).compactMap {
                calendar.date(byAdding: .day, value: $0, to: interval.start)
            }
        case .month:
            let dayCount = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30)
            let step = max(1, Int(ceil(Double(dayCount) / 6.0)))
            var offsets = Array(stride(from: 0, to: dayCount, by: step))
            if offsets.last != dayCount - 1 { offsets.append(dayCount - 1) }
            return offsets.compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        case .year:
            let monthOffsets = [0, 2, 4, 6, 8, 10, 11]
            return monthOffsets.compactMap {
                calendar.date(byAdding: .month, value: $0, to: interval.start)
            }
        }
    }

    private func walkingAsymmetryXAxisLabel(for date: Date) -> String {
        if abs(date.timeIntervalSince(interval.end)) < 1 {
            switch selectedPeriod {
            case .day: return "24"
            case .week: return ""
            case .month: return ""
            case .year: return ""
            }
        }
        return xAxisLabel(for: date)
    }

    private var dateRow: some View {
        HStack {
            Button { shiftDate(by: -1) } label: { Image(systemName: "chevron.left").font(.appSystem(size: 17, weight: .bold)).foregroundColor(Theme.Colors.textPrimary) }
                .buttonStyle(.plain)
            Spacer()
            Text(periodTitle)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "EFF2F2"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
            Button { shiftDate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(canMoveForward ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveForward)
        }
    }

    private var distributionSection: some View {
        HStack(spacing: 10) {
            statCard(title: selectedChartDate == nil ? "最近" : "所选", value: currentText, tint: summary.tint)
            statCard(
                title: destination == .walkingAsymmetry ? "较高" : "高点",
                value: highText,
                tint: destination == .walkingAsymmetry ? Color(hex: "E26B4F") : Color(hex: "A56A24")
            )
            statCard(
                title: destination == .walkingAsymmetry ? "较低" : "低点",
                value: lowText,
                tint: destination == .walkingAsymmetry ? Color(hex: "1B9266") : Color(hex: "6B83E8")
            )
        }
    }

    private var metricSignalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(metricSignalSectionTitle)
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(Array(metricSignalItems.prefix(3))) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: item.symbol)
                                .font(.appSystem(size: 12, weight: .bold))
                                .foregroundColor(item.tint)
                            Text(item.title)
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(item.value)
                            .font(.appSystem(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(item.detail)
                            .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(9)
                    .background(item.tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(item.tint.opacity(0.09), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(TodayVisualTokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(TodayVisualTokens.surfaceStroke.opacity(0.6), lineWidth: 0.5))
    }

    private var metricSignalItems: [BodyIndexMetricSignalItem] {
        let latest = points.last?.value
        let average = averageValue
        let spread = zip(points, points.dropFirst()).map { abs($1.value - $0.value) }
        let averageChange = spread.isEmpty ? nil : spread.reduce(0, +) / Double(spread.count)
        switch destination {
        case .hrv:
            return [
                .init(title: "最近 HRV", value: latest.map(formatValue) ?? "暂无", detail: "观察窗口内最近一笔有效记录", symbol: "waveform.path.ecg", tint: summary.tint),
                .init(title: "周期均值", value: average.map(formatValue) ?? "暂无", detail: "比单个高低点更适合判断恢复方向", symbol: "equal.circle.fill", tint: Color(hex: "1B9266")),
                .init(title: "平均波动", value: averageChange.map(formatValue) ?? "暂无", detail: "相邻有效样本的平均变化幅度", symbol: "arrow.up.and.down", tint: Color(hex: "7D8BFF")),
                .init(title: "有效样本", value: "\(points.count) 个", detail: "样本越连续，趋势解读越可靠", symbol: "checkmark.circle.fill", tint: Color(hex: "33A6DA"))
            ]
        case .restingHeartRate:
            let outsideCount = points.filter { !(50...80).contains($0.value) }.count
            return [
                .init(title: "最近静息心率", value: latest.map(formatValue) ?? "暂无", detail: "最近一笔静息状态记录", symbol: "heart.fill", tint: summary.tint),
                .init(title: "周期均值", value: average.map(formatValue) ?? "暂无", detail: "用于对照个人长期常态", symbol: "chart.line.uptrend.xyaxis", tint: Color(hex: "7D8BFF")),
                .init(title: "参考区间外", value: "\(outsideCount) 个", detail: "低于 50 或高于 80 bpm 的样本", symbol: "exclamationmark.circle.fill", tint: outsideCount > 0 ? Color(hex: "E26B4F") : Color(hex: "1B9266")),
                .init(title: "有效样本", value: "\(points.count) 个", detail: "尽量比较相似测量条件下的数据", symbol: "checkmark.circle.fill", tint: Color(hex: "33A6DA"))
            ]
        case .vo2Max:
            return [
                .init(title: "VO₂ Max", value: latest.map(formatValue) ?? "暂无", detail: activeStatusText, symbol: "lungs.fill", tint: summary.tint),
                .init(
                    title: "静息心率",
                    value: personalizationContext.restingHeartRateBaseline.map { "\(Int($0.rounded())) bpm" } ?? "暂无",
                    detail: "恢复参考",
                    symbol: "heart.fill",
                    tint: Color(hex: "9B7650")
                ),
                .init(
                    title: "记录来源",
                    value: personalizationContext.vo2SourceText ?? "等待样本",
                    detail: points.isEmpty ? "等待同步" : "\(points.count) 个样本",
                    symbol: "figure.run",
                    tint: Color(hex: "7C8B6A")
                )
            ]
        case .wristTemperature:
            let deviation = latest.flatMap { latest in average.map { latest - $0 } }
            return [
                .init(title: "最近夜间值", value: latest.map(formatValue) ?? "暂无", detail: "来自睡眠期间的手腕温度记录", symbol: "thermometer.medium", tint: summary.tint),
                .init(title: "周期基线", value: average.map(formatValue) ?? "暂无", detail: "当前范围内有效样本的均值", symbol: "scope", tint: Color(hex: "7D8BFF")),
                .init(title: "最新偏移", value: deviation.map { String(format: "%+.1f ℃", $0) } ?? "暂无", detail: "最近值相对当前周期基线", symbol: "arrow.left.and.right", tint: Color(hex: "F3A53B")),
                .init(title: "有效夜晚", value: "\(points.count) 晚", detail: "连续夜间记录比单次变化更有意义", symbol: "moon.stars.fill", tint: Color(hex: "6750A4"))
            ]
        case .sunlight:
            let total = points.map(\.value).reduce(0, +)
            let reachedCount = points.filter { $0.value >= 20 }.count
            return [
                .init(title: selectedPeriod == .day ? "当日累计" : "范围累计", value: points.isEmpty ? "暂无" : formatValue(total), detail: "所选范围内已记录的自然光时长", symbol: "sun.max.fill", tint: summary.tint),
                .init(title: "平均时长", value: average.map(formatValue) ?? "暂无", detail: selectedPeriod == .day ? "每个有记录时段的平均值" : "每个有效日的平均值", symbol: "clock.fill", tint: Color(hex: "7D8BFF")),
                .init(title: "达到 20 分钟", value: "\(reachedCount) 个", detail: selectedPeriod == .day ? "达到参考时长的小时段" : "达到日常参考的有效日", symbol: "checkmark.seal.fill", tint: Color(hex: "1B9266")),
                .init(title: "有效记录", value: "\(points.count) 个", detail: "未佩戴时段可能不会被记录", symbol: "applewatch", tint: Color(hex: "33A6DA"))
            ]
        case .walkingAsymmetry:
            let elevatedCount = points.filter { $0.value > 10 }.count
            return [
                .init(title: "最近不对称", value: latest.map(formatValue) ?? "暂无", detail: "数值越低通常表示左右步伐越平衡", symbol: "figure.walk", tint: walkingAsymmetryColor(for: latest ?? 0)),
                .init(title: "周期均值", value: average.map(formatValue) ?? "暂无", detail: "用于判断是否持续偏离稳定区间", symbol: "equal.circle.fill", tint: Color(hex: "7D8BFF")),
                .init(title: "超过 10%", value: "\(elevatedCount) 个", detail: "需要结合疲劳、疼痛和活动负荷观察", symbol: "exclamationmark.triangle.fill", tint: elevatedCount > 0 ? Color(hex: "E26B4F") : Color(hex: "1B9266")),
                .init(title: "有效样本", value: "\(points.count) 个", detail: "连续多日偏高比单次波动更值得留意", symbol: "checkmark.circle.fill", tint: Color(hex: "33A6DA"))
            ]
        case .heartRhythm:
            let metrics = HeartRhythmStabilityPresentation.overviewMetrics(for: heartRhythmResult)
            let symbols = ["gauge.with.dots.needle.50percent", "waveform.path.ecg.rectangle", "exclamationmark.heart.fill", "heart.text.square.fill"]
            let tints = [summary.tint, Color(hex: "7D8BFF"), Color(hex: "E26B4F"), Color(hex: "33A6DA")]
            return zip(zip(metrics, symbols), tints).map { pair, tint in
                let (metric, symbol) = pair
                return .init(title: metric.title, value: metric.value, detail: metric.detail, symbol: symbol, tint: tint)
            }
        }
    }

    private var metricSignalSectionTitle: String {
        switch destination {
        case .hrv: return "恢复概览"
        case .restingHeartRate: return "心率概览"
        case .vo2Max: return "摘要"
        case .wristTemperature: return "夜间温度概览"
        case .sunlight: return "日照概览"
        case .walkingAsymmetry: return "步态概览"
        case .heartRhythm: return "心律概览"
        }
    }

    private var personalizedContent: BodyIndexPersonalizedContent {
        BodyIndexPersonalization.content(
            for: destination,
            points: points,
            currentValue: selectedPoint?.value ?? Double(summary.valueText),
            heartRhythmResult: heartRhythmResult,
            context: personalizationContext
        )
    }

    private var personalizedMotion: BodyIndexPersonalizationMotion {
        BodyIndexPersonalizationMotion.resolve(
            reduceMotion: reduceMotion,
            isActive: personalizedMotionActive
        )
    }

    private var personalizedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                Text("个人坐标")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(summary.tint)
                    .tracking(1.2)
                Rectangle()
                    .fill(summary.tint.opacity(0.28))
                    .frame(height: 1)
                Text("基于你的数据")
                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Text(personalizedContent.headline)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(personalizedContent.detail)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if destination == .sunlight {
                sunlightEnvironmentBand
            } else {
                personalizedFactsRail
                if destination == .wristTemperature {
                    wristEnvironmentBand
                }
            }

            if let primaryAction = personalizedContent.actions.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今天先做")
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(summary.tint)
                        .tracking(0.8)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.up.right")
                            .font(.appSystem(size: 11, weight: .black))
                            .foregroundColor(summary.tint)
                            .padding(.top, 2)
                        Text(primaryAction)
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if personalizedContent.actions.count > 1 {
                        Text(personalizedContent.actions[1])
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.leading, 22)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(summary.tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            TodayVisualTokens.surface
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(summary.tint)
                .frame(width: 3)
                .padding(.vertical, 22)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TodayVisualTokens.surfaceStroke.opacity(0.6), lineWidth: 0.5)
        )

    }

    private var personalizedFactsRail: some View {
        VStack(spacing: 0) {
            ForEach(Array(personalizedContent.facts.enumerated()), id: \.element.title) { index, fact in
                HStack(spacing: 12) {
                    ZStack {
                        if index < personalizedContent.facts.count - 1 {
                            Rectangle()
                                .fill(summary.tint.opacity(0.18))
                                .frame(width: 1, height: 32)
                                .offset(y: 24)
                        }
                        Circle()
                            .fill(index == 0 ? summary.tint : Color.white)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(summary.tint.opacity(index == 0 ? 0 : 0.28), lineWidth: 1))
                            .scaleEffect(index == 0 ? personalizedMotion.primaryNodeScale : 1)
                            .animation(
                                reduceMotion || index != 0 ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                                value: personalizedMotionActive
                            )
                        Image(systemName: fact.symbol)
                            .font(.appSystem(size: 11, weight: .bold))
                            .foregroundColor(index == 0 ? .white : summary.tint)
                    }

                    Text(fact.title)
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Spacer(minLength: 8)

                    Text(fact.value)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 2)
    }

    private var wristEnvironmentBand: some View {
        HStack(spacing: 12) {
            Image(systemName: sunlightOutdoorContext.weatherSymbolName)
                .font(.appSystem(size: 20, weight: .semibold))
                .foregroundColor(summary.tint)
                .offset(y: personalizedMotion.weatherOffset)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                    value: personalizedMotionActive
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("当地环境 · \(sunlightOutdoorContext.locationName)")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Text("\(sunlightOutdoorContext.currentConditionDescription)  \(sunlightOutdoorContext.currentTemperatureText)")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sunlightEnvironmentBand: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: sunlightOutdoorContext.weatherSymbolName)
                    .font(.appSystem(size: 28, weight: .semibold))
                    .foregroundColor(summary.tint)
                    .frame(width: 42)
                    .offset(y: personalizedMotion.weatherOffset)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                        value: personalizedMotionActive
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(sunlightOutdoorContext.locationName) · \(Date.now.formatted(.dateTime.hour().minute()))")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("\(sunlightOutdoorContext.currentConditionDescription)  \(sunlightOutdoorContext.currentTemperatureText)")
                        .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("UV")
                        .font(.appSystem(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(sunlightOutdoorContext.currentUVIndex.map(String.init) ?? "--")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(summary.tint)
                }
            }
            .padding(.bottom, 13)

            Rectangle().fill(TodayVisualTokens.surfaceStroke).frame(height: 1)

            HStack {
                Label("峰值 \(sunlightOutdoorContext.peakUVIndex.map(String.init) ?? "--")", systemImage: "sun.max")
                Spacer()
                Label(sunlightOutdoorContext.bestExposureWindowText, systemImage: "clock")
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.vertical, 12)

            HStack {
                Label(sunlightOutdoorContext.sunriseText, systemImage: "sunrise.fill")
                Spacer()
                Text(sunlightOutdoorContext.statusLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(summary.tint.opacity(0.12), in: Capsule())
                Spacer()
                Label(sunlightOutdoorContext.sunsetText, systemImage: "sunset.fill")
            }
            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.bottom, 12)

            Text(sunlightOutdoorContext.recommendationHeadline)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(sunlightOutdoorContext.recommendationDetail)
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Label(sunlightOutdoorContext.cautionText, systemImage: "checkmark.shield")
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text("天气数据来源：Apple Weather")
                .padding(.top, 8)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(14)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func reloadSunlightOutdoorContext() async {
        guard destination == .sunlight || destination == .wristTemperature else { return }
        sunlightOutdoorContext = await SunlightSheetViewModel().loadOutdoorContext(for: referenceDate)
    }

    private func startPersonalizedMotionIfNeeded() {
        if reduceMotion {
            personalizedMotionActive = false
            return
        }
        personalizedMotionActive = false
        DispatchQueue.main.async {
            personalizedMotionActive = true
        }
    }

    private func signedFormattedValue(_ value: Double) -> String {
        let formatted = formatValue(abs(value))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "−\(formatted)" }
        return formatted
    }

    private func trendTint(for delta: Double?, higherIsBetter: Bool) -> Color {
        guard let delta else { return Theme.Colors.textTertiary }
        if abs(delta) < 0.001 { return Color(hex: "7D8BFF") }
        let improved = higherIsBetter ? delta > 0 : delta < 0
        return improved ? Color(hex: "1B9266") : Color(hex: "E26B4F")
    }

    private func walkingAsymmetryColor(for value: Double) -> Color {
        if value <= 10 { return Color(hex: "1B9266") }
        if value <= 15 { return Color(hex: "F3A53B") }
        return Color(hex: "E26B4F")
    }

    private func restingHeartRateColor(for value: Double) -> Color {
        (50...80).contains(value) ? Color(hex: "1B9266") : Color(hex: "E26B4F")
    }

    private func chartZoneLegend(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.appSystem(size: 11, weight: .bold, design: .rounded)).foregroundColor(tint)
            Text(value).font(.appSystem(size: 18, weight: .heavy, design: .rounded)).foregroundColor(Theme.Colors.textPrimary).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TodayVisualTokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(TodayVisualTokens.surfaceStroke.opacity(0.6), lineWidth: 0.5))
    }

    private var interpretationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("状态解读", systemImage: summary.symbol)
                    .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(activeStatusText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }
            Text(activeInterpretationText)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(activeDataCaption)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

        }
        .padding(16)
        .background(TodayVisualTokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(TodayVisualTokens.surfaceStroke.opacity(0.6), lineWidth: 0.5))
    }

    private var fullAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("完整指标解读", systemImage: "text.book.closed.fill")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                Text("如何理解")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(analysisBullets, id: \.self) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider().overlay(TodayVisualTokens.surfaceStroke)

            VStack(alignment: .leading, spacing: 10) {
                Text("今天怎么做")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(actionBullets, id: \.self) { item in
                    Label {
                        Text(item)
                            .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(statusColor)
                    }
                }
            }
        }
        .padding(16)
        .background(TodayVisualTokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(TodayVisualTokens.surfaceStroke.opacity(0.6), lineWidth: 0.5))
    }

    private var analysisBullets: [String] {
        switch destination {
        case .hrv:
            return [
                "优先与自己的长期基线比较，不直接与他人的数值比较。",
                "连续下降常与睡眠不足、训练负荷、心理压力或身体不适有关。",
                "单次偏高或偏低都不能独立代表健康问题，应结合静息心率和主观感受。"
            ]
        case .restingHeartRate:
            return [
                "静息心率更适合看连续趋势，短时变化可能来自咖啡因、睡眠和情绪。",
                "相对个人常态持续升高时，可同步检查恢复、发热或近期训练负荷。",
                "测量时间与佩戴稳定性会影响数值，尽量比较相似条件下的数据。"
            ]
        case .vo2Max:
            return [
                "心肺能力变化通常较慢，周和月趋势比单日数值更有意义。",
                "步行或跑步样本、心率质量和运动强度都会影响系统估算。",
                "数值应结合年龄、训练经历和个人长期方向理解。"
            ]
        case .sunlight:
            return [
                "白天前半段的自然光更有助于稳定昼夜节律。",
                "连续多日接近日常目标，比偶尔一次长时间暴露更有参考意义。",
                "设备记录可能漏掉未佩戴时段，趋势适合用于习惯管理而非精确剂量判断。"
            ]
        case .wristTemperature:
            return [
                "手腕温度重点看相对个人基线的连续偏移，不等同于体温计读数。",
                "睡眠环境、经期、饮酒和身体状态都可能改变夜间趋势。",
                "连续异常并伴随不适时，应使用可靠体温计复测并按需咨询专业人员。"
            ]
        case .walkingAsymmetry:
            return [
                "偶发不对称较常见，连续多日偏高时更值得关注。",
                "疲劳、鞋履、路面和近期运动损伤都可能影响步态。",
                "应结合步速、疼痛和活动负荷阅读，不能单独用于诊断。"
            ]
        case .heartRhythm:
            return [
                "心律稳定性综合房颤负担、心律不齐通知与 ECG 结论聚合估算。",
                "为参考指标，不能替代医生诊断，异常线索较多时建议就医核实。",
                "数据主要来自 Apple Watch，未佩戴时可能无数据。"
            ]
        }
    }

    private var actionBullets: [String] {
        switch destination {
        case .hrv:
            return ["保持今晚睡眠窗口稳定", "偏低时减少额外高强度负荷"]
        case .restingHeartRate:
            return ["补水并减少临睡前刺激", "连续偏离个人常态时优先安排恢复"]
        case .vo2Max:
            return ["保持规律有氧训练", "用数周趋势评估训练效果"]
        case .sunlight:
            return ["上午安排一次户外自然光暴露", "避免为了补时长而在强光下过度暴晒"]
        case .wristTemperature:
            return ["保持睡眠环境和佩戴条件稳定", "伴随不适时使用体温计复测"]
        case .walkingAsymmetry:
            return ["今天选择平稳路面并留意疼痛", "连续偏高时降低冲击性活动"]
        case .heartRhythm:
            return ["出现持续心悸或胸闷时及时就医", "保持佩戴以持续记录心律事件"]
        }
    }

    private var shareFacts: [BodyIndexPersonalizedFact] {
        if !personalizedContent.facts.isEmpty {
            return personalizedContent.facts
        }
        guard destination == .sunlight else { return [] }
        let sunlightUnit = summary.unitText.isEmpty ? "分钟" : summary.unitText
        let sunlightValue = ["暂无", "—", "--"].contains(currentText)
            ? "暂无"
            : "\(currentText) \(sunlightUnit)"
        return [
            .init(title: "日照记录", value: sunlightValue, symbol: "sun.max.fill"),
            .init(title: "当前天气", value: "\(sunlightOutdoorContext.currentConditionDescription) \(sunlightOutdoorContext.currentTemperatureText)", symbol: sunlightOutdoorContext.weatherSymbolName),
            .init(title: "当前 UV", value: sunlightOutdoorContext.currentUVIndex.map(String.init) ?? "暂无", symbol: "sun.max.trianglebadge.exclamationmark"),
            .init(title: "适宜时段", value: sunlightOutdoorContext.bestExposureWindowText, symbol: "clock")
        ]
    }

    private var shareContent: BodyIndexShareContent {
        BodyIndexShareContent(
            title: summary.title,
            periodText: periodTitle,
            valueText: currentText,
            unitText: summary.unitText.isEmpty
                ? chartUnitText.replacingOccurrences(of: "单位 ", with: "")
                : summary.unitText,
            statusText: points.isEmpty ? summary.statusText : activeStatusText,
            headline: personalizedContent.headline,
            detail: personalizedContent.detail,
            facts: shareFacts,
            sampleCaption: activeDataCaption
        )
    }

    private func shiftDate(by value: Int) {
        let calendar = Calendar.current
        let candidate = calendar.date(byAdding: selectedPeriod.calendarComponent, value: value, to: referenceDate) ?? referenceDate
        let today = calendar.startOfDay(for: Date())
        if value > 0, !canMoveForward { return }
        selectedChartDate = nil
        referenceDate = min(candidate, today)
    }

    private func reloadPoints() async {
        let requestedPeriod = selectedPeriod
        let requestedDate = referenceDate
        let metric = destination.rawValue
        let period = requestedPeriod.logKey
        let requestID = String(UUID().uuidString.prefix(8)).lowercased()
        let queryRoute = bodyIndexQueryRoute(for: requestedPeriod)
        let dayCount: Int
        switch requestedPeriod {
        case .day: dayCount = 1
        case .week: dayCount = 7
        case .month: dayCount = 31
        case .year: dayCount = 366
        }
        let rangeEndMode = interval.end > Date() ? "now" : "period_end"
        let anchorMode = Calendar.current.isDateInToday(requestedDate) ? "today" : "historical"
        let startedAt = Date()
        Self.logger.info(
            "[Today][BodyIndexes] operation=dataLoadStart requestID=\(requestID, privacy: .public) metric=\(metric, privacy: .public) period=\(period, privacy: .public) query=\(queryRoute, privacy: .public) requestedDays=\(dayCount, privacy: .public) anchor=\(anchorMode, privacy: .public) rangeEnd=\(rangeEndMode, privacy: .public)"
        )
        isLoadingPoints = true
        loadedPoints = []
        selectedChartDate = nil

        let queryEnd = min(interval.end, Date())
        let fetchedPoints: [TimeSeriesPointDouble]
        var loadOutcome = "success"
        do {
            switch destination {
            case .hrv:
                if selectedPeriod == .day, Calendar.current.isDateInToday(referenceDate) {
                    fetchedPoints = try await HealthKitManager.shared.fetchTodayHRVSamples()
                } else {
                    fetchedPoints = try await HealthKitManager.shared.fetchDailyHRVAverages(days: dayCount, endDate: queryEnd)
                }
            case .restingHeartRate:
                fetchedPoints = try await HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: dayCount, endDate: queryEnd)
            case .wristTemperature:
                fetchedPoints = try await HealthKitManager.shared.fetchDailySleepingWristTemperatureAverages(days: dayCount, endDate: queryEnd)
            case .sunlight:
                let intervalUnit = selectedPeriod == .day ? DateComponents(hour: 1) : DateComponents(day: 1)
                fetchedPoints = try await HealthKitManager.shared.fetchTimeInDaylightSeries(
                    start: interval.start,
                    end: queryEnd,
                    interval: intervalUnit
                )
            case .walkingAsymmetry:
                if selectedPeriod == .day {
                    fetchedPoints = try await HealthKitManager.shared.fetchWalkingAsymmetrySamples(on: referenceDate)
                } else {
                    fetchedPoints = try await HealthKitManager.shared.fetchDailyWalkingAsymmetryAverages(days: dayCount, endDate: queryEnd)
                }
            case .vo2Max:
                fetchedPoints = try await HealthKitManager.shared.fetchDailyResolvedVo2MaxAverages(days: dayCount, endDate: queryEnd)
            case .heartRhythm:
                fetchedPoints = []
            }
        } catch {
            fetchedPoints = []
            loadOutcome = "failed"
            let errorType = String(reflecting: type(of: error))
            Self.logger.error(
                "[Today][BodyIndexes] operation=dataLoadFailed requestID=\(requestID, privacy: .public) metric=\(metric, privacy: .public) period=\(period, privacy: .public) query=\(queryRoute, privacy: .public) errorType=\(errorType, privacy: .public)"
            )
        }

        guard selectedPeriod == requestedPeriod,
              Calendar.current.isDate(referenceDate, inSameDayAs: requestedDate) else {
            let elapsedMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            Self.logger.notice(
                "[Today][BodyIndexes] operation=dataLoadDiscarded requestID=\(requestID, privacy: .public) metric=\(metric, privacy: .public) period=\(period, privacy: .public) reason=selection_changed durationMs=\(elapsedMilliseconds, privacy: .public)"
            )
            return
        }

        let rejectedNonFiniteCount = fetchedPoints.lazy.filter { !$0.value.isFinite }.count
        let rejectedNegativeCount = fetchedPoints.lazy.filter { $0.value.isFinite && $0.value < 0 }.count
        let rejectedAfterEndCount = fetchedPoints.lazy.filter { $0.value.isFinite && $0.value >= 0 && $0.date > queryEnd }.count
        loadedPoints = fetchedPoints
            .filter { $0.value.isFinite && $0.value >= 0 && $0.date <= queryEnd }
            .sorted { $0.date < $1.date }
        isLoadingPoints = false
        let validCount = loadedPoints.count
        let visibleHealthKitCount = loadedPoints.lazy.filter { interval.contains($0.date) }.count
        let fallbackCandidateCount = summary.trendPoints.lazy.filter {
            $0.value.isFinite && $0.value >= 0 && interval.contains($0.date)
        }.count
        let displayedCount = points.count
        let chartState = displayedCount == 0 ? "empty" : "ready"
        let dataSource = bodyIndexDataSource(
            visibleHealthKitCount: visibleHealthKitCount,
            fallbackCandidateCount: fallbackCandidateCount,
            displayedCount: displayedCount
        )
        let inputPointCount: Int
        switch dataSource {
        case "healthkit": inputPointCount = visibleHealthKitCount
        case "summary_trend": inputPointCount = fallbackCandidateCount
        case "summary_current": inputPointCount = 1
        default: inputPointCount = 0
        }
        let renderTransform = bodyIndexRenderTransform(inputCount: inputPointCount)
        let elapsedMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        Self.logger.info(
            "[Today][BodyIndexes] operation=dataLoadComplete requestID=\(requestID, privacy: .public) metric=\(metric, privacy: .public) period=\(period, privacy: .public) query=\(queryRoute, privacy: .public) outcome=\(loadOutcome, privacy: .public) durationMs=\(elapsedMilliseconds, privacy: .public) fetchedCount=\(fetchedPoints.count, privacy: .public) validCount=\(validCount, privacy: .public) rejectedNonFiniteCount=\(rejectedNonFiniteCount, privacy: .public) rejectedNegativeCount=\(rejectedNegativeCount, privacy: .public) rejectedAfterEndCount=\(rejectedAfterEndCount, privacy: .public) visibleHealthKitCount=\(visibleHealthKitCount, privacy: .public) fallbackCandidateCount=\(fallbackCandidateCount, privacy: .public) source=\(dataSource, privacy: .public)"
        )
        logBodyIndexDataSnapshot(
            requestID: requestID,
            metric: metric,
            period: period,
            stage: "fetched",
            source: "healthkit",
            snapshotPoints: fetchedPoints
        )
        logBodyIndexDataSnapshot(
            requestID: requestID,
            metric: metric,
            period: period,
            stage: "valid",
            source: "healthkit",
            snapshotPoints: loadedPoints
        )
        logBodyIndexDataSnapshot(
            requestID: requestID,
            metric: metric,
            period: period,
            stage: "rendered",
            source: dataSource,
            snapshotPoints: points
        )
        Self.logger.info(
            "[Today][BodyIndexes] operation=chartRender requestID=\(requestID, privacy: .public) metric=\(metric, privacy: .public) period=\(period, privacy: .public) state=\(chartState, privacy: .public) source=\(dataSource, privacy: .public) inputPointCount=\(inputPointCount, privacy: .public) pointCount=\(displayedCount, privacy: .public) transform=\(renderTransform, privacy: .public) selection=\(displayedCount == 0 ? "disabled" : "enabled", privacy: .public)"
        )
        logWalkingAsymmetryTimeline(
            requestID: requestID,
            period: period,
            source: dataSource,
            state: chartState
        )
    }

    /// 打印步态不对称真实时间轴，便于核对样本位置、周期边界与动态刻度。
    private func logWalkingAsymmetryTimeline(
        requestID: String,
        period: String,
        source: String,
        state: String
    ) {
        guard destination == .walkingAsymmetry else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let domainStart = formatter.string(from: chartDomain.lowerBound)
        let domainEnd = formatter.string(from: chartDomain.upperBound)
        let axisPayload = walkingAsymmetryXAxisDates.map { date in
            "{time=\(formatter.string(from: date)),label=\(walkingAsymmetryXAxisLabel(for: date))}"
        }.joined(separator: ",")
        let renderedPayload = bodyIndexPointSnapshot(points)
        Self.logger.info(
            "[Today][WalkingAsymmetry] operation=timelineRender requestID=\(requestID, privacy: .public) period=\(period, privacy: .public) state=\(state, privacy: .public) source=\(source, privacy: .public) domainStart=\(domainStart, privacy: .public) domainEnd=\(domainEnd, privacy: .public) axisCount=\(walkingAsymmetryXAxisDates.count, privacy: .public) axis=[\(axisPayload, privacy: .public)] pointCount=\(points.count, privacy: .public) \(renderedPayload, privacy: .public)"
        )
    }

    private func logWalkingAsymmetrySelection(_ selectedDate: Date?) {
        guard destination == .walkingAsymmetry else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        guard let selectedDate else {
            Self.logger.info("[Today][WalkingAsymmetry] operation=selectionCleared")
            return
        }
        let selectedTime = formatter.string(from: selectedDate)
        let nearest = points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
        let sampleTime = nearest.map { formatter.string(from: $0.date) } ?? "none"
        let sampleValue = nearest.map { String(format: "%.6f", $0.value) } ?? "none"
        Self.logger.info(
            "[Today][WalkingAsymmetry] operation=selection selectedTime=\(selectedTime, privacy: .public) nearestSampleTime=\(sampleTime, privacy: .public) nearestValuePercent=\(sampleValue, privacy: .public)"
        )
    }

    /// 输出身体指数点位快照，长周期仅保留首尾数据以控制日志长度。
    private func logBodyIndexDataSnapshot(
        requestID: String,
        metric: String,
        period: String,
        stage: String,
        source: String,
        snapshotPoints: [TimeSeriesPointDouble]
    ) {
        let snapshot = bodyIndexPointSnapshot(snapshotPoints)
        let unit = bodyIndexLogUnit
        Self.logger.info(
            "[Today][BodyIndexes] operation=dataSnapshot requestID=\(requestID, privacy: .public) metric=\(metric, privacy: .public) period=\(period, privacy: .public) stage=\(stage, privacy: .public) source=\(source, privacy: .public) unit=\(unit, privacy: .public) count=\(snapshotPoints.count, privacy: .public) \(snapshot, privacy: .public)"
        )
    }

    private func bodyIndexPointSnapshot(_ snapshotPoints: [TimeSeriesPointDouble]) -> String {
        let maximumPreviewCount = 12
        let previewPoints: [TimeSeriesPointDouble]
        let previewMode: String
        if snapshotPoints.count <= maximumPreviewCount {
            previewPoints = snapshotPoints
            previewMode = "complete"
        } else {
            let edgeCount = maximumPreviewCount / 2
            previewPoints = Array(snapshotPoints.prefix(edgeCount)) + Array(snapshotPoints.suffix(edgeCount))
            previewMode = "first_6_last_6"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let payload = previewPoints.map { point in
            let timestamp = formatter.string(from: point.date)
            let value = String(format: "%.6f", point.value)
            let displayValue = formatValue(point.value)
            return "{time=\(timestamp),value=\(value),display=\(displayValue)}"
        }.joined(separator: ",")
        let omittedCount = max(0, snapshotPoints.count - previewPoints.count)
        return "preview=\(previewMode) omittedCount=\(omittedCount) points=[\(payload)]"
    }

    private var bodyIndexLogUnit: String {
        switch destination {
        case .hrv: return "ms"
        case .restingHeartRate: return "bpm"
        case .vo2Max: return "mL_per_kg_min"
        case .wristTemperature: return "degC"
        case .sunlight: return "min"
        case .walkingAsymmetry: return "percent"
        case .heartRhythm: return "score"
        }
    }
    private func bodyIndexQueryRoute(for period: BodyBatteryDetailPeriod) -> String {
        switch destination {
        case .hrv where period == .day && Calendar.current.isDateInToday(referenceDate):
            return "sample_query"
        case .sunlight where period == .day:
            return "hourly_statistics"
        case .sunlight:
            return "daily_interval_statistics"
        case .heartRhythm:
            return "not_applicable"
        case .walkingAsymmetry where period == .day:
            return "sample_query"
        case .hrv, .restingHeartRate, .vo2Max, .wristTemperature, .walkingAsymmetry:
            return "daily_statistics"
        }
    }

    private func bodyIndexDataSource(
        visibleHealthKitCount: Int,
        fallbackCandidateCount: Int,
        displayedCount: Int
    ) -> String {
        if visibleHealthKitCount > 0 { return "healthkit" }
        if fallbackCandidateCount > 0 { return "summary_trend" }
        if displayedCount > 0 { return "summary_current" }
        return "none"
    }

    private func bodyIndexRenderTransform(inputCount: Int) -> String {
        if selectedPeriod == .year, inputCount > 0 { return "monthly_average" }
        if destination != .walkingAsymmetry, selectedPeriod == .day, inputCount == 1 { return "midday_alignment" }
        if destination == .walkingAsymmetry, selectedPeriod == .day, inputCount > 0 { return "real_sample_time" }
        return "none"
    }

    private func chartSelectionRow(point: TimeSeriesPointDouble) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectionDateText(for: point.date))
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(point.id == points.last?.id ? "最近样本" : "所选样本")
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            Text(formatValue(point.value))
                .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(statusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func selectionDateText(for date: Date) -> String {
        switch selectedPeriod {
        case .day:
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        case .year:
            return ChineseDateText.compactMonth(date)
        case .week, .month:
            return ChineseDateText.fullDate(date)
        }
    }

    private func yAxisLabel(for value: Double) -> String {
        switch destination {
        case .vo2Max, .wristTemperature, .walkingAsymmetry:
            return String(format: "%.1f", value)
        case .hrv, .restingHeartRate, .sunlight:
            return "\(Int(value.rounded()))"
        case .heartRhythm:
            return "\(Int(value.rounded()))"
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch selectedPeriod {
        case .day:
            if abs(date.timeIntervalSince(interval.end)) < 1 {
                return "24"
            }
            return String(Calendar.current.component(.hour, from: date))
        case .week:
            return date.formatted(.dateTime.weekday(.narrow))
        case .month:
            return String(localized: "\(Calendar.current.component(.day, from: date))日")
        case .year:
            return String(localized: "\(Calendar.current.component(.month, from: date))月")
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch destination {
        case .hrv: return "\(Int(value.rounded())) ms"
        case .restingHeartRate: return "\(Int(value.rounded())) bpm"
        case .vo2Max: return String(format: "%.1f", value)
        case .wristTemperature: return String(format: "%.1f ℃", value)
        case .sunlight: return "\(Int(value.rounded())) 分钟"
        case .walkingAsymmetry: return String(format: "%.1f%%", value)
        case .heartRhythm: return "\(Int(value.rounded())) 分"
        }
    }
}

private enum BodyBatteryDetailPeriod: CaseIterable, Hashable {
    case day
    case week
    case month
    case year

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }

    var logKey: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return "今日"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "今年"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    var rollingRange: BodySignalRollingRange {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }
}

struct BodySignalDetailContentView: View {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "TodaySignals")
    let detail: TodayBodySignalDetail
    let assessment: StressPresentationAssessment
    let focusCapacityAssessment: StressFocusCapacityAssessment
    let historyStressPoints: [TimeSeriesPoint]
    let recentAvgHrv: Double?
    let restingHeartRate: Double?
    let recentAvgRestingHeartRate: Double?
    let bodyBatteryRecoveryScore: Int?
    let bodyBatteryRecoveryInput: StressBodyBatteryRecoveryInput?
    let bodyBatteryWakeDate: Date?
    let bodyBatteryCurrentValue: Int?
    let bodyBatteryLoadInput: StressBodyBatteryLoadInput
    let heartRhythmResult: HeartRhythmStabilityResult
    let focusCapacityTrendSnapshot: StressFocusCapacityTrendSnapshot
    var showsDismissButton: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedBodyBatteryPeriod: BodyBatteryDetailPeriod = .day
    @State private var bodyBatteryReferenceDate: Date
    @State private var showingBodyBatteryDeepAnalysis = false
    @State private var loadedBodyBatteryStressPoints: [TimeSeriesPoint] = []
    @State private var isLoadingBodyBatteryTrend = false
    @State private var bodyBatteryLoadRequestID = UUID()
    @State private var selectedBodyBatteryChartDate: Date?
    @State private var cachedBodyBatterySourcePoints: [TimeSeriesPoint]?
    @State private var bodyBatteryChartProgress = 0.0
    @State private var hasAnimatedBodyBatteryChart = false

    init(
        detail: TodayBodySignalDetail,
        assessment: StressPresentationAssessment,
        focusCapacityAssessment: StressFocusCapacityAssessment,
        history: HealthHistory?,
        recentAvgHrv: Double?,
        restingHeartRate: Double?,
        recentAvgRestingHeartRate: Double?,
        bodyBatteryRecoveryScore: Int?,
        bodyBatteryRecoveryInput: StressBodyBatteryRecoveryInput?,
        bodyBatteryWakeDate: Date?,
        bodyBatteryCurrentValue: Int?,
        bodyBatteryLoadInput: StressBodyBatteryLoadInput,
        bodyBatteryTrendPoints: [TimeSeriesPoint],
        heartRhythmResult: HeartRhythmStabilityResult,
        focusCapacityTrendSnapshot: StressFocusCapacityTrendSnapshot,
        initialDate: Date = Date(),
        showsDismissButton: Bool = false
    ) {
        self.detail = detail
        self.assessment = assessment
        self.focusCapacityAssessment = focusCapacityAssessment
        let calendar = Calendar.current
        let now = Date()
        let initialReferenceDate = calendar.startOfDay(for: initialDate)
        let resolvedHistoryStressPoints = history?.stressPoints ?? []
        let initialBodyBatteryPoints: [TimeSeriesPoint]
        if detail == .bodyBattery,
           calendar.isDate(initialReferenceDate, inSameDayAs: now) {
            initialBodyBatteryPoints = bodyBatteryTrendPoints
        } else {
            initialBodyBatteryPoints = []
        }

        self.historyStressPoints = resolvedHistoryStressPoints
        self.recentAvgHrv = recentAvgHrv
        self.restingHeartRate = restingHeartRate
        self.recentAvgRestingHeartRate = recentAvgRestingHeartRate
        self.bodyBatteryRecoveryScore = bodyBatteryRecoveryScore
        self.bodyBatteryRecoveryInput = bodyBatteryRecoveryInput
        self.bodyBatteryWakeDate = bodyBatteryWakeDate
        self.bodyBatteryCurrentValue = bodyBatteryCurrentValue
        self.bodyBatteryLoadInput = bodyBatteryLoadInput
        self.heartRhythmResult = heartRhythmResult
        self.focusCapacityTrendSnapshot = focusCapacityTrendSnapshot
        self.showsDismissButton = showsDismissButton
        _bodyBatteryReferenceDate = State(initialValue: initialReferenceDate)
        _cachedBodyBatterySourcePoints = State(initialValue: initialBodyBatteryPoints)
    }

    private var value: Int? {
        if detail == .bodyBattery {
            return bodyBatteryCurrentValue ?? cachedBodyBatterySourcePoints?.last?.value
        }
        return resolvedFocusCapacityAssessment.score
    }

    private var resolvedFocusCapacityAssessment: StressFocusCapacityAssessment {
        guard focusCapacityAssessment.score == nil,
              let stressScore = locallyResolvedStressScore else {
            return focusCapacityAssessment
        }
        return StressFocusCapacityEngine.evaluate(input: StressFocusCapacityInput(
            now: Date(),
            stressScore: stressScore,
            bodyBatteryScore: bodyBatteryCurrentValue,
            stressConfidence: nil,
            stressQuality: .low,
            sleepMinutes: nil,
            sleepGoalMinutes: nil,
            sleepScore: nil,
            wakeDate: nil,
            sedentaryMinutes: nil,
            waterIntakeMl: nil,
            waterTargetMl: nil
        ))
    }

    private var locallyResolvedStressScore: Int? {
        if let loaded = loadedBodyBatteryStressPoints.last?.value {
            return loaded
        }
        return historyStressPoints
            .filter { bodyBatteryPeriodInterval.contains($0.date) && $0.value > 0 }
            .max { $0.timestamp < $1.timestamp }?
            .value
    }

    private var bodyBatteryPeriodInterval: DateInterval {
        selectedBodyBatteryPeriod.rollingRange.interval(anchorDate: bodyBatteryReferenceDate)
    }

    private var bodyBatteryStressSourcePoints: [TimeSeriesPoint] {
        resolvedBodyBatteryStressSourcePoints(loadedStressPoints: loadedBodyBatteryStressPoints)
    }

    private func resolvedBodyBatteryStressSourcePoints(
        loadedStressPoints: [TimeSeriesPoint]
    ) -> [TimeSeriesPoint] {
        let calendar = Calendar.current
        let historyPoints = historyStressPoints
            .filter { bodyBatteryPeriodInterval.contains($0.date) && $0.value > 0 }
            .sorted { $0.date < $1.date }

        if selectedBodyBatteryPeriod == .day {
            return historyPoints.isEmpty ? loadedStressPoints : historyPoints
        }

        var merged = bodyBatteryDailyPointsByDate(loadedStressPoints, calendar: calendar)
        for (date, point) in bodyBatteryDailyPointsByDate(historyPoints, calendar: calendar) {
            merged[date] = point
        }
        return merged.values.sorted { $0.date < $1.date }
    }

    private func bodyBatteryDailyPointsByDate(
        _ points: [TimeSeriesPoint],
        calendar: Calendar
    ) -> [Date: TimeSeriesPoint] {
        var totals: [Date: (sum: Int, count: Int)] = [:]
        for point in points {
            let date = calendar.startOfDay(for: point.date)
            let current = totals[date] ?? (sum: 0, count: 0)
            totals[date] = (sum: current.sum + point.value, count: current.count + 1)
        }

        var result: [Date: TimeSeriesPoint] = [:]
        for (date, total) in totals {
            let average = Int((Double(total.sum) / Double(total.count)).rounded())
            result[date] = TimeSeriesPoint(
                timestamp: Int64(date.timeIntervalSince1970),
                value: average
            )
        }
        return result
    }

    private var bodyBatterySourcePoints: [TimeSeriesPoint] {
        if detail == .bodyBattery {
            if let cachedBodyBatterySourcePoints {
                return cachedBodyBatterySourcePoints
            }
            guard let bodyBatteryCurrentValue else { return [] }
            return [TimeSeriesPoint(
                timestamp: Int64(Date().timeIntervalSince1970),
                value: bodyBatteryCurrentValue
            )]
        }

        return makeBodyBatterySourcePoints()
    }

    private func makeBodyBatterySourcePoints(
        loadedStressPoints: [TimeSeriesPoint]? = nil
    ) -> [TimeSeriesPoint] {
        if detail == .bodyBattery {
            let calendar = Calendar.current
            let resolvedLoadedStressPoints = loadedStressPoints ?? loadedBodyBatteryStressPoints
            let stressSourcePoints = resolvedBodyBatteryStressSourcePoints(
                loadedStressPoints: resolvedLoadedStressPoints
            )
            if selectedBodyBatteryPeriod == .day {
                let isToday = calendar.isDateInToday(bodyBatteryReferenceDate)
                let endDate = isToday
                    ? min(Date(), bodyBatteryPeriodInterval.end.addingTimeInterval(-1))
                    : bodyBatteryPeriodInterval.end.addingTimeInterval(-1)
                let trajectory = StressBodyBatteryEngine.trajectory(
                    stressPoints: stressSourcePoints,
                    fallbackStress: stressSourcePoints.last?.value ?? (isToday ? assessment.score : nil),
                    recoveryScore: isToday ? bodyBatteryRecoveryScore : nil,
                    wakeDate: isToday ? bodyBatteryWakeDate : nil,
                    endDate: endDate,
                    calendar: calendar,
                    load: bodyBatteryLoadInput
                )
                return isToday
                    ? HeartRhythmStabilityEngine.applyPenalty(
                        trajectory: trajectory,
                        result: heartRhythmResult
                    )
                    : trajectory
            }

            var points = stressSourcePoints.map {
                TimeSeriesPoint(
                    timestamp: $0.timestamp,
                    value: StressBodyBatteryEngine.estimatedDailyLevel(averageStress: $0.value)
                )
            }
            if bodyBatteryPeriodInterval.contains(Date()), let bodyBatteryCurrentValue {
                points.removeAll { calendar.isDateInToday($0.date) }
                let today = calendar.startOfDay(for: Date())
                points.append(TimeSeriesPoint(
                    timestamp: Int64(today.timeIntervalSince1970),
                    value: bodyBatteryCurrentValue
                ))
            }
            return points.sorted { $0.date < $1.date }
        }

        var points = bodyBatteryStressSourcePoints
            .map { TimeSeriesPoint(timestamp: $0.timestamp, value: detail.value(fromStressScore: $0.value)) }
            .sorted { $0.date < $1.date }

        if Calendar.current.isDateInToday(bodyBatteryReferenceDate), let value {
            let nowTimestamp = Int64(Date().timeIntervalSince1970)
            if points.isEmpty || abs((points.last?.timestamp ?? 0) - nowTimestamp) > 600 {
                points.append(TimeSeriesPoint(timestamp: nowTimestamp, value: value))
            }
        }
        return points
    }

    private var activeBodyBatteryPoints: [TimeSeriesPoint] {
        if usesFocusCapacityTrendSnapshot {
            return focusCapacityTrendSnapshot.points
        }
        let interval = bodyBatteryPeriodInterval
        let filtered = bodyBatterySourcePoints.filter { interval.contains($0.date) }
        switch selectedBodyBatteryPeriod {
        case .day:
            return filtered
        case .week, .month:
            return aggregateBodyBatteryPoints(filtered, component: .day)
        case .year:
            return aggregateBodyBatteryPoints(filtered, component: .month)
        }
    }

    private var activeBodyBatteryAverage: Int? {
        if usesFocusCapacityTrendSnapshot {
            return focusCapacityTrendSnapshot.averageValue
        }
        guard !activeBodyBatteryPoints.isEmpty else {
            return Calendar.current.isDateInToday(bodyBatteryReferenceDate) ? value : nil
        }
        let total = activeBodyBatteryPoints.map(\.value).reduce(0, +)
        return Int((Double(total) / Double(activeBodyBatteryPoints.count)).rounded())
    }

    private var activeBodyBatteryPeakPoint: TimeSeriesPoint? {
        if usesFocusCapacityTrendSnapshot {
            return focusCapacityTrendSnapshot.peakPoint
        }
        return activeBodyBatteryPoints.max { $0.value < $1.value }
    }

    private var activeBodyBatteryLowPoint: TimeSeriesPoint? {
        if usesFocusCapacityTrendSnapshot {
            return focusCapacityTrendSnapshot.lowPoint
        }
        return activeBodyBatteryPoints.min { $0.value < $1.value }
    }

    private var selectedBodyBatteryPoint: TimeSeriesPoint? {
        guard !activeBodyBatteryPoints.isEmpty else { return nil }
        guard let selectedBodyBatteryChartDate else { return activeBodyBatteryPoints.last }
        return activeBodyBatteryPoints.min {
            abs($0.date.timeIntervalSince(selectedBodyBatteryChartDate))
                < abs($1.date.timeIntervalSince(selectedBodyBatteryChartDate))
        }
    }

    private var bodyBatteryChartDomain: ClosedRange<Date> {
        bodyBatteryPeriodInterval.start...bodyBatteryPeriodInterval.end
    }

    private var bodyBatteryXAxisDates: [Date] {
        let calendar = Calendar.current
        let start = bodyBatteryPeriodInterval.start
        switch selectedBodyBatteryPeriod {
        case .day:
            return [0, 6, 12, 18, 24].compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }
        case .week:
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let days = max(1, calendar.dateComponents([.day], from: start, to: bodyBatteryPeriodInterval.end).day ?? 30)
            return [0, 7, 14, 21, days - 1].compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .year:
            return [0, 3, 6, 9, 11].compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
        }
    }

    private var activeBodyBatteryTone: Color {
        guard let activeBodyBatteryAverage else { return Color(hex: "8DA39A") }
        if detail == .focusCapacity {
            switch StressFocusCapacityEngine.band(for: activeBodyBatteryAverage) {
            case .strong: return Color(hex: "6B83E8")
            case .available: return Color(hex: "2FBF8F")
            case .limited: return Color(hex: "A56A24")
            case .depleted: return Color(hex: "E36A5C")
            case .unavailable: return Color(hex: "8DA39A")
            }
        }
        switch activeBodyBatteryAverage {
        case 55...: return Color(hex: "2FBF8F")
        case 30..<55: return Color(hex: "A56A24")
        default: return Color(hex: "E36A5C")
        }
    }

    private var activeBodyBatteryStatus: String {
        detail.statusText(for: activeBodyBatteryAverage)
    }

    private var activeBodyBatteryAdvice: String {
        guard let activeBodyBatteryAverage else {
            return String(localized: "继续同步综合压力所需的 HRV、心率和静息心率样本，\(detail.title)会使用同一批数据自动更新。")
        }
        switch detail {
        case .bodyBattery:
            switch activeBodyBatteryAverage {
            case 80...:
                return String(localized: "这段时间的综合压力整体较低，可用恢复余量充足。可以正常推进重点事项，同时给高消耗任务留出间隔。")
            case 55..<80:
                return String(localized: "这段时间仍有可用余量，但不适合把训练、深度工作和密集社交连续堆叠。分段推进会更稳。")
            case 30..<55:
                return String(localized: "综合压力已经明显压缩可用余量。优先完成必要事项，减少额外刺激，并把恢复动作提前。")
            default:
                return String(localized: "当前更接近恢复窗口。先降低负荷、补水进食并安排轻活动，复杂任务和高强度训练尽量后移。")
            }
        case .focusCapacity:
            return StressFocusCapacityPresentation.rangeAdvice(forScore: activeBodyBatteryAverage)
        }
    }

    private var bodyBatterySelectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        switch selectedBodyBatteryPeriod {
        case .day:
            if Calendar.current.isDateInToday(bodyBatteryReferenceDate) { return "今天" }
            formatter.setLocalizedDateFormatFromTemplate("Md")
        case .week, .month, .year:
            let interval = bodyBatteryPeriodInterval
            formatter.setLocalizedDateFormatFromTemplate("Md")
            let end = interval.end.addingTimeInterval(-1)
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: end))"
        }
        return formatter.string(from: bodyBatteryReferenceDate)
    }

    private var usesFocusCapacityTrendSnapshot: Bool {
        detail == .focusCapacity
            && selectedBodyBatteryPeriod == .day
            && Calendar.current.isDateInToday(bodyBatteryReferenceDate)
            && !focusCapacityTrendSnapshot.points.isEmpty
    }

    private var trendPoints: [TimeSeriesPoint] {
        activeBodyBatteryPoints
    }

    private var averageValue: Int? {
        let values = trendPoints.map(\.value)
        guard !values.isEmpty else { return value }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private var peakValue: Int? {
        return trendPoints.map(\.value).max() ?? value
    }

    private var lowValue: Int? {
        return trendPoints.map(\.value).min() ?? value
    }

    private var bestPoint: TimeSeriesPoint? {
        return trendPoints.max { $0.value < $1.value }
    }

    private var lowPoint: TimeSeriesPoint? {
        return trendPoints.min { $0.value < $1.value }
    }

    private var dataQualityTitle: String {
        if detail == .focusCapacity {
            return StressFocusCapacityPresentation.dataQualityTitle(for: resolvedFocusCapacityAssessment)
        }
        let count = trendPoints.count
        if count >= 8 { return "样本较完整" }
        if count >= 3 { return "样本可参考" }
        if value != nil { return "当前点参考" }
        return String(localized: "等待同步")
    }

    private var dataQualityDetail: String {
        if detail == .focusCapacity {
            return StressFocusCapacityPresentation.dataQualityDetail(for: resolvedFocusCapacityAssessment)
        }
        let count = trendPoints.count
        if count >= 8 {
            return String(localized: "今天已有 \(count) 个可用点，适合看日内方向。")
        }
        if count >= 3 {
            return String(localized: "今天已有 \(count) 个可用点，可以先看大致节奏。")
        }
        if value != nil {
            return String(localized: "当前主要来自最新综合压力估算，趋势还需要更多样本。")
        }
        return String(localized: "保持佩戴并同步健康数据后，这里会更新样本质量。")
    }

    private var stressContributionText: String {
        guard let score = assessment.score else { return "等待综合压力" }
        switch score {
        case 0..<35:
            return String(localized: "压力较低，当前是主要加分项。")
        case 35..<65:
            return String(localized: "压力中等，对状态有轻微消耗。")
        default:
            return String(localized: "压力偏高，是当前主要扣分项。")
        }
    }

    private var hrvContributionText: String {
        guard let recentAvgHrv else { return "等待近期 HRV 基线" }
        if recentAvgHrv >= 50 {
            return String(localized: "HRV 基线较好，恢复底盘相对稳。")
        }
        if recentAvgHrv >= 35 {
            return String(localized: "HRV 基线处在中段，适合留意波动。")
        }
        return String(localized: "HRV 基线偏低，建议优先补恢复。")
    }

    private var heartContributionText: String {
        guard let restingHeartRate else { return "等待静息心率" }
        if restingHeartRate <= 65 {
            return String(localized: "静息心率较稳，对状态较友好。")
        }
        if restingHeartRate <= 78 {
            return String(localized: "静息心率中等，继续观察即可。")
        }
        return String(localized: "静息心率偏高，可能提示负荷抬升。")
    }

    private var isShowingCurrentBodyRecovery: Bool {
        detail == .bodyBattery
            && selectedBodyBatteryPeriod == .day
            && Calendar.current.isDateInToday(bodyBatteryReferenceDate)
    }

    private var bodyRecoveryPersonalization: BodyRecoveryPersonalization {
        let recoveryInput = bodyBatteryRecoveryInput
        return BodyRecoveryPersonalizationEngine.make(input: BodyRecoveryPersonalizationInput(
            currentBodyBattery: bodyBatteryCurrentValue,
            overnightRecoveryScore: bodyBatteryRecoveryScore,
            stressScore: assessment.score,
            nightlyHrv: recoveryInput?.nightlyHrv,
            baselineHrv: recoveryInput?.baselineHrv ?? recentAvgHrv,
            overnightHeartRate: recoveryInput?.overnightHeartRate,
            baselineOvernightHeartRate: recoveryInput?.baselineOvernightHeartRate,
            restingHeartRate: recoveryInput?.restingHeartRate ?? restingHeartRate,
            baselineRestingHeartRate: recoveryInput?.baselineRestingHeartRate,
            physicalEffortSampleCount: bodyBatteryLoadInput.physicalEffortSamples.count,
            workoutEventCount: bodyBatteryLoadInput.workoutEffortEvents.count,
            isCurrentDay: isShowingCurrentBodyRecovery
        ))
    }

    private func bodyRecoveryToneColor(_ tone: BodyRecoveryPresentationTone) -> Color {
        switch tone {
        case .positive:
            return Color(hex: "2FBF8F")
        case .neutral:
            return Color(hex: "6B83E8")
        case .caution:
            return Color(hex: "A56A24")
        case .critical:
            return Color(hex: "E36A5C")
        }
    }

    private var resolvedBodyBatteryValue: Int {
        value ?? 0
    }

    private var bodyBatteryStageSymbol: String {
        guard value != nil else { return "clock.badge.questionmark" }
        switch resolvedBodyBatteryValue {
        case 80...:
            return "battery.100"
        case 55..<80:
            return "battery.75"
        case 30..<55:
            return "battery.50"
        default:
            return "battery.25"
        }
    }

    private var bodyBatteryStageTitle: String {
        guard value != nil else { return "等待建立身体电量" }
        switch resolvedBodyBatteryValue {
        case 80...:
            return "恢复余量充足"
        case 55..<80:
            return String(localized: "可用但要留间隔")
        case 30..<55:
            return String(localized: "电量偏紧")
        default:
            return "优先恢复"
        }
    }

    private var bodyBatteryStageDetail: String {
        guard value != nil else {
            return String(localized: "同步睡眠、HRV、静息心率和压力样本后，身体电量会建立醒来基线并累计今天的消耗。")
        }
        switch resolvedBodyBatteryValue {
        case 80...:
            return String(localized: "今天可以正常推进，但高消耗事项之间仍建议保留恢复间隔。")
        case 55..<80:
            return String(localized: "适合做重要但可控的事情，避免长时间连续输出。")
        case 30..<55:
            return String(localized: "把任务切小，先保住基础节奏，别把额外消耗堆到一起。")
        default:
            return String(localized: "今天更适合恢复、补水、轻活动和减少刺激，复杂任务可以后移。")
        }
    }

    private var bodyBatteryPriorityText: String {
        guard value != nil else { return "等数据" }
        switch resolvedBodyBatteryValue {
        case 70...:
            return String(localized: "推进")
        case 45..<70:
            return String(localized: "分段")
        default:
            return "恢复"
        }
    }

    private var bodyBatteryPacingText: String {
        guard value != nil else { return "观察" }
        switch resolvedBodyBatteryValue {
        case 80...:
            return "正常"
        case 55..<80:
            return String(localized: "留白")
        case 30..<55:
            return String(localized: "降载")
        default:
            return String(localized: "慢速")
        }
    }

    var body: some View {
        bodyBatteryReferenceBody
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                logPageEntry()
            }
            .task {
                await reloadBodySignalTrend()
            }
            .onChange(of: selectedBodyBatteryPeriod) { _, _ in
                selectedBodyBatteryChartDate = nil
                cachedBodyBatterySourcePoints = nil
                guard !usesFocusCapacityTrendSnapshot else { return }
                Task { await reloadBodySignalTrend() }
            }
            .onChange(of: bodyBatteryReferenceDate) { _, _ in
                selectedBodyBatteryChartDate = nil
                cachedBodyBatterySourcePoints = nil
                guard !usesFocusCapacityTrendSnapshot else { return }
                Task { await reloadBodySignalTrend() }
            }
            .onChange(of: bodyBatteryCurrentValue) { _, _ in
                cachedBodyBatterySourcePoints = makeBodyBatterySourcePoints()
            }
            .onChange(of: bodyBatteryLoadInput) { _, _ in
                cachedBodyBatterySourcePoints = makeBodyBatterySourcePoints()
            }
    }

    private func logPageEntry() {
        switch detail {
        case .bodyBattery:
            Self.logger.info(
                "[Today][BodyBattery] operation=detailPageEnter technicalID=stress.bodyBattery"
            )
        case .focusCapacity:
            Self.logger.info(
                "[Today][FocusCapacity] operation=detailPageEnter technicalID=stress.focusCapacity"
            )
        }
    }

    private func reloadBodySignalTrend() async {
        await reloadBodyBatteryTrend()
        printBodySignalDebugData()
        switch detail {
        case .bodyBattery:
            Self.logger.info(
                "[Today][BodyBattery] operation=render technicalID=stress.bodyBattery"
            )
        case .focusCapacity:
            Self.logger.info(
                "[Today][FocusCapacity] operation=render technicalID=stress.focusCapacity"
            )
        }
    }

    private func printBodySignalDebugData() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func dateText(_ date: Date) -> String {
            formatter.string(from: date)
        }
        func intText(_ value: Int?) -> String {
            value.map(String.init) ?? "nil"
        }
        func doubleText(_ value: Double?) -> String {
            value.map { String(format: "%.2f", $0) } ?? "nil"
        }

        let pageName = detail == .bodyBattery ? "身体电量" : "专注能力"
        var lines: [String] = []
        lines.append("=== [BodySignalDebug] \(pageName)页面数据 ===")
        lines.append("metric=\(detail.rawValue) period=\(selectedBodyBatteryPeriod.rollingRange.rawValue) referenceDate=\(dateText(bodyBatteryReferenceDate))")
        lines.append("queryWindow=\(dateText(bodyBatteryPeriodInterval.start)) ~ \(dateText(bodyBatteryPeriodInterval.end)) queryEnd=\(dateText(selectedBodyBatteryPeriod.rollingRange.queryEnd(anchorDate: bodyBatteryReferenceDate))) expectedDays=\(selectedBodyBatteryPeriod.rollingRange.dayCount)")
        lines.append("current=\(intText(value)) average=\(intText(activeBodyBatteryAverage)) peak=\(intText(activeBodyBatteryPeakPoint?.value)) low=\(intText(activeBodyBatteryLowPoint?.value))")
        lines.append("recentAvgHrv=\(doubleText(recentAvgHrv)) restingHeartRate=\(doubleText(restingHeartRate)) recentAvgRestingHeartRate=\(doubleText(recentAvgRestingHeartRate))")
        lines.append("stressAssessment=\(String(reflecting: assessment))")

        if detail == .bodyBattery {
            lines.append("recoveryScore=\(intText(bodyBatteryRecoveryScore)) wakeDate=\(bodyBatteryWakeDate.map(dateText) ?? "nil")")
            lines.append("recoveryInput=\(String(reflecting: bodyBatteryRecoveryInput))")
            lines.append("loadInput=\(String(reflecting: bodyBatteryLoadInput))")
            lines.append("heartRhythmResult=\(String(reflecting: heartRhythmResult))")
        } else {
            lines.append("focusAssessment=\(String(reflecting: resolvedFocusCapacityAssessment))")
            lines.append("focusTrendSnapshot=\(String(reflecting: focusCapacityTrendSnapshot))")
        }

        lines.append("loadedStressPoints: \(loadedBodyBatteryStressPoints.count) 条")
        for (index, point) in loadedBodyBatteryStressPoints.enumerated() {
            lines.append("  [\(index)] \(dateText(point.date)) stress=\(point.value)")
        }
        lines.append("renderedTrendPoints: \(activeBodyBatteryPoints.count) 条")
        for (index, point) in activeBodyBatteryPoints.enumerated() {
            lines.append("  [\(index)] \(dateText(point.date)) value=\(point.value)")
        }
        print(lines.joined(separator: "\n"))
    }

    private var bodyBatteryReferenceBody: some View {
        ZStack {
            LinearGradient(
                colors: [detail.tint.opacity(0.08), Theme.Colors.pageBackground, Theme.Colors.pageBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        heroCard
                        bodyBatteryPeriodPicker
                        bodyBatteryCurveSection
                        bodySignalOverviewPanel
                        signalSheetAdviceCard

                        HealthDisclaimerCard(
                            message: detail == .bodyBattery
                                ? "身体电量由睡眠、HRV、静息心率与日内压力估算，用于日常节奏管理参考，不代表医学意义上的能量储备，也不构成医疗诊断或治疗建议。"
                                : StressFocusCapacityPresentation.disclaimer
                        )
                    }
                    .padding(.horizontal, Theme.Layout.padding)
                    .padding(.top, 0)
                    .padding(.bottom, 88)
                }
            }
        }
    }

    private var bodyBatteryModalHeader: some View {
        ZStack {
            Text("\(detail.title)分析")
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                ShareLink(item: bodyBatteryShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(detail.tint)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Layout.padding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [detail.tint.opacity(0.08), Color.white.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var bodyBatteryPeriodPicker: some View {
        ModernReportSegmentedPicker(
            selection: $selectedBodyBatteryPeriod,
            options: BodyBatteryDetailPeriod.allCases.map {
                ModernReportPickerOption(value: $0, title: $0.title)
            }
        )
    }

    private var bodySignalOverviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("摘要")
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("随健康数据更新")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(detail.tint)
            }

            HStack(spacing: 8) {
                bodySignalOverviewMetric(
                    title: "当前",
                    value: value.map(localizedPercent) ?? "--",
                    detail: detail.statusText(for: value),
                    symbol: detail.symbol
                )
                bodySignalOverviewMetric(
                    title: "周期均值",
                    value: activeBodyBatteryAverage.map(localizedPercent) ?? "--",
                    detail: bodyBatterySelectedDateTitle,
                    symbol: "equal.circle.fill"
                )
                bodySignalOverviewMetric(
                    title: detail == .bodyBattery ? "夜间恢复" : "状态",
                    value: detail == .bodyBattery
                        ? bodyBatteryRecoveryScore.map(localizedPercent) ?? "--"
                        : activeBodyBatteryStatus,
                    detail: activeBodyBatteryStatus,
                    symbol: detail == .bodyBattery ? "moon.stars.fill" : "scope"
                )
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private func bodySignalOverviewMetric(
        title: String,
        value: String,
        detail metricDetail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metricDetail)
                .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .padding(10)
        .background(detail.tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(detail.tint.opacity(0.10), lineWidth: 1)
        )
    }

    private var bodyBatteryCurveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            bodyBatteryDateRow

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(detail == .bodyBattery ? "电量曲线" : "状态变化")
                    .font(.appSystem(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(detail == .bodyBattery ? "夜间恢复 + 日内压力积分" : StressFocusCapacityPresentation.shareMethod)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer()

                Text(activeBodyBatteryAverage.map { "均值 \(localizedPercent($0))" } ?? "等待样本")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(activeBodyBatteryTone)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(activeBodyBatteryTone.opacity(0.10), in: Capsule())
            }

            bodyBatteryReferenceChart
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "DDEDE6"), lineWidth: 1)
        )
        .shadow(color: Color(hex: "176B52").opacity(0.07), radius: 14, x: 0, y: 7)
    }

    private var bodyBatteryDateRow: some View {
        HStack {
            Button {
                shiftBodyBatteryReferenceDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 7) {
                Text(selectedBodyBatteryPeriod.shortTitle)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "2C7B62"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(hex: "E2F6EE"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(bodyBatterySelectedDateTitle)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()

            Button {
                shiftBodyBatteryReferenceDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(canMoveBodyBatteryForward ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveBodyBatteryForward)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var bodyBatteryReferenceChart: some View {
        VStack(spacing: 10) {
            ZStack {
                Chart {
                    if detail == .focusCapacity {
                        RectangleMark(
                            xStart: .value("开始", bodyBatteryChartDomain.lowerBound),
                            xEnd: .value("结束", bodyBatteryChartDomain.upperBound),
                            yStart: .value("恢复区下界", 0),
                            yEnd: .value("恢复区上界", 40)
                        )
                        .foregroundStyle(Color(hex: "F5C6A5").opacity(0.10))

                        RectangleMark(
                            xStart: .value("开始", bodyBatteryChartDomain.lowerBound),
                            xEnd: .value("结束", bodyBatteryChartDomain.upperBound),
                            yStart: .value("稳定区下界", 40),
                            yEnd: .value("稳定区上界", 70)
                        )
                        .foregroundStyle(detail.tint.opacity(0.055))

                        RectangleMark(
                            xStart: .value("开始", bodyBatteryChartDomain.lowerBound),
                            xEnd: .value("结束", bodyBatteryChartDomain.upperBound),
                            yStart: .value("专注区下界", 70),
                            yEnd: .value("专注区上界", 100)
                        )
                        .foregroundStyle(Color(hex: "A8DCC5").opacity(0.09))
                    }

                    ForEach(activeBodyBatteryPoints) { point in
                        if activeBodyBatteryPoints.count > 1 {
                            if detail == .bodyBattery {
                                AreaMark(
                                    x: .value("时间", point.date),
                                    y: .value(detail.title, animatedBodyBatteryValue(point.value))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [activeBodyBatteryTone.opacity(0.30), activeBodyBatteryTone.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }

                            LineMark(
                                x: .value("时间", point.date),
                                y: .value(detail.title, animatedBodyBatteryValue(point.value))
                            )
                            .foregroundStyle(activeBodyBatteryTone)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(detail == .bodyBattery ? .catmullRom : .monotone)
                        }

                        if activeBodyBatteryPoints.count <= 14
                            || point.id == selectedBodyBatteryPoint?.id
                            || point.id == activeBodyBatteryPoints.last?.id {
                            PointMark(
                                x: .value("时间", point.date),
                                y: .value(detail.title, animatedBodyBatteryValue(point.value))
                            )
                            .foregroundStyle(Theme.Colors.surface)
                            .symbolSize(point.id == selectedBodyBatteryPoint?.id ? 82 : 38)
                            .annotation(position: .overlay) {
                                Circle()
                                    .fill(activeBodyBatteryTone)
                                    .frame(width: point.id == selectedBodyBatteryPoint?.id ? 11 : 7)
                            }
                            .opacity(reduceMotion ? 1 : bodyBatteryChartProgress)
                        }

                        if let selectedBodyBatteryPoint, selectedBodyBatteryChartDate != nil,
                           point.id == selectedBodyBatteryPoint.id {
                            RuleMark(x: .value("选中", point.date))
                                .foregroundStyle(activeBodyBatteryTone.opacity(0.26))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: bodyBatteryChartDomain)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
                            .foregroundStyle(activeBodyBatteryTone.opacity(0.13))
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)")
                                    .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: bodyBatteryXAxisDates) { value in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color(hex: "A6B6AF"))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(bodyBatteryAxisLabel(for: date))
                                    .font(.appSystem(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedBodyBatteryChartDate)
                .chartPlotStyle { plotArea in
                    plotArea
                        .clipped()
                        .modernReportChartPlotSurface(tint: activeBodyBatteryTone, cornerRadius: 20)
                }
                .chartLegend(.hidden)
                .frame(height: 218)
                .opacity(activeBodyBatteryPoints.isEmpty ? 0 : 1)
                .accessibilityLabel("\(detail.title)趋势图")
                .accessibilityValue(
                    selectedBodyBatteryPoint.map { "\(bodyBatterySelectionDateText(for: $0.date))，\(localizedPercent($0.value))" }
                    ?? "暂无数据"
                )
                .task(id: bodyBatteryChartAnimationID) {
                    await presentBodyBatteryChartIfNeeded()
                }

                if isLoadingBodyBatteryTrend && activeBodyBatteryPoints.isEmpty {
                    ModernReportChartLoadingState(
                        title: "正在读取健康数据",
                        tint: activeBodyBatteryTone
                    )
                } else if activeBodyBatteryPoints.isEmpty {
                    ModernReportChartEmptyState(
                        symbol: detail == .bodyBattery ? "battery.50percent" : "scope",
                        title: detail == .bodyBattery ? "等待身体电量曲线" : "等待专注趋势",
                        message: detail == .bodyBattery
                            ? "完成一次睡眠并持续佩戴手表，眠屿会结合恢复与日内压力生成电量变化。"
                            : "同步 HRV、心率和压力样本后，会显示专注评分在一天中的变化。",
                        tint: detail.tint
                    )
                }
            }

            if detail == .focusCapacity && !activeBodyBatteryPoints.isEmpty {
                HStack(spacing: 12) {
                    focusChartLegend(title: "恢复 0–39", color: Color(hex: "D79262"))
                    focusChartLegend(title: "稳定 40–69", color: detail.tint)
                    focusChartLegend(title: "专注 70+", color: Color(hex: "4B9C79"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let selectedBodyBatteryPoint {
                bodyBatterySelectionRow(point: selectedBodyBatteryPoint)
            }
        }
    }

    private func focusChartLegend(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    private func animatedBodyBatteryValue(_ value: Int) -> Double {
        Double(value) * (reduceMotion ? 1 : bodyBatteryChartProgress)
    }

    private var bodyBatteryChartAnimationID: String {
        let values = activeBodyBatteryPoints.map { String($0.value) }.joined(separator: "|")
        return "\(detail.rawValue)|\(selectedBodyBatteryPeriod.title)|\(Int(bodyBatteryPeriodInterval.start.timeIntervalSince1970))|\(values)"
    }

    @MainActor
    private func presentBodyBatteryChartIfNeeded() async {
        guard !activeBodyBatteryPoints.isEmpty else { return }
        guard !reduceMotion else {
            bodyBatteryChartProgress = 1
            hasAnimatedBodyBatteryChart = true
            return
        }
        guard !hasAnimatedBodyBatteryChart else {
            bodyBatteryChartProgress = 1
            return
        }

        hasAnimatedBodyBatteryChart = true
        bodyBatteryChartProgress = 0
        try? await Task.sleep(for: MotionTokens.chartDrawDelay)
        guard !Task.isCancelled else { return }
        withAnimation(MotionTokens.chartDrawAnimation) {
            bodyBatteryChartProgress = 1
        }
    }

    private var bodyBatteryInterpretationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("趋势解读")
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: activeBodyBatteryAverage.map {
                        if detail == .bodyBattery {
                            return $0 < 40 ? "battery.25percent" : "bolt.heart.fill"
                        }
                        return $0 < 40 ? "pause.circle.fill" : "scope"
                    } ?? "clock.badge.questionmark")
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(activeBodyBatteryTone)
                        .frame(width: 40, height: 40)
                        .background(activeBodyBatteryTone.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeBodyBatteryStatus)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("\(bodyBatterySelectedDateTitle)\(detail.title) · \(activeBodyBatteryAverage.map { "平均 \(localizedPercent($0))" } ?? "等待样本")")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Text(activeBodyBatteryAdvice)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .padding(16)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "DDEDE6"), lineWidth: 1)
            )
        }
    }

    private var bodyRecoveryPersonalizedOverviewSection: some View {
        let presentation = bodyRecoveryPersonalization
        let tone = bodyRecoveryToneColor(presentation.tone)

        return VStack(alignment: .leading, spacing: 12) {
            Text("个性化恢复结论")
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: presentation.hasHealthData ? bodyBatteryStageSymbol : "applewatch.radiowaves.left.and.right")
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(tone)
                        .frame(width: 42, height: 42)
                        .background(tone.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.statusTitle)
                            .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(presentation.summary)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if presentation.hasHealthData {
                    HStack(spacing: 8) {
                        bodyBatteryMiniPill(
                            title: "当前身体电量",
                            value: bodyBatteryCurrentValue.map(localizedPercent) ?? "--"
                        )
                        bodyBatteryMiniPill(
                            title: "夜间恢复",
                            value: bodyBatteryRecoveryScore.map(localizedPercent) ?? "--"
                        )
                    }
                } else {
                    Label("同步完成后会自动刷新，无需手动重新进入页面。", systemImage: "arrow.triangle.2.circlepath")
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .padding(16)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tone.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: tone.opacity(0.07), radius: 14, x: 0, y: 7)
        }
    }

    private var bodyBatteryReturnToTodayCard: some View {
        Button {
            selectedBodyBatteryPeriod = .day
            bodyBatteryReferenceDate = Calendar.current.startOfDay(for: Date())
            selectedBodyBatteryChartDate = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "176B52"))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "E2F6EE"), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("返回今天查看个性化建议")
                        .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("历史周期只展示趋势，避免混入今天的实时恢复结论。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(15)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "DDEDE6"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var bodyBatteryAdvancedAnalysisButton: some View {
        Button {
            showingBodyBatteryDeepAnalysis.toggle()
        } label: {
            Label(
                showingBodyBatteryDeepAnalysis ? "收起指标说明" : "查看指标说明",
                systemImage: showingBodyBatteryDeepAnalysis ? "chevron.up" : "info.circle"
            )
            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "176B52"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(hex: "E2F6EE"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var heroCard: some View {
        ModernSignalSheetHero(
            eyebrow: "身体信号",
            title: detail.title,
            value: value.map(String.init) ?? "--",
            unit: value == nil ? "" : (detail == .bodyBattery ? "%" : "/ 100"),
            state: detail.statusText(for: value),
            description: detail.summary(for: value),
            progress: Double(max(0, min(100, value ?? 0))) / 100,
            tint: detail.tint,
            symbol: detail.symbol,
            pills: detail == .bodyBattery ? [
                ModernSignalHeroPill(symbol: "battery.75", text: "可用电量"),
                ModernSignalHeroPill(symbol: "moon.stars.fill", text: "夜间恢复"),
                ModernSignalHeroPill(symbol: "leaf.fill", text: bodyBatteryPacingText)
            ] : [
                ModernSignalHeroPill(symbol: "scope", text: "节律匹配"),
                ModernSignalHeroPill(symbol: "waveform.path.ecg", text: dataQualityTitle),
                ModernSignalHeroPill(symbol: "battery.75", text: "精力在线")
            ],
            onClose: { dismiss() }
        )
    }

    private var signalSheetAdviceCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.appSystem(size: 16, weight: .black))
                .foregroundColor(detail.tint)
                .frame(width: 38, height: 38)
                .background(Theme.Colors.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(activeBodyBatteryStatus)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(activeBodyBatteryAdvice)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(detail.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(detail.tint.opacity(0.12), lineWidth: 1)
        }
    }

    private var bodyBatteryHeroDigest: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: bodyBatteryStageSymbol)
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(detail.tint)
                    .frame(width: 34, height: 34)
                    .bbTintedChip(tint: detail.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous), tintOpacity: 0.09)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bodyBatteryStageTitle)
                        .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(bodyBatteryStageDetail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                bodyBatteryMiniPill(title: "优先级", value: bodyBatteryPriorityText)
                bodyBatteryMiniPill(title: "节奏", value: bodyBatteryPacingText)
            }
        }
        .padding(14)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var bodyBatteryRecoveryCard: some View {
        let presentation = bodyRecoveryPersonalization

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.heart.fill")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(detail.tint)
                    .frame(width: 42, height: 42)
                    .bbTintedChip(tint: detail.tint, in: RoundedRectangle(cornerRadius: 15, style: .continuous), tintOpacity: 0.10)

                VStack(alignment: .leading, spacing: 5) {
                    Text("影响恢复的因素")
                        .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(presentation.factors.isEmpty
                        ? "当前还没有足够的真实指标用于拆解恢复因素。"
                        : "以下内容来自今天已经同步的个人健康信号，缺失指标不会参与判断。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if presentation.factors.isEmpty {
                Label("保持佩戴并允许健康数据完成同步。", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(presentation.factors) { factor in
                        recoverySignalRow(
                            symbol: factor.symbol,
                            title: factor.title,
                            value: factor.valueText,
                            note: factor.detailText,
                            tint: bodyRecoveryToneColor(factor.tone)
                        )
                    }
                }
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var bodyBatteryBudgetCard: some View {
        let presentation = bodyRecoveryPersonalization

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(detail.tint)
                Text("今日能量预算")
                    .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(presentation.budgetBadge)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(detail.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .bbTintedChip(tint: detail.tint, in: Capsule(), tintOpacity: 0.08)
            }

            Text(presentation.budgetSummary)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if presentation.actions.isEmpty {
                Label("数据补齐后，这里会生成三条按优先级排序的今日建议。", systemImage: "clock.badge.questionmark")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(presentation.actions) { action in
                        bodyBatteryBudgetRow(BodyBatteryBudgetItem(
                            symbol: action.symbol,
                            title: action.title,
                            detail: action.detailText,
                            tone: bodyRecoveryToneColor(action.tone)
                        ))
                    }
                }
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日走势")
                    .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(trendSummaryText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(detail.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .bbTintedChip(tint: detail.tint, in: Capsule(), tintOpacity: 0.06)
            }

            if trendPoints.isEmpty {
                Text("今天暂无足够压力样本，等同步后这里会自动出现日内曲线。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                GeometryReader { proxy in
                    let points = normalizedTrendPoints(in: proxy.size)
                    ZStack {
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                        .stroke(detail.tint.opacity(0.72), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            Circle()
                                .fill(index == points.count - 1 ? detail.tint : Color.white)
                                .frame(width: index == points.count - 1 ? 8 : 6, height: index == points.count - 1 ? 8 : 6)
                                .overlay(
                                    Circle()
                                        .stroke(detail.tint.opacity(index == points.count - 1 ? 0 : 0.7), lineWidth: 1.5)
                                )
                                .position(point)
                        }
                    }
                }
                .frame(height: 96)
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var scoreBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分数拆解")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            metricRow(title: "当前分数", value: value.map { "\($0)%" } ?? "--", detailText: detail.statusText(for: value))
            metricRow(title: "平均水平", value: averageValue.map { "\($0)%" } ?? "--", detailText: trendAverageText)
            metricRow(title: "最高 / 最低", value: "\(peakValue.map { "\($0)" } ?? "--") / \(lowValue.map { "\($0)" } ?? "--")", detailText: trendRangeText)
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var timeWindowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关键时段")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: 10) {
                windowPill(
                    title: detail == .bodyBattery ? "电量高点" : "专注高点",
                    value: bestPoint.map { detailTimeText(for: $0.date) } ?? "--",
                    note: bestPoint.map { "\($0.value)%" } ?? "等待样本"
                )

                windowPill(
                    title: detail == .bodyBattery ? "电量低点" : "专注低点",
                    value: lowPoint.map { detailTimeText(for: $0.date) } ?? "--",
                    note: lowPoint.map { "\($0.value)%" } ?? "等待样本"
                )
            }

            Text(timeWindowAdvice)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var dataQualityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据质量")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: dataQualitySymbol)
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(detail.tint)
                    .frame(width: 38, height: 38)
                    .bbTintedChip(tint: detail.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous), tintOpacity: 0.08)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dataQualityTitle)
                        .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(dataQualityDetail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var scaleLegendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分数刻度")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(scaleLegendItems, id: \.range) { item in
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.color)
                        .frame(width: 8, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.range)
                            .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(item.meaning)
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var scenarioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("适合场景")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(scenarioItems, id: \.title) { item in
                labeledInsightRow(symbol: item.symbol, title: item.title, detailText: item.detail)
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var actionPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天怎么用")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(Array(actionPlan.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(detail.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .bbTintedChip(tint: detail.tint, in: Capsule(), tintOpacity: 0.07)
                    Text(item)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var observationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("下一步观察")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(observationItems, id: \.title) { item in
                labeledInsightRow(symbol: item.symbol, title: item.title, detailText: item.detail)
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var detailGauge: some View {
        GeometryReader { proxy in
            let progress = CGFloat((value ?? 0)) / 100.0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(detail.tint.opacity(0.12))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [detail.tint.opacity(0.62), detail.tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 12)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日解读")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(detail.summary(for: value))
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(detail.bullets.enumerated()), id: \.offset) { index, bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(detail.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .bbTintedChip(tint: detail.tint, in: Capsule(), tintOpacity: 0.07)
                        Text(bullet)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var signalBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail == .focusCapacity ? StressFocusCapacityPresentation.dimensionsTitle : "参考信号")
                .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            if detail == .focusCapacity {
                ForEach(
                    Array(StressFocusCapacityPresentation.metricItems(for: resolvedFocusCapacityAssessment).enumerated()),
                    id: \.offset
                ) { _, item in
                    signalRow(title: item.title, value: item.valueText, note: item.note)
                }
            } else {
                signalRow(title: "综合压力", value: assessment.score.map { "\($0)/100" } ?? "--", note: stressContributionText)
                signalRow(title: "近期 HRV", value: recentAvgHrv.map { String(format: "%.0f ms", $0) } ?? "--", note: hrvContributionText)
                signalRow(title: "静息心率", value: restingHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--", note: heartContributionText)
            }
        }
        .todaySecondaryCard(tint: detail.tint)
    }

    private var trendSummaryText: String {
        guard let value else { return "等待同步" }
        switch value {
        case 80...:
            return String(localized: "高位稳定")
        case 55..<80:
            return String(localized: "中段可用")
        case 30..<55:
            return String(localized: "略有下压")
        default:
            return String(localized: "偏低")
        }
    }

    private var trendAverageText: String {
        guard let averageValue else { return "等待样本" }
        switch averageValue {
        case 80...:
            return String(localized: "今天整体较强")
        case 55..<80:
            return String(localized: "今天中段可用")
        case 30..<55:
            return String(localized: "今天明显受压")
        default:
            return String(localized: "今天偏低")
        }
    }

    private var trendRangeText: String {
        guard let peakValue, let lowValue else { return "等待样本" }
        return String(localized: "\(localizedPercent(peakValue)) 高位，\(localizedPercent(lowValue)) 低位")
    }

    private var timeWindowAdvice: String {
        guard let bestPoint, let lowPoint else {
            return String(localized: "等今天积累更多点位后，这里会提示更适合推进和更适合恢复的时段。")
        }
        switch detail {
        case .bodyBattery:
            return String(localized: "\(detailTimeText(for: bestPoint.date)) 附近电量更高，适合安排较费力的事情；\(detailTimeText(for: lowPoint.date)) 附近更适合降载或补恢复。")
        case .focusCapacity:
            return String(localized: "\(detailTimeText(for: bestPoint.date)) 附近专注条件更好，适合做重点任务；\(detailTimeText(for: lowPoint.date)) 附近更适合处理低阻力事项。")
        }
    }

    private var dataQualitySymbol: String {
        if detail == .focusCapacity {
            switch resolvedFocusCapacityAssessment.availableDimensionCount {
            case 5...: return "checkmark.seal.fill"
            case 3..<5: return "chart.line.uptrend.xyaxis"
            case 1..<3: return "dot.radiowaves.left.and.right"
            default: return "clock.badge.questionmark"
            }
        }
        let count = trendPoints.count
        if count >= 8 { return "checkmark.seal.fill" }
        if count >= 3 { return "chart.line.uptrend.xyaxis" }
        if value != nil { return "dot.radiowaves.left.and.right" }
        return "clock.badge.questionmark"
    }

    private var scaleLegendItems: [BodySignalScaleLegendItem] {
        switch detail {
        case .bodyBattery:
            return [
                BodySignalScaleLegendItem(range: "80-100", meaning: "恢复余量较足，可以正常推进。", color: detail.tint),
                BodySignalScaleLegendItem(range: "55-79", meaning: "状态可用，适合分段完成任务。", color: detail.tint.opacity(0.74)),
                BodySignalScaleLegendItem(range: "30-54", meaning: "电量偏紧，减少额外消耗。", color: Color(hex: "D9952A")),
                BodySignalScaleLegendItem(range: "0-29", meaning: "优先恢复，不建议硬顶高强度。", color: Color(hex: "E25D5D"))
            ]
        case .focusCapacity:
            let colors = [
                detail.tint,
                detail.tint.opacity(0.74),
                Color(hex: "D9952A"),
                Color(hex: "E25D5D")
            ]
            return StressFocusCapacityPresentation.scaleItems.enumerated().map { index, item in
                BodySignalScaleLegendItem(
                    range: item.range,
                    meaning: item.meaning,
                    color: colors[index]
                )
            }
        }
    }

    private var scenarioItems: [BodySignalInsightItem] {
        let current = value ?? 0
        switch detail {
        case .bodyBattery:
            if value == nil {
                return [
                    BodySignalInsightItem(symbol: "applewatch", title: "等待佩戴样本", detail: "先保持设备佩戴和健康同步，页面会补齐今日可用余量。"),
                    BodySignalInsightItem(symbol: "bed.double.fill", title: "先看恢复底盘", detail: "睡眠和 HRV 样本回来后，身体电量的参考性会更高。")
                ]
            }
            if current >= 70 {
                return [
                    BodySignalInsightItem(symbol: "figure.walk.motion", title: "适合推进", detail: "可以安排外出、训练或复杂家务，但中间保留恢复间隔。"),
                    BodySignalInsightItem(symbol: "bolt.heart.fill", title: "适合轻挑战", detail: "如果要加一点强度，优先选择可控时长，不要一路拉满。")
                ]
            }
            if current >= 45 {
                return [
                    BodySignalInsightItem(symbol: "list.bullet.clipboard", title: "适合分段", detail: "把任务切成几段完成，避免连续消耗太久。"),
                    BodySignalInsightItem(symbol: "cup.and.saucer.fill", title: "适合补给", detail: "补水、短休息和轻走动会比继续硬顶更划算。")
                ]
            }
            return [
                BodySignalInsightItem(symbol: "moon.zzz.fill", title: "适合恢复", detail: "把恢复动作放前面，减少训练、熬夜和刺激性输入。"),
                BodySignalInsightItem(symbol: "leaf.fill", title: "适合低负荷", detail: "选择简单整理、轻拉伸或散步，避免临时加码。")
            ]
        case .focusCapacity:
            return StressFocusCapacityPresentation.scenarioItems(forScore: value).map {
                BodySignalInsightItem(symbol: $0.symbol, title: $0.title, detail: $0.detail)
            }
        }
    }

    private var observationItems: [BodySignalInsightItem] {
        switch detail {
        case .bodyBattery:
            return [
                BodySignalInsightItem(symbol: "waveform.path.ecg", title: "看 HRV 是否回稳", detail: "如果 HRV 后续回升，身体电量通常更容易恢复。"),
                BodySignalInsightItem(symbol: "heart.fill", title: "看静息心率是否抬高", detail: "静息心率持续偏高时，电量读数更需要保守解读。"),
                BodySignalInsightItem(symbol: "chart.line.uptrend.xyaxis", title: "看低点持续多久", detail: "短暂低点常见，长时间低位才更值得调整节奏。")
            ]
        case .focusCapacity:
            return StressFocusCapacityPresentation.observationItems.map {
                BodySignalInsightItem(symbol: $0.symbol, title: $0.title, detail: $0.detail)
            }
        }
    }

    private var actionPlan: [String] {
        switch detail {
        case .bodyBattery:
            return [
                value == nil ? "先等同步完成，再判断今天的恢复余量。" : "把今天最重的事情放在电量更高的时段。",
                "每完成一段高消耗任务，给自己留一个短恢复间隔。",
                "如果分数偏低，优先睡眠、补水、轻活动和少刺激。"
            ]
        case .focusCapacity:
            return StressFocusCapacityPresentation.actionPlan(hasData: value != nil)
        }
    }

    private var bodyBatteryShareText: String {
        guard let activeBodyBatteryAverage else {
            return String(localized: "\(bodyBatterySelectedDateTitle)暂无足够的\(detail.title)样本。")
        }
        let method = detail == .bodyBattery
            ? "由夜间恢复和日内压力累计估算"
            : StressFocusCapacityPresentation.shareMethod
        return String(localized: "\(bodyBatterySelectedDateTitle)\(detail.title)均值 \(localizedPercent(activeBodyBatteryAverage))，\(activeBodyBatteryStatus)。\(detail.title)\(method)。")
    }

    private var canMoveBodyBatteryForward: Bool {
        guard let nextDate = Calendar.current.date(
            byAdding: selectedBodyBatteryPeriod.calendarComponent,
            value: 1,
            to: bodyBatteryReferenceDate
        ) else { return false }
        let nextStart: Date
        switch selectedBodyBatteryPeriod {
        case .day:
            nextStart = Calendar.current.startOfDay(for: nextDate)
        case .week:
            nextStart = Calendar.current.dateInterval(of: .weekOfYear, for: nextDate)?.start ?? nextDate
        case .month:
            nextStart = Calendar.current.dateInterval(of: .month, for: nextDate)?.start ?? nextDate
        case .year:
            nextStart = Calendar.current.dateInterval(of: .year, for: nextDate)?.start ?? nextDate
        }
        return nextStart <= Date()
    }

    private func aggregateBodyBatteryPoints(
        _ points: [TimeSeriesPoint],
        component: Calendar.Component
    ) -> [TimeSeriesPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { point -> Date in
            if component == .month {
                return calendar.dateInterval(of: .month, for: point.date)?.start ?? calendar.startOfDay(for: point.date)
            }
            return calendar.startOfDay(for: point.date)
        }

        return grouped.map { date, samples in
            let average = Int((Double(samples.map(\.value).reduce(0, +)) / Double(samples.count)).rounded())
            return TimeSeriesPoint(timestamp: Int64(date.timeIntervalSince1970), value: average)
        }
        .sorted { $0.date < $1.date }
    }

    private func shiftBodyBatteryReferenceDate(by offset: Int) {
        guard let nextDate = Calendar.current.date(
            byAdding: selectedBodyBatteryPeriod.calendarComponent,
            value: offset,
            to: bodyBatteryReferenceDate
        ) else { return }
        if offset > 0, !canMoveBodyBatteryForward { return }
        bodyBatteryReferenceDate = min(nextDate, Date())
    }

    private func reloadBodyBatteryTrend() async {
        guard detail == .bodyBattery || !usesFocusCapacityTrendSnapshot else { return }
        let requestID = UUID()
        bodyBatteryLoadRequestID = requestID
        let requestedPeriod = selectedBodyBatteryPeriod
        let requestedDate = bodyBatteryReferenceDate
        let requestedInterval = bodyBatteryPeriodInterval
        isLoadingBodyBatteryTrend = true
        loadedBodyBatteryStressPoints = []
        cachedBodyBatterySourcePoints = nil

        defer {
            if bodyBatteryLoadRequestID == requestID {
                isLoadingBodyBatteryTrend = false
            }
        }

        let fetchedStressPoints: [TimeSeriesPoint]
        if requestedPeriod == .day {
            let existingHistoryPoints = historyStressPoints
                .filter { requestedInterval.contains($0.date) && $0.value > 0 }
            if !existingHistoryPoints.isEmpty {
                loadedBodyBatteryStressPoints = []
                cachedBodyBatterySourcePoints = makeBodyBatterySourcePoints(loadedStressPoints: [])
                isLoadingBodyBatteryTrend = false
                return
            }

            let queryEnd = min(requestedInterval.end, Date())
            async let hrvTask = try? HealthKitManager.shared.fetchHRVSamples(on: requestedDate)
            async let heartRateTask = try? HealthKitManager.shared.fetchHeartRateSeries(
                start: requestedInterval.start,
                end: queryEnd,
                maxPoints: 180
            )
            async let restingTask = try? HealthKitManager.shared.fetchRestingHeartRate(on: requestedDate)

            let hrvSamples = await hrvTask ?? []
            let heartRateSamples = await heartRateTask ?? []
            let restingHeartRate = await restingTask
            fetchedStressPoints = StressDailyEngine.sevenMinuteStressPoints(
                hrv: hrvSamples,
                heartRate: heartRateSamples,
                restingHeartRate: restingHeartRate,
                restingHeartRateBaseline: recentAvgRestingHeartRate,
                hrvBaseline: recentAvgHrv,
                in: DateInterval(start: requestedInterval.start, end: queryEnd)
            )
        } else {
            let queryEnd = min(requestedInterval.end, Date())
            let dayCount = requestedPeriod.rollingRange.dayCount

            async let hrvTask = try? HealthKitManager.shared.fetchDailyHRVAverages(days: dayCount, endDate: queryEnd)
            async let heartRateTask = try? HealthKitManager.shared.fetchDailyHeartRateAverages(days: dayCount, endDate: queryEnd)
            async let restingTask = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: dayCount, endDate: queryEnd)

            let dailyStress = HealthStressEstimator.estimateDailyStress(
                hrv: await hrvTask ?? [],
                heartRate: await heartRateTask ?? [],
                restingHeartRate: await restingTask ?? []
            )
            fetchedStressPoints = dailyStress.map {
                TimeSeriesPoint(timestamp: $0.timestamp, value: Int($0.value.rounded()))
            }
        }

        guard bodyBatteryLoadRequestID == requestID,
              selectedBodyBatteryPeriod == requestedPeriod,
              Calendar.current.isDate(bodyBatteryReferenceDate, inSameDayAs: requestedDate) else { return }

        let resolvedStressPoints = fetchedStressPoints
            .filter { $0.value > 0 && requestedInterval.contains($0.date) }
            .sorted { $0.date < $1.date }
        loadedBodyBatteryStressPoints = resolvedStressPoints
        cachedBodyBatterySourcePoints = makeBodyBatterySourcePoints(loadedStressPoints: resolvedStressPoints)
        let renderedPointCount = cachedBodyBatterySourcePoints?.count ?? 0
        let chartState = renderedPointCount == 0 ? "empty" : "ready"
        Self.logger.info(
            "[Today][BodySignals] operation=dataLoadComplete metric=\(detail.rawValue, privacy: .public) period=\(requestedPeriod.rollingRange.rawValue, privacy: .public) stressPointCount=\(resolvedStressPoints.count, privacy: .public)"
        )
        Self.logger.info(
            "[Today][BodySignals] operation=chartRender metric=\(detail.rawValue, privacy: .public) period=\(requestedPeriod.rollingRange.rawValue, privacy: .public) state=\(chartState, privacy: .public) pointCount=\(renderedPointCount, privacy: .public)"
        )
    }

    private func bodyBatteryAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        switch selectedBodyBatteryPeriod {
        case .day:
            if abs(date.timeIntervalSince(bodyBatteryPeriodInterval.end)) < 1 {
                return "24:00"
            }
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "EEE"
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("d")
        case .year:
            formatter.setLocalizedDateFormatFromTemplate("MMM")
        }
        return formatter.string(from: date)
    }

    private func bodyBatterySelectionDateText(for date: Date) -> String {
        switch selectedBodyBatteryPeriod {
        case .day:
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        case .week, .month:
            return ChineseDateText.fullDate(date)
        case .year:
            return ChineseDateText.compactMonth(date)
        }
    }

    private func bodyBatterySelectionRow(point: TimeSeriesPoint) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(activeBodyBatteryTone)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(bodyBatterySelectionDateText(for: point.date))
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(selectedBodyBatteryChartDate == nil ? "最近样本" : "所选样本")
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            Text(localizedPercent(point.value))
                .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(activeBodyBatteryTone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(activeBodyBatteryTone.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func bodyBatteryMiniPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func recoverySignalRow(symbol: String, title: String, value: String, note: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 13, weight: .black))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .bbTintedChip(tint: tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous), tintOpacity: 0.08)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text(value)
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                Text(note)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func bodyBatteryBudgetRow(_ item: BodyBatteryBudgetItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.appSystem(size: 13, weight: .black))
                .foregroundColor(item.tone)
                .frame(width: 30, height: 30)
                .bbTintedChip(tint: item.tone, in: RoundedRectangle(cornerRadius: 11, style: .continuous), tintOpacity: 0.08)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(item.detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func windowPill(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(note)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(detail.tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bbTintedChip(tint: detail.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintOpacity: 0.055)
    }

    private func labeledInsightRow(symbol: String, title: String, detailText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(detail.tint)
                .frame(width: 30, height: 30)
                .bbTintedChip(tint: detail.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous), tintOpacity: 0.075)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detailText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func normalizedTrendPoints(in size: CGSize) -> [CGPoint] {
        guard let minValue = trendPoints.map(\.value).min(),
              let maxValue = trendPoints.map(\.value).max(),
              maxValue > minValue else {
            return trendPoints.enumerated().map { index, _ in
                CGPoint(
                    x: size.width * CGFloat(index) / max(1, CGFloat(trendPoints.count - 1)),
                    y: size.height * 0.5
                )
            }
        }

        return trendPoints.enumerated().map { index, point in
            let x = trendPoints.count > 1 ? size.width * CGFloat(index) / CGFloat(trendPoints.count - 1) : size.width * 0.5
            let progress = CGFloat((point.value - minValue)) / CGFloat(maxValue - minValue)
            let y = size.height * (0.15 + (1 - progress) * 0.7)
            return CGPoint(x: x, y: y)
        }
    }

    private func metricRow(title: String, value: String, detailText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detailText)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            Text(value)
                .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(detail.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
    }

    private func signalRow(title: String, value: String, note: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(note)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            Text(value)
                .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(detail.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 8)
    }
}

private struct TodayInfoSheet: View {
    let topic: TodayInfoTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.appSystem(size: 20, weight: .black))
                            .foregroundColor(Theme.Colors.mintGreen)
                            .frame(width: 46, height: 46)
                            .bbTintedChip(tint: Theme.Colors.mintGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintOpacity: 0.10)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("数据说明")
                                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.mintGreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .bbTintedChip(tint: Theme.Colors.mintGreen, in: Capsule(), tintOpacity: 0.08)
                            Text(topic.title)
                                .font(.appSystem(size: 26, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.appSystem(size: 13, weight: .black))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(Theme.Colors.secondarySurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(topic.summary)
                        .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .todaySecondaryCard(tint: Theme.Colors.mintGreen, cornerRadius: 28, padding: 18, shadow: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.appSystem(size: 14, weight: .black))
                            .foregroundColor(Theme.Colors.mintGreen)
                        Text("阅读要点")
                            .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    ForEach(Array(topic.bullets.enumerated()), id: \.offset) { index, bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(hex: "2F8F78"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .bbTintedChip(tint: Theme.Colors.mintGreen, in: Capsule(), tintOpacity: 0.08)

                            Text(bullet)
                                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .todaySecondaryCard(tint: Theme.Colors.mintGreen)

                HealthDisclaimerCard(
                    message: "这些说明用于帮助理解今日页图表的含义与数据来源，不构成医疗诊断结论。",
                    style: .compact,
                    strokeColor: Color.white.opacity(0.92)
                )
            }
            .padding(.horizontal, Theme.Layout.padding)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .background(
            Theme.Colors.pageBackground
            .ignoresSafeArea()
        )
    }
}

private struct TodayAIInsightSection: View {
    let assessment: StressPresentationAssessment
    let avgHrvToday: Double?
    let recentAvgHrv: Double?
    let restingHeartRate: Double?
    let recentAvgRestingHeartRate: Double?
    let currentBpm: Double?
    let realtimeHealth: RealtimeHealth?

    private var resolvedAssessment: StressPresentationAssessment {
        StressPresentation.assessment(from: StressPresentation.evaluation(from: realtimeHealth))
    }

    private var effectiveAssessment: StressPresentationAssessment {
        assessment.hasData ? assessment : resolvedAssessment
    }

    private var style: StressVisualStyle {
        StressVisualStyle.style(for: effectiveAssessment.band)
    }

    private var summaryText: String {
        let trimmed = effectiveAssessment.adviceDetail
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if let sentence = trimmed.split(whereSeparator: { "。！？!?.；;".contains($0) }).first, !sentence.isEmpty {
            return String(sentence).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) + "。"
        }
        return trimmed
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.small) {
            TodayAIMascotMiniBadge(style: style, assessment: effectiveAssessment)

            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                Text("今日建议")
                    .font(Theme.Typography.label)
                    .foregroundColor(style.accentColor)

                Text(summaryText)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(style.accentColor.opacity(0.72))
                .frame(width: 26, height: 26)
                .bbTintedChip(tint: style.accentColor, in: Circle(), tintOpacity: 0.06)
        }
        .padding(16)
        .todayCardSurface(tint: style.accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日建议，\(summaryText)")
        .accessibilityHint("打开健康助手查看详细建议")
    }
}

private enum TodayAIMascotState: Int, CaseIterable, Sendable {
    case idle = 0
    case happy = 1
    case thinking = 2
    case sleep = 3
    case stress = 4
    case celebrate = 5
}

private struct TodayAIMascotMood: Equatable {
    let state: TodayAIMascotState
    let label: String
    let orbitSymbol: String
    let floatOffset: CGFloat
    let scale: CGFloat
    let rotation: Double
    let pace: Double
    let tremble: CGFloat

    static func mood(for assessment: StressPresentationAssessment) -> TodayAIMascotMood {
        guard assessment.hasData else {
            return TodayAIMascotMood(
                state: .idle,
                label: "同步中",
                orbitSymbol: "antenna.radiowaves.left.and.right",
                floatOffset: 4,
                scale: 1.01,
                rotation: 0,
                pace: 2.4,
                tremble: 0
            )
        }

        switch assessment.band {
        case .waiting:
            return TodayAIMascotMood(
                state: .idle,
                label: "同步中",
                orbitSymbol: "antenna.radiowaves.left.and.right",
                floatOffset: 4,
                scale: 1.01,
                rotation: 0,
                pace: 2.4,
                tremble: 0
            )
        case .relaxed:
            return TodayAIMascotMood(
                state: .happy,
                label: "轻松",
                orbitSymbol: "leaf.fill",
                floatOffset: 5,
                scale: 1.04,
                rotation: -1.5,
                pace: 2.8,
                tremble: 0
            )
        case .steady:
            return TodayAIMascotMood(
                state: .thinking,
                label: steadyLabel(for: assessment.score),
                orbitSymbol: "circle.dotted",
                floatOffset: 4,
                scale: 1.03,
                rotation: 1.2,
                pace: 2.5,
                tremble: 0
            )
        case .mild:
            return TodayAIMascotMood(
                state: .thinking,
                label: "提个醒",
                orbitSymbol: "sun.min.fill",
                floatOffset: 6,
                scale: 1.05,
                rotation: -2.0,
                pace: 2.1,
                tremble: 0
            )
        case .caution:
            return TodayAIMascotMood(
                state: .stress,
                label: "慢下来",
                orbitSymbol: "bolt.heart.fill",
                floatOffset: 7,
                scale: 1.06,
                rotation: 2.4,
                pace: 1.8,
                tremble: 1.8
            )
        case .high:
            return TodayAIMascotMood(
                state: .sleep,
                label: "先休息",
                orbitSymbol: "exclamationmark.triangle.fill",
                floatOffset: 8,
                scale: 1.07,
                rotation: -2.8,
                pace: 1.55,
                tremble: 2.4
            )
        }
    }

    private static func steadyLabel(for score: Int?) -> String {
        guard let score else { return "平稳" }

        switch score {
        case ..<36:
            return String(localized: "状态不错")
        case 36..<43:
            return String(localized: "平稳")
        default:
            return String(localized: "留意波动")
        }
    }
}

private struct TodayAIMascotMiniBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    let style: StressVisualStyle
    let assessment: StressPresentationAssessment

    private var mood: TodayAIMascotMood {
        TodayAIMascotMood.mood(for: assessment)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(style.glowColor.opacity(0.86))
                .frame(width: 44, height: 44)

            Circle()
                .stroke(style.accentColor.opacity(0.18), lineWidth: 1)
                .frame(width: 38, height: 38)
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.1 : 0.94))

            Image(systemName: mood.orbitSymbol)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(style.accentColor)
                .frame(width: 32, height: 32)
                .background(Theme.Colors.surface, in: Circle())
        }
        .frame(width: 44, height: 44)
        .task(id: animationID) {
            isAnimating = false
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: mood.pace * 0.7).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityHidden(true)
    }

    private var animationID: String {
        "\(assessment.band.rawValue)-\(reduceMotion)"
    }
}

private struct DashboardFAQQuestion: Identifiable {
    let question: String

    var id: String { question }
}

private struct BodyIndexSharePreviewSheet: View {
    let content: BodyIndexShareContent
    let symbol: String
    let tint: Color
    let trendValues: [Double]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var activityPayload: BodyIndexShareActivityPayload?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TodayVisualTokens.canvas.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.compact) {
                header

                GeometryReader { proxy in
                    let cardWidth = min(390, max(280, proxy.size.width - 32))

                    ScrollView(showsIndicators: false) {
                        BodyIndexSharePosterCard(
                            content: content,
                            symbol: symbol,
                            tint: tint,
                            trendValues: trendValues
                        )
                        .frame(width: cardWidth, height: cardWidth * 600 / 390)
                        .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 12)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            shareFooter
        }
        .sheet(item: $activityPayload) { payload in
            BodyIndexActivityView(items: payload.items)
        }
        .alert("无法生成分享卡片", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后再试")
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("分享身体指数")
                    .font(Theme.Typography.cardTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("确认预览后选择分享方式")
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.surface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Theme.Colors.surfaceBorder, lineWidth: Theme.Stroke.subtleWidth)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var shareFooter: some View {
        VStack(spacing: Theme.Spacing.small) {
            Label("不包含原始样本、设备信息或精确记录时间", systemImage: "lock.shield.fill")
                .font(Theme.Typography.label)
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Theme.Spacing.small) {
                shareActionButton(
                    title: "分享文字",
                    systemImage: "text.quote",
                    isPrimary: false,
                    action: sharePlainText
                )
                .accessibilityHint("打开系统分享面板，仅分享文字摘要")

                shareActionButton(
                    title: "分享图片",
                    systemImage: "photo.fill",
                    isPrimary: true,
                    action: sharePoster
                )
                .accessibilityHint("打开系统分享面板，仅分享当前预览图片")
            }
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.top, Theme.Spacing.small)
        .padding(.bottom, Theme.Spacing.compact)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.surfaceBorder)
                .frame(height: Theme.Stroke.subtleWidth)
        }
    }

    private func shareActionButton(
        title: LocalizedStringKey,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(isPrimary ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(
                    isPrimary ? Theme.Colors.mintGreen : Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                        .stroke(
                            isPrimary ? Color.clear : Theme.Colors.surfaceBorder,
                            lineWidth: Theme.Stroke.standardWidth
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func sharePlainText() {
        activityPayload = BodyIndexShareActivityPayload(items: [content.plainText])
    }

    private func sharePoster() {
        let renderer = ImageRenderer(
            content: BodyIndexSharePosterCard(
                content: content,
                symbol: symbol,
                tint: tint,
                trendValues: trendValues
            )
            .frame(width: 390, height: 600)
        )
        renderer.scale = max(2, displayScale)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else {
            errorMessage = String(localized: "图片生成失败，请稍后再试。")
            return
        }
        // 图片与文字由用户明确二选一，避免图片分享时额外附带一份长文本。
        activityPayload = BodyIndexShareActivityPayload(items: [image])
    }
}

private struct BodyIndexSharePosterCard: View {
    let content: BodyIndexShareContent
    let symbol: String
    let tint: Color
    let trendValues: [Double]

    private let ink = Theme.Colors.textPrimary
    private let secondaryInk = Theme.Colors.textSecondary

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Theme.Colors.surface, Theme.Colors.secondarySurface, tint.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(tint.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: 72, y: -86)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.appSystem(size: 18, weight: .bold, level: .two))
                        .foregroundColor(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("眠屿 · 身体指数")
                            .font(.appSystem(size: 13, weight: .black, design: .rounded, level: .two))
                            .foregroundColor(ink)
                        Text(content.periodText)
                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded, level: .two))
                            .foregroundColor(secondaryInk)
                    }

                    Spacer()

                    Text(content.statusText)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded, level: .two))
                        .foregroundColor(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.10), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(content.title)
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded, level: .two))
                        .foregroundColor(secondaryInk)
                    Text(content.formattedValue)
                        .font(.appSystem(size: 48, weight: .black, design: .rounded, level: .two))
                        .monospacedDigit()
                        .foregroundColor(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                BodyIndexShareSparkline(values: trendValues, tint: tint)
                    .frame(height: 72)
                    .overlay(alignment: .bottomLeading) {
                        Text(content.sampleCaption)
                            .font(.appSystem(size: 10, weight: .semibold, design: .rounded, level: .two))
                            .foregroundColor(secondaryInk)
                            .padding(.bottom, 2)
                    }

                VStack(alignment: .leading, spacing: 7) {
                    Text(content.headline)
                        .font(.appSystem(size: 20, weight: .black, design: .rounded, level: .two))
                        .foregroundColor(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(content.detail)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded, level: .two))
                        .foregroundColor(secondaryInk)
                        .lineSpacing(2)
                        .lineLimit(3)
                }

                LazyVGrid(columns: shareFactColumns, spacing: 8) {
                    ForEach(Array(content.facts.prefix(2).enumerated()), id: \.offset) { _, fact in
                        HStack(spacing: 8) {
                            Image(systemName: fact.symbol)
                                .font(.appSystem(size: 13, weight: .bold, level: .two))
                                .foregroundColor(tint)
                                .frame(width: 24, height: 24)
                                .background(tint.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.title)
                                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded, level: .two))
                                    .foregroundColor(secondaryInk)
                                Text(fact.value)
                                    .font(.appSystem(size: 12, weight: .bold, design: .rounded, level: .two))
                                    .foregroundColor(ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous))
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Text("基于已授权健康数据生成")
                    Spacer()
                    Label("隐私保护", systemImage: "lock.fill")
                }
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded, level: .two))
                .foregroundColor(secondaryInk.opacity(0.86))
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder.opacity(0.72), lineWidth: Theme.Stroke.standardWidth)
        }
    }

    private var shareFactColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }
}

private struct BodyIndexShareSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let finiteValues = values.filter(\.isFinite)
            let minimum = finiteValues.min() ?? 0
            let maximum = finiteValues.max() ?? 1
            let spread = max(maximum - minimum, 0.001)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.58))

                if finiteValues.count >= 2 {
                    Path { path in
                        for (index, value) in finiteValues.enumerated() {
                            let x = proxy.size.width * CGFloat(index) / CGFloat(max(1, finiteValues.count - 1))
                            let ratio = (value - minimum) / spread
                            let y = 12 + (proxy.size.height - 30) * CGFloat(1 - ratio)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                } else {
                    Capsule()
                        .fill(tint.opacity(0.32))
                        .frame(height: 3)
                        .padding(.horizontal, 18)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BodyIndexShareActivityPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct BodyIndexActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TodayOtherMetricDetailSummary {
    let title: String
    let valueText: String
    let unitText: String
    let statusText: String
    let deltaText: String
    let lastUpdatedText: String
    let summaryText: String
    let symbol: String
    let tint: Color
    let statusTone: DashboardOtherMetricStatusTone
    let trendPoints: [TimeSeriesPointDouble]
}

private struct BodyIndexMetricSignalItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
}

private extension View {
    func todaySecondaryCard(
        tint: Color = Color(hex: "C7D7EA"),
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 16,
        shadow: Bool = false
    ) -> some View {
        self
            .padding(padding)
            .todayCardSurface(tint: tint, cornerRadius: cornerRadius, emphasized: shadow)
    }
}

private extension DashboardOtherMetricDestination {
    var detailSymbol: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .vo2Max: return "lungs.fill"
        case .wristTemperature: return "thermometer.medium"
        case .sunlight: return "sun.max.fill"
        case .walkingAsymmetry: return "figure.walk"
        case .heartRhythm: return "waveform.path.ecg.rectangle"
        }
    }

    var detailTint: Color {
        switch self {
        case .hrv: return Color(hex: "58C6E8")
        case .restingHeartRate: return Color(hex: "B93A3A")
        case .vo2Max: return Color(hex: "B38A58")
        case .wristTemperature: return Color(hex: "8266C6")
        case .sunlight: return Color(hex: "A56A24")
        case .walkingAsymmetry: return Color(hex: "33A6DA")
        case .heartRhythm: return Color(hex: "E8657F")
        }
    }

    var detailSummaryText: String {
        switch self {
        case .hrv:
            return String(localized: "先看今天是否接近近期基线，再结合压力和睡眠判断恢复空间。")
        case .restingHeartRate:
            return String(localized: "静息心率更适合看日内负荷和长期趋势，持续抬高时再结合身体感受。")
        case .vo2Max:
            return String(localized: "心肺耐力更新较慢，重点看趋势方向和样本来源，不必追逐单日波动。")
        case .wristTemperature:
            return String(localized: "手腕温度更像睡眠期间的节律线索，连续偏移比单次变化更值得关注。")
        case .sunlight:
            return String(localized: "自然光暴露会影响昼夜节律，先看今天是否积累到足够的户外时间。")
        case .walkingAsymmetry:
            return String(localized: "步态不对称用于观察左右步伐平衡，趋势比单个点更有参考意义。")
        case .heartRhythm:
            return String(localized: "心律稳定性综合房颤负担、心律不齐通知与 ECG 结论，为参考指标，不作医疗诊断。")
        }
    }
}

private struct TodayOtherMetricDetailIntroCard: View {
    let summary: TodayOtherMetricDetailSummary

    private var statusColor: Color {
        switch summary.statusTone {
        case .positive: return Color(hex: "1B9266")
        case .normal: return summary.tint
        case .caution: return Color(hex: "F06F45")
        case .muted: return Theme.Colors.textTertiary
        }
    }

    private var validTrendPoints: [TimeSeriesPointDouble] {
        summary.trendPoints.filter { $0.value >= 0 }
    }

    private var showsTrend: Bool {
        validTrendPoints.count >= 2
    }

    var body: some View {
        ModernReportHero(
            eyebrow: "今日身体指数",
            title: summary.title,
            value: summary.valueText,
            unit: summary.unitText,
            ghostUnit: summary.unitText.isEmpty ? "SIGNAL" : summary.unitText,
            captions: [
                ModernReportCaption(symbol: "arrow.left.and.right", text: summary.deltaText),
                ModernReportCaption(symbol: "clock.fill", text: summary.lastUpdatedText),
                ModernReportCaption(symbol: "info.circle.fill", text: summary.summaryText)
            ],
            badge: ModernReportBadge(
                symbol: "checkmark.circle.fill",
                text: summary.statusText,
                tint: statusColor
            ),
            accent: summary.tint,
            symbol: summary.symbol
        )
    }

    private func detailChip(text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.appSystem(size: 10, weight: .black))
            Text(text)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.05), in: Capsule())
    }
}

private struct TodayOtherMetricCard: View {
    let metric: DashboardOtherMetricCardModel

    private var accentColor: Color {
        switch metric.destination {
        case .hrv: return Color(hex: "58C6E8")
        case .restingHeartRate: return Color(hex: "B93A3A")
        case .vo2Max: return Color(hex: "B38A58")
        case .wristTemperature: return Color(hex: "F7B143")
        case .sunlight: return Color(hex: "A56A24")
        case .walkingAsymmetry: return Color(hex: "87D991")
        case .heartRhythm: return Color(hex: "E8657F")
        case .none: return Theme.Colors.textTertiary
        }
    }

    private var statusColor: Color {
        switch metric.statusTone {
        case .positive: return Color(hex: "1B9266")
        case .normal: return Color(hex: "7A7E86")
        case .caution: return Color(hex: "F06F45")
        case .muted: return Color(hex: "7A7E86")
        }
    }

    private var symbol: String {
        switch metric.destination {
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .vo2Max: return "lungs.fill"
        case .wristTemperature: return "thermometer.medium"
        case .sunlight: return "sun.max.fill"
        case .walkingAsymmetry: return "figure.walk"
        case .heartRhythm: return "waveform.path.ecg.rectangle"
        case .none: return "circle.fill"
        }
    }

    private var statusSymbol: String {
        switch metric.statusTone {
        case .positive:
            return "checkmark.circle.fill"
        case .normal:
            return "questionmark.circle"
        case .caution:
            return "exclamationmark.triangle.fill"
        case .muted:
            return "questionmark.circle"
        }
    }

    private var showsSparkline: Bool {
        metric.statusTone != .muted && metric.trendPoints.filter { $0.value >= 0 }.count >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(accentColor)
                    .frame(width: 23, height: 23)

                Text(metric.title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    if metric.isInteractive {
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 14, weight: .black))
                    }
                }
                .foregroundColor(Color(hex: "B7B7BD"))
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(metric.valueText)
                            .font(.appSystem(size: 29, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)

                        if !metric.unitText.isEmpty {
                            Text(metric.unitText)
                                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "B8BAC0"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: statusSymbol)
                            .font(.appSystem(size: 12, weight: .black))
                        Text(metric.statusText)
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundColor(statusColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if showsSparkline {
                    TodayOtherMetricSparkline(points: metric.trendPoints, accentColor: accentColor)
                        .frame(width: 96, height: 42)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .todayCardSurface(tint: accentColor)
    }
}

private struct TodayOtherMetricSparkline: View {
    let points: [TimeSeriesPointDouble]
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            let normalized = normalizedPoints(in: geometry.size)

            ZStack {
                Path { path in
                    let y = geometry.size.height * 0.38
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(
                    Color(hex: "AFAFB4"),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [4, 5])
                )

                if normalized.count >= 2 {
                    Path { path in
                        path.move(to: normalized[0])
                        for point in normalized.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    ForEach(Array(normalized.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(accentColor, lineWidth: 3))
                            .frame(width: 13, height: 13)
                            .position(point)
                    }
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let valid = points.filter { $0.value >= 0 }
        guard let minValue = valid.map(\.value).min(),
              let maxValue = valid.map(\.value).max(),
              !valid.isEmpty else {
            return []
        }

        let range = max(maxValue - minValue, 0.0001)
        let stepX = valid.count > 1 ? size.width / CGFloat(valid.count - 1) : 0
        let verticalPadding: CGFloat = 10
        let availableHeight = max(1, size.height - verticalPadding * 2)

        return valid.enumerated().map { index, point in
            let normalizedY = (point.value - minValue) / range
            return CGPoint(
                x: CGFloat(index) * stepX,
                y: size.height - verticalPadding - CGFloat(normalizedY) * availableHeight
            )
        }
    }
}

private struct AuthorizedTodayCard: View {
    @State private var showingInsightSheet = false
    @State private var aiInitialPrompt = "请解释我今天的压力和恢复状态，并告诉我现在最值得优先处理的事情。"
    let assessment: StressPresentationAssessment
    let realtimeHealth: RealtimeHealth?
    let restingHeartRate: Double?
    let avgHrvToday: Double?
    let recentAvgHrv: Double?
    let recentAvgRestingHeartRate: Double?
    let history: HealthHistory?

    private var style: StressVisualStyle {
        StressVisualStyle.style(for: assessment.band)
    }

    private var isWaitingState: Bool {
        !assessment.hasData
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(isWaitingState ? 0.40 : 0.22))
                .bbTintedSurface(tint: style.accentColor, in: RoundedRectangle(cornerRadius: 32, style: .continuous), tintStrength: isWaitingState ? 0.045 : 0.07)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )

            VStack(spacing: 0) {
                StressHeroArtwork(style: style)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .padding(.top, 10)
                    .opacity(isWaitingState ? 0.44 : 1)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("Hi，你今日综合压力状态")
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary.opacity(isWaitingState ? 0.62 : 1))
                        Label {
                            Text(assessment.hasData ? "状态评估" : "等待采集")
                        } icon: {
                            Image(systemName: style.metricSymbol)
                        }
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(style.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .bbTintedChip(tint: style.accentColor, in: Capsule(), tintOpacity: 0.07)
                        Spacer(minLength: 0)
                    }

                    if assessment.hasData {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(assessment.valueText)
                                .font(.appSystem(size: 52, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("/100")
                                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                            Text(assessment.title)
                                .font(.appSystem(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(style.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Spacer(minLength: 0)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(assessment.title)
                                .font(.appSystem(size: 42, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("请在解锁 Apple Watch 的情况下继续保持佩戴。")
                                .font(.appSystem(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(style.accentColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PressureScaleBar(assessment: assessment, style: style)
                        .frame(height: 22)
                        .opacity(isWaitingState ? 0.54 : 1)

                    MetricsRow(
                        style: style,
                        avgHrvToday: resolvedAvgHrvToday,
                        recentAvgHrv: resolvedRecentAvgHrv,
                        restingHeartRate: resolvedRestingHeartRate,
                        recentAvgResting: resolvedRecentAvgResting
                    )
                    .opacity(isWaitingState ? 0.5 : 1)

                    AdviceBlock(
                        style: style,
                        title: assessment.adviceTitle,
                        detail: assessment.adviceDetail,
                        updatedAt: updatedAtText
                    )
                    .opacity(isWaitingState ? 0.58 : 1)

                    Divider()
                        .opacity(isWaitingState ? 0.34 : 1)

                    HStack {
                        NavigationLink {
                            PressureDetailView(
                                history: history,
                                preferredAssessment: assessment,
                                preferredRealtimeHealth: realtimeHealth,
                                preferredAvgHrvToday: avgHrvToday,
                                preferredRecentAvgHrv: recentAvgHrv,
                                preferredRestingHeartRate: restingHeartRate,
                                preferredRecentAvgRestingHeartRate: recentAvgRestingHeartRate
                            )
                        } label: {
                            Text("详细解读")
                                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(style.buttonColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingInsightSheet = true
                        } label: {
                            Text("问问AI")
                                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(style.buttonColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .padding(.bottom, 6)
        }
        .sheet(isPresented: $showingInsightSheet, onDismiss: {
            aiInitialPrompt = "请解释我今天的压力和恢复状态，并告诉我现在最值得优先处理的事情。"
        }) {
            HealthAIView(
                context: makeHealthAIContext(
                    assessment: assessment,
                    realtimeHealth: realtimeHealth,
                    restingHeartRate: restingHeartRate,
                    avgHrvToday: avgHrvToday,
                    recentAvgHrv: recentAvgHrv,
                    recentAvgRestingHeartRate: recentAvgRestingHeartRate,
                    sleepData: nil,
                    sleepInterval: nil,
                    nightlyHrv: nil,
                    nightlyRespiratoryRate: nil,
                    sleepingWristTemperature: nil
                ),
                initialPrompt: aiInitialPrompt
            )
            .adaptiveSheetChrome(style: .reading, detents: [.large], dragIndicator: .visible)
        }
    }

    private var resolvedAvgHrvToday: Double {
        if let avgHrvToday, avgHrvToday > 0 { return avgHrvToday }
        if let realtimeHealth, realtimeHealth.hrv > 0 { return realtimeHealth.hrv }
        return 0
    }

    private var resolvedRestingHeartRate: Double {
        if let restingHeartRate, restingHeartRate > 0 { return restingHeartRate }
        if let realtimeHealth, realtimeHealth.bpm > 0 { return Double(realtimeHealth.bpm) }
        return 0
    }

    private var resolvedRecentAvgHrv: Double {
        recentAvgHrv ?? 0
    }

    private var resolvedRecentAvgResting: Double {
        recentAvgRestingHeartRate ?? 0
    }

    private var updatedAtText: String? {
        guard let ts = assessment.updatedAtSeconds, ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let time = date.formatted(.dateTime.hour().minute())
        return String(localized: "数据更新于 \(time)")
    }
}

private struct PressureScaleBar: View {
    let assessment: StressPresentationAssessment
    let style: StressVisualStyle

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let segmentWidth = max(24, (geo.size.width - spacing * 4) / 5)
            let value = assessment.score.flatMap { $0 > 0 ? Double($0) : nil } ?? style.scaleValue

            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(Array(style.scaleSegmentColors.enumerated()), id: \.offset) { idx, color in
                        Capsule()
                            .fill(color.opacity(segmentOpacity(for: idx)))
                            .frame(width: segmentWidth, height: idx == style.highlightScaleSegment ? 18 : 14)
                            .overlay(
                                Capsule()
                                    .stroke(color.opacity(idx == style.highlightScaleSegment ? 0.22 : 0), lineWidth: 1)
                            )
                            .shadow(
                                color: idx == style.highlightScaleSegment ? color.opacity(0.24) : .clear,
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    }
                }

                if let value {
                    Circle()
                        .fill(Theme.Colors.background)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(style.accentColor.opacity(0.75), lineWidth: 5))
                        .shadow(color: style.accentColor.opacity(0.24), radius: 8, x: 0, y: 4)
                        .offset(x: offsetX(for: value, totalWidth: geo.size.width) - 10, y: -1)
                }
            }
        }
    }

    private func segmentOpacity(for idx: Int) -> Double {
        if let highlight = style.highlightScaleSegment {
            return idx == highlight ? 1.0 : 0.52
        }
        return 0.5
    }

    private func offsetX(for value: Double, totalWidth: CGFloat) -> CGFloat {
        let clamped = max(0, min(100, value))
        return totalWidth * CGFloat(clamped / 100.0)
    }
}

private struct MetricsRow: View {
    let style: StressVisualStyle
    let avgHrvToday: Double
    let recentAvgHrv: Double
    let restingHeartRate: Double
    let recentAvgResting: Double

    var body: some View {
        HStack(spacing: 0) {
            MetricMiniCard(
                accentColor: style.accentColor,
                glowColor: style.glowColor,
                title: "今日平均HRV",
                valueText: avgHrvToday > 0 ? String(format: "%.0f", avgHrvToday) : "—",
                unit: "ms",
                deltaText: deltaText(current: avgHrvToday, baseline: recentAvgHrv),
                isUp: avgHrvToday > recentAvgHrv,
                sparkline: sparklineValues(seed: avgHrvToday)
            )

            Divider()
                .padding(.vertical, 10)

            MetricMiniCard(
                accentColor: style.secondaryColor,
                glowColor: style.glowColor,
                title: "静息心率",
                valueText: restingHeartRate > 0 ? String(format: "%.0f", restingHeartRate) : "—",
                unit: "次/分",
                deltaText: deltaText(current: restingHeartRate, baseline: recentAvgResting),
                isUp: restingHeartRate > recentAvgResting,
                sparkline: sparklineValues(seed: restingHeartRate)
            )
        }
        .bbTintedSurface(tint: style.accentColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous), tintStrength: 0.06, shadow: false)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func deltaText(current: Double, baseline: Double) -> String? {
        guard current > 0, baseline > 0 else { return nil }
        return String(format: String(localized: "近期平均%.0f%@"), baseline, current == baseline ? "" : "")
    }

    private func sparklineValues(seed: Double) -> [Double] {
        guard seed > 0 else { return [] }
        let a = max(0, seed + 6)
        let b = max(0, seed + 2)
        let c = max(0, seed - 4)
        let d = max(0, seed)
        return [a, b, c, d]
    }
}

private struct MetricMiniCard: View {
    let accentColor: Color
    let glowColor: Color
    let title: String
    let valueText: String
    let unit: String
    let deltaText: String?
    let isUp: Bool
    let sparkline: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
            .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.appSystem(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if let deltaText {
                HStack(spacing: 6) {
                    Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.appSystem(size: 10, weight: .bold))
                        .foregroundColor(isUp ? accentColor : Color(hex: "34C759"))
                    Text(deltaText)
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Sparkline(values: sparkline)
                .frame(height: 34)
                .opacity(sparkline.isEmpty ? 0 : 1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glowColor.opacity(0.18))
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 0
            let range = max(1, maxV - minV)

            Path { path in
                guard values.count >= 2 else { return }
                for idx in values.indices {
                    let x = w * CGFloat(Double(idx) / Double(values.count - 1))
                    let y = h - (h * CGFloat((values[idx] - minV) / range))
                    if idx == values.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct AdviceBlock: View {
    let style: StressVisualStyle
    let title: String
    let detail: String
    let updatedAt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .bbTintedChip(tint: style.accentColor, in: Circle(), tintOpacity: 0.08)
                    Image(systemName: style.adviceSymbol)
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(style.accentColor)
                }
                .frame(width: 28, height: 28)

                Text(title)
                    .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detail)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if let updatedAt {
                Text(updatedAt)
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.top, 2)
            }
        }
    }
}

private struct StressHeroArtwork: View {
    let style: StressVisualStyle

    private var isWaitingState: Bool {
        style.illustrationVariant == .waitingOrbit
    }

    var body: some View {
        ZStack {
            if isWaitingState {
                Color.white.opacity(0.34)

                Circle()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: 180, height: 180)
                    .offset(x: 120, y: -88)
                    .blur(radius: 2)

                Circle()
                    .fill(Color(hex: "D9DEE8").opacity(0.34))
                    .frame(width: 150, height: 150)
                    .offset(x: -132, y: -74)
                    .blur(radius: 6)

                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 84)
                    .offset(y: 72)

                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { idx in
                        Ellipse()
                            .fill(Color(hex: idx.isMultiple(of: 2) ? "D8DEE8" : "E6EAF1").opacity(idx == 1 ? 0.28 : 0.2))
                            .frame(width: 78, height: CGFloat(110 + idx * 10))
                            .offset(y: CGFloat(80 + (idx % 2 == 0 ? 8 : -2)))
                    }
                }
                .opacity(0.9)
                .offset(y: 30)
            } else {
                LinearGradient(
                    colors: style.heroGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(style.glowColor.opacity(0.95))
                    .frame(width: 210, height: 210)
                    .offset(x: 124, y: -94)

                Circle()
                    .fill(style.secondaryColor.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .offset(x: -150, y: -82)

                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.white.opacity(0.24))
                    .frame(height: 94)
                    .offset(y: 68)
                    .blur(radius: 0.4)

                HStack(spacing: 26) {
                    ForEach(0..<4, id: \.self) { idx in
                        Ellipse()
                            .fill((idx.isMultiple(of: 2) ? style.secondaryColor : style.accentColor).opacity(idx == 1 ? 0.22 : 0.16))
                            .frame(width: 82, height: CGFloat(118 + idx * 12))
                            .offset(y: CGFloat(76 + (idx % 2 == 0 ? 10 : -2)))
                    }
                }
                .opacity(0.85)
                .offset(y: 28)
            }

            Image(style.heroImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 212, height: 212)
                .offset(y: 26)
                .opacity(isWaitingState ? 0.72 : 1)
        }
    }
}

private struct TodayChartsCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStressTimestamp: Int64?
    @State private var todaySleepIntervals: [DateInterval] = []
    let assessment: StressPresentationAssessment
    let realtimeHealth: RealtimeHealth?
    let history: HealthHistory?
    let sevenMinuteStressPoints: [TimeSeriesPoint]
    let avgHrvToday: Double?
    let recentAvgHrv: Double?
    let restingHeartRate: Double?
    let onShowInfo: (TodayInfoTopic) -> Void
    private let stressChartBucketSeconds: Int64 = 20 * 60
    private let stressChartBucketMinutes: Int = 20
    private let stressInterpolationBucketSeconds: Int64 = 10 * 60
    private let stressInterpolationMaximumGapMinutes: Int = 120

    private var style: StressVisualStyle {
        StressVisualStyle.style(for: assessment.band)
    }

    private struct Point: Identifiable {
        let id: String
        let timestamp: Int64
        let value: Double

        var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
        var time: String {
            date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        init(timestamp: Int64, value: Double) {
            self.timestamp = timestamp
            self.value = value
            self.id = "\(timestamp)-\(Int(value.rounded()))"
        }
    }

    private struct StressChartPoint: Identifiable {
        let timestamp: Int64
        let value: Double
        let isEstimated: Bool

        var id: String { "\(timestamp)-\(Int(value.rounded()))" }
        var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

        init(timestamp: Int64, value: Double, isEstimated: Bool = false) {
            self.timestamp = timestamp
            self.value = value
            self.isEstimated = isEstimated
        }
    }

    var body: some View {
        unlockedTrendContent
        .padding(16)
        .todayCardSurface(tint: style.accentColor, emphasized: true)
        .task {
            await loadTodaySleepIntervals()
        }
    }

    private var unlockedTrendContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("综合压力")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("今日")
                        .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(stressTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .bbTintedChip(tint: stressTint, in: Capsule(), tintOpacity: 0.07)

                    Button {
                        onShowInfo(.dailyStress)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.appSystem(size: 14, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                stressChartPanel
                    .padding(.vertical, 8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("今日HRV趋势")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Button {
                        onShowInfo(.hrvTrend)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.appSystem(size: 14, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                hrvChartPanel
                    .padding(.vertical, 8)
            }

        }
    }

    @ViewBuilder
    private var stressChartPanel: some View {
        if stressChartPoints.isEmpty {
            TodayEmptyChart(text: style.chartEmptyText)
                .frame(height: 140)
        } else {
            stressSummaryStrip

            stressChart

            stressStateLegend

            if stressEstimatedCount > 0 {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(stressTint.opacity(0.38))
                        .frame(width: 14, height: 8)
                    Text("浅色柱为相邻样本之间的估算")
                        .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

        }
    }

    private var stressSummaryStrip: some View {
        HStack(spacing: 0) {
            stressSummaryItem(title: "当前", value: stressCurrentValue)
            stressSummaryDivider
            stressSummaryItem(title: "均值", value: stressAverageValue)
            stressSummaryDivider
            stressSummaryItem(title: "峰值", value: stressPeakValue)
            stressSummaryDivider
            stressSummaryItem(title: "样本", value: stressChartPoints.count)
        }
        .padding(.vertical, 9)
    }

    private func stressSummaryItem(title: String, value: Double?) -> some View {
        stressSummaryItem(title: title, value: value.map { Int($0.rounded()) })
    }

    private func stressSummaryItem(title: String, value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            if let value {
                Text("\(value)")
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()
            } else {
                Text("--")
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stressSummaryDivider: some View {
        Rectangle()
            .fill(Theme.Colors.textTertiary.opacity(0.14))
            .frame(width: 1, height: 25)
    }

    private var stressChart: some View {
        StressTimelineStyledChart(
            points: stressTimelinePoints,
            domain: todayChartDomain,
            axisDates: stressAxisDates,
            axisLabel: stressAxisLabel(for:),
            accent: stressTint,
            emptyText: style.chartEmptyText,
            sleepIntervals: todaySleepIntervals,
            height: 168,
            metricName: "综合压力",
            presentation: .compact,
            bucketDuration: TimeInterval(stressInterpolationBucketSeconds),
            estimatedTimestamps: stressTimelineSeries.estimatedTimestamps,
            selectedTimestamp: $selectedStressTimestamp
        )
    }

    private var stressStateLegend: some View {
        HStack(spacing: 14) {
            stressLegendItem(color: Color(hex: "34C759"), title: "放松")
            stressLegendItem(color: Color(hex: "007F79"), title: "平稳")
            stressLegendItem(color: Color(hex: "FF9F0A"), title: "轻度压力")
            stressLegendItem(color: Color(hex: "FF7A00"), title: "注意压力")
            stressLegendItem(color: Color(hex: "D70015"), title: "压力偏高")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func stressLegendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }


    @ViewBuilder
    private var hrvChartPanel: some View {
        if hrvPoints.isEmpty {
            TodayEmptyChart(text: hrvEmptyChartText)
                .frame(height: 140)
        } else {
            hrvSummaryStrip

            hrvChart

            hrvTrendLegend
        }
    }

    private var hrvChart: some View {
        TodayHRVPenChart(
            samples: hrvPoints.map { TimeSeriesPointDouble(timestamp: $0.timestamp, value: $0.value) },
            xDomain: todayChartDomain,
            yDomain: hrvChartDomain,
            axisDates: stressAxisDates.filter { !stressAxisLabel(for: $0).isEmpty },
            axisValues: hrvAxisValues,
            reference: hrvReferenceValue,
            referenceLabel: hrvReferenceBadgeText,
            average: hrvShouldShowIntradayAverageMark ? hrvIntradayAverage : nil,
            tint: hrvGlowColor,
            lineGradient: hrvLineGradient
        )
    }

    private var hrvSummaryStrip: some View {
        HStack(spacing: 0) {
            hrvSummaryItem(title: "当前", value: latestHrvValue)
            hrvSummaryDivider
            hrvSummaryItem(title: "均值", value: hrvIntradayAverage)
            hrvSummaryDivider
            hrvSummaryItem(title: hrvReferenceSummaryTitle, value: hrvReferenceValue)
            hrvSummaryDivider
            hrvSummaryItem(title: "波动", value: hrvRangeValue)
        }
        .padding(.vertical, 9)
    }

    private func hrvSummaryItem(title: String, value: Double?) -> some View {
        hrvSummaryItem(title: title, value: value.map { Int($0.rounded()) })
    }

    private func hrvSummaryItem(title: String, value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                if let value {
                    Text("\(value)")
                        .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .monospacedDigit()
                }
                if value != nil {
                    Text("ms")
                        .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }
            .minimumScaleFactor(0.82)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var hrvSummaryDivider: some View {
        Rectangle()
            .fill(Theme.Colors.textTertiary.opacity(0.14))
            .frame(width: 1, height: 25)
    }

    private var hrvTrendLegend: some View {
        HStack(spacing: 12) {
            hrvLegendItem(color: Color(hex: "33B58F"), title: "高于参考")
            hrvLegendItem(color: Color(hex: "57B8B0"), title: "接近参考")
            hrvLegendItem(color: Color(hex: "6D7EF7"), title: "低于参考")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func hrvLegendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private var hrvInsightBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hrvTrendSymbol)
                .font(.appSystem(size: 15, weight: .bold))
                .foregroundColor(hrvTrendTint)
                .frame(width: 28, height: 28)
                .bbTintedChip(tint: hrvTrendTint, in: Circle(), tintOpacity: 0.12)

            VStack(alignment: .leading, spacing: 3) {
                Text(hrvTrendTitle)
                    .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                Text(hrvTrendDetailText)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(hrvTrendTint.opacity(0.32))
                .frame(width: 3)
        }
    }


    private var hrvEmptyChartText: String {
        assessment.band == .waiting ? "正在等待今日 HRV 样本" : "暂无今日数据"
    }


    private var hrvPoints: [Point] {
        let rawPoints = history?.hrvHistory.compactMap { item -> Point? in
            guard let timestamp = item.timestamp, let value = item.sdnn, value > 0 else { return nil }
            return Point(timestamp: timestamp, value: value)
        } ?? []

        if !rawPoints.isEmpty {
            let startTimestamp = Int64(todayStart.timeIntervalSince1970)
            let bucketSize: Int64 = 7 * 60
            let grouped = Dictionary(grouping: rawPoints) {
                ($0.timestamp - startTimestamp) / bucketSize
            }
            return grouped.compactMap { bucket, points in
                guard !points.isEmpty else { return nil }
                let average = points.map(\.value).reduce(0, +) / Double(points.count)
                return Point(timestamp: startTimestamp + bucket * bucketSize, value: average)
            }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(206)
            .map { $0 }
        }

        guard let realtimeHealth else { return [] }
        let value = realtimeHealth.hrv
        guard value > 0 else { return [] }
        return [Point(timestamp: realtimeHealth.timestamp, value: value)]
    }

    private var latestHrvValue: Double? {
        hrvPoints.last?.value
    }


    private var hrvIntradayAverage: Double? {
        if let avgHrvToday, avgHrvToday > 0 {
            return avgHrvToday
        }
        let values = hrvPoints.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var hrvReferenceValue: Double? {
        if let recentAvgHrv, recentAvgHrv > 0 {
            return recentAvgHrv
        }
        return hrvIntradayAverage
    }

    private var hrvUsesRecentBaseline: Bool {
        recentAvgHrv.flatMap { $0 > 0 ? $0 : nil } != nil
    }

    private var hrvReferenceLabel: String {
        hrvUsesRecentBaseline ? "近期基线" : "日内均值"
    }

    private var hrvReferenceSummaryTitle: String {
        hrvUsesRecentBaseline ? "基线" : "参考"
    }

    private var hrvReferenceBadgeText: String {
        guard let reference = hrvReferenceValue else { return "" }
        return "\(hrvReferenceLabel) \(Int(reference.rounded())) ms"
    }

    private var hrvShouldShowIntradayAverageMark: Bool {
        guard hrvUsesRecentBaseline,
              let average = hrvIntradayAverage,
              let reference = hrvReferenceValue else {
            return false
        }
        return abs(average - reference) >= 1
    }

    private var hrvGlowColor: Color {
        if let latest = latestHrvValue {
            return hrvLineColor(for: latest)
        }
        return Color(hex: "3AAE9B")
    }

    private var hrvLineGradient: LinearGradient {
        LinearGradient(
            colors: hrvGradientStops,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var hrvSampleBadgeText: String {
        "今日 \(hrvPoints.count) 个样本"
    }

    private var hrvRangeValue: Double? {
        let values = hrvPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return maxValue - minValue
    }

    private var hrvFirstPoint: Point? {
        hrvPoints.first
    }

    private var hrvPeakPoint: Point? {
        hrvPoints.max { $0.value < $1.value }
    }

    private var hrvLowPoint: Point? {
        hrvPoints.min { $0.value < $1.value }
    }

    private var hrvDayDelta: Double? {
        guard let first = hrvFirstPoint, let latest = hrvPoints.last, first.id != latest.id else { return nil }
        return latest.value - first.value
    }

    private var hrvTrendTint: Color {
        guard let delta = hrvDayDelta else {
            return hrvLineColor(for: latestHrvValue ?? hrvReferenceValue ?? 0)
        }
        if delta >= 5 { return Color(hex: "33B58F") }
        if delta <= -5 { return Color(hex: "6D7EF7") }
        if (hrvRangeValue ?? 0) >= 18 { return Color(hex: "FFA364") }
        return Color(hex: "57B8B0")
    }

    private var hrvTrendSymbol: String {
        guard let delta = hrvDayDelta else { return "waveform.path.ecg" }
        if delta >= 5 { return "arrow.up.right" }
        if delta <= -5 { return "arrow.down.right" }
        if (hrvRangeValue ?? 0) >= 18 { return "waveform.path" }
        return "equal"
    }

    private var hrvTrendTitle: String {
        guard hrvDayDelta != nil else { return "等待更多日内样本" }
        if let delta = hrvDayDelta, delta >= 5 { return "今日 HRV 正在回升" }
        if let delta = hrvDayDelta, delta <= -5 { return "今日 HRV 有所走低" }
        if (hrvRangeValue ?? 0) >= 18 { return "今日 HRV 波动偏大" }
        return String(localized: "今日 HRV 节律平稳")
    }

    private var hrvTrendDetailText: String {
        guard let latest = hrvPoints.last else {
            return String(localized: "继续等待健康 App 同步样本后，会显示日内节律。")
        }

        let referenceText: String
        if let reference = hrvReferenceValue {
            let delta = latest.value - reference
            if abs(delta) < 3 {
                referenceText = "最新值接近\(hrvReferenceLabel)"
            } else if delta > 0 {
                referenceText = "最新值高于\(hrvReferenceLabel) \(Int(abs(delta).rounded())) ms"
            } else {
                referenceText = "最新值低于\(hrvReferenceLabel) \(Int(abs(delta).rounded())) ms"
            }
        } else {
            referenceText = "继续积累样本后可比较参考线"
        }

        if let dayDelta = hrvDayDelta {
            let direction = dayDelta >= 0 ? "较首个样本高" : "较首个样本低"
            return "\(referenceText)，\(direction) \(Int(abs(dayDelta).rounded())) ms；\(hrvExtremeText)。"
        }

        return "\(referenceText)；\(hrvExtremeText)。"
    }

    private var hrvExtremeText: String {
        guard let low = hrvLowPoint, let peak = hrvPeakPoint, low.id != peak.id else {
            return String(localized: "当前样本还不足以判断高低点")
        }
        return String(localized: "低点 \(low.time)，高点 \(peak.time)")
    }

    private var hrvChartDomain: ClosedRange<Double> {
        let values = hrvPoints.map(\.value) + [hrvReferenceValue].compactMap { $0 }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 20...80
        }
        if abs(maxValue - minValue) < 1 {
            let padding = max(6, maxValue * 0.12)
            return max(0, minValue - padding)...(maxValue + padding)
        }
        let padding = max(6, (maxValue - minValue) * 0.22)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var hrvChartDescription: String {
        guard let latest = latestHrvValue else {
            return assessment.band == .waiting ? "正在等待今日 HRV 样本。" : "今日还没有足够的 HRV 样本。"
        }
        guard let reference = hrvReferenceValue else {
            return String(localized: "当前 HRV 为 \(Int(latest.rounded())) ms，继续积累样本后会更容易看清波动节律。")
        }
        let delta = latest - reference
        let referenceText = hrvReferenceLabel
        if abs(delta) < 3 {
            return String(localized: "当前 HRV \(Int(latest.rounded())) ms，基本贴近\(referenceText)，恢复节律相对平稳。")
        }
        if delta > 0 {
            return String(localized: "当前 HRV \(Int(latest.rounded())) ms，高于\(referenceText) \(Int(abs(delta).rounded())) ms，恢复状态相对更放松。")
        }
        return String(localized: "当前 HRV \(Int(latest.rounded())) ms，低于\(referenceText) \(Int(abs(delta).rounded())) ms，可能存在疲劳或压力负荷抬升。")
    }

    private var hrvGradientStops: [Color] {
        let values = hrvPoints.map(\.value)
        guard !values.isEmpty else {
            return [Color(hex: "3AAE9B"), Color(hex: "6D7EF7")]
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        if abs(maxValue - minValue) < 1 {
            let color = hrvLineColor(for: maxValue)
            return [color.opacity(0.88), color]
        }

        let midValue = values.reduce(0, +) / Double(values.count)
        return [
            hrvLineColor(for: minValue),
            hrvLineColor(for: midValue),
            hrvLineColor(for: maxValue)
        ]
    }

    private var stressChartPoints: [StressChartPoint] {
        let hrvPoints = history?.hrvHistory.compactMap { item -> TimeSeriesPointDouble? in
            guard let timestamp = item.timestamp, let value = item.sdnn, value > 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: timestamp, value: value)
        } ?? []
        let generatedSevenMinutePoints = StressDailyEngine.sevenMinuteStressPoints(
            hrv: hrvPoints,
            heartRate: history?.hrPoints ?? [],
            restingHeartRate: restingHeartRate,
            in: DateInterval(start: todayStart, end: todayEnd)
        )

        let sourcePoints: [TimeSeriesPoint]
        if !sevenMinuteStressPoints.isEmpty {
            sourcePoints = sevenMinuteStressPoints
        } else if !generatedSevenMinutePoints.isEmpty {
            sourcePoints = generatedSevenMinutePoints
        } else {
            sourcePoints = history?.stressPoints ?? []
        }
        var points = sourcePoints
            .filter { $0.value > 0 && todayChartDomain.contains($0.date) }
            .map { StressChartPoint(timestamp: $0.timestamp, value: Double($0.value)) }

        if let realtimeHealth,
           realtimeHealth.stress_value > 0,
           todayChartDomain.contains(Date(timeIntervalSince1970: TimeInterval(realtimeHealth.timestamp))) {
            let todayStartTimestamp = Int64(todayStart.timeIntervalSince1970)
            let bucketTimestamp = stressBucketTimestamp(
                for: realtimeHealth.timestamp,
                startTimestamp: todayStartTimestamp
            )
            points.append(
                StressChartPoint(
                    timestamp: bucketTimestamp,
                    value: Double(realtimeHealth.stress_value)
                )
            )
        }

        var groupedValues: [Int64: [Double]] = [:]
        let todayStartTimestamp = Int64(todayStart.timeIntervalSince1970)
        for point in points {
            let bucketTimestamp = stressBucketTimestamp(
                for: point.timestamp,
                startTimestamp: todayStartTimestamp
            )
            groupedValues[bucketTimestamp, default: []].append(point.value)
        }

        return groupedValues.compactMap { timestamp, values in
            guard !values.isEmpty else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return StressChartPoint(timestamp: timestamp, value: average)
        }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(206)
            .map { $0 }
    }

    private func stressBucketTimestamp(for timestamp: Int64, startTimestamp: Int64) -> Int64 {
        startTimestamp + (timestamp - startTimestamp) / stressChartBucketSeconds * stressChartBucketSeconds
    }

    private var stressTimelinePoints: [TimeSeriesPoint] {
        stressTimelineSeries.points
    }

    private var measuredStressTimelinePoints: [TimeSeriesPoint] {
        stressChartPoints.map {
            TimeSeriesPoint(timestamp: $0.timestamp, value: Int($0.value.rounded()))
        }
    }

    private var stressTimelineSeries: StressChartInterpolationResult {
        StressChartGapInterpolator.interpolate(
            points: measuredStressTimelinePoints,
            bucketSeconds: stressInterpolationBucketSeconds,
            maximumGapSeconds: Int64(stressInterpolationMaximumGapMinutes * 60),
            domain: todayChartDomain,
            now: Date()
        )
    }

    private var stressDisplayPoints: [StressChartPoint] {
        let estimatedTimestamps = stressTimelineSeries.estimatedTimestamps
        return stressTimelineSeries.points.map {
            StressChartPoint(
                timestamp: $0.timestamp,
                value: Double($0.value),
                isEstimated: estimatedTimestamps.contains($0.timestamp)
            )
        }
    }

    private var stressEstimatedCount: Int {
        stressTimelineSeries.estimatedTimestamps.count
    }

    private var stressSampleBadgeText: String {
        String(localized: "今日 \(stressChartPoints.count) 个样本 · \(stressEstimatedCount) 个估算")
    }

    private var stressCurrentValue: Double? {
        stressChartPoints.last?.value
    }

    private var stressAverageValue: Double? {
        guard !stressChartPoints.isEmpty else { return nil }
        return stressChartPoints.map(\.value).reduce(0, +) / Double(stressChartPoints.count)
    }

    private var stressPeakValue: Double? {
        stressChartPoints.map(\.value).max()
    }

    private var selectedStressPoint: StressChartPoint? {
        guard let selectedStressTimestamp else { return nil }
        return stressDisplayPoints.first(where: { $0.timestamp == selectedStressTimestamp })
    }

    private var stressTint: Color {
        style.accentColor
    }

    private var stressChartDescription: String {
        guard stressCurrentValue != nil else { return style.chartEmptyText }
        if let selectedStressPoint {
            return selectedStressDescription(for: selectedStressPoint)
        }
        return assessment.adviceDetail
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: todayStart)
            ?? todayStart.addingTimeInterval(24 * 60 * 60)
    }

    private var todayChartDomain: ClosedRange<Date> {
        todayStart...todayEnd
    }

    private var stressAxisDates: [Date] {
        let bucketOffsets = stride(from: 0, to: 24 * 60, by: stressChartBucketMinutes)
        let labeledOffsets = stride(from: 0, through: 24 * 60, by: 3 * 60)
        return Set(bucketOffsets).union(labeledOffsets).sorted().compactMap {
            Calendar.current.date(byAdding: .minute, value: $0, to: todayStart)
        }
    }

    private func stressAxisLabel(for date: Date) -> String {
        if abs(date.timeIntervalSince(todayEnd)) < 1 { return "24" }
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        guard minute == 0, hour.isMultiple(of: 3) else { return "" }
        return String(format: "%02d", Calendar.current.component(.hour, from: date))
    }

    private var hrvAxisValues: [Double] {
        let lower = hrvChartDomain.lowerBound
        let upper = hrvChartDomain.upperBound
        let step = (upper - lower) / 3
        return [
            floor(lower),
            floor(lower + step),
            floor(lower + step * 2),
            ceil(upper)
        ]
    }

    private func stressColor(_ value: Double) -> Color {
        // 与 StressBand 色调体系对齐
        switch value {
        case ..<30:
            return Color(hex: "34C759")
        case 30..<50:
            return Color(hex: "007F79")
        case 50..<70:
            return Color(hex: "FF9F0A")
        case 70..<85:
            return Color(hex: "FF7A00")
        default:
            return Color(hex: "D70015")
        }
    }


    private func hrvLineColor(for value: Double) -> Color {
        if let reference = hrvReferenceValue {
            let delta = value - reference
            if delta >= 6 { return Color(hex: "33B58F") }
            if delta <= -6 { return Color(hex: "6D7EF7") }
            return Color(hex: "57B8B0")
        }
        if value >= 55 { return Color(hex: "33B58F") }
        if value >= 35 { return Color(hex: "57B8B0") }
        return Color(hex: "6D7EF7")
    }


    private func loadTodaySleepIntervals() async {
        let intervals = (try? await HealthKitManager.shared.fetchSleepIntervals(on: todayStart)) ?? []
        todaySleepIntervals = intervals.map { DateInterval(start: $0.start, end: $0.end) }
    }

    private func selectedStressDescription(for point: StressChartPoint) -> String {
        let timeText = point.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if point.isEstimated {
            return String(localized: "\(timeText) 综合压力约为 \(Int(point.value.rounded()))，由相邻有效样本插值得到，不参与当前、均值或峰值计算。")
        }
        switch point.value {
        case ..<35:
            return String(localized: "\(timeText) 这一段综合压力处在较低区间，身体负荷相对平稳。")
        case 35..<70:
            return String(localized: "\(timeText) 这一段综合压力有一定抬升，但还在可控范围内，适合继续观察后续是否回落。")
        default:
            return String(localized: "\(timeText) 这一段综合压力进入偏高区间，如果持续时间较长，通常更值得安排恢复或降负荷。")
        }
    }

}

private struct TodayEmptyChart: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// 夜间恢复区中睡眠卡片下方的鼾声分析入口。
/// 视觉与 SleepSummaryCard 同一套 Today 卡片语言（渐变面+描边）；点击打开鼾声分析模块。
struct TodaySnoreAnalysisEntryCard: View {
    private var accent: Color { Color(hex: "4FA98B") }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("鼾声分析")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("声音时间线 · 严重程度 · 趋势与历史")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "9AA6AD"))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(0.08),
                    TodayVisualTokens.surface,
                    Color(hex: "FBFDFB")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
                .stroke(Color(hex: "DFEAED"), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开鼾声分析")
    }
}

private struct SleepSummaryCard: View {
    @Bindable var viewModel: SleepViewModel

    private var presentation: TodaySleepRecoveryCardPresentation {
        TodaySleepRecoveryCardPresentationBuilder.make(
            primaryData: viewModel.sleepData,
            fallbackSummary: viewModel.latestSleepSummary,
            primaryInterval: viewModel.sleepInterval,
            goalMinutes: viewModel.sleepGoalMinutes,
            nightlyHrv: viewModel.nightlyHrv,
            nightlyRespirationRate: viewModel.nightlyRespirationRate,
            recentNights: viewModel.recentNightSummaries
        )
    }

    private var accent: Color {
        switch presentation.tone {
        case .stable: return Color(hex: "4FA98B")
        case .attention: return Color(hex: "D8954E")
        case .recovery: return Color(hex: "D97862")
        case .building: return Color(hex: "788890")
        }
    }

    private var durationText: String {
        guard presentation.durationMinutes > 0 else { return "--h --m" }
        return String(localized: "\(presentation.durationMinutes / 60)h \(presentation.durationMinutes % 60)m")
    }

    private var qualitySubtitle: String {
        guard presentation.sleepScore > 0 else {
            return presentation.state == .loading
                ? String(localized: "等待同步")
                : String(localized: "暂无评分")
        }
        return String(localized: "睡眠质量 \(presentation.sleepScore)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: "moon.stars.fill")
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 28)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                Text(verbatim: String(localized: "睡眠"))
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer(minLength: 8)

                Text(verbatim: presentation.badgeText)
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.10), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: durationText)
                    .font(.appSystem(size: 32, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: qualitySubtitle)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(accent)

                if !presentation.timeRangeText.isEmpty {
                    Text(verbatim: presentation.timeRangeText)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            if presentation.state == .content, !presentation.metrics.isEmpty {
                metricStrip
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todaySleepGlassSurface(accent: accent)
        .contentShape(RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开夜间恢复详情")
    }

    private var metricStrip: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: presentation.metrics.count == 1 ? 1 : 2
            ),
            spacing: 8
        ) {
            ForEach(presentation.metrics, id: \.title) { metric in
                HStack(spacing: 7) {
                    Image(systemName: metric.systemImage)
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(metric.value)\(metric.unit)")
                            .font(.appSystem(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(verbatim: metric.title)
                            .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Theme.Colors.secondarySurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private extension View {
    /// HTML 稿里的首页睡眠模块是轻玻璃摘要卡；iOS 26+ 使用 Liquid Glass，旧系统退化为浅玻璃白卡。
    @ViewBuilder
    func todaySleepGlassSurface(accent: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.bbLiquidGlassSurface(
                tint: accent,
                in: RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous),
                tintStrength: 0.08,
                shadow: true
            )
        } else {
            self
                .background(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.07),
                            Theme.Colors.surface.opacity(0.96),
                            Color(hex: "FBFDFB")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
                        .stroke(Color(hex: "DFEAED"), lineWidth: 1)
                }
        }
    }
}

private struct TodaySedentarySummaryCard: View {
    @Bindable var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenDetail: () -> Void

    private var state: DashboardSedentaryState { viewModel.sedentaryState }
    private var summary: SedentaryDaySummary { viewModel.sedentaryTodaySummary }

    private var accentColor: Color {
        if state.sourceStatus == .needsAuthorization { return Color(hex: "5E8CFF") }
        if state.sourceStatus == .sleeping { return Color(hex: "7C8CFF") }
        if state.sourceStatus == .autoStartDisabled || state.sourceStatus == .noActivitySamples { return Color(hex: "9BA3C8") }
        if state.sourceStatus == .unavailable { return Color(hex: "F46B5A") }
        if state.elapsedMinutes >= 90 { return Color(hex: "F46B5A") }
        if state.elapsedMinutes >= 60 { return Color(hex: "F2A357") }
        return Color(hex: "38D98A")
    }

    private var statusText: String {
        switch state.sourceStatus {
        case .needsAuthorization:
            return String(localized: "等待授权")
        case .sleeping:
            return "睡眠暂停"
        case .autoStartDisabled:
            return String(localized: "自动关闭")
        case .noActivitySamples:
            return String(localized: "等待样本")
        case .unavailable:
            return String(localized: "同步异常")
        case .ready:
            if state.isCounting { return state.elapsedMinutes >= 60 ? "久坐中" : "计时中" }
            return "活动中"
        }
    }

    private var totalSedentaryMinutesValue: Int? {
        if summary.totalSedentaryMinutes > 0 {
            return summary.totalSedentaryMinutes
        }
        if state.isCounting {
            return state.elapsedMinutes
        }
        return nil
    }

    private var supportingText: String {
        switch state.sourceStatus {
        case .needsAuthorization:
            return String(localized: "授权后开始统计今日久坐、打断和分布。")
        case .sleeping:
            return String(localized: "睡眠期间暂停计时，醒来后继续累计。")
        case .autoStartDisabled:
            return String(localized: "自动开始关闭后，这里不会继续累积久坐统计。")
        case .noActivitySamples:
            return String(localized: "继续佩戴设备，等步数和站立样本补齐。")
        case .unavailable:
            return String(localized: "健康同步暂时不可用，稍后会自动重试。")
        case .ready:
            if let session = summary.focusSession {
                return session.isOngoing
                    ? "当前焦点时段 \(session.timeRangeText) · \(session.kind.title)"
                    : "今日焦点时段 \(session.timeRangeText) · \(session.kind.title)"
            }
            if summary.activeBreakCount > 0 {
                return String(localized: "今天已经完成 \(summary.activeBreakCount) 次打断。")
            }
            return String(localized: "今日久坐统计已开启，继续积累更多样本。")
        }
    }

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if state.sourceStatus == .ready || summary.totalSedentaryMinutes > 0 {
                    heroSection
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .todayCardSurface(tint: accentColor)
        }
        .todayCardButtonStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("久坐，\(statusText)，\(supportingText)")
        .accessibilityHint("打开久坐详情")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.seated.side")
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(accentColor)
                .frame(width: 24, height: 24)
                .bbTintedChip(tint: Color(hex: "E4ECF5"), in: Circle(), tintOpacity: 0.045)

            Text("久坐")
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Text(statusText)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .bbTintedChip(tint: Color(hex: "E4ECF5"), in: Capsule(), tintOpacity: 0.045)
        }
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("累计久坐")
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                sedentaryDurationDisplay

            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 12) {
                statBadge(title: "打断次数", value: summary.activeBreakCount, unit: "次")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.appSystem(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(supportingText)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func statBadge(title: String, value: Int, unit: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("\(value)")
                .font(.appSystem(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let unit {
                Text(unit)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor.opacity(0.88))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sedentaryDurationDisplay: some View {
        if let minutes = totalSedentaryMinutesValue {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(hours)")
                    .font(.appSystem(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("h")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("\(remainingMinutes)")
                    .font(.appSystem(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("m")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        } else {
            Text("--")
                .font(.appSystem(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private enum HealthGuideState {
    case authorized
    case unsupported
    case needsAuthorization
}

private struct HealthKitAuthorizationCard: View {
    let mode: HealthGuideState
    let onAuthorized: () -> Void

    @State private var isRequesting = false
    @State private var showAuthError = false

    private var actionColor: Color {
        Theme.Colors.mintGreen
    }

    var body: some View {
        VStack(spacing: 0) {
            SpaceHeroIllustration()
                .frame(height: 172)
                .frame(maxWidth: .infinity)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black, location: 0),
                            .init(color: Color.black, location: 0.70),
                            .init(color: Color.black.opacity(0.72), location: 0.88),
                            .init(color: Color.clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: TodayVisualTokens.cardCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: TodayVisualTokens.cardCornerRadius,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text(mode == .needsAuthorization ? "健康权限" : "设备检查")
                    } icon: {
                        Image(systemName: mode == .needsAuthorization ? "heart.text.square.fill" : "iphone.slash")
                    }
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(actionColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .bbTintedChip(tint: actionColor, in: Capsule(), tintOpacity: 0.08)

                    Text(titleText)
                        .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detailText)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .padding(.top, 4)

                    if mode == .needsAuthorization {
                        Button {
                            guard !isRequesting else { return }
                            isRequesting = true
                            Task {
                                // 经协调器发起：只有系统仍允许展示授权框时才发起请求。
                                let phase = await HealthAuthorizationCoordinator.shared.requestAuthorizationIfNeeded()
                                await MainActor.run {
                                    isRequesting = false
                                    if phase.isAuthorizedLike {
                                        onAuthorized()
                                    } else {
                                        showAuthError = true
                                    }
                                }
                            }
                        } label: {
                            Group {
                                if isRequesting {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("正在请求权限…")
                                    }
                                } else {
                                    Text("立即打开")
                                }
                            }
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.onAccent.opacity(0.98))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .bbTintedPrimaryButton(tint: actionColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("当前设备不支持 Health 数据读取。")
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .todayCardSurface(tint: actionColor)
        .alert("健康权限未开启", isPresented: $showAuthError) {
            Button("打开系统设置") {
                HealthAuthorizationCoordinator.shared.openHealthSettings()
            }
            Button("稍后再说", role: .cancel) { }
        } message: {
            Text("请在\"设置 > 隐私与安全性 > 健康\"中允许 眠屿 读取数据。")
        }
    }

    private var titleText: String {
        switch mode {
        case .authorized:
            return ""
        case .unsupported:
            return String(localized: "当前设备不支持健康数据")
        case .needsAuthorization:
            return String(localized: "眠屿 无法获取心率数据")
        }
    }

    private var detailText: String {
        switch mode {
        case .authorized:
            return ""
        case .unsupported:
            return String(localized: "此设备不提供 Apple Health 数据能力（例如部分模拟器或不支持 HealthKit 的设备）。请在 iPhone 真机上使用。")
        case .needsAuthorization:
            return "眠屿 需要读取你的健康数据，才能判断今日压力、展示趋势并给出建议。\n请放心，健康数据仅保存在本地设备，我们不会上传任何相关信息。"
        }
    }
}

private struct NotificationGuideCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.clear)
                        .bbTintedChip(tint: Theme.Colors.mintGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintOpacity: 0.09)
                    Image(systemName: "bell.badge.fill")
                        .font(.appSystem(size: 18, weight: .semibold))
                        .foregroundColor(Theme.Colors.mintGreen)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("打开手机通知，及时掌握压力状态")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("建议打开手机及手表通知，及时掌握 HRV 值所呈现的压力状态。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        let settings = await UNUserNotificationCenter.current().notificationSettings()
                        if settings.authorizationStatus == .notDetermined {
                            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 32, height: 32)
                        .bbTintedChip(tint: Theme.Colors.mintGreen, in: Circle(), tintOpacity: 0.06)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .todayCardSurface(tint: Theme.Colors.mintGreen)
    }
}

private struct FAQSection: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let onSelectQuestion: (String) -> Void

    private let items: [FAQItem] = [
        FAQItem(
            question: "手表无法收到压力通知？",
            title: "手表收不到压力通知？",
            subtitle: "先检查通知权限、专注模式和连接状态。",
            tag: "通知",
            systemImage: "bubble.left.and.bubble.right.fill",
            tint: Theme.Colors.mintGreen
        ),
        FAQItem(
            question: "非 Apple Watch 如何同步到健康？",
            title: "非 Apple Watch 怎么同步健康？",
            subtitle: "先在厂商 App 完成配对，再看 iPhone 健康是否已接入。",
            tag: "第三方",
            systemImage: "link.badge.plus",
            tint: Color(hex: "6B83E8")
        ),
        FAQItem(
            question: "压力监测频率相关说明",
            title: "压力多久会更新一次？",
            subtitle: "后台采样不是实时秒更，静止时更容易拿到样本。",
            tag: "频率",
            systemImage: "applewatch.watchface",
            tint: Theme.Colors.mintGreen
        ),
        FAQItem(
            question: "压力与HRV基础科普",
            title: "HRV 和压力是什么关系？",
            subtitle: "恢复好时 HRV 往往更高，疲劳和压力会拉低它。",
            tag: "科普",
            systemImage: "waveform.path.ecg",
            tint: Color(hex: "7C8CFF")
        ),
        FAQItem(
            question: "如何提高测量准确度？",
            title: "怎样提高测量准确度？",
            subtitle: "佩戴贴合、保持静止和持续同步都很重要。",
            tag: "准确度",
            systemImage: "scope",
            tint: Color(hex: "D9952A")
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                Text("常见问题")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("快速了解数据、设备和测量问题")
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if adaptiveLayout.usesExpandedLayout {
                LazyVGrid(columns: adaptiveLayout.gridItems(minWidth: 232, maxColumns: adaptiveLayout.rootGridColumnCount), spacing: Theme.Spacing.small) {
                    faqItems
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.small) {
                        faqItems
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var faqItems: some View {
        ForEach(items) { item in
            Button {
                onSelectQuestion(item.question)
            } label: {
                FAQTile(
                    title: item.title,
                    subtitle: item.subtitle,
                    tag: item.tag,
                    systemImage: item.systemImage,
                    tint: item.tint
                )
                .frame(maxWidth: .infinity, minHeight: adaptiveLayout.usesExpandedLayout ? 164 : nil)
                .frame(width: adaptiveLayout.usesExpandedLayout ? nil : 232)
            }
            .todayCardButtonStyle()
        }
    }

}

private struct FAQItem: Identifiable {
    let question: String
    let title: String
    let subtitle: String
    let tag: String
    let systemImage: String
    let tint: Color

    var id: String { question }
}

private extension UNAuthorizationStatus {
    var allowsDashboardNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

private struct FAQTile: View {
    let title: String
    let subtitle: String
    let tag: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(tint.opacity(0.10))
                    Image(systemName: systemImage)
                        .font(.appSystem(size: 20, weight: .bold))
                        .foregroundColor(tint)
                }
                .frame(width: 46, height: 46)

                Spacer(minLength: 8)

                Text(tag)
                    .font(Theme.Typography.label)
                    .foregroundColor(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("查看说明")
                    .font(Theme.Typography.captionBold)
                Image(systemName: "arrow.up.right")
                    .font(.appSystem(size: 12, weight: .bold))
            }
            .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .padding(Theme.Spacing.medium)
        .todayCardSurface(tint: tint)
    }
}

private struct SpaceHeroIllustration: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "D9F1E8"),
                    Color(hex: "E9E7F5")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Astronaut()
                .offset(y: 6)
        }
    }
}

private struct Astronaut: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: 320, height: 120)
                .offset(y: 74)

            HStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.90))
                    .frame(width: 112, height: 96)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                    )

                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 150, height: 128)
                    .overlay(
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                    )
            }
            .offset(y: 18)

            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 118, height: 118)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .fill(Color.black.opacity(0.10))
                        .frame(width: 74, height: 74)
                )
                .offset(x: -16, y: -8)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .frame(width: 42, height: 30)
                .offset(x: 38, y: 24)

            Circle()
                .fill(Color(hex: "B9C0FF").opacity(0.45))
                .frame(width: 18, height: 18)
                .offset(x: 60, y: -20)

            Circle()
                .fill(Color(hex: "B9C0FF").opacity(0.45))
                .frame(width: 18, height: 18)
                .offset(x: 14, y: -20)
        }
    }
}

#Preview("等待数据") {
    dashboardPreviewCard(
        StressPresentationAssessment(
            score: nil,
            band: .waiting,
            title: "等待数据",
            adviceTitle: "正在等待健康 App 同步今日样本。",
            adviceDetail: "请在解锁 Apple Watch 的情况下继续佩戴，眠屿 会在采集到足够的 HRV 和心率后自动更新今日状态。",
            tint: .tertiary,
            updatedAtSeconds: nil
        )
    )
}

#Preview("放松") {
    dashboardPreviewCard(StressPresentation.assessmentFromScore(22, now: .now, updatedAtSeconds: Int64(Date().timeIntervalSince1970)))
}

#Preview("平稳") {
    dashboardPreviewCard(StressPresentation.assessmentFromScore(42, now: .now, updatedAtSeconds: Int64(Date().timeIntervalSince1970)))
}

#Preview("轻度压力") {
    dashboardPreviewCard(StressPresentation.assessmentFromScore(61, now: .now, updatedAtSeconds: Int64(Date().timeIntervalSince1970)))
}

#Preview("注意压力") {
    dashboardPreviewCard(StressPresentation.assessmentFromScore(76, now: .now, updatedAtSeconds: Int64(Date().timeIntervalSince1970)))
}

#Preview("压力偏高") {
    dashboardPreviewCard(StressPresentation.assessmentFromScore(92, now: .now, updatedAtSeconds: Int64(Date().timeIntervalSince1970)))
}

#Preview("权限引导") {
    ScrollView {
        HealthKitAuthorizationCard(mode: .needsAuthorization) { }
            .padding()
            .background(Theme.Colors.secondaryBackground)
    }
}

@ViewBuilder
private func dashboardPreviewCard(_ assessment: StressPresentationAssessment) -> some View {
    ScrollView {
        AuthorizedTodayCard(
            assessment: assessment,
            realtimeHealth: nil,
            restingHeartRate: nil,
            avgHrvToday: assessment.hasData ? 46 : nil,
            recentAvgHrv: assessment.hasData ? 52 : nil,
            recentAvgRestingHeartRate: assessment.hasData ? 68 : nil,
            history: nil
        )
        .padding()
        .background(Theme.Colors.secondaryBackground)
    }
}
