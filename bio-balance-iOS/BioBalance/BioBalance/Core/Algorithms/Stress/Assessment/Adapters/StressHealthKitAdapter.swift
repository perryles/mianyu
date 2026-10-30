import Foundation
import HealthKit

enum StressHealthKitAdapter {
    static func makeRealtimeInput(
        now: Date,
        heartRatePoints: [TimeSeriesPoint],
        hrvPoints: [TimeSeriesPointDouble],
        restingHeartRate: Double?,
        restingBaseline: HealthBaselineState,
        hrvBaseline: HealthBaselineState,
        sleepInterval: SleepInterval?,
        sleepMinutes: Int?,
        sleepEfficiency: Double?,
        nightlyHrv: Double?,
        overnightMinHeartRate: Double?,
        workoutContext: LatestWorkoutContext?,
        chronologicalAge: Int?,
        habitualSleepWindow: StressHabitualSleepWindow
    ) -> StressRealtimeInput {
        let validHeartRate = heartRatePoints
            .filter { $0.value > 0 && $0.date <= now }
            .sorted { $0.timestamp < $1.timestamp }
        let validHrv = hrvPoints
            .filter { $0.value > 0 && $0.date <= now }
            .sorted { $0.timestamp < $1.timestamp }
        let latestHeartRate = validHeartRate.last.map {
            StressMetricSample(value: Double($0.value), measuredAt: $0.date)
        }
        let latestHrv = validHrv.last.map {
            StressMetricSample(value: $0.value, measuredAt: $0.date)
        }
        let recentHeartRate = validHeartRate.filter { now.timeIntervalSince($0.date) <= 30 * 60 }.map {
            StressMetricSample(value: Double($0.value), measuredAt: $0.date)
        }
        let recentHrv = validHrv.filter { now.timeIntervalSince($0.date) <= 30 * 60 }.map {
            StressMetricSample(value: $0.value, measuredAt: $0.date)
        }
        let resolvedRestingBaseline = stressBaseline(from: restingBaseline)
        let workout = makeWorkoutContext(
            from: workoutContext,
            now: now,
            currentHeartRate: latestHeartRate?.value,
            baselineRestingHeartRate: resolvedRestingBaseline.value ?? restingHeartRate,
            age: chronologicalAge
        )

        return StressRealtimeInput(
            now: now,
            heartRate: latestHeartRate,
            hrv: latestHrv,
            restingHeartRate: restingHeartRate,
            restingHeartRateBaseline: resolvedRestingBaseline,
            hrvBaseline: stressBaseline(from: hrvBaseline),
            hrvPoints30m: recentHrv,
            heartRatePoints30m: recentHeartRate,
            sleepInterval: sleepInterval.map { StressDateInterval(start: $0.start, end: $0.end) },
            sleepMinutes: sleepMinutes,
            sleepEfficiency: sleepEfficiency,
            nightlyHrv: nightlyHrv,
            overnightMinHeartRate: overnightMinHeartRate,
            workout: workout,
            chronologicalAge: chronologicalAge,
            habitualSleepWindow: habitualSleepWindow
        )
    }

    private static func stressBaseline(from state: HealthBaselineState) -> StressBaseline {
        StressBaseline(
            value: state.value,
            sampleCount: state.sampleCount,
            minimumSampleCount: state.minimumSampleCount,
            trustedSampleCount: state.trustedSampleCount
        )
    }

    private static func makeWorkoutContext(
        from context: LatestWorkoutContext?,
        now: Date,
        currentHeartRate: Double?,
        baselineRestingHeartRate: Double?,
        age: Int?
    ) -> StressWorkoutContext {
        guard let context else { return .inactive }
        let kind = workoutKind(context.activityType)
        let baseline = max(1, baselineRestingHeartRate ?? 62)
        let estimatedMaxHeartRate = 208 - 0.7 * Double(age ?? 30)
        let reserve = max(estimatedMaxHeartRate - baseline, 1)
        let intensity = StressRules.clamp(((currentHeartRate ?? baseline) - baseline) / reserve, lower: 0, upper: 1)
        let activeBlend: Double
        switch kind {
        case .running, .cycling: activeBlend = intensity >= 0.65 ? 0.70 : 0.55
        case .strength: activeBlend = 0.45
        case .highIntensityIntervalTraining: activeBlend = 0.75
        case .other: activeBlend = 0.55
        case .none: activeBlend = 0
        }
        let minutesSinceEnd = context.endedAt.map { max(0, Int(now.timeIntervalSince($0) / 60)) }
        let blend: Double
        if context.isActive {
            blend = activeBlend
        } else if let minutesSinceEnd {
            blend = activeBlend * Foundation.exp(-Double(minutesSinceEnd) / 20)
        } else {
            blend = 0
        }
        return StressWorkoutContext(
            isActive: context.isActive,
            kind: kind,
            typeTitle: context.activityType.map { HealthKitManager.workoutActivityTitlePublic(for: $0) },
            intensity: intensity,
            workoutBlend: StressRules.clamp(blend, lower: 0, upper: 0.75),
            minutesSinceEnd: minutesSinceEnd
        )
    }

    private static func workoutKind(_ type: HKWorkoutActivityType?) -> StressWorkoutKind {
        switch type {
        case .running: return .running
        case .cycling: return .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .some: return .other
        case .none: return .none
        }
    }
}
