import SwiftUI

@MainActor
@Observable
class HabitViewModel {
    var waterAmount: Int = 0
    var caffeineAmount: Int = 0
    var waterTarget: Int = 2000
    var waterCompletionRate: Double = 0.0
    var isSubmitting: Bool = false
    var successMessage: String?

    var sleepDuration: Int = 0
    var activeEnergy: Int = 0
    var basalEnergy: Int = 0
    var stepCount: Int = 0
    var sleepScore: Int = 0
    var restingHr: Double = 0.0
    var exerciseMinutes: Int = 0
    var standHours: Int = 0
    var sunlightMinutes: Int = 0
    var mindfulnessMinutes: Int = 0
    var environmentalAudioExposureDb: Double = 0.0
    var sleepingWristTemperature: Double = 0.0
    var walkingAsymmetryPercentage: Double = 0.0
    var stateOfMindTitle: String = "未记录"
    var stateOfMindDetail: String = "暂未从健康 App 获取到心理状态"
    var stateOfMindIntensity: Int = 0
    var stateOfMindDate: Date?
    var suggestion: String = ""

    var lifeHabitRows: [HabitLifeRowModel] = []
    var bodyHabitHeroCardModel: HabitBodyHeroCardModel = .placeholder
    var bodyHabitMetricCards: [HabitBodyMetricCardModel] = []
    var selectedDateHRV: Double?
    var dailyActionCards: [HabitDailyActionCardModel] = []
    var wellnessActionCards: [DailyWellnessActionCardModel] = []
    var dailyWellnessSummary: DailyWellnessSummary = .empty()
    var longTermHabitSummary: LongTermHabitSummary = .empty()
    var microRecoveryState: DailyWellnessMicroRecoveryState = .idle
    var wellnessReminderEnabled: Bool = false
    var wellnessReminderTimeText: String = "20:30"
    var fitnessCalendarModel: HabitFitnessCalendarModel = HabitFitnessCalendarModel(
        scope: .week,
        rangeTitle: "",
        streakText: "等待同步",
        summaryPills: ["连续 0 天", "锻炼 0 分钟", "消耗 0 kcal"],
        days: []
    )
    var fitnessStatsCards: [HabitFitnessStatsCardModel] = []
    var selectedActionDayDetail: ActionDayDetailModel?
    var calendarScope: HabitCalendarScope = .week
    var selectedActionRecord: LocalActionDayRecord?

    var hydrationCompletionRate: Double {
        guard waterTarget > 0 else { return 0.0 }
        return min(1.0, Double(waterAmount) / Double(max(1, waterTarget)))
    }

    var hydrationHeadlineText: String {
        waterTarget > 0 ? "\(waterAmount) / \(waterTarget) ml" : "\(waterAmount) ml"
    }

    private var currentLoadID = UUID()
    var selectedDateContext = Date()
    var heartRateSeries: [TimeSeriesPoint] = []
    var heartRateDailyTrend: [TimeSeriesPointDouble] = []
    var activeEnergyTrend: [TimeSeriesPointDouble] = []
    var basalEnergyTrend: [TimeSeriesPointDouble] = []
    var standHoursTrend: [TimeSeriesPointDouble] = []
    var hrvTrend: [TimeSeriesPointDouble] = []
    var restingHeartRateTrend: [TimeSeriesPointDouble] = []
    var sunlightTrend: [TimeSeriesPointDouble] = []
    var wristTemperatureTrend: [TimeSeriesPointDouble] = []
    var walkingAsymmetryTrend: [TimeSeriesPointDouble] = []
    var exerciseMinutesTrend: [TimeSeriesPointDouble] = []
    var calendarWorkoutSummaries: [Date: WorkoutDaySummary] = [:]
    private var successMessageDismissTask: Task<Void, Never>?
    let actionRecordStore: ActionRecordStore
    let dailyWellnessStore: DailyWellnessStore
    let longTermHabitEngine: LongTermHabitEngine

    init(actionRecordStore: ActionRecordStore? = nil, dailyWellnessStore: DailyWellnessStore? = nil) {
        let resolvedDailyWellnessStore = dailyWellnessStore ?? .shared
        self.actionRecordStore = actionRecordStore ?? .shared
        self.dailyWellnessStore = resolvedDailyWellnessStore
        self.longTermHabitEngine = LongTermHabitEngine()
        let reminder = resolvedDailyWellnessStore.loadReminderSettings()
        self.wellnessReminderEnabled = reminder.isEnabled
        self.wellnessReminderTimeText = reminder.timeText
    }

    func loadData() {
        loadData(for: Date())
    }

    func loadData(for selectedDate: Date) {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: selectedDate)
        let isToday = calendar.isDateInToday(normalizedDate)
        let loadID = UUID()
        currentLoadID = loadID
        selectedDateContext = normalizedDate

        resetDisplayState()
        rebuildLifeHabitRows()
        rebuildBodyHabitModels()
        rebuildActionModels()
        suggestion = localSuggestion(for: normalizedDate)

        Task {
            let calendarRange = self.calendarFetchRange(anchoredAt: normalizedDate)
            let daylightStart = calendar.date(byAdding: .day, value: -6, to: normalizedDate) ?? normalizedDate

            // 全部 HealthKit 查询并发发起：HKHealthStore 支持并发查询，
            // 逐个串行 await 会让健康页首屏等待整条查询链才出数。
            async let waterIntakeFetch = HealthKitManager.shared.fetchDietaryWaterIntake(on: normalizedDate)
            async let caffeineIntakeFetch = HealthKitManager.shared.fetchDietaryCaffeine(on: normalizedDate)
            async let durationFetch = HealthKitManager.shared.fetchSleepDurationInMinutes(on: normalizedDate)
            async let energyFetch = HealthKitManager.shared.fetchActiveEnergyBurned(on: normalizedDate)
            async let basalFetch = HealthKitManager.shared.fetchBasalEnergyBurned(on: normalizedDate)
            async let stepsFetch = HealthKitManager.shared.fetchStepsCount(on: normalizedDate)
            async let hrFetch = HealthKitManager.shared.fetchRestingHeartRate(on: normalizedDate)
            async let exerciseFetch = HealthKitManager.shared.fetchExerciseTime(on: normalizedDate)
            async let standFetch = HealthKitManager.shared.fetchStandHours(on: normalizedDate)
            async let sunlightFetch = HealthKitManager.shared.fetchTimeInDaylightMinutes(on: normalizedDate)
            async let mindfulnessFetch = HealthKitManager.shared.fetchMindfulnessMinutes(on: normalizedDate)
            async let environmentalAudioFetch = HealthKitManager.shared.fetchEnvironmentalAudioExposure(on: normalizedDate)
            async let stateOfMindFetch = HealthKitManager.shared.fetchLatestStateOfMind(on: normalizedDate)
            async let heartSeriesFetch = HealthKitManager.shared.fetchHeartRateSeries(on: normalizedDate, maxPoints: 96)
            async let heartTrendFetch = HealthKitManager.shared.fetchDailyHeartRateAverages(days: 7, endDate: normalizedDate)
            async let restingTrendFetch = HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 30)
            async let basalTrendFetch = HealthKitManager.shared.fetchDailyBasalEnergySums(days: 7, endDate: normalizedDate)
            async let energyTrendFetch = HealthKitManager.shared.fetchDailyActiveEnergySums(days: 7, endDate: normalizedDate)
            async let standTrendFetch = HealthKitManager.shared.fetchDailyStandHours(days: 7, endDate: normalizedDate)
            async let exerciseTrendFetch = HealthKitManager.shared.fetchDailyExerciseTimeSums(days: 7, endDate: normalizedDate)
            async let hrvTrendFetch = HealthKitManager.shared.fetchDailyHRVAverages(days: 7, endDate: normalizedDate)
            async let daylightTrendFetch = HealthKitManager.shared.fetchTimeInDaylightSeries(
                start: daylightStart,
                end: normalizedDate,
                interval: DateComponents(day: 1)
            )
            async let wristTrendFetch = HealthKitManager.shared.fetchDailySleepingWristTemperatureAverages(days: 30)
            async let walkingAsymmetryTrendFetch = HealthKitManager.shared.fetchDailyWalkingAsymmetryAverages(days: 30)
            async let walkingAsymmetryFetch = HealthKitManager.shared.fetchWalkingAsymmetryPercentage(on: normalizedDate)
            async let selectedDayHrvFetch = HealthKitManager.shared.fetchDailyHRVAverages(days: 1, endDate: normalizedDate)
            async let calendarEnergyTrendFetch = HealthKitManager.shared.fetchDailyActiveEnergySums(
                days: calendarRange.days,
                endDate: calendarRange.endDate
            )
            async let calendarExerciseTrendFetch = HealthKitManager.shared.fetchDailyExerciseTimeSums(
                days: calendarRange.days,
                endDate: calendarRange.endDate
            )
            async let calendarStandTrendFetch = HealthKitManager.shared.fetchDailyStandHours(
                days: calendarRange.days,
                endDate: calendarRange.endDate
            )
            async let calendarHrvTrendFetch = HealthKitManager.shared.fetchDailyHRVAverages(
                days: calendarRange.days,
                endDate: calendarRange.endDate
            )
            async let workoutSummariesFetch = HealthKitManager.shared.fetchWorkoutDaySummaries(
                startDate: calendarRange.startDate,
                endDate: calendarRange.endDate
            )

            let waterIntake = (try? await waterIntakeFetch) ?? 0
            let caffeineIntake = (try? await caffeineIntakeFetch) ?? 0
            let duration = try? await durationFetch
            let energy = try? await energyFetch
            let basal = try? await basalFetch
            let steps = try? await stepsFetch
            let hr = try? await hrFetch
            let exercise = try? await exerciseFetch
            let stand = try? await standFetch
            let sunlight = try? await sunlightFetch
            let mindfulness = try? await mindfulnessFetch
            let environmentalAudio = try? await environmentalAudioFetch
            let stateOfMind = try? await stateOfMindFetch

            // 第一波提交：当日标量先上屏，首屏卡片不用等趋势 / 日历区间的重查询。
            await MainActor.run {
                guard self.currentLoadID == loadID else { return }
                self.waterAmount = waterIntake
                self.caffeineAmount = caffeineIntake
                self.waterCompletionRate = self.waterTarget > 0
                    ? min(1.0, Double(waterIntake) / Double(max(1, self.waterTarget)))
                    : 0.0
                self.activeEnergy = energy ?? 0
                self.basalEnergy = basal ?? 0
                self.stepCount = steps ?? 0
                self.restingHr = hr ?? 0.0
                self.sleepDuration = max(0, duration ?? 0)
                self.exerciseMinutes = exercise ?? 0
                self.standHours = stand ?? 0
                self.sunlightMinutes = max(0, sunlight ?? 0)
                self.mindfulnessMinutes = mindfulness ?? 0
                self.environmentalAudioExposureDb = environmentalAudio ?? 0.0
                self.stateOfMindTitle = stateOfMind?.title ?? "未记录"
                self.stateOfMindDetail = stateOfMind?.detail ?? "打开健康 App 记录心理状态后会显示在这里"
                self.stateOfMindIntensity = stateOfMind?.intensity ?? 0
                self.stateOfMindDate = stateOfMind?.date
                self.rebuildLifeHabitRows()
                self.rebuildBodyHabitModels()
                self.rebuildActionModels()

                if isToday {
                    let resolvedExerciseGoal = UserDefaults.standard.integer(forKey: "onboarding_goal_exerciseMinutes")
                    let resolvedStandGoal = UserDefaults.standard.integer(forKey: "onboarding_goal_standHours")
                    AppGroupManager.shared.saveActivitySummary(
                        steps: steps,
                        activeEnergy: energy,
                        exerciseMinutes: exercise,
                        standHours: stand,
                        exerciseMinutesGoal: resolvedExerciseGoal > 0 ? resolvedExerciseGoal : nil,
                        standHoursGoal: resolvedStandGoal > 0 ? resolvedStandGoal : nil
                    )
                    AppGroupManager.shared.saveSleepSummary(
                        durationMinutes: duration.flatMap { $0 > 0 ? $0 : nil },
                        score: self.sleepScore > 0 ? self.sleepScore : nil
                    )
                    AppGroupManager.shared.saveHabitSummary(
                        waterIntakeMl: Double(waterIntake),
                        waterTargetMl: self.waterTarget,
                        waterCompletionRate: self.waterCompletionRate,
                        caffeineRemainedMg: Double(caffeineIntake)
                    )
                    WidgetRefreshCoordinator.refresh([.overall, .activity, .activityConfigurable, .sleep], reason: .healthUpdate)
                }
            }

            // 第二波收集：趋势 / 序列 / 日历区间数据，到齐后统一补交。
            let heartSeries = (try? await heartSeriesFetch) ?? []
            let heartTrend = (try? await heartTrendFetch) ?? []
            let restingTrend = trimTrend(
                (try? await restingTrendFetch) ?? [],
                endingAt: normalizedDate,
                days: 7
            )
            let basalTrend = (try? await basalTrendFetch) ?? []
            let energyTrend = (try? await energyTrendFetch) ?? []
            let standTrend = (try? await standTrendFetch) ?? []
            let exerciseTrend = (try? await exerciseTrendFetch) ?? []
            let resolvedHrvTrend = (try? await hrvTrendFetch) ?? []
            let daylightTrend = (try? await daylightTrendFetch) ?? []
            let resolvedWristTrend = trimTrend(
                (try? await wristTrendFetch) ?? [],
                endingAt: normalizedDate,
                days: 7
            )
            let resolvedWalkingAsymmetryTrend = trimTrend(
                (try? await walkingAsymmetryTrendFetch) ?? [],
                endingAt: normalizedDate,
                days: 7
            )
            let walkingAsymmetry = try? await walkingAsymmetryFetch
            let selectedDayHrv = (try? await selectedDayHrvFetch)?.last?.value
            let calendarEnergyTrend = (try? await calendarEnergyTrendFetch) ?? []
            let calendarExerciseTrend = (try? await calendarExerciseTrendFetch) ?? []
            let calendarStandTrend = (try? await calendarStandTrendFetch) ?? []
            let calendarHrvTrend = (try? await calendarHrvTrendFetch) ?? []
            let workoutSummaries = (try? await workoutSummariesFetch) ?? []

            // 第二波提交：只补趋势 / 序列 / 日历区间衍生数据，标量已在第一波上屏。
            await MainActor.run {
                guard self.currentLoadID == loadID else { return }
                self.sleepingWristTemperature = resolvedWristTrend.last?.value ?? 0.0
                self.walkingAsymmetryPercentage = max(0, walkingAsymmetry ?? resolvedWalkingAsymmetryTrend.last?.value ?? 0.0)
                self.heartRateSeries = heartSeries
                self.heartRateDailyTrend = heartTrend
                self.basalEnergyTrend = basalTrend
                self.activeEnergyTrend = energyTrend
                self.standHoursTrend = standTrend
                self.exerciseMinutesTrend = exerciseTrend
                self.hrvTrend = resolvedHrvTrend
                self.restingHeartRateTrend = restingTrend
                self.sunlightTrend = daylightTrend
                self.wristTemperatureTrend = resolvedWristTrend
                self.walkingAsymmetryTrend = resolvedWalkingAsymmetryTrend
                self.selectedDateHRV = selectedDayHrv ?? nil
                self.calendarWorkoutSummaries = Dictionary(
                    uniqueKeysWithValues: workoutSummaries.map { (calendar.startOfDay(for: $0.date), $0) }
                )
                self.rebuildLifeHabitRows()
                self.rebuildBodyHabitModels()
                self.rebuildActionModels(
                    calendarEnergyTrend: calendarEnergyTrend,
                    calendarExerciseTrend: calendarExerciseTrend,
                    calendarStandTrend: calendarStandTrend,
                    calendarHrvTrend: calendarHrvTrend
                )
            }
        }
    }

    func recordHabit(type: String, amount: Int) {
        isSubmitting = true

        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0 else {
            isSubmitting = false
            showSuccessMessage("请输入有效数值")
            return
        }

        actionRecordStore.updateRecord(for: selectedDateContext) { record in
            switch normalizedType {
            case "water":
                record.waterMl += amount
                if !record.completedActions.contains(.water) {
                    record.completedActions.append(.water)
                }
            case "caffeine":
                record.caffeineMg += amount
            default:
                break
            }
        }
        if normalizedType == "caffeine" {
            actionRecordStore.recordCaffeineDose(amountMg: amount, source: .quickAdd)
        }

        isSubmitting = false
        let message: String
        switch normalizedType {
        case "water":
            message = "已写入健康 App \(amount) ml"
            let settings = HabitReminderManager.shared.load()
            HabitReminderManager.shared.scheduleWaterNudgeIfNeeded(settings: settings)
            Task { try? await HealthKitManager.shared.saveDietaryWater(milliliters: amount) }
        case "caffeine":
            message = "已写入健康 App \(amount) mg"
            Task {
                try? await HealthKitManager.shared.saveDietaryCaffeine(milligrams: amount)
                await PersonalizedReminderCenter.shared.evaluateAndReschedule()
            }
        default:
            message = "已记录 \(normalizedType) \(amount)"
        }

        showSuccessMessage(message)
        if normalizedType == "water" || normalizedType == "caffeine" {
            Task { @MainActor [weak self] in
                self?.loadData(for: self?.selectedDateContext ?? Date())
            }
        } else {
            applyLocalActionRecord(actionRecordStore.record(for: selectedDateContext))
            rebuildLifeHabitRows()
            rebuildActionModels()
            persistHabitSummaryToAppGroup()
            WidgetRefreshCoordinator.refresh([.overall], reason: .healthUpdate)
        }
    }

    func recordDrink(
        preset: DrinkPreset,
        amountMl: Int,
        completion: ((Bool) -> Void)? = nil
    ) {
        // 防重入：HealthKit 写入与本地汇总在 Task 内异步完成，连点会在 UI 禁用生效前重复提交。
        guard !isSubmitting else {
            completion?(false)
            return
        }
        let normalizedAmount = max(0, amountMl)
        guard normalizedAmount > 0 else {
            showSuccessMessage("请输入有效容量")
            completion?(false)
            return
        }

        let payload = preset.payload(for: normalizedAmount)
        guard payload.waterAmountMl > 0 || payload.caffeineAmountMg > 0 else {
            showSuccessMessage("这杯没有可记录内容")
            completion?(false)
            return
        }

        isSubmitting = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if payload.waterAmountMl > 0 {
                    try await HealthKitManager.shared.saveDietaryWater(milliliters: payload.waterAmountMl)
                }
                if payload.caffeineAmountMg > 0 {
                    try await HealthKitManager.shared.saveDietaryCaffeine(milligrams: payload.caffeineAmountMg)
                    self.actionRecordStore.recordCaffeineDose(
                        amountMg: payload.caffeineAmountMg,
                        source: .drinkCheckin,
                        note: preset.title
                    )
                    await PersonalizedReminderCenter.shared.evaluateAndReschedule()
                }

                self.waterAmount += payload.waterAmountMl
                self.caffeineAmount += payload.caffeineAmountMg
                self.waterCompletionRate = self.waterTarget > 0
                    ? min(1.0, Double(self.waterAmount) / Double(max(1, self.waterTarget)))
                    : 0.0
                self.actionRecordStore.updateRecord(for: self.selectedDateContext) { record in
                    if payload.waterAmountMl > 0 {
                        record.waterMl += payload.waterAmountMl
                        if !record.completedActions.contains(.water) {
                            record.completedActions.append(.water)
                        }
                    }
                    if payload.caffeineAmountMg > 0 {
                        record.caffeineMg += payload.caffeineAmountMg
                    }
                }
                self.persistHabitSummaryToAppGroup()

                self.isSubmitting = false
                self.showSuccessMessage("已写入健康 App \(normalizedAmount) ml")

                let settings = HabitReminderManager.shared.load()
                HabitReminderManager.shared.scheduleWaterNudgeIfNeeded(settings: settings)

                self.loadData(for: self.selectedDateContext)
                completion?(true)
            } catch {
                self.isSubmitting = false
                self.showSuccessMessage("写入健康 App 失败")
                completion?(false)
            }
        }
    }

    func showSuccessMessage(_ message: String, duration: Duration = .seconds(2)) {
        successMessageDismissTask?.cancel()
        successMessage = message
        successMessageDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            successMessage = nil
            successMessageDismissTask = nil
        }
    }
}
