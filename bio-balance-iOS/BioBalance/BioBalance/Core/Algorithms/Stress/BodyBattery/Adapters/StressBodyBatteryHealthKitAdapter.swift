import Foundation

enum StressBodyBatteryHealthKitAdapter {
    static func makeBodyBatteryRecoveryInput(
        sleepData: SleepData?,
        recentNightSummaries: [SleepTrendNightSummary],
        sleepGoalMinutes: Int,
        nightlyHrv: Double?,
        baselineHrv: Double?,
        overnightHeartRate: Double?,
        baselineOvernightHeartRate: Double?,
        restingHeartRate: Double?,
        baselineRestingHeartRate: Double?,
        nightlyRespiratoryRate: Double?,
        baselineNightlyRespiratoryRate: Double?,
        sleepingWristTemperature: Double?,
        baselineSleepingWristTemperature: Double?,
        sleepingBreathingDisturbances: Double?,
        baselineSleepingBreathingDisturbances: Double?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> StressBodyBatteryRecoveryInput {
        let latestNight = recentNightSummaries.last {
            $0.asleepMinutes > 0 && calendar.isDate($0.day, inSameDayAs: referenceDate)
        }
        let sourcedStages = sleepData?.stages.filter {
            $0.duration > 0 && ($0.sourceType != nil || $0.startDate != nil || $0.endDate != nil)
        } ?? []

        func stageMinutes(matching names: [String]) -> Int? {
            let minutes = sourcedStages
                .filter { stage in names.contains { stage.stage.localizedCaseInsensitiveContains($0) } }
                .reduce(0) { $0 + $1.duration }
            return minutes > 0 ? minutes : nil
        }

        return StressBodyBatteryRecoveryInput(
            sleepMinutes: sleepData?.duration_minutes,
            sleepGoalMinutes: sleepGoalMinutes,
            sleepScoreFallback: sleepData?.sleep_score,
            sleepEfficiency: latestNight?.efficiency,
            deepSleepMinutes: latestNight?.deepMinutes ?? stageMinutes(matching: ["深睡", "Deep"]),
            remSleepMinutes: latestNight?.remMinutes ?? stageMinutes(matching: ["快速眼动", "REM"]),
            nightlyHrv: nightlyHrv,
            baselineHrv: baselineHrv,
            overnightHeartRate: overnightHeartRate,
            baselineOvernightHeartRate: baselineOvernightHeartRate,
            restingHeartRate: restingHeartRate,
            baselineRestingHeartRate: baselineRestingHeartRate,
            nightlyRespiratoryRate: nightlyRespiratoryRate,
            baselineNightlyRespiratoryRate: baselineNightlyRespiratoryRate,
            sleepingWristTemperature: sleepingWristTemperature,
            baselineSleepingWristTemperature: baselineSleepingWristTemperature,
            sleepingBreathingDisturbances: sleepingBreathingDisturbances,
            baselineSleepingBreathingDisturbances: baselineSleepingBreathingDisturbances
        )
    }

    static func makeBodyBatteryLoadInput(
        physicalEffort: [HealthPhysicalEffortSample],
        workoutEffort: [HealthWorkoutEffortSample]
    ) -> StressBodyBatteryLoadInput {
        StressBodyBatteryLoadInput(
            physicalEffortSamples: physicalEffort.map {
                StressBodyBatteryPhysicalEffortSample(
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    metabolicEquivalent: $0.metabolicEquivalent
                )
            },
            workoutEffortEvents: workoutEffort.map {
                StressBodyBatteryWorkoutEffortEvent(
                    endedAt: $0.endedAt,
                    durationMinutes: $0.durationMinutes,
                    score: $0.score,
                    isEstimated: $0.isEstimated
                )
            }
        )
    }
}
