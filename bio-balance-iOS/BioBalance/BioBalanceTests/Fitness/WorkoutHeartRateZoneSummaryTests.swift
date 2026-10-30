import Testing
import HealthKit
@testable import BioBalance

struct WorkoutHeartRateZoneSummaryTests {
    @Test func calculatesTotalAndDominantZone() {
        let summary = WorkoutZoneSummary(
            metric: .heartRate,
            source: .system,
            zones: [
                WorkoutZone(index: 1, duration: 120, minimumValue: nil, maximumValue: 120),
                WorkoutZone(index: 2, duration: 480, minimumValue: 120, maximumValue: 140),
                WorkoutZone(index: 3, duration: 300, minimumValue: 140, maximumValue: 160)
            ]
        )

        #expect(summary.totalDuration == 900)
        #expect(summary.dominantZone?.index == 2)
    }

    @Test func ignoresNegativeDurationInTotal() {
        let summary = WorkoutZoneSummary(
            metric: .heartRate,
            source: .user,
            zones: [WorkoutZone(index: 1, duration: -10, minimumValue: nil, maximumValue: 120)]
        )

        #expect(summary.totalDuration == 0)
    }

    @Test func prefersHigherZoneWhenDurationsTie() {
        let summary = WorkoutZoneSummary(
            metric: .cyclingPower,
            source: .app,
            zones: [
                WorkoutZone(index: 2, duration: 300, minimumValue: 120, maximumValue: 140),
                WorkoutZone(index: 3, duration: 300, minimumValue: 140, maximumValue: 160)
            ]
        )

        #expect(summary.dominantZone?.index == 3)
    }

    @Test func excludesMindAndBodySessionsFromFitnessReviews() {
        #expect(!HealthKitManager.isFitnessWorkoutActivity(.mindAndBody))
        #expect(HealthKitManager.isFitnessWorkoutActivity(.running))
        #expect(HealthKitManager.isFitnessWorkoutActivity(.traditionalStrengthTraining))
    }
}
