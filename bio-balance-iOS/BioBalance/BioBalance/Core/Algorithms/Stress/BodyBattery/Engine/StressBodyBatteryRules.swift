import Foundation

nonisolated enum StressBodyBatteryRules {
    static let minimumLevel = 5
    static let maximumLevel = 100
    static let secondsPerHour = 3_600.0
    static let secondsPerDay = 86_400.0

    enum Recovery {
        static let defaultSleepGoalMinutes = 480
        static let minimumBaselineValueCount = 4
        static let minimumHistoricalBaselineValueCount = 3

        static let sleepDurationWeight = 0.20
        static let sleepEfficiencyWeight = 0.09
        static let restorativeSleepWeight = 0.06
        static let sleepScoreFallbackWeight = 0.15
        static let hrvWeight = 0.25
        static let heartRateWeight = 0.15
        static let respiratoryRateWeight = 0.10
        static let wristTemperatureWeight = 0.10
        static let breathingDisturbancesWeight = 0.05

        static let fullRawComponentWeight = sleepDurationWeight
            + sleepEfficiencyWeight
            + restorativeSleepWeight
            + hrvWeight
            + heartRateWeight
            + respiratoryRateWeight
            + wristTemperatureWeight
            + breathingDisturbancesWeight

        private static let sleepEfficiencyFloor = 0.70
        private static let sleepEfficiencyRange = 0.25
        private static let restorativeSleepRatioFloor = 0.18
        private static let restorativeSleepRatioRange = 0.27
        private static let hrvDeltaRange = -0.50...0.40
        private static let hrvBaselineScore = 75.0
        private static let hrvDeltaScale = 100.0
        private static let heartRateRiseRange = -0.15...0.30
        private static let heartRateBaselineScore = 75.0
        private static let heartRateRiseScale = 200.0
        private static let stableVitalScore = 95.0
        private static let respiratoryDeviationScale = 250.0
        private static let wristTemperatureDeviationScale = 30.0
        private static let breathingDisturbanceRiseScale = 180.0

        static func sleepDurationScore(minutes: Int, goalMinutes: Int) -> Double {
            Double(minutes) / Double(max(goalMinutes, 1)) * 100
        }

        static func sleepEfficiencyScore(_ efficiency: Double) -> Double {
            (efficiency - sleepEfficiencyFloor) / sleepEfficiencyRange * 100
        }

        static func restorativeSleepScore(minutes: Int, sleepMinutes: Int) -> Double {
            let ratio = Double(minutes) / Double(sleepMinutes)
            return (ratio - restorativeSleepRatioFloor) / restorativeSleepRatioRange * 100
        }

        static func hrvScore(current: Double, baseline: Double) -> Double {
            let delta = clamp((current - baseline) / baseline, to: hrvDeltaRange)
            return hrvBaselineScore + delta * hrvDeltaScale
        }

        static func heartRateScore(current: Double, baseline: Double) -> Double {
            let rise = clamp((current - baseline) / baseline, to: heartRateRiseRange)
            return heartRateBaselineScore - rise * heartRateRiseScale
        }

        static func respiratoryRateScore(current: Double, baseline: Double) -> Double {
            stableVitalScore - abs((current - baseline) / baseline) * respiratoryDeviationScale
        }

        static func wristTemperatureScore(current: Double, baseline: Double) -> Double {
            stableVitalScore - abs(current - baseline) * wristTemperatureDeviationScale
        }

        static func breathingDisturbancesScore(current: Double, baseline: Double) -> Double {
            let rise = max(0, current - baseline) / max(baseline, 1)
            return stableVitalScore - rise * breathingDisturbanceRiseScale
        }
    }

    enum DayLoad {
        static let defaultWakeHour = 7
        static let defaultStress = 20
        static let fallbackStartingBase = 78.0
        static let fallbackStartingStressScale = 0.25
        static let estimatedDailyBase = 82.0
        static let estimatedDailyStressScale = 0.55

        static let restingMetabolicEquivalent = 1.5
        static let metabolicEquivalentRange = 6.5
        static let physicalLoadContribution = 0.70

        static let baseDrainPerHour = 0.7
        static let nonlinearDrainExponent = 1.6
        static let stressDrainScale = 5.0
        static let lowStressRecoveryThreshold = 20.0
        static let maximumRecoveryPerHour = 1.2
        static let physicalRecoveryCutoff = 0.05
        static let postWorkoutRecoveryCutoff = 0.10

        static let workoutIntegrationOffsetsHours = [0.0, 1.0, 3.0, 6.0, 12.0]

        static func fallbackStartingLevel(stress: Int) -> Int {
            clampLevel(fallbackStartingBase - Double(clampStress(stress)) * fallbackStartingStressScale)
        }

        static func estimatedDailyLevel(averageStress: Int) -> Int {
            clampLevel(estimatedDailyBase - Double(clampStress(averageStress)) * estimatedDailyStressScale)
        }

        static func normalizedPhysicalEffort(metabolicEquivalent: Double) -> Double {
            clamp(
                (metabolicEquivalent - restingMetabolicEquivalent) / metabolicEquivalentRange,
                lower: 0,
                upper: 1
            )
        }

        static func combinedLoad(stress: Double, physicalLoad: Double) -> Double {
            let normalizedStress = clamp(stress) / 100
            return 1 - (1 - normalizedStress) * (1 - physicalLoad * physicalLoadContribution)
        }

        static func drainPerHour(
            combinedLoad: Double,
            postWorkoutLoad: Double,
            trainingLoadMultiplier: Double
        ) -> Double {
            baseDrainPerHour
                + (pow(combinedLoad, nonlinearDrainExponent) * stressDrainScale + postWorkoutLoad)
                * trainingLoadMultiplier
        }

        static func recoveryPerHour(
            stress: Double,
            physicalLoad: Double,
            postWorkoutLoad: Double
        ) -> Double {
            guard stress < lowStressRecoveryThreshold,
                  physicalLoad < physicalRecoveryCutoff,
                  postWorkoutLoad < postWorkoutRecoveryCutoff else { return 0 }
            return (lowStressRecoveryThreshold - stress) / lowStressRecoveryThreshold
                * maximumRecoveryPerHour
        }
    }

    enum Workout {
        static let postWorkoutDurationHours = 12.0
        static let scoreRange = 1.0...10.0
        static let scoreDivisor = 10.0
        static let referenceDurationMinutes = 30.0
        static let minimumDurationMinutes = 1.0
        static let durationFactorRange = 0.65...1.60
        static let estimatedSourceFactor = 0.90
        static let debtScale = 0.90
        static let decayTimeConstantHours = 4.0

        static let recentWindowDays = 7.0
        static let baselineWindowDays = 28.0
        static let minimumBaselineEventCount = 3
        static let loadRatioRange = 0.0...2.0
        static let overloadScale = 0.15
        static let multiplierRange = 1.0...1.15

        static func postWorkoutLoad(
            hoursSinceEnd: Double,
            score: Double,
            durationMinutes: Double,
            isEstimated: Bool
        ) -> Double {
            guard hoursSinceEnd >= 0, hoursSinceEnd <= postWorkoutDurationHours else { return 0 }
            let normalizedScore = clamp(score, to: scoreRange) / scoreDivisor
            let durationFactor = clamp(
                sqrt(durationMinutes / referenceDurationMinutes),
                to: durationFactorRange
            )
            let sourceFactor = isEstimated ? estimatedSourceFactor : 1
            return debtScale * normalizedScore * durationFactor * sourceFactor
                * Foundation.exp(-hoursSinceEnd / decayTimeConstantHours)
        }

        static func trainingLoadMultiplier(
            recentLoad: Double,
            baselineLoad: Double,
            baselineEventCount: Int
        ) -> Double {
            guard baselineEventCount >= minimumBaselineEventCount, baselineLoad > 0 else { return 1 }
            let windowScale = baselineWindowDays / recentWindowDays
            let loadRatio = clamp(recentLoad * windowScale / baselineLoad, to: loadRatioRange)
            return clamp(
                1 + max(0, loadRatio - 1) * overloadScale,
                to: multiplierRange
            )
        }
    }

    static func clampStress(_ value: Int) -> Int {
        min(maximumLevel, max(0, value))
    }

    static func clampLevel(_ value: Double) -> Int {
        Int(clamp(value, lower: Double(minimumLevel), upper: Double(maximumLevel)).rounded())
    }

    static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        min(upper, max(lower, value))
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
