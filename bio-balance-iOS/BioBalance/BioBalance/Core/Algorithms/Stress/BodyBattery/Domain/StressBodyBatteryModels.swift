import Foundation

nonisolated struct StressBodyBatteryRecoveryInput: Sendable, Equatable {
    let sleepMinutes: Int?
    let sleepGoalMinutes: Int
    let sleepScoreFallback: Int?
    let sleepEfficiency: Double?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let nightlyHrv: Double?
    let baselineHrv: Double?
    let overnightHeartRate: Double?
    let baselineOvernightHeartRate: Double?
    let restingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let nightlyRespiratoryRate: Double?
    let baselineNightlyRespiratoryRate: Double?
    let sleepingWristTemperature: Double?
    let baselineSleepingWristTemperature: Double?
    let sleepingBreathingDisturbances: Double?
    let baselineSleepingBreathingDisturbances: Double?
}

nonisolated struct StressBodyBatteryPhysicalEffortSample: Sendable, Equatable {
    let startDate: Date
    let endDate: Date
    let metabolicEquivalent: Double
}

nonisolated struct StressBodyBatteryWorkoutEffortEvent: Sendable, Equatable {
    let endedAt: Date
    let durationMinutes: Double
    let score: Double
    let isEstimated: Bool
}

nonisolated struct StressBodyBatteryLoadInput: Sendable, Equatable {
    let physicalEffortSamples: [StressBodyBatteryPhysicalEffortSample]
    let workoutEffortEvents: [StressBodyBatteryWorkoutEffortEvent]

    static let empty = StressBodyBatteryLoadInput(
        physicalEffortSamples: [],
        workoutEffortEvents: []
    )
}
