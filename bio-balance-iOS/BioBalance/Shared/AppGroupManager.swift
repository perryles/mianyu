import Foundation

nonisolated public final class AppGroupManager: Sendable {
    public static let shared = AppGroupManager()
    nonisolated public static let suiteName = AppGroupSchema.appGroupIdentifier

    nonisolated static func userDefaults() -> UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
    public enum Keys {
        public static let latestHeartRate = AppGroupSchema.Keys.latestHeartRate
        public static let latestHRV = AppGroupSchema.Keys.latestHRV
        public static let lastSyncTime = AppGroupSchema.Keys.lastSyncTime
        public static let latestStress = AppGroupSchema.Keys.latestStress
        public static let stressTrend = AppGroupSchema.Keys.stressTrend
        public static let stressHistoryData = AppGroupSchema.Keys.stressHistoryData
        public static let healthSummary = AppGroupSchema.Keys.healthSummary
        public static let waterIntakeMl = AppGroupSchema.Keys.waterIntakeMl
        public static let waterTargetMl = AppGroupSchema.Keys.waterTargetMl
        public static let waterCompletionRate = AppGroupSchema.Keys.waterCompletionRate
        public static let caffeineRemainedMg = AppGroupSchema.Keys.caffeineRemainedMg
        public static let steps = AppGroupSchema.Keys.steps
        public static let activeEnergy = AppGroupSchema.Keys.activeEnergy
        public static let exerciseMinutes = AppGroupSchema.Keys.exerciseMinutes
        public static let standHours = AppGroupSchema.Keys.standHours
        public static let sleepDurationMinutes = AppGroupSchema.Keys.sleepDurationMinutes
        public static let sleepScore = AppGroupSchema.Keys.sleepScore
        public static let sleepMonitoringState = AppGroupSchema.Keys.sleepMonitoringState
        public static let sleepLatestSummary = AppGroupSchema.Keys.sleepLatestSummary
        public static let sleepSnoreDurationMinutes = AppGroupSchema.Keys.sleepSnoreDurationMinutes
        public static let sleepSnoreIntensity = AppGroupSchema.Keys.sleepSnoreIntensity
        public static let sleepInsightHeadline = AppGroupSchema.Keys.sleepInsightHeadline
        public static let sleepWatchConfidence = AppGroupSchema.Keys.sleepWatchConfidence
        public static let lateNightRecoveryPrompt = AppGroupSchema.Keys.lateNightRecoveryPrompt
        public static let lateNightRecoverySeverity = AppGroupSchema.Keys.lateNightRecoverySeverity
        public static let sleepEnvironmentCompletionRate = AppGroupSchema.Keys.sleepEnvironmentCompletionRate
        public static let sleepEnvironmentPrompt = AppGroupSchema.Keys.sleepEnvironmentPrompt
        public static let stepsGoal = AppGroupSchema.Keys.stepsGoal
        public static let activeEnergyGoal = AppGroupSchema.Keys.activeEnergyGoal
        public static let exerciseMinutesGoal = AppGroupSchema.Keys.exerciseMinutesGoal
        public static let standHoursGoal = AppGroupSchema.Keys.standHoursGoal
        public static let sleepGoalMinutes = AppGroupSchema.Keys.sleepGoalMinutes
        public static let stepsCompletionRate = AppGroupSchema.Keys.stepsCompletionRate
        public static let activeEnergyCompletionRate = AppGroupSchema.Keys.activeEnergyCompletionRate
        public static let exerciseMinutesCompletionRate = AppGroupSchema.Keys.exerciseMinutesCompletionRate
        public static let standHoursCompletionRate = AppGroupSchema.Keys.standHoursCompletionRate
        public static let sleepDurationCompletionRate = AppGroupSchema.Keys.sleepDurationCompletionRate
        public static let activityCompletionRate = AppGroupSchema.Keys.activityCompletionRate
        public static let walkingSpeedMps = AppGroupSchema.Keys.walkingSpeedMps
        public static let walkingPaceSecondsPerKm = AppGroupSchema.Keys.walkingPaceSecondsPerKm
        public static let sunlightMinutesToday = AppGroupSchema.Keys.sunlightMinutesToday
        public static let sunlightGoalMinutes = AppGroupSchema.Keys.sunlightGoalMinutes
        public static let sunlightCompletionRate = AppGroupSchema.Keys.sunlightCompletionRate
        public static let sunlightUpdatedAt = AppGroupSchema.Keys.sunlightUpdatedAt
        public static let sedentaryElapsedMinutes = AppGroupSchema.Keys.sedentaryElapsedMinutes
        public static let sedentaryIsCounting = AppGroupSchema.Keys.sedentaryIsCounting
        public static let sedentaryPausedBySleep = AppGroupSchema.Keys.sedentaryPausedBySleep
        public static let sedentarySeatedStartAt = AppGroupSchema.Keys.sedentarySeatedStartAt
        public static let sedentaryLastActivityAt = AppGroupSchema.Keys.sedentaryLastActivityAt
        public static let sedentaryUpdatedAt = AppGroupSchema.Keys.sedentaryUpdatedAt
        public static let sedentaryBreakIsActive = AppGroupSchema.Keys.sedentaryBreakIsActive
        public static let sedentaryBreakDurationMinutes = AppGroupSchema.Keys.sedentaryBreakDurationMinutes
        public static let sedentaryBreakStartedAt = AppGroupSchema.Keys.sedentaryBreakStartedAt
        public static let periodPhase = AppGroupSchema.Keys.periodPhase
        public static let periodCycleDay = AppGroupSchema.Keys.periodCycleDay
        public static let periodIsFertile = AppGroupSchema.Keys.periodIsFertile
        public static let periodNextStart = AppGroupSchema.Keys.periodNextStart
        public static let periodFertileStart = AppGroupSchema.Keys.periodFertileStart
        public static let periodFertileEnd = AppGroupSchema.Keys.periodFertileEnd
        public static let periodPredictionSource = AppGroupSchema.Keys.periodPredictionSource
        public static let defaultComplicationTemplate = AppGroupSchema.Keys.defaultComplicationTemplate
        public static let defaultComplicationTemplateUpdatedAt = AppGroupSchema.Keys.defaultComplicationTemplateUpdatedAt
        public static let watchThemeId = AppGroupSchema.Keys.watchThemeId
        public static let watchMascotEnabled = AppGroupSchema.Keys.watchMascotEnabled
        public static let watchMascotMessage = AppGroupSchema.Keys.watchMascotMessage
        public static let watchCustomThemeId = AppGroupSchema.Keys.watchCustomThemeId
        public static let bodyAgeValueYears = AppGroupSchema.Keys.bodyAgeValueYears
        public static let bodyAgeStatusText = AppGroupSchema.Keys.bodyAgeStatusText
        public static let bodyAgeComparisonText = AppGroupSchema.Keys.bodyAgeComparisonText
        public static let bodyAgeSuggestionText = AppGroupSchema.Keys.bodyAgeSuggestionText
        public static let bodyAgeCoverageText = AppGroupSchema.Keys.bodyAgeCoverageText
        public static let bodyAgeDirectionText = AppGroupSchema.Keys.bodyAgeDirectionText
        public static let vo2MaxValue = AppGroupSchema.Keys.vo2MaxValue
        public static let vo2MaxConfidence = AppGroupSchema.Keys.vo2MaxConfidence
        public static let vo2MaxTrend = AppGroupSchema.Keys.vo2MaxTrend
        public static let vo2MaxFitnessLevel = AppGroupSchema.Keys.vo2MaxFitnessLevel
        public static let vo2MaxSource = AppGroupSchema.Keys.vo2MaxSource
        public static let vo2MaxDriverSummary = AppGroupSchema.Keys.vo2MaxDriverSummary
        public static let appFontScaleLevel = AppGroupSchema.Keys.appFontScaleLevel
    }
    
    private var sharedDefaults: UserDefaults? { Self.userDefaults() }
    
    private init() {}
    
    public func save<T>(value: T, forKey key: String) {
        sharedDefaults?.set(value, forKey: key)
    }
    
    public func set<T>(value: T?, forKey key: String) {
        if let value {
            sharedDefaults?.set(value, forKey: key)
        } else {
            sharedDefaults?.removeObject(forKey: key)
        }
    }
    
    public func saveHeartRate(_ value: Double?) {
        guard let value, value > 0 else {
            set(value: nil as Double?, forKey: Keys.latestHeartRate)
            return
        }
        save(value: value, forKey: Keys.latestHeartRate)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }
    
    public func saveHRV(_ value: Double?) {
        guard let value, value > 0 else {
            set(value: nil as Double?, forKey: Keys.latestHRV)
            return
        }
        save(value: value, forKey: Keys.latestHRV)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }
    
    public func saveStress(_ value: Double?, trend: String?) {
        guard let value, value >= 0 else {
            set(value: nil as Double?, forKey: Keys.latestStress)
            set(value: nil as String?, forKey: Keys.stressTrend)
            return
        }
        save(value: value, forKey: Keys.latestStress)
        if let trend {
            save(value: trend, forKey: Keys.stressTrend)
        } else {
            set(value: nil as String?, forKey: Keys.stressTrend)
        }
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveStressHistory(_ points: [WatchStressHistoryPoint]) {
        let sanitized = points
            .filter { $0.value > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        if sanitized.isEmpty {
            set(value: nil as Data?, forKey: Keys.stressHistoryData)
            return
        }
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        save(value: data, forKey: Keys.stressHistoryData)
    }
    
    public func saveHealthSummary(_ summary: String) {
        save(value: summary, forKey: Keys.healthSummary)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveHabitSummary(waterIntakeMl: Double, waterTargetMl: Int?, waterCompletionRate: Double?, caffeineRemainedMg: Double) {
        save(value: waterIntakeMl, forKey: Keys.waterIntakeMl)
        if let waterTargetMl {
            save(value: waterTargetMl, forKey: Keys.waterTargetMl)
        }
        if let waterCompletionRate {
            save(value: waterCompletionRate, forKey: Keys.waterCompletionRate)
        }
        save(value: caffeineRemainedMg, forKey: Keys.caffeineRemainedMg)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveSunlightSummary(minutesToday: Int?, goalMinutes: Int = 20) {
        let now = Date()
        let effectiveMinutes = max(0, minutesToday ?? 0)
        let completion = goalMinutes > 0 ? min(1.0, Double(effectiveMinutes) / Double(goalMinutes)) : nil

        set(value: minutesToday, forKey: Keys.sunlightMinutesToday)
        set(value: goalMinutes, forKey: Keys.sunlightGoalMinutes)
        set(value: minutesToday == nil ? nil : completion, forKey: Keys.sunlightCompletionRate)
        if minutesToday == nil {
            set(value: nil as TimeInterval?, forKey: Keys.sunlightUpdatedAt)
        } else {
            save(value: now.timeIntervalSince1970, forKey: Keys.sunlightUpdatedAt)
        }
        save(value: now.timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }
    
    public func saveActivitySummary(
        steps: Int?,
        activeEnergy: Int?,
        exerciseMinutes: Int?,
        standHours: Int?,
        stepsGoal: Int? = nil,
        activeEnergyGoal: Int? = nil,
        exerciseMinutesGoal: Int? = nil,
        standHoursGoal: Int? = nil
    ) {
        set(value: steps, forKey: Keys.steps)
        set(value: activeEnergy, forKey: Keys.activeEnergy)
        set(value: exerciseMinutes, forKey: Keys.exerciseMinutes)
        set(value: standHours, forKey: Keys.standHours)
        
        let resolvedStepsGoal = stepsGoal ?? 8000
        let resolvedActiveEnergyGoal = activeEnergyGoal ?? 500
        let resolvedExerciseMinutesGoal = exerciseMinutesGoal ?? 30
        let resolvedStandHoursGoal = standHoursGoal ?? 12
        
        set(value: resolvedStepsGoal, forKey: Keys.stepsGoal)
        set(value: resolvedActiveEnergyGoal, forKey: Keys.activeEnergyGoal)
        set(value: resolvedExerciseMinutesGoal, forKey: Keys.exerciseMinutesGoal)
        set(value: resolvedStandHoursGoal, forKey: Keys.standHoursGoal)
        
        let stepsRate = completionRate(value: steps, goal: resolvedStepsGoal)
        let energyRate = completionRate(value: activeEnergy, goal: resolvedActiveEnergyGoal)
        let exerciseRate = completionRate(value: exerciseMinutes, goal: resolvedExerciseMinutesGoal)
        let standRate = completionRate(value: standHours, goal: resolvedStandHoursGoal)
        
        set(value: stepsRate, forKey: Keys.stepsCompletionRate)
        set(value: energyRate, forKey: Keys.activeEnergyCompletionRate)
        set(value: exerciseRate, forKey: Keys.exerciseMinutesCompletionRate)
        set(value: standRate, forKey: Keys.standHoursCompletionRate)
        
        let parts = [stepsRate, energyRate, exerciseRate, standRate].compactMap { $0 }
        set(value: parts.isEmpty ? nil : min(1.0, parts.reduce(0.0, +) / Double(parts.count)), forKey: Keys.activityCompletionRate)
        
        if steps != nil || activeEnergy != nil || exerciseMinutes != nil || standHours != nil {
            save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
        }
    }

    public func saveWalkingMobilitySummary(speedMps: Double?, paceSecondsPerKm: Int?) {
        set(value: speedMps, forKey: Keys.walkingSpeedMps)
        set(value: paceSecondsPerKm, forKey: Keys.walkingPaceSecondsPerKm)
        if speedMps != nil || paceSecondsPerKm != nil {
            save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
        }
    }
    
    public func saveSleepSummary(durationMinutes: Int?, score: Int?, goalMinutes: Int? = nil) {
        set(value: durationMinutes, forKey: Keys.sleepDurationMinutes)
        set(value: score, forKey: Keys.sleepScore)
        
        let resolvedGoalMinutes: Int
        if let goalMinutes {
            resolvedGoalMinutes = goalMinutes
        } else {
            let hours = UserDefaults.standard.double(forKey: "sleepGoalHours")
            resolvedGoalMinutes = Int((hours > 0 ? hours : 8.0) * 60.0)
        }
        set(value: resolvedGoalMinutes, forKey: Keys.sleepGoalMinutes)
        set(value: completionRate(value: durationMinutes, goal: resolvedGoalMinutes), forKey: Keys.sleepDurationCompletionRate)
        
        if durationMinutes != nil || score != nil {
            save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
        }
    }

    public func saveSleepGuidance(
        lateNightRecoveryPrompt: String?,
        lateNightRecoverySeverity: String?,
        environmentCompletionRate: Double?,
        environmentPrompt: String?
    ) {
        set(value: lateNightRecoveryPrompt, forKey: Keys.lateNightRecoveryPrompt)
        set(value: lateNightRecoverySeverity, forKey: Keys.lateNightRecoverySeverity)
        set(value: environmentCompletionRate.map { min(1.0, max(0.0, $0)) }, forKey: Keys.sleepEnvironmentCompletionRate)
        set(value: environmentPrompt, forKey: Keys.sleepEnvironmentPrompt)

        if lateNightRecoveryPrompt != nil || environmentCompletionRate != nil || environmentPrompt != nil {
            save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
        }
    }

    func saveSleepMonitoringState(_ state: SleepMonitoringState?) {
        guard let state else {
            set(value: nil as Data?, forKey: Keys.sleepMonitoringState)
            return
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        save(value: data, forKey: Keys.sleepMonitoringState)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    func saveSleepLatestSummary(_ summary: SleepSessionSummary?) {
        guard let summary else {
            set(value: nil as Data?, forKey: Keys.sleepLatestSummary)
            set(value: nil as Double?, forKey: Keys.sleepSnoreDurationMinutes)
            set(value: nil as String?, forKey: Keys.sleepSnoreIntensity)
            set(value: nil as String?, forKey: Keys.sleepInsightHeadline)
            set(value: nil as Double?, forKey: Keys.sleepWatchConfidence)
            return
        }
        guard let data = try? JSONEncoder().encode(summary) else { return }
        save(value: data, forKey: Keys.sleepLatestSummary)
        set(value: summary.snoreSummary.snoreDurationMinutes, forKey: Keys.sleepSnoreDurationMinutes)
        set(value: summary.snoreSummary.intensity.rawValue, forKey: Keys.sleepSnoreIntensity)
        set(value: summary.insight.headline, forKey: Keys.sleepInsightHeadline)
        set(value: summary.watchConfidence, forKey: Keys.sleepWatchConfidence)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveSedentaryState(
        elapsedMinutes: Int,
        isCounting: Bool,
        pausedBySleep: Bool = false,
        seatedStartAt: Date?,
        lastActivityAt: Date?,
        updatedAt: Date? = nil
    ) {
        save(value: max(0, elapsedMinutes), forKey: Keys.sedentaryElapsedMinutes)
        save(value: isCounting, forKey: Keys.sedentaryIsCounting)
        save(value: pausedBySleep, forKey: Keys.sedentaryPausedBySleep)
        set(value: seatedStartAt?.timeIntervalSince1970, forKey: Keys.sedentarySeatedStartAt)
        set(value: lastActivityAt?.timeIntervalSince1970, forKey: Keys.sedentaryLastActivityAt)
        save(value: (updatedAt ?? Date()).timeIntervalSince1970, forKey: Keys.sedentaryUpdatedAt)
    }

    public func saveSedentaryBreakState(
        isActive: Bool,
        durationMinutes: Int?,
        startedAt: Date?
    ) {
        save(value: isActive, forKey: Keys.sedentaryBreakIsActive)
        set(value: durationMinutes, forKey: Keys.sedentaryBreakDurationMinutes)
        set(value: startedAt?.timeIntervalSince1970, forKey: Keys.sedentaryBreakStartedAt)
    }

    public func savePeriodSummary(
        phase: String?,
        cycleDay: Int?,
        isFertile: Bool?,
        nextPeriodStart: String?,
        fertileStart: String?,
        fertileEnd: String?,
        predictionSource: String?
    ) {
        set(value: phase, forKey: Keys.periodPhase)
        set(value: cycleDay, forKey: Keys.periodCycleDay)
        set(value: isFertile, forKey: Keys.periodIsFertile)
        set(value: nextPeriodStart, forKey: Keys.periodNextStart)
        set(value: fertileStart, forKey: Keys.periodFertileStart)
        set(value: fertileEnd, forKey: Keys.periodFertileEnd)
        set(value: predictionSource, forKey: Keys.periodPredictionSource)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveDefaultComplicationTemplate(_ template: String) {
        save(value: template, forKey: Keys.defaultComplicationTemplate)
        save(value: Date().timeIntervalSince1970, forKey: Keys.defaultComplicationTemplateUpdatedAt)
    }

    public func saveWatchThemeId(_ themeId: String) {
        save(value: themeId, forKey: Keys.watchThemeId)
    }

    /// 保存当前使用中的自定义主题 id；nil 表示恢复官方主题。
    public func saveWatchCustomThemeId(_ themeId: String?) {
        if let themeId {
            save(value: themeId, forKey: Keys.watchCustomThemeId)
        } else {
            sharedDefaults?.removeObject(forKey: Keys.watchCustomThemeId)
        }
    }

    public func saveWatchMascotConfiguration(isEnabled: Bool, message: String?) {
        save(value: isEnabled, forKey: Keys.watchMascotEnabled)
        set(value: WatchMascotContentPolicy.normalize(message), forKey: Keys.watchMascotMessage)
    }

    public func saveBodyAgeSummary(
        valueYears: Double?,
        statusText: String?,
        comparisonText: String?,
        suggestionText: String?,
        coverageText: String?,
        directionText: String?
    ) {
        set(value: valueYears, forKey: Keys.bodyAgeValueYears)
        set(value: statusText, forKey: Keys.bodyAgeStatusText)
        set(value: comparisonText, forKey: Keys.bodyAgeComparisonText)
        set(value: suggestionText, forKey: Keys.bodyAgeSuggestionText)
        set(value: coverageText, forKey: Keys.bodyAgeCoverageText)
        set(value: directionText, forKey: Keys.bodyAgeDirectionText)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveVO2Summary(
        value: Double?,
        confidence: Int?,
        trend: String?,
        fitnessLevel: String?,
        source: String?,
        driverSummary: String?
    ) {
        set(value: value, forKey: Keys.vo2MaxValue)
        set(value: confidence, forKey: Keys.vo2MaxConfidence)
        set(value: trend, forKey: Keys.vo2MaxTrend)
        set(value: fitnessLevel, forKey: Keys.vo2MaxFitnessLevel)
        set(value: source, forKey: Keys.vo2MaxSource)
        set(value: driverSummary, forKey: Keys.vo2MaxDriverSummary)
        save(value: Date().timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }

    public func saveAppFontScaleLevel(_ rawValue: Int) {
        save(value: rawValue, forKey: Keys.appFontScaleLevel)
    }

    public func saveLastSyncTime(_ date: Date) {
        save(value: date.timeIntervalSince1970, forKey: Keys.lastSyncTime)
    }
    
    public func getValue<T>(forKey key: String) -> T? {
        sharedDefaults?.value(forKey: key) as? T
    }
    
    public func getLatestHeartRate() -> Double? {
        getValue(forKey: Keys.latestHeartRate)
    }
    
    public func getLatestHRV() -> Double? {
        getValue(forKey: Keys.latestHRV)
    }
    
    public func getLatestStress() -> Double? {
        getValue(forKey: Keys.latestStress)
    }
    
    public func getStressTrend() -> String? {
        getValue(forKey: Keys.stressTrend)
    }

    public func getStressHistory() -> [WatchStressHistoryPoint] {
        guard let data: Data = getValue(forKey: Keys.stressHistoryData),
              let points = try? JSONDecoder().decode([WatchStressHistoryPoint].self, from: data) else {
            return []
        }
        return points.sorted { $0.timestamp < $1.timestamp }
    }
    
    public func getHealthSummary() -> String? {
        getValue(forKey: Keys.healthSummary)
    }

    public func getWaterIntakeMl() -> Double? {
        getValue(forKey: Keys.waterIntakeMl)
    }

    public func getWaterTargetMl() -> Int? {
        getValue(forKey: Keys.waterTargetMl)
    }

    public func getWaterCompletionRate() -> Double? {
        getValue(forKey: Keys.waterCompletionRate)
    }

    public func getCaffeineRemainedMg() -> Double? {
        getValue(forKey: Keys.caffeineRemainedMg)
    }
    
    public func getSteps() -> Int? {
        getValue(forKey: Keys.steps)
    }
    
    public func getActiveEnergy() -> Int? {
        getValue(forKey: Keys.activeEnergy)
    }

    public func getStepsGoal() -> Int? {
        getValue(forKey: Keys.stepsGoal)
    }

    public func getActiveEnergyGoal() -> Int? {
        getValue(forKey: Keys.activeEnergyGoal)
    }
    
    public func getExerciseMinutes() -> Int? {
        getValue(forKey: Keys.exerciseMinutes)
    }

    public func getExerciseMinutesGoal() -> Int? {
        getValue(forKey: Keys.exerciseMinutesGoal)
    }
    
    public func getStandHours() -> Int? {
        getValue(forKey: Keys.standHours)
    }

    public func getStandHoursGoal() -> Int? {
        getValue(forKey: Keys.standHoursGoal)
    }
    
    public func getSleepDurationMinutes() -> Int? {
        getValue(forKey: Keys.sleepDurationMinutes)
    }
    
    public func getSleepScore() -> Int? {
        getValue(forKey: Keys.sleepScore)
    }

    func getSleepMonitoringState() -> SleepMonitoringState? {
        guard let data: Data = getValue(forKey: Keys.sleepMonitoringState) else { return nil }
        return try? JSONDecoder().decode(SleepMonitoringState.self, from: data)
    }

    func getSleepLatestSummary() -> SleepSessionSummary? {
        guard let data: Data = getValue(forKey: Keys.sleepLatestSummary) else { return nil }
        return try? JSONDecoder().decode(SleepSessionSummary.self, from: data)
    }

    public func getSleepSnoreDurationMinutes() -> Double? {
        getValue(forKey: Keys.sleepSnoreDurationMinutes)
    }

    public func getSleepSnoreIntensity() -> String? {
        getValue(forKey: Keys.sleepSnoreIntensity)
    }

    public func getSleepInsightHeadline() -> String? {
        getValue(forKey: Keys.sleepInsightHeadline)
    }

    public func getSleepWatchConfidence() -> Double? {
        getValue(forKey: Keys.sleepWatchConfidence)
    }

    public func getLateNightRecoveryPrompt() -> String? {
        getValue(forKey: Keys.lateNightRecoveryPrompt)
    }

    public func getLateNightRecoverySeverity() -> String? {
        getValue(forKey: Keys.lateNightRecoverySeverity)
    }

    public func getSleepEnvironmentCompletionRate() -> Double? {
        getValue(forKey: Keys.sleepEnvironmentCompletionRate)
    }

    public func getSleepEnvironmentPrompt() -> String? {
        getValue(forKey: Keys.sleepEnvironmentPrompt)
    }
    
    public func getStepsCompletionRate() -> Double? {
        getValue(forKey: Keys.stepsCompletionRate)
    }
    
    public func getActiveEnergyCompletionRate() -> Double? {
        getValue(forKey: Keys.activeEnergyCompletionRate)
    }
    
    public func getExerciseMinutesCompletionRate() -> Double? {
        getValue(forKey: Keys.exerciseMinutesCompletionRate)
    }
    
    public func getStandHoursCompletionRate() -> Double? {
        getValue(forKey: Keys.standHoursCompletionRate)
    }
    
    public func getSleepDurationCompletionRate() -> Double? {
        getValue(forKey: Keys.sleepDurationCompletionRate)
    }
    
    public func getActivityCompletionRate() -> Double? {
        getValue(forKey: Keys.activityCompletionRate)
    }

    public func getWalkingSpeedMps() -> Double? {
        getValue(forKey: Keys.walkingSpeedMps)
    }

    public func getWalkingPaceSecondsPerKm() -> Int? {
        getValue(forKey: Keys.walkingPaceSecondsPerKm)
    }

    public func getSunlightMinutesToday() -> Int? {
        getValue(forKey: Keys.sunlightMinutesToday)
    }

    public func getSunlightGoalMinutes() -> Int? {
        getValue(forKey: Keys.sunlightGoalMinutes)
    }

    public func getSunlightCompletionRate() -> Double? {
        getValue(forKey: Keys.sunlightCompletionRate)
    }

    public func getSunlightUpdatedAt() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.sunlightUpdatedAt) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func getSedentaryElapsedMinutes() -> Int? {
        getValue(forKey: Keys.sedentaryElapsedMinutes)
    }

    public func getSedentaryIsCounting() -> Bool? {
        getValue(forKey: Keys.sedentaryIsCounting)
    }

    public func getSedentaryPausedBySleep() -> Bool? {
        getValue(forKey: Keys.sedentaryPausedBySleep)
    }

    public func getSedentarySeatedStartAt() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.sedentarySeatedStartAt) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func getSedentaryLastActivityAt() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.sedentaryLastActivityAt) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func getSedentaryUpdatedAt() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.sedentaryUpdatedAt) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func getSedentaryBreakIsActive() -> Bool? {
        getValue(forKey: Keys.sedentaryBreakIsActive)
    }

    public func getSedentaryBreakDurationMinutes() -> Int? {
        getValue(forKey: Keys.sedentaryBreakDurationMinutes)
    }

    public func getSedentaryBreakStartedAt() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.sedentaryBreakStartedAt) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func getPeriodPhase() -> String? {
        getValue(forKey: Keys.periodPhase)
    }

    public func getPeriodCycleDay() -> Int? {
        getValue(forKey: Keys.periodCycleDay)
    }

    public func getPeriodIsFertile() -> Bool? {
        getValue(forKey: Keys.periodIsFertile)
    }

    public func getPeriodNextStart() -> String? {
        getValue(forKey: Keys.periodNextStart)
    }

    public func getPeriodFertileStart() -> String? {
        getValue(forKey: Keys.periodFertileStart)
    }

    public func getPeriodFertileEnd() -> String? {
        getValue(forKey: Keys.periodFertileEnd)
    }

    public func getPeriodPredictionSource() -> String? {
        getValue(forKey: Keys.periodPredictionSource)
    }

    public func getDefaultComplicationTemplate() -> String? {
        getValue(forKey: Keys.defaultComplicationTemplate)
    }

    public func getWatchThemeId() -> String? {
        getValue(forKey: Keys.watchThemeId)
    }

    public func getWatchCustomThemeId() -> String? {
        getValue(forKey: Keys.watchCustomThemeId)
    }

    public func getWatchMascotEnabled() -> Bool? {
        getValue(forKey: Keys.watchMascotEnabled)
    }

    public func getWatchMascotMessage() -> String? {
        getValue(forKey: Keys.watchMascotMessage)
    }

    public func getBodyAgeValueYears() -> Double? {
        getValue(forKey: Keys.bodyAgeValueYears)
    }

    public func getBodyAgeStatusText() -> String? {
        getValue(forKey: Keys.bodyAgeStatusText)
    }

    public func getBodyAgeComparisonText() -> String? {
        getValue(forKey: Keys.bodyAgeComparisonText)
    }

    public func getBodyAgeSuggestionText() -> String? {
        getValue(forKey: Keys.bodyAgeSuggestionText)
    }

    public func getBodyAgeCoverageText() -> String? {
        getValue(forKey: Keys.bodyAgeCoverageText)
    }

    public func getBodyAgeDirectionText() -> String? {
        getValue(forKey: Keys.bodyAgeDirectionText)
    }

    public func getVO2MaxValue() -> Double? {
        getValue(forKey: Keys.vo2MaxValue)
    }

    public func getVO2MaxConfidence() -> Int? {
        getValue(forKey: Keys.vo2MaxConfidence)
    }

    public func getVO2MaxTrend() -> String? {
        getValue(forKey: Keys.vo2MaxTrend)
    }

    public func getVO2MaxFitnessLevel() -> String? {
        getValue(forKey: Keys.vo2MaxFitnessLevel)
    }

    public func getVO2MaxSource() -> String? {
        getValue(forKey: Keys.vo2MaxSource)
    }

    public func getVO2MaxDriverSummary() -> String? {
        getValue(forKey: Keys.vo2MaxDriverSummary)
    }

    public func getDefaultComplicationTemplateUpdatedAt() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.defaultComplicationTemplateUpdatedAt) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func getAppFontScaleLevelRawValue() -> Int? {
        getValue(forKey: Keys.appFontScaleLevel)
    }
    
    public func getLastSyncTime() -> Date? {
        guard let timestamp: TimeInterval = getValue(forKey: Keys.lastSyncTime) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    public static let pageCacheKeys: [String] = [
            Keys.latestHeartRate,
            Keys.latestHRV,
            Keys.lastSyncTime,
            Keys.latestStress,
            Keys.stressTrend,
            Keys.stressHistoryData,
            Keys.healthSummary,
            Keys.waterIntakeMl,
            Keys.waterCompletionRate,
            Keys.caffeineRemainedMg,
            Keys.steps,
            Keys.activeEnergy,
            Keys.exerciseMinutes,
            Keys.standHours,
            Keys.sleepDurationMinutes,
            Keys.sleepScore,
            Keys.sleepMonitoringState,
            Keys.sleepLatestSummary,
            Keys.sleepSnoreDurationMinutes,
            Keys.sleepSnoreIntensity,
            Keys.sleepInsightHeadline,
            Keys.sleepWatchConfidence,
            Keys.lateNightRecoveryPrompt,
            Keys.lateNightRecoverySeverity,
            Keys.sleepEnvironmentCompletionRate,
            Keys.sleepEnvironmentPrompt,
            Keys.walkingSpeedMps,
            Keys.walkingPaceSecondsPerKm,
            Keys.sunlightMinutesToday,
            Keys.sunlightCompletionRate,
            Keys.sunlightUpdatedAt,
            Keys.stepsCompletionRate,
            Keys.activeEnergyCompletionRate,
            Keys.exerciseMinutesCompletionRate,
            Keys.standHoursCompletionRate,
            Keys.sleepDurationCompletionRate,
            Keys.activityCompletionRate,
            Keys.sedentaryElapsedMinutes,
            Keys.sedentaryIsCounting,
            Keys.sedentaryPausedBySleep,
            Keys.sedentarySeatedStartAt,
            Keys.sedentaryLastActivityAt,
            Keys.sedentaryUpdatedAt,
            Keys.sedentaryBreakIsActive,
            Keys.sedentaryBreakDurationMinutes,
            Keys.sedentaryBreakStartedAt,
            Keys.periodPhase,
            Keys.periodCycleDay,
            Keys.periodIsFertile,
            Keys.periodNextStart,
            Keys.periodFertileStart,
            Keys.periodFertileEnd,
            Keys.periodPredictionSource,
            Keys.watchThemeId,
            Keys.watchMascotEnabled,
            Keys.watchMascotMessage,
            Keys.watchCustomThemeId,
            Keys.bodyAgeValueYears,
            Keys.bodyAgeStatusText,
            Keys.bodyAgeComparisonText,
            Keys.bodyAgeSuggestionText,
            Keys.bodyAgeCoverageText,
            Keys.bodyAgeDirectionText,
            Keys.vo2MaxValue,
            Keys.vo2MaxConfidence,
            Keys.vo2MaxTrend,
            Keys.vo2MaxFitnessLevel,
            Keys.vo2MaxSource,
            Keys.vo2MaxDriverSummary
    ]

    public func clearPageCacheEntries() {
        Self.pageCacheKeys.forEach { sharedDefaults?.removeObject(forKey: $0) }
        if let sharedDefaults {
            AppGroupSnapshotStore.clear(defaults: sharedDefaults)
        }
    }
    
    private func completionRate<T: BinaryInteger>(value: T?, goal: Int) -> Double? {
        guard let value, goal > 0 else { return nil }
        return min(1.0, Double(value) / Double(goal))
    }
}
