import SwiftUI
import HealthKit
import WidgetKit
import OSLog

nonisolated enum DashboardCardStressSource: String, Sendable {
    case daily
    case current
    case todayReconstructed = "today_reconstructed"
    case todaySnapshot = "today_snapshot"
    case unavailable
}

nonisolated struct DashboardCardStressResolution: Sendable {
    let assessment: StressPresentationAssessment
    let source: DashboardCardStressSource
}

@MainActor
@Observable
class DashboardViewModel {
    static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "VO2Max")
    static let signalsLogger = Logger(subsystem: "com.boundesu.BioBalance", category: "TodaySignals")
    /// 页面级共享实例：今日页 / 健康页 / 压力页共用同一实时链路，
    /// 避免多实例各自轮询并重复执行 Widget/Watch 持久化重活。
    static let shared = DashboardViewModel()
    /// 今日页不再提供跨日期切换，所有首页查询始终锚定当前自然日。
    var selectedDate: Date {
        Calendar.current.startOfDay(for: now())
    }
    var realtimeHealth: RealtimeHealth?
    var history: HealthHistory?
    var restingHeartRate: Double?
    var avgHrvToday: Double?
    var recentAvgHrv: Double?
    var recentAvgRestingHeartRate: Double?
    var vo2Max: Double?
    var recentAvgVo2Max: Double?
    var vo2MaxIsEstimated = false
    var vo2MaxAssessment: VO2MaxDailyAssessment?
    var vo2MaxHistory: [VO2MaxDailyAssessment] = []
    var todayActivityPoints: [TimeSeriesPointDouble] = []
    var bodyBatteryLoadInput: StressBodyBatteryLoadInput = .empty
    var todaySevenMinuteStressPoints: [TimeSeriesPoint] = []
    var todayWalkingSpeedMps: Double?
    var currentStressEvaluation: StressEvaluation
    var dailyStressEvaluation: StressEvaluation
    var currentStressAssessment: StressPresentationAssessment
    var dailyStressAssessment: StressPresentationAssessment
    var otherMetrics: [DashboardOtherMetricCardModel] = []
    /// 最近一次心律稳定性评估结果，供身体电量扣分因子与详情页复用。
    var heartRhythmResult: HeartRhythmStabilityResult = .unavailable
    var sedentaryState: DashboardSedentaryState = .waiting
    var sedentaryTodaySummary: SedentaryDaySummary = .placeholder(on: Date(), status: .noData)
    var sedentaryRecentSummaries: [SedentaryDaySummary] = []
    var sedentaryBreakProgress: SedentaryBreakProgressState = .idle
    var isLoadingMoreSedentaryHistory = false
    var hasMoreSedentaryHistory = true
    var sedentaryAutoStartEnabled: Bool
    var sedentaryReminderEnabled: Bool
    var sedentaryReminderIntervalMinutes: Int
    
    var lastAlertAt: Date?
    let stressStore: StressStore
    let now: () -> Date
    let sedentaryNotificationPrefix = "dashboard_sedentary_reminder_"
    private static let sedentaryAutoStartEnabledKey = "dashboard_sedentary_auto_start_enabled"
    private static let sedentaryReminderEnabledKey = "dashboard_sedentary_reminder_enabled"
    private static let sedentaryReminderIntervalKey = "dashboard_sedentary_reminder_interval_minutes"
    private static let sedentaryHistoryLookbackDays = 365
    let sedentaryInitialHistoryDays = 8
    let sedentaryHistoryPageDays = 7
    var nextSedentaryHistoryEndDate: Date?
    private var realtimeObservationTask: Task<Void, Never>?
    private var dashboardLoadTask: Task<Void, Never>?
    /// Widget / Watch 持久化链路节流状态（PEN-3 P0-1）：避免实时更新每秒触发重活。
    /// internal 以便 DashboardViewModel+Persistence.swift 扩展访问。
    var lastWidgetPersistAt: Date?
    var lastWidgetPersistedRealtime: RealtimeHealth?
    static let widgetPersistMinInterval: TimeInterval = 10
    private var loadGeneration = 0
    private var lastLoadedDate: Date?
    private var lastLoadedAt: ContinuousClock.Instant?
    private let refreshClock = ContinuousClock()
    private let refreshPolicy = DashboardRefreshPolicy()
    var lastStressResolutionLogKey: String?
    
    init(
        stressStore: StressStore? = nil,
        vo2MaxStore: VO2MaxAssessmentStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let stressStore = stressStore ?? StressStore()
        let vo2MaxStore = vo2MaxStore ?? VO2MaxAssessmentStore()
        let initialDate = now()
        let liveCurrent = StressPresentation.evaluation(
            from: HealthDataManager.shared.realtimeHealth,
            now: initialDate
        )
        let cachedStress = try? stressStore.load()
        let canRestoreCachedStress = cachedStress.map {
            Calendar.current.isDate($0.savedAt, inSameDayAs: initialDate)
        } ?? false
        let initialCurrent = liveCurrent.result != nil
            ? liveCurrent
            : (canRestoreCachedStress ? cachedStress?.current : nil) ?? liveCurrent
        let initialDaily: StressEvaluation = canRestoreCachedStress
            ? (cachedStress?.daily ?? .unavailable(.noDailySamples))
            : .unavailable(.noDailySamples)
        let cachedVO2Assessments = vo2MaxStore.load()
        let initialVO2Candidates = VO2MaxRules.assessmentsInDashboardRollingWeek(
            onOrBefore: initialDate,
            in: cachedVO2Assessments
        )
        let initialVO2Assessment = initialVO2Candidates.last
        self.stressStore = stressStore
        self.now = now
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.sedentaryAutoStartEnabledKey) == nil {
            defaults.set(true, forKey: Self.sedentaryAutoStartEnabledKey)
        }
        if defaults.object(forKey: Self.sedentaryReminderEnabledKey) == nil {
            defaults.set(true, forKey: Self.sedentaryReminderEnabledKey)
        }
        if defaults.object(forKey: Self.sedentaryReminderIntervalKey) == nil {
            defaults.set(60, forKey: Self.sedentaryReminderIntervalKey)
        }
        self.sedentaryAutoStartEnabled = defaults.bool(forKey: Self.sedentaryAutoStartEnabledKey)
        self.sedentaryReminderEnabled = defaults.bool(forKey: Self.sedentaryReminderEnabledKey)
        self.sedentaryReminderIntervalMinutes = max(15, defaults.integer(forKey: Self.sedentaryReminderIntervalKey))
        self.currentStressEvaluation = initialCurrent
        self.dailyStressEvaluation = initialDaily
        self.currentStressAssessment = StressPresentation.assessment(from: initialCurrent)
        self.dailyStressAssessment = StressPresentation.assessment(from: initialDaily)
        self.vo2MaxHistory = cachedVO2Assessments
        self.vo2MaxAssessment = initialVO2Assessment
        self.vo2Max = initialVO2Assessment?.value
        self.recentAvgVo2Max = Self.recentMeasuredVO2Average(
            before: initialVO2Assessment,
            in: cachedVO2Assessments
        )
        self.vo2MaxIsEstimated = initialVO2Assessment?.source == .engineEstimated
        let initialVO2Source = initialVO2Assessment?.source.rawValue ?? "none"
        let initialVO2AgeDays = initialVO2Assessment.map {
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: $0.date),
                to: Calendar.current.startOfDay(for: initialDate)
            ).day ?? -1
        } ?? -1
        Self.signalsLogger.info(
            "[Today][VO2Max] operation=restoreWeekly windowDays=\(VO2MaxRules.dashboardRollingWindowDays, privacy: .public) cachedCount=\(cachedVO2Assessments.count, privacy: .public) weeklyCandidateCount=\(initialVO2Candidates.count, privacy: .public) selected=\(initialVO2Assessment != nil, privacy: .public) selectedAgeDays=\(initialVO2AgeDays, privacy: .public) source=\(initialVO2Source, privacy: .public)"
        )
        startRealtimeObservation()
    }

    isolated deinit {
        // 防止非共享实例释放后轮询 Task 永久空转（PEN-3 P2-6）。
        realtimeObservationTask?.cancel()
    }

    private func startRealtimeObservation() {
        realtimeObservationTask = Task { [weak self] in
            if let realtime = HealthDataManager.shared.realtimeHealth {
                self?.handleRealtimeUpdate(realtime, syncToHealthDataManager: false)
            }

            for await _ in NotificationCenter.default.notifications(
                named: .healthDataManagerRealtimeHealthDidChange,
                object: HealthDataManager.shared
            ) {
                guard !Task.isCancelled, let self else { return }
                guard let realtime = HealthDataManager.shared.realtimeHealth else { continue }
                self.handleRealtimeUpdate(realtime, syncToHealthDataManager: false)
            }
        }
    }

    var sedentaryInsightContent: SedentaryInsightContent {
        Self.makeSedentaryInsightContent(
            state: sedentaryState,
            summary: sedentaryTodaySummary,
            breakProgress: sedentaryBreakProgress,
            remindersEnabled: sedentaryReminderEnabled,
            historySummaries: sedentaryRecentSummaries,
            now: now()
        )
    }

    var sedentaryHistoryMinimumDate: Date {
        let calendar = Calendar.current
        let reference = calendar.startOfDay(for: now())
        return calendar.date(byAdding: .day, value: -(Self.sedentaryHistoryLookbackDays), to: reference) ?? reference
    }

    func setSedentaryAutoStartEnabled(_ enabled: Bool) {
        sedentaryAutoStartEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.sedentaryAutoStartEnabledKey)

        if enabled {
            Task { await refreshSedentaryState() }
        } else {
            clearSedentaryBreakState(preserveCompletionFeedback: false)
            cancelSedentaryReminders()
            sedentaryState = DashboardSedentaryState(
                seatedStartAt: nil,
                lastActivityAt: nil,
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                sourceStatus: .autoStartDisabled
            )
            HealthDataManager.shared.pushSedentaryToWatch(
                elapsedMinutes: 0,
                isCounting: false,
                pausedBySleep: false,
                seatedStartAt: nil,
                lastActivityAt: nil
            )
        }
    }

    func setSedentaryReminderEnabled(_ enabled: Bool) {
        sedentaryReminderEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.sedentaryReminderEnabledKey)

        if enabled {
            Task {
                _ = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
                await refreshSedentaryState()
            }
        } else {
            cancelSedentaryReminders()
        }
    }

    func setSedentaryReminderIntervalMinutes(_ minutes: Int) {
        sedentaryReminderIntervalMinutes = max(15, minutes)
        UserDefaults.standard.set(sedentaryReminderIntervalMinutes, forKey: Self.sedentaryReminderIntervalKey)
        syncSedentaryReminder()
    }
    
    var isViewingToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: now())
    }

    var cardStressAssessment: StressPresentationAssessment {
        cardStressResolution.assessment
    }

    var cardStressSource: String {
        cardStressResolution.source.rawValue
    }

    private var cardStressResolution: DashboardCardStressResolution {
        if dailyStressAssessment.hasData {
            return DashboardCardStressResolution(assessment: dailyStressAssessment, source: .daily)
        }
        if currentStressAssessment.hasData {
            return DashboardCardStressResolution(assessment: currentStressAssessment, source: .current)
        }

        // 日汇总刻意不把 HealthKit 重建点当成实时真值；但今日卡片仍应展示
        // 已经存在的当日压力估算，否则身体电量与专注能力也会被连锁置空。
        let calendar = Calendar.current
        let referenceDate = selectedDate
        let reconstructed = (todaySevenMinuteStressPoints + (history?.stressPoints ?? []))
            .filter {
                (1...100).contains($0.value)
                    && calendar.isDate($0.date, inSameDayAs: referenceDate)
            }
            .max { $0.timestamp < $1.timestamp }
        if let reconstructed {
            return DashboardCardStressResolution(
                assessment: StressPresentation.assessmentFromScore(
                    reconstructed.value,
                    now: now(),
                    updatedAtSeconds: reconstructed.timestamp
                ),
                source: .todayReconstructed
            )
        }

        if let realtimeHealth,
           (1...100).contains(realtimeHealth.stress_value),
           calendar.isDate(
                Date(timeIntervalSince1970: TimeInterval(realtimeHealth.timestamp)),
                inSameDayAs: referenceDate
           ) {
            return DashboardCardStressResolution(
                assessment: StressPresentation.assessmentFromScore(
                    realtimeHealth.stress_value,
                    now: now(),
                    updatedAtSeconds: realtimeHealth.timestamp
                ),
                source: .todaySnapshot
            )
        }

        return DashboardCardStressResolution(assessment: currentStressAssessment, source: .unavailable)
    }

    private var workRhythmHealthContext: HealthAIContext {
        HealthAIContextBuilder().makeContext(
            assessment: dailyStressAssessment,
            realtimeHealth: realtimeHealth,
            restingHeartRate: restingHeartRate,
            avgHrvToday: avgHrvToday,
            recentAvgHrv: recentAvgHrv,
            recentAvgRestingHeartRate: recentAvgRestingHeartRate,
            sleepData: nil,
            sleepInterval: nil,
            nightlyHrv: nil,
            nightlyRespiratoryRate: nil,
            sleepingWristTemperature: nil,
            sedentaryState: sedentaryState,
            sedentarySummary: sedentaryTodaySummary,
            activityPoints: todayActivityPoints,
            walkingSpeedMpsToday: todayWalkingSpeedMps,
            waterMlToday: AppGroupManager.shared.getWaterIntakeMl().map { Int($0.rounded()) },
            caffeineConsumedTodayMg: nil,
            daylightMinutesToday: AppGroupManager.shared.getValue(forKey: AppGroupManager.Keys.sunlightMinutesToday)
        )
    }

    func loadData(force: Bool = false) {
        let loadDate = selectedDate
        let clockNow = refreshClock.now
        let shouldRefresh = refreshPolicy.shouldRefresh(
            requestedDate: loadDate,
            lastLoadedDate: lastLoadedDate,
            lastLoadedAt: lastLoadedAt,
            now: clockNow,
            calendar: .current,
            force: force
        )
        guard shouldRefresh else {
            Self.signalsLogger.info("[Today][Signals] operation=loadSkipped reason=refresh_throttled")
            return
        }

        dashboardLoadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        Self.signalsLogger.info(
            "[Today][Signals] operation=loadStart generation=\(generation, privacy: .public) force=\(force, privacy: .public)"
        )

        if isViewingToday, let currentRealtime = HealthDataManager.shared.realtimeHealth {
            realtimeHealth = currentRealtime
        } else if !isViewingToday {
            realtimeHealth = nil
        }

        dashboardLoadTask = Task { [weak self] in
            guard let self else { return }
            let includeRealtime = Calendar.current.isDate(loadDate, inSameDayAs: self.now())

            await self.loadPrimaryMetrics(for: loadDate, includeRealtime: includeRealtime)
            guard !Task.isCancelled, generation == self.loadGeneration else { return }
            await self.refreshLocalAssessment(for: loadDate)
            await self.refreshOtherMetrics()
            self.refreshSedentaryBreakProgress()
            await self.refreshSedentaryState()

            guard !Task.isCancelled,
                  generation == self.loadGeneration,
                  Calendar.current.isDate(self.selectedDate, inSameDayAs: loadDate) else { return }
            if self.isViewingToday {
                self.persistStressHistoryForWatch()
            }
            self.refreshAssessmentFromCurrentState()
            self.lastLoadedDate = loadDate
            self.lastLoadedAt = self.refreshClock.now
            self.logStressResolution(operation: "loadComplete")
        }
    }

    func cancelLoading() {
        dashboardLoadTask?.cancel()
        dashboardLoadTask = nil
    }

    private func loadPrimaryMetrics(for loadDate: Date, includeRealtime: Bool) async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: loadDate)
        let queryEnd = min(
            calendar.date(byAdding: .day, value: 1, to: dayStart) ?? loadDate,
            now()
        )
        let bodyBatteryDayStart = dayStart
        let bodyBatteryDayEnd = queryEnd
        let workoutLookbackStart = calendar.date(byAdding: .day, value: -28, to: bodyBatteryDayEnd)
            ?? bodyBatteryDayStart

        // 身体信号共享这些输入。并行读取，避免 30 天 VO₂ / 运动负荷查询
        // 把压力、身体电量和专注能力一起阻塞在“等待同步”。
        async let realBpmTask: Double? = includeRealtime
            ? (try? await HealthKitManager.shared.fetchLatestHeartRate())
            : nil
        async let realHrvTask: Double? = includeRealtime
            ? (try? await HealthKitManager.shared.fetchLatestHRV())
            : nil
        async let restingTask = try? HealthKitManager.shared.fetchRestingHeartRate(on: loadDate)
        async let avgHrvTask = try? HealthKitManager.shared.fetchAverageHRV(on: loadDate)
        async let hrvPointsTask = try? HealthKitManager.shared.fetchHRVSamples(on: loadDate)
        async let heartRatePointsTask = try? HealthKitManager.shared.fetchHeartRateSeries(on: loadDate, maxPoints: 720)
        async let activityPointsTask = try? HealthKitManager.shared.fetchDailyStepSums(days: 7, endDate: queryEnd)
        async let walkingSpeedPointsTask = try? HealthKitManager.shared.fetchDailyWalkingSpeedAverages(days: 1, endDate: queryEnd)
        async let recentHrvPointsTask = try? HealthKitManager.shared.fetchDailyHRVAverages(days: 14, endDate: queryEnd)
        async let recentRestingPointsTask = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 14, endDate: queryEnd)
        async let vo2AssessmentsTask = resolvedVO2Assessments(days: 30, endDate: queryEnd)
        async let physicalEffortTask = bodyBatteryDayEnd > bodyBatteryDayStart
            ? ((try? await HealthKitManager.shared.fetchPhysicalEffortSamples(
                startDate: bodyBatteryDayStart,
                endDate: bodyBatteryDayEnd
            )) ?? [])
            : []
        async let workoutEffortTask = bodyBatteryDayEnd > workoutLookbackStart
            ? ((try? await HealthKitManager.shared.fetchWorkoutEffortSamples(
                startDate: workoutLookbackStart,
                endDate: bodyBatteryDayEnd
            )) ?? [])
            : []

        let realBpm = await realBpmTask
        let realHrv = await realHrvTask
        let resting = await restingTask
        let avgHrv = await avgHrvTask
        let hrvPoints = await hrvPointsTask ?? []
        let heartRatePoints = await heartRatePointsTask ?? []
        let recentHrvPoints = await recentHrvPointsTask ?? []
        let recentRestingPoints = await recentRestingPointsTask ?? []

        Self.signalsLogger.info(
            "[Today][Signals] operation=primaryInputsLoaded includeRealtime=\(includeRealtime, privacy: .public) latestHeartRateAvailable=\(realBpm != nil, privacy: .public) latestHRVAvailable=\(realHrv != nil, privacy: .public) todayHRVCount=\(hrvPoints.count, privacy: .public) todayHeartRateCount=\(heartRatePoints.count, privacy: .public)"
        )

        guard Calendar.current.isDate(selectedDate, inSameDayAs: loadDate) else { return }

        if includeRealtime {
            let localRealtime = HealthDataManager.shared.realtimeHealth
            let resolvedBpm = realBpm.flatMap { $0 > 0 ? Int($0.rounded()) : nil } ?? localRealtime?.bpm ?? 0
            let resolvedHrv = realHrv.flatMap { $0 > 0 ? $0 : nil } ?? localRealtime?.hrv ?? 0
            let existingStress = localRealtime?.stress_value ?? 0
            let resolvedStress = existingStress > 0
                ? existingStress
                : ((resolvedBpm > 0 || resolvedHrv > 0)
                    ? Self.estimateStress(
                        hrv: resolvedHrv,
                        heartRate: Double(resolvedBpm),
                        restingHeartRate: resting
                    )
                    : 0)
            let usesDerivedStress = existingStress <= 0 && resolvedStress > 0
            let resolvedTimestamp = existingStress > 0
                ? (localRealtime?.timestamp ?? Int64(now().timeIntervalSince1970))
                : Int64(now().timeIntervalSince1970)

            if resolvedBpm > 0 || resolvedHrv > 0 || resolvedStress > 0 {
                realtimeHealth = RealtimeHealth(
                    bpm: resolvedBpm,
                    hrv_sdnn: resolvedHrv,
                    stress_value: resolvedStress,
                    stress_level: usesDerivedStress
                        ? StressRules.state(for: resolvedStress).rawValue
                        : localRealtime?.stress_level,
                    stress_explanation_code: usesDerivedStress
                        ? StressExplanationCode.fallback.rawValue
                        : localRealtime?.stress_explanation_code,
                    stress_confidence: usesDerivedStress ? 0.34 : localRealtime?.stress_confidence,
                    stress_quality: usesDerivedStress
                        ? StressDataQuality.low.rawValue
                        : localRealtime?.stress_quality,
                    stress_algorithm_version: usesDerivedStress
                        ? StressResult.currentAlgorithmVersion
                        : localRealtime?.stress_algorithm_version,
                    // 页面已经从 HealthKit 生命体征算出低置信度压力时，不能继续沿用
                    // 上游快照的“无压力样本”原因，否则展示层会优先判定为不可用。
                    stress_unavailable_reason: usesDerivedStress
                        ? nil
                        : localRealtime?.stress_unavailable_reason,
                    daily_stress_value: localRealtime?.daily_stress_value,
                    daily_stress_quality: localRealtime?.daily_stress_quality,
                    daily_stress_algorithm_version: localRealtime?.daily_stress_algorithm_version,
                    timestamp: resolvedTimestamp,
                    hr_abnormal: localRealtime?.hr_abnormal,
                    hr_abnormal_type: localRealtime?.hr_abnormal_type
                )
                if let realtimeHealth, localRealtime != nil {
                    // 页面拼装的对象可能只有刚读取的生命体征，压力仍在 3.1 引擎中计算。
                    // 仅在已有公共实时快照时更新 Widget，且不把页面对象反写到 HealthDataManager。
                    persistForWidgets(realtimeHealth, syncToHealthDataManager: false)
                }
                Self.signalsLogger.info(
                    "[Today][Signals] operation=realtimeResolved source=\(usesDerivedStress ? "healthkit_fallback" : "canonical", privacy: .public) stressAvailable=\(resolvedStress > 0, privacy: .public)"
                )
            } else {
                realtimeHealth = nil
                Self.signalsLogger.notice(
                    "[Today][Signals] operation=realtimeResolved source=none stressAvailable=false"
                )
            }
        } else {
            realtimeHealth = makeHistoricalRealtime(from: hrvPoints, heartRate: heartRatePoints)
        }

        restingHeartRate = resting.flatMap { $0 > 0 ? $0 : nil }
        if let avgHrv, avgHrv > 0 {
            avgHrvToday = avgHrv
        } else if let realHrv, realHrv > 0 {
            avgHrvToday = realHrv
        } else {
            avgHrvToday = nil
        }
        recentAvgHrv = HealthBaselineStrategy.usableValue(for: recentHrvPoints.map(\.value), metric: .hrvSDNN)
        recentAvgRestingHeartRate = HealthBaselineStrategy.usableValue(for: recentRestingPoints.map(\.value), metric: .restingHeartRate)
        mergeHealthKitTodayHistory(hrvToday: hrvPoints, heartRateToday: heartRatePoints)
        refreshAssessmentFromCurrentState()

        // 压力链路先发布；下面较重的趋势、VO₂ 与运动负荷随后补齐其余卡片。
        let activityPoints = await activityPointsTask ?? []
        let walkingSpeedPoints = await walkingSpeedPointsTask ?? []
        let vo2Assessments = await vo2AssessmentsTask
        let physicalEffort = await physicalEffortTask
        let workoutEffort = await workoutEffortTask
        guard Calendar.current.isDate(selectedDate, inSameDayAs: loadDate) else { return }
        todayActivityPoints = activityPoints
        bodyBatteryLoadInput = StressBodyBatteryHealthKitAdapter.makeBodyBatteryLoadInput(
            physicalEffort: physicalEffort,
            workoutEffort: workoutEffort
        )
        todayWalkingSpeedMps = walkingSpeedPoints.last(where: { $0.value > 0 })?.value
        applyVO2Assessments(vo2Assessments, on: loadDate)
        refreshAssessmentFromCurrentState()
    }
}
