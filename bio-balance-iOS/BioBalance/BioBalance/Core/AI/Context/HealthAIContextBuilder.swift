import Foundation

/// 将 HealthKit、压力、行为和本地档案数据收敛为 AI 可使用的最小健康上下文。
struct HealthAIContextBuilder {
    private let calendar = Calendar.current
    private let caffeineCoach = CaffeineSleepStressCoachEngine()

    func makeContext(
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
        sedentaryState: DashboardSedentaryState?,
        sedentarySummary: SedentaryDaySummary?,
        activityPoints: [TimeSeriesPointDouble] = [],
        walkingSpeedMpsToday: Double? = nil,
        waterMlToday: Int? = nil,
        caffeineConsumedTodayMg: Int? = nil,
        daylightMinutesToday: Int? = nil,
        healthProfileSummary: HealthProfileAIDigest? = nil
    ) -> HealthAIContext {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        let resolvedWater = waterMlToday ?? AppGroupManager.shared.getWaterIntakeMl().flatMap(toNonnegativeRoundedInt)
        let doseEvents = caffeineCoach.loadDoseEvents(for: Date())
        let locallyRecordedCaffeine = ActionRecordStore.shared.record(for: Date()).caffeineMg
        let resolvedCaffeine = Self.resolveCaffeineConsumedToday(
            explicitAmount: caffeineConsumedTodayMg,
            locallyRecordedAmount: locallyRecordedCaffeine,
            doseEvents: doseEvents
        )
        let resolvedDaylight = daylightMinutesToday ?? AppGroupManager.shared.getValue(forKey: AppGroupManager.Keys.sunlightMinutesToday)
        // 隐含的 8 小时默认值只参与确定性计算，不能作为“用户已设置目标”发送给模型。
        let configuredSleepGoalMinutes = SleepGoalResolver.configuredGoalMinutes()
        let sleepGoalMinutesForCoach = configuredSleepGoalMinutes ?? SleepGoalResolver.goalMinutes()
        let caffeineAssessment = caffeineCoach.assessSleepRisk(
            dailyTotalMg: resolvedCaffeine,
            doseEvents: doseEvents,
            now: Date(),
            targetBedtime: targetBedtime(from: sleepInterval, now: Date()),
            sleepGoalMinutes: sleepGoalMinutesForCoach,
            stressScore: assessment.hasData ? Int(assessment.valueText) : realtimeHealth?.stress_value,
            lastNightSleepMinutes: sleepData?.duration_minutes,
            lastNightSleepScore: sleepData?.sleep_score
        )

        let sleep = HealthAIContext.SleepSummary(
            durationMinutes: positiveInt(sleepData?.duration_minutes),
            score: positiveInt(sleepData?.sleep_score),
            startLocalTime: sleepInterval.map { formatter.string(from: $0.start) },
            endLocalTime: sleepInterval.map { formatter.string(from: $0.end) },
            awakeCount: positiveInt(sleepData?.awake_count),
            deepMinutes: sleepData?.stages.first(where: { $0.stage.contains("深") }).map(\.duration),
            remMinutes: sleepData?.stages.first(where: { $0.stage.contains("快速") || $0.stage.uppercased().contains("REM") }).map(\.duration)
        )

        let recoveryVitals = HealthAIContext.RecoveryVitals(
            nightlyHrvMs: positiveDouble(nightlyHrv),
            nightlyAverageHeartRate: positiveInt(sleepData?.avg_heart_rate),
            nightlyRespiratoryRate: positiveDouble(nightlyRespiratoryRate),
            wristTemperatureCelsius: sleepingWristTemperature
        )

        let todayVitals = HealthAIContext.TodayVitals(
            currentHeartRate: positiveInt(realtimeHealth?.bpm),
            restingHeartRate: toRoundedInt(restingHeartRate),
            recentAverageRestingHeartRate: toRoundedInt(recentAvgRestingHeartRate),
            todayAverageHrv: positiveDouble(avgHrvToday),
            recentAverageHrv: positiveDouble(recentAvgHrv)
        )

        let stress = HealthAIContext.StressSummary(
            score: assessment.score,
            currentScore: realtimeHealth.flatMap { realtime in
                realtime.stress_level != nil || realtime.stress_value > 0 ? realtime.stress_value : nil
            },
            dailyScore: assessment.score,
            band: assessment.band.rawValue,
            title: assessment.title,
            summary: assessment.adviceDetail
        )

        let todaySteps = activityPoints
            .last(where: { calendar.isDateInToday($0.date) })
            .flatMap { toNonnegativeRoundedInt($0.value) }

        let activity = HealthAIContext.ActivitySummary(
            stepsToday: todaySteps,
            exerciseMinutesToday: nil,
            standHoursToday: nil,
            walkingSpeedMpsToday: positiveDouble(walkingSpeedMpsToday)
        )

        let recoveryBehavior = HealthAIContext.RecoveryBehavior(
            sedentaryElapsedMinutesCurrent: sedentaryState?.isCounting == true ? sedentaryState?.elapsedMinutes : nil,
            sedentaryTotalMinutesToday: sedentarySummary?.totalSedentaryMinutes,
            sedentaryLongestSessionMinutesToday: sedentarySummary?.longestSessionMinutes,
            activeBreakCountToday: sedentarySummary?.activeBreakCount
        )

        let provisionalContext = HealthAIContext(
            dateText: ISO8601DateFormatter().string(from: Date()),
            sleep: sleep,
            recoveryVitals: recoveryVitals,
            todayVitals: todayVitals,
            stress: stress,
            activity: activity,
            recoveryBehavior: recoveryBehavior,
            caffeineConsumedTodayMg: positiveInt(resolvedCaffeine),
            caffeineEstimatedRemainingMg: positiveInt(caffeineAssessment.currentRemainingMg),
            daylightMinutesToday: positiveInt(resolvedDaylight),
            waterMlToday: positiveInt(resolvedWater),
            sleepGoalMinutes: configuredSleepGoalMinutes,
            recoveryScriptPlan: nil,
            healthProfileSummary: healthProfileSummary,
            disclaimer: "仅供健康管理参考，不构成医疗诊断、治疗或急救建议。如有持续不适或异常指标，请咨询医生。"
        )
        let script = RecoveryScriptEngine().makePlan(context: provisionalContext)
        let wellnessRecord = DailyWellnessStore.shared.summary(endingAt: Date(), days: 7).todayRecord
        let habitSuggestions = DailyWellnessActionKind.allCases
            .filter { !wellnessRecord.isCompleted($0) }
            .map { $0.definition.subtitle }
        let challengeSuggestions = RecoveryChallengeStore.shared.activeChallenge().map {
            ["继续\($0.definition.title)：\($0.definition.ruleText)。"]
        } ?? []
        let goalSuggestions = GoalsStore.shared.activeGoals.map { "推进目标：\($0.title)。" }
        let suppressedSuggestionCategories = DailyRecoverySuggestionCooldownStore.shared.activeCategories()
        let orchestration = DailyRecoveryOrchestrationEngine().makePlan(
            recoveryPlan: script,
            habitSuggestions: habitSuggestions,
            challengeSuggestions: challengeSuggestions,
            goalSuggestions: goalSuggestions,
            suppressedSuggestionCategories: suppressedSuggestionCategories,
            now: Date()
        )
        DailyRecoveryOrchestrationStore.shared.save(orchestration)

        let finalContext = HealthAIContext(
            dateText: ISO8601DateFormatter().string(from: Date()),
            sleep: sleep,
            recoveryVitals: recoveryVitals,
            todayVitals: todayVitals,
            stress: stress,
            activity: activity,
            recoveryBehavior: recoveryBehavior,
            caffeineConsumedTodayMg: positiveInt(resolvedCaffeine),
            caffeineEstimatedRemainingMg: positiveInt(caffeineAssessment.currentRemainingMg),
            daylightMinutesToday: positiveInt(resolvedDaylight),
            waterMlToday: positiveInt(resolvedWater),
            sleepGoalMinutes: configuredSleepGoalMinutes,
            recoveryScriptPlan: script,
            healthProfileSummary: healthProfileSummary,
            disclaimer: "仅供健康管理参考，不构成医疗诊断、治疗或急救建议。如有持续不适或异常指标，请咨询医生。"
        )
        DailyDeterministicHealthSnapshotStore.shared.save(
            DailyDeterministicHealthSnapshot.make(context: finalContext)
        )
        return finalContext
    }

    private func positiveDouble(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func resolveCaffeineConsumedToday(
        explicitAmount: Int?,
        locallyRecordedAmount: Int,
        doseEvents: [CaffeineDoseEvent]
    ) -> Int {
        let maximumDoseMg = 5_000
        let maximumDailyTotalMg = 20_000
        let timedDoseTotal = doseEvents.reduce(0) { total, event in
            let dose = min(maximumDoseMg, max(0, event.amountMg))
            return min(maximumDailyTotalMg, total + dose)
        }
        return min(
            maximumDailyTotalMg,
            max(0, explicitAmount ?? 0, locallyRecordedAmount, timedDoseTotal)
        )
    }

    private func positiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func toRoundedInt(_ value: Double?) -> Int? {
        guard let value,
              value.isFinite,
              let rounded = Int(exactly: value.rounded()),
              rounded > 0 else { return nil }
        return rounded
    }

    private func toNonnegativeRoundedInt(_ value: Double) -> Int? {
        guard value.isFinite,
              let rounded = Int(exactly: value.rounded()),
              rounded >= 0 else { return nil }
        return rounded
    }

    private func targetBedtime(from interval: SleepInterval?, now: Date) -> Date {
        let calendar = Calendar.current
        if let interval {
            return interval.start.addingTimeInterval(24 * 60 * 60)
        }
        let goalMinutes = SleepGoalResolver.goalMinutes()
        let wakeTarget = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: now) ?? now
        return wakeTarget.addingTimeInterval(TimeInterval(-goalMinutes * 60))
    }
}
