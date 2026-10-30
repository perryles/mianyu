import Foundation

struct WatchBodyAgeSummary {
    let valueYears: Double?
    let statusText: String?
    let comparisonText: String?
    let suggestionText: String?
    let coverageText: String?
    let directionText: String?
    let trendValues: [Double]?
}

enum WatchSyncMetrics {
    static func paceSecondsPerKilometer(from speedMps: Double?) -> Int? {
        guard let speedMps, speedMps > 0 else { return nil }
        let pace = 1000.0 / speedMps
        guard pace.isFinite, pace > 0 else { return nil }
        return Int(pace.rounded())
    }
}

struct WatchSyncSnapshotFactory {
    let latestBodyAgeSummary: WatchBodyAgeSummary?
    let realtimeHealth: RealtimeHealth?
    let currentActivity: ActivityData?
    let currentSleep: SleepData?
    let currentStress: StressData?

    func makeSnapshot(realtime: RealtimeHealth?) -> WatchSyncSnapshot {
        let resolvedRealtime = realtime ?? realtimeHealth

        let bpm = sanitizedBPM(resolvedRealtime?.bpm ?? Int(AppGroupManager.shared.getLatestHeartRate() ?? 0))
        let hrv = sanitizedHRV(resolvedRealtime?.hrv ?? AppGroupManager.shared.getLatestHRV() ?? 0)
        let stress = sanitizedStress(resolvedRealtime?.stress_value ?? Int(AppGroupManager.shared.getLatestStress() ?? 0))

        let steps: Int
        let activeEnergy: Int
        let exerciseMinutes: Int
        let standHours: Int
        let walkingSpeedMps: Double?
        let walkingPaceSecondsPerKm: Int?
        if let currentActivity {
            steps = max(0, currentActivity.steps)
            activeEnergy = max(0, currentActivity.active_energy)
            exerciseMinutes = max(0, currentActivity.exercise_time)
            standHours = max(0, currentActivity.stand_hours)
            walkingSpeedMps = sanitizedSpeed(currentActivity.walking_speed_mps)
            walkingPaceSecondsPerKm = WatchSyncMetrics.paceSecondsPerKilometer(from: currentActivity.walking_speed_mps)
        } else {
            steps = max(0, AppGroupManager.shared.getSteps() ?? 0)
            activeEnergy = max(0, AppGroupManager.shared.getActiveEnergy() ?? 0)
            exerciseMinutes = max(0, AppGroupManager.shared.getExerciseMinutes() ?? 0)
            standHours = max(0, AppGroupManager.shared.getStandHours() ?? 0)
            walkingSpeedMps = sanitizedSpeed(AppGroupManager.shared.getWalkingSpeedMps())
            walkingPaceSecondsPerKm = sanitizedPace(AppGroupManager.shared.getWalkingPaceSecondsPerKm())
        }

        let stepsGoal = max(0, AppGroupManager.shared.getStepsGoal() ?? 8000)
        let activeEnergyGoal = max(0, AppGroupManager.shared.getActiveEnergyGoal() ?? 500)
        let exerciseMinutesGoal = max(0, AppGroupManager.shared.getExerciseMinutesGoal() ?? 30)
        let standHoursGoal = max(0, AppGroupManager.shared.getStandHoursGoal() ?? 12)

        let sleepDurationMinutes: Int
        let sleepScore: Int
        let sleepSummary = AppGroupManager.shared.getSleepLatestSummary()
        let sleepMonitoringState = AppGroupManager.shared.getSleepMonitoringState()
        if let currentSleep {
            sleepDurationMinutes = max(0, currentSleep.duration_minutes)
            sleepScore = max(0, currentSleep.sleep_score)
        } else {
            sleepDurationMinutes = max(0, sleepSummary?.sleepDurationMinutes ?? AppGroupManager.shared.getSleepDurationMinutes() ?? 0)
            sleepScore = max(0, sleepSummary?.sleepScore ?? AppGroupManager.shared.getSleepScore() ?? 0)
        }

        let waterIntakeMl = max(0, Int((AppGroupManager.shared.getWaterIntakeMl() ?? 0).rounded()))
        let waterTargetMl = max(0, AppGroupManager.shared.getWaterTargetMl() ?? 2000)
        let waterCompletionRate = sanitizedRate(AppGroupManager.shared.getWaterCompletionRate() ?? 0)
        let caffeineRemainedMg = max(0, Int((AppGroupManager.shared.getCaffeineRemainedMg() ?? 0).rounded()))

        let sedentaryElapsedMinutes = max(0, AppGroupManager.shared.getSedentaryElapsedMinutes() ?? 0)
        let sedentaryIsCounting = AppGroupManager.shared.getSedentaryIsCounting() ?? false
        let sedentaryPausedBySleep = AppGroupManager.shared.getSedentaryPausedBySleep() ?? false
        let sedentarySeatedStartAtSeconds = AppGroupManager.shared.getSedentarySeatedStartAt().map { Int($0.timeIntervalSince1970) }
        let sedentaryLastActivityAtSeconds = AppGroupManager.shared.getSedentaryLastActivityAt().map { Int($0.timeIntervalSince1970) }
        let sedentaryUpdatedAtSeconds = AppGroupManager.shared.getSedentaryUpdatedAt().map { Int($0.timeIntervalSince1970) }
        let sedentaryBreakIsActive = AppGroupManager.shared.getSedentaryBreakIsActive() ?? false
        let sedentaryBreakDurationMinutes = max(0, AppGroupManager.shared.getSedentaryBreakDurationMinutes() ?? 0)
        let sedentaryBreakStartedAtSeconds = AppGroupManager.shared.getSedentaryBreakStartedAt().map { Int($0.timeIntervalSince1970) }
        let periodPhase = AppGroupManager.shared.getPeriodPhase()
        let periodCycleDay = AppGroupManager.shared.getPeriodCycleDay()
        let periodIsFertile = AppGroupManager.shared.getPeriodIsFertile()
        let periodNextStart = AppGroupManager.shared.getPeriodNextStart()
        let periodFertileStart = AppGroupManager.shared.getPeriodFertileStart()
        let periodFertileEnd = AppGroupManager.shared.getPeriodFertileEnd()
        let periodPredictionSource = AppGroupManager.shared.getPeriodPredictionSource()
        let defaultComplicationTemplate = AppGroupManager.shared.getDefaultComplicationTemplate()
        let watchThemeId = AppGroupManager.shared.getWatchThemeId()
        let watchCustomThemeId = AppGroupManager.shared.getWatchCustomThemeId()
        let watchMascotEnabled = AppGroupManager.shared.getWatchMascotEnabled() ?? true
        let watchMascotMessage = AppGroupManager.shared.getWatchMascotMessage()
        let bodyAgeSummary = latestBodyAgeSummary ?? loadStoredBodyAgeSummary()
        let stressHistory = resolvedStressHistory(realtime: resolvedRealtime)
        let recoveryPlan = loadRecoveryPlanSnapshot()

        return WatchSyncSnapshot(
            bpm: bpm,
            hrv: hrv,
            stress: stress,
            stressState: resolvedRealtime?.stress_level,
            stressExplanationCode: resolvedRealtime?.stress_explanation_code,
            stressConfidence: resolvedRealtime?.stress_confidence,
            stressQuality: resolvedRealtime?.stress_quality ?? AppGroupManager.shared.getValue(forKey: AppGroupSchema.Keys.stressQuality),
            stressAlgorithmVersion: resolvedRealtime?.stress_algorithm_version ?? AppGroupManager.shared.getValue(forKey: AppGroupSchema.Keys.stressAlgorithmVersion),
            dailyStress: resolvedRealtime?.daily_stress_value ?? AppGroupManager.shared.getValue(forKey: AppGroupSchema.Keys.dailyStress),
            dailyStressQuality: resolvedRealtime?.daily_stress_quality ?? AppGroupManager.shared.getValue(forKey: AppGroupSchema.Keys.dailyStressQuality),
            dailyStressAlgorithmVersion: resolvedRealtime?.daily_stress_algorithm_version ?? AppGroupManager.shared.getValue(forKey: AppGroupSchema.Keys.dailyStressAlgorithmVersion),
            stressTrend: nonEmpty(AppGroupManager.shared.getStressTrend()) ?? "稳定",
            timestamp: Int(Date().timeIntervalSince1970),
            steps: steps,
            activeEnergy: activeEnergy,
            exerciseMinutes: exerciseMinutes,
            standHours: standHours,
            walkingSpeedMps: walkingSpeedMps,
            walkingPaceSecondsPerKm: walkingPaceSecondsPerKm,
            stepsGoal: stepsGoal,
            activeEnergyGoal: activeEnergyGoal,
            exerciseMinutesGoal: exerciseMinutesGoal,
            standHoursGoal: standHoursGoal,
            sleepDurationMinutes: sleepDurationMinutes,
            sleepScore: sleepScore,
            lateNightRecoveryPrompt: AppGroupManager.shared.getLateNightRecoveryPrompt(),
            lateNightRecoverySeverity: AppGroupManager.shared.getLateNightRecoverySeverity(),
            sleepEnvironmentCompletionRate: AppGroupManager.shared.getSleepEnvironmentCompletionRate(),
            sleepEnvironmentPrompt: AppGroupManager.shared.getSleepEnvironmentPrompt(),
            waterIntakeMl: waterIntakeMl,
            waterTargetMl: waterTargetMl,
            waterCompletionRate: waterCompletionRate,
            caffeineRemainedMg: caffeineRemainedMg,
            sedentaryElapsedMinutes: sedentaryElapsedMinutes,
            sedentaryIsCounting: sedentaryIsCounting,
            sedentaryPausedBySleep: sedentaryPausedBySleep,
            sedentarySeatedStartAtSeconds: sedentarySeatedStartAtSeconds,
            sedentaryLastActivityAtSeconds: sedentaryLastActivityAtSeconds,
            sedentaryUpdatedAtSeconds: sedentaryUpdatedAtSeconds,
            sedentaryBreakIsActive: sedentaryBreakIsActive,
            sedentaryBreakDurationMinutes: sedentaryBreakDurationMinutes,
            sedentaryBreakStartedAtSeconds: sedentaryBreakStartedAtSeconds,
            periodPhase: periodPhase,
            periodCycleDay: periodCycleDay,
            periodIsFertile: periodIsFertile,
            periodNextStart: periodNextStart,
            periodFertileStart: periodFertileStart,
            periodFertileEnd: periodFertileEnd,
            periodPredictionSource: periodPredictionSource,
            defaultComplicationTemplate: defaultComplicationTemplate,
            watchThemeId: watchThemeId,
            watchMascotEnabled: watchMascotEnabled,
            watchMascotMessage: watchMascotMessage,
            watchMascotMessageConfigured: true,
            watchCustomThemeId: watchCustomThemeId,
            bodyAgeValueYears: bodyAgeSummary?.valueYears,
            bodyAgeStatusText: bodyAgeSummary?.statusText,
            bodyAgeComparisonText: bodyAgeSummary?.comparisonText,
            bodyAgeSuggestionText: bodyAgeSummary?.suggestionText,
            bodyAgeCoverageText: bodyAgeSummary?.coverageText,
            bodyAgeDirectionText: bodyAgeSummary?.directionText,
            vo2MaxValue: AppGroupManager.shared.getVO2MaxValue(),
            vo2MaxConfidence: AppGroupManager.shared.getVO2MaxConfidence(),
            vo2MaxTrend: AppGroupManager.shared.getVO2MaxTrend(),
            vo2MaxFitnessLevel: AppGroupManager.shared.getVO2MaxFitnessLevel(),
            vo2MaxSource: AppGroupManager.shared.getVO2MaxSource(),
            vo2MaxDriverSummary: AppGroupManager.shared.getVO2MaxDriverSummary(),
            stressHistory: stressHistory,
            sleepMonitoringPhase: sleepMonitoringState?.phase.rawValue,
            sleepMonitoringActive: sleepMonitoringState?.phase == .monitoring,
            sleepSnoreIntensity: sleepSummary?.snoreSummary.intensity.rawValue ?? AppGroupManager.shared.getSleepSnoreIntensity(),
            sleepSnoreDurationMinutes: sleepSummary?.snoreSummary.snoreDurationMinutes ?? AppGroupManager.shared.getSleepSnoreDurationMinutes(),
            sleepInsightHeadline: sleepSummary?.insight.headline ?? AppGroupManager.shared.getSleepInsightHeadline(),
            sleepWatchConfidence: sleepSummary?.watchConfidence ?? AppGroupManager.shared.getSleepWatchConfidence(),
            recoveryPlan: recoveryPlan
        )
    }

    static func makeRecoveryPlanProjection(
        plan: DailyRecoveryOrchestrationPlan,
        actionStates: [String: DailyRecoveryActionStateRecord]
    ) -> WatchRecoveryPlanSnapshot {
        var actions = [
            WatchRecoveryPlanActionSnapshot(
                actionID: plan.mainActionID,
                title: plan.mainGoal,
                role: "main",
                state: actionStates[plan.mainActionID]?.state.rawValue ?? DailyRecoveryActionState.pending.rawValue
            )
        ]

        actions.append(contentsOf: zip(plan.supportingActionIDs, plan.supportingActions).map { actionID, title in
            WatchRecoveryPlanActionSnapshot(
                actionID: actionID,
                title: title,
                role: "supporting",
                state: actionStates[actionID]?.state.rawValue ?? DailyRecoveryActionState.pending.rawValue
            )
        })

        return WatchRecoveryPlanSnapshot(
            planID: plan.planID,
            dayStart: Int(plan.date.timeIntervalSince1970),
            actions: actions
        )
    }

    private func loadRecoveryPlanSnapshot(
        for date: Date = Date(),
        calendar: Calendar = .current
    ) -> WatchRecoveryPlanSnapshot? {
        let store = DailyRecoveryOrchestrationStore.shared
        guard let plan = store.load(for: date, calendar: calendar) else { return nil }
        return Self.makeRecoveryPlanProjection(
            plan: plan,
            actionStates: store.actionStates(for: plan)
        )
    }

    private func resolvedStressHistory(realtime: RealtimeHealth?) -> [WatchStressHistoryPoint] {
        var points = AppGroupManager.shared.getStressHistory()

        if points.isEmpty, let localHistory = currentStress?.history, !localHistory.isEmpty {
            points = localHistory.compactMap { point -> WatchStressHistoryPoint? in
                guard point.timestamp > 0, point.value > 0, point.value <= 100 else { return nil }
                return WatchStressHistoryPoint(
                    timestamp: Int(point.timestamp),
                    value: point.value
                )
            }
        }

        if let realtime, realtime.stress_value > 0 {
            let realtimePoint = WatchStressHistoryPoint(
                timestamp: Int(realtime.timestamp),
                value: max(0, min(100, realtime.stress_value))
            )
            if let last = points.last {
                if abs(last.timestamp - realtimePoint.timestamp) > 300 || last.value != realtimePoint.value {
                    points.append(realtimePoint)
                }
            } else {
                points.append(realtimePoint)
            }
        }

        return WatchSnapshotArbitration.boundedStressHistory(points)
    }

    private func loadStoredBodyAgeSummary() -> WatchBodyAgeSummary? {
        let appGroup = AppGroupManager.shared
        let valueYears = appGroup.getBodyAgeValueYears().flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let statusText = nonEmpty(appGroup.getBodyAgeStatusText())
        let comparisonText = nonEmpty(appGroup.getBodyAgeComparisonText())
        let suggestionText = nonEmpty(appGroup.getBodyAgeSuggestionText())
        let coverageText = nonEmpty(appGroup.getBodyAgeCoverageText())
        let directionText = nonEmpty(appGroup.getBodyAgeDirectionText())

        guard valueYears != nil
            || statusText != nil
            || comparisonText != nil
            || suggestionText != nil
            || coverageText != nil
            || directionText != nil else {
            return nil
        }

        return WatchBodyAgeSummary(
            valueYears: valueYears,
            statusText: statusText,
            comparisonText: comparisonText,
            suggestionText: suggestionText,
            coverageText: coverageText,
            directionText: directionText,
            trendValues: nil
        )
    }

    private func sanitizedBPM(_ value: Int) -> Int {
        value > 0 ? min(250, value) : 0
    }

    private func sanitizedHRV(_ value: Double) -> Double {
        value.isFinite ? min(max(0, value), 500) : 0
    }

    private func sanitizedStress(_ value: Int) -> Int {
        value > 0 ? min(100, value) : 0
    }

    private func sanitizedRate(_ value: Double) -> Double {
        value.isFinite ? min(max(0, value), 1) : 0
    }

    private func sanitizedSpeed(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func sanitizedPace(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
