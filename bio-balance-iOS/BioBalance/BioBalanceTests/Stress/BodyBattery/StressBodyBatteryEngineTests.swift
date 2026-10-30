import XCTest
@testable import BioBalance

nonisolated final class StressBodyBatteryEngineTests: XCTestCase {
    @MainActor func testRawRecoveryComponentWeightsSumToOne() {
        XCTAssertEqual(
            StressBodyBatteryRules.Recovery.fullRawComponentWeight,
            1,
            accuracy: 0.000_001
        )
    }

    @MainActor func testEstimatedDailyLevelClampsOutOfRangeStress() {
        let belowRange = StressBodyBatteryEngine.estimatedDailyLevel(averageStress: -1_000)
        let aboveRange = StressBodyBatteryEngine.estimatedDailyLevel(averageStress: 1_000)

        XCTAssertEqual(belowRange, 82)
        XCTAssertEqual(aboveRange, 27)
        XCTAssertTrue(StressBodyBatteryRules.minimumLevel...StressBodyBatteryRules.maximumLevel ~= belowRange)
        XCTAssertTrue(StressBodyBatteryRules.minimumLevel...StressBodyBatteryRules.maximumLevel ~= aboveRange)
    }

    @MainActor func testTrainingLoadMultiplierIsCapped() {
        let multiplier = StressBodyBatteryRules.Workout.trainingLoadMultiplier(
            recentLoad: 10_000,
            baselineLoad: 100,
            baselineEventCount: 10
        )

        XCTAssertEqual(multiplier, 1.15, accuracy: 0.000_001)
    }

    @MainActor func testBetterOvernightRecoveryProducesHigherStartingLevel() throws {
        let strong = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(
            sleepMinutes: 480,
            sleepScore: 92,
            nightlyHrv: 60,
            baselineHrv: 50,
            restingHeartRate: 56,
            baselineRestingHeartRate: 60
        ))
        let weak = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(
            sleepMinutes: 300,
            sleepScore: 55,
            nightlyHrv: 35,
            baselineHrv: 50,
            restingHeartRate: 68,
            baselineRestingHeartRate: 60
        ))

        XCTAssertGreaterThan(strong, weak)
    }

    @MainActor func testSustainedHighStressDrainsMoreThanLowStress() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let wake = try XCTUnwrap(calendar.date(byAdding: .hour, value: 7, to: day))
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: wake))

        let low = try XCTUnwrap(StressBodyBatteryEngine.currentValue(
            stressPoints: [],
            fallbackStress: 20,
            recoveryScore: 85,
            wakeDate: wake,
            now: end,
            calendar: calendar
        ))
        let high = try XCTUnwrap(StressBodyBatteryEngine.currentValue(
            stressPoints: [],
            fallbackStress: 80,
            recoveryScore: 85,
            wakeDate: wake,
            now: end,
            calendar: calendar
        ))

        XCTAssertGreaterThan(low, high)
        XCTAssertGreaterThanOrEqual(high, StressBodyBatteryEngine.minimumLevel)
    }

    @MainActor func testTrajectoryDeduplicatesEqualTimestamps() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let wake = try XCTUnwrap(calendar.date(byAdding: .hour, value: 7, to: day))
        let sampleDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: wake))
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: wake))
        let timestamp = Int64(sampleDate.timeIntervalSince1970)

        let points = StressBodyBatteryEngine.trajectory(
            stressPoints: [
                TimeSeriesPoint(timestamp: timestamp, value: 30),
                TimeSeriesPoint(timestamp: timestamp, value: 60)
            ],
            fallbackStress: 60,
            recoveryScore: 80,
            wakeDate: wake,
            endDate: end,
            calendar: calendar
        )

        XCTAssertEqual(points.map(\.timestamp).count, Set(points.map(\.timestamp)).count)
    }

    @MainActor func testCurrentValueMatchesTrajectoryEndpoint() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let wake = try XCTUnwrap(calendar.date(byAdding: .hour, value: 7, to: day))
        let sampleDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: wake))
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 5, to: wake))
        let stressPoints = [
            TimeSeriesPoint(timestamp: Int64(sampleDate.timeIntervalSince1970), value: 65)
        ]
        let trajectory = StressBodyBatteryEngine.trajectory(
            stressPoints: stressPoints,
            fallbackStress: 65,
            recoveryScore: 82,
            wakeDate: wake,
            endDate: end,
            calendar: calendar
        )
        let currentValue = StressBodyBatteryEngine.currentValue(
            stressPoints: stressPoints,
            fallbackStress: 65,
            recoveryScore: 82,
            wakeDate: wake,
            now: end,
            calendar: calendar
        )

        XCTAssertFalse(trajectory.isEmpty)
        XCTAssertEqual(trajectory.last?.timestamp, Int64(end.timeIntervalSince1970))
        XCTAssertEqual(trajectory.last?.value, currentValue)
    }

    @MainActor func testNightlyVitalDeviationsReduceRecoveryScore() throws {
        let stable = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(input: recoveryInput(
            respiratoryRate: 15,
            wristTemperature: 36.2,
            breathingDisturbances: 4
        )))
        let disturbed = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(input: recoveryInput(
            respiratoryRate: 18,
            wristTemperature: 37.2,
            breathingDisturbances: 8
        )))

        XCTAssertGreaterThan(stable, disturbed)
    }

    @MainActor func testSleepScoreFallbackIsUsedWhenSleepDurationIsZero() throws {
        let score = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(
            sleepMinutes: 0,
            sleepScore: 82,
            nightlyHrv: nil,
            baselineHrv: nil,
            restingHeartRate: nil,
            baselineRestingHeartRate: nil
        ))

        XCTAssertEqual(score, 82)
    }

    @MainActor func testBreathingDisturbanceSupportsZeroPersonalBaseline() throws {
        let baseline = StressBodyBatteryEngine.personalBaseline(
            [0, 0, 0, 2],
            allowsZero: true
        )
        XCTAssertEqual(baseline, 0)

        let stable = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(input: recoveryInput(
            respiratoryRate: 15,
            wristTemperature: 36.2,
            breathingDisturbances: 0,
            breathingDisturbanceBaseline: 0
        )))
        let disturbed = try XCTUnwrap(StressBodyBatteryEngine.recoveryScore(input: recoveryInput(
            respiratoryRate: 15,
            wristTemperature: 36.2,
            breathingDisturbances: 1,
            breathingDisturbanceBaseline: 0
        )))

        XCTAssertGreaterThan(stable, disturbed)
    }

    @MainActor func testPhysicalEffortAddsDrainWithoutDoubleCountingStress() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let wake = try XCTUnwrap(calendar.date(byAdding: .hour, value: 7, to: day))
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 4, to: wake))
        let baseline = try XCTUnwrap(StressBodyBatteryEngine.currentValue(
            stressPoints: [],
            fallbackStress: 35,
            recoveryScore: 85,
            wakeDate: wake,
            now: end,
            calendar: calendar
        ))
        let effort = try XCTUnwrap(StressBodyBatteryEngine.currentValue(
            stressPoints: [],
            fallbackStress: 35,
            recoveryScore: 85,
            wakeDate: wake,
            now: end,
            calendar: calendar,
            load: StressBodyBatteryLoadInput(
                physicalEffortSamples: [StressBodyBatteryPhysicalEffortSample(
                    startDate: wake,
                    endDate: end,
                    metabolicEquivalent: 7
                )],
                workoutEffortEvents: []
            )
        ))

        XCTAssertGreaterThan(baseline, effort)
    }

    @MainActor func testWorkoutEffortCreatesDecayingPostWorkoutLoad() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let wake = try XCTUnwrap(calendar.date(byAdding: .hour, value: 7, to: day))
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 6, to: wake))
        let baseline = try XCTUnwrap(StressBodyBatteryEngine.currentValue(
            stressPoints: [],
            fallbackStress: 30,
            recoveryScore: 85,
            wakeDate: wake,
            now: end,
            calendar: calendar
        ))
        let afterWorkout = try XCTUnwrap(StressBodyBatteryEngine.currentValue(
            stressPoints: [],
            fallbackStress: 30,
            recoveryScore: 85,
            wakeDate: wake,
            now: end,
            calendar: calendar,
            load: StressBodyBatteryLoadInput(
                physicalEffortSamples: [],
                workoutEffortEvents: [StressBodyBatteryWorkoutEffortEvent(
                    endedAt: wake,
                    durationMinutes: 60,
                    score: 9,
                    isEstimated: false
                )]
            )
        ))

        XCTAssertGreaterThan(baseline, afterWorkout)
    }

    @MainActor private func recoveryInput(
        respiratoryRate: Double,
        wristTemperature: Double,
        breathingDisturbances: Double,
        breathingDisturbanceBaseline: Double = 4
    ) -> StressBodyBatteryRecoveryInput {
        StressBodyBatteryRecoveryInput(
            sleepMinutes: 480,
            sleepGoalMinutes: 480,
            sleepScoreFallback: 90,
            sleepEfficiency: 0.92,
            deepSleepMinutes: 90,
            remSleepMinutes: 105,
            nightlyHrv: 55,
            baselineHrv: 50,
            overnightHeartRate: 55,
            baselineOvernightHeartRate: 57,
            restingHeartRate: nil,
            baselineRestingHeartRate: nil,
            nightlyRespiratoryRate: respiratoryRate,
            baselineNightlyRespiratoryRate: 15,
            sleepingWristTemperature: wristTemperature,
            baselineSleepingWristTemperature: 36.2,
            sleepingBreathingDisturbances: breathingDisturbances,
            baselineSleepingBreathingDisturbances: breathingDisturbanceBaseline
        )
    }
}
