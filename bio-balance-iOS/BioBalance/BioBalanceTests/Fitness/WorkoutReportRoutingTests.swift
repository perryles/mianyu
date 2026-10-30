import Foundation
import HealthKit
import Testing
@testable import BioBalance

struct WorkoutReportRoutingTests {
    @Test func validatesPoolLengthPresetsAndCustomValues() throws {
        #expect(SwimmingPoolLength.presets.map(\.displayTitle) == ["25 m", "50 m", "25 yd"])
        #expect(SwimmingPoolLength.meters25.metersValue == 25)
        #expect(SwimmingPoolLength.meters50.metersValue == 50)
        #expect(abs(SwimmingPoolLength.yards25.metersValue - 22.86) < 0.000_001)
        #expect(SwimmingPoolLength(value: 33.3, unit: .meters)?.metersValue == 33.3)
        #expect(SwimmingPoolLength(value: 0, unit: .meters) == nil)
        #expect(SwimmingPoolLength(value: .infinity, unit: .meters) == nil)
        #expect(SwimmingPoolLength(value: 500, unit: .meters) == nil)
    }

    @Test func buildsValidPoolAndOpenWaterSessionConfigurations() {
        let pool = SwimmingSessionConfiguration.pool(.meters25)
        #expect(pool.location == .pool)
        #expect(pool.poolLength == .meters25)
        #expect(pool.isPool)

        let openWater = SwimmingSessionConfiguration.openWater
        #expect(openWater.location == .openWater)
        #expect(openWater.poolLength == nil)
        #expect(!openWater.isPool)
    }

    @Test func restrictsWorkoutLifecycleToLegalTransitions() {
        #expect(SwimmingWorkoutLifecycle.canTransition(from: .idle, to: .preparing))
        #expect(SwimmingWorkoutLifecycle.canTransition(from: .preparing, to: .idle))
        #expect(SwimmingWorkoutLifecycle.canTransition(from: .running, to: .paused))
        #expect(SwimmingWorkoutLifecycle.canTransition(from: .paused, to: .ending))
        #expect(SwimmingWorkoutLifecycle.canTransition(from: .ending, to: .finished))
        #expect(!SwimmingWorkoutLifecycle.canTransition(from: .idle, to: .running))
        #expect(!SwimmingWorkoutLifecycle.canTransition(from: .finished, to: .running))
    }

    @Test func routesRecognizedWorkoutTitlesToDedicatedReports() {
        #expect(WorkoutReportKind.recognized(from: "户外跑步") == .running)
        #expect(WorkoutReportKind.recognized(from: "泳池游泳") == .swimming)
        #expect(WorkoutReportKind.recognized(from: "开放水域游泳") == .swimming)
        #expect(WorkoutReportKind.recognized(from: "游泳") == .swimming)
        #expect(WorkoutReportKind.recognized(from: "传统力量训练") == .strength)
        #expect(WorkoutReportKind.recognized(from: "户外骑行") == .cycling)
        #expect(WorkoutReportKind.recognized(from: "瑜伽") == .yoga)
        #expect(WorkoutReportKind.recognized(from: "太极") == .other)
    }

    @Test func calculatesPoolSwimmingMetricsOnlyFromAvailableMeasurements() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let report = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            location: .pool,
            poolLengthMeters: 25,
            distanceMeters: 100,
            strokeCount: 80,
            laps: (1...4).map {
                SwimmingLapReport(index: $0, duration: 30, distanceMeters: 25, stroke: .freestyle)
            }
        )

        #expect(try #require(report.averagePaceSecondsPer100Meters) == 120)
        // A workout-wide stroke total cannot be assigned evenly to individual laps.
        #expect(report.swolfScore == nil)
        #expect(report.dominantStroke == .freestyle)

        let lapMeasuredReport = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            location: .pool,
            poolLengthMeters: 25,
            distanceMeters: 100,
            strokeCount: 80,
            laps: (1...4).map {
                SwimmingLapReport(
                    index: $0,
                    duration: 30,
                    distanceMeters: 25,
                    stroke: .freestyle,
                    strokeCount: 20
                )
            }
        )
        #expect(lapMeasuredReport.swolfScore == 50)
        #expect(lapMeasuredReport.laps[0].paceSecondsPer100Meters == 120)

        let partialLapScores = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            location: .pool,
            poolLengthMeters: 25,
            distanceMeters: 100,
            strokeCount: 80,
            laps: [
                SwimmingLapReport(index: 1, duration: 30, distanceMeters: 25, stroke: .freestyle, strokeCount: 20),
                SwimmingLapReport(index: 2, duration: 30, distanceMeters: 25, stroke: .freestyle)
            ]
        )
        #expect(partialLapScores.swolfScore == nil)

        let healthKitScore = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(120),
            duration: 120,
            location: .pool,
            poolLengthMeters: 25,
            distanceMeters: 100,
            strokeCount: 80,
            activeEnergyKilocalories: 112,
            healthKitSWOLFScore: 46,
            laps: []
        )
        #expect(healthKitScore.swolfScore == 46)
        #expect(healthKitScore.activeEnergyKilocalories == 112)
    }

    @Test func attributesStrokeSamplesOnlyWhenTheyFitExactLaps() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let strokeType = try #require(HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount))
        func strokeSample(_ startOffset: TimeInterval, _ duration: TimeInterval, _ count: Double) -> HKQuantitySample {
            HKQuantitySample(
                type: strokeType,
                quantity: HKQuantity(unit: .count(), doubleValue: count),
                start: start.addingTimeInterval(startOffset),
                end: start.addingTimeInterval(startOffset + duration)
            )
        }

        let laps = [
            DateInterval(start: start, duration: 30),
            DateInterval(start: start.addingTimeInterval(30), duration: 30),
            DateInterval(start: start.addingTimeInterval(60), duration: 30)
        ]
        let exactSamples = [
            strokeSample(0, 30, 18),
            strokeSample(30, 30, 22),
            strokeSample(60, 30, 20)
        ]
        #expect(HealthKitManager.swimmingStrokeCounts(for: laps, in: exactSamples) == [18, 22, 20])

        let overlappingSamples = [
            strokeSample(0, 30, 18),
            strokeSample(30, 60, 42)
        ]
        #expect(HealthKitManager.swimmingStrokeCounts(for: laps, in: overlappingSamples) == [18, nil, nil])

        let invalidSamples = [strokeSample(0, 30, .nan)]
        #expect(HealthKitManager.swimmingStrokeCounts(for: laps, in: invalidSamples) == [nil, nil, nil])
        #expect(HealthKitManager.swimmingStrokeCounts(for: laps, in: []).allSatisfy { $0 == nil })
    }

    @Test func downsamplesHeartRateWhilePreservingEndpoints() {
        let samples: [(offset: TimeInterval, bpm: Double)] = (0..<1_000).map {
            (offset: TimeInterval($0), bpm: Double(100 + $0))
        }
        let downsampled = HealthKitManager.downsampleHeartRate(samples, maximumCount: 5)

        #expect(downsampled.map(\.offset) == [0, 250, 500, 750, 999])
        #expect(downsampled.map(\.bpm) == [100, 350, 600, 850, 1_099])
        #expect(HealthKitManager.downsampleHeartRate(samples, maximumCount: 1_000).map(\.offset) == samples.map(\.offset))
        #expect(HealthKitManager.downsampleHeartRate(samples, maximumCount: 1_000).map(\.bpm) == samples.map(\.bpm))
    }

    @Test func calculatesSharedSwimmingMetricsAndFormatting() {
        #expect(SwimmingMetricsCalculator.paceSecondsPer100Meters(duration: 300, distanceMeters: 1_000) == 30)
        #expect(SwimmingMetricsCalculator.paceSecondsPer100Meters(duration: 0, distanceMeters: 100) == nil)
        #expect(SwimmingMetricsCalculator.paceSecondsPer100Meters(duration: .infinity, distanceMeters: 100) == nil)

        #expect(SwimmingMetricsCalculator.strokesPerMinute(strokeCount: 150, duration: 300) == 30)
        #expect(SwimmingMetricsCalculator.strokesPerMinute(strokeCount: 0, duration: 300) == nil)
        #expect(SwimmingMetricsCalculator.strokesPerMinute(strokeCount: 10, duration: 0) == nil)

        #expect(SwimmingMetricsCalculator.durationText(59.9) == "00:59")
        #expect(SwimmingMetricsCalculator.durationText(3_723) == "1:02:03")
        #expect(SwimmingMetricsCalculator.durationText(-1) == nil)
        #expect(SwimmingMetricsCalculator.paceText(95.4) == "1:35")
        #expect(SwimmingMetricsCalculator.paceText(.nan) == nil)
    }

    @Test func usesRecordingDurationInsteadOfWallClockDurationForPace() {
        let start = Date(timeIntervalSince1970: 25_000)
        let report = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(600),
            duration: 300,
            location: .openWater,
            poolLengthMeters: nil,
            distanceMeters: 1_000,
            strokeCount: 300,
            laps: []
        )

        #expect(report.duration == 300)
        #expect(report.averagePaceSecondsPer100Meters == 30)
        #expect(report.strokesPerMinute == 60)
    }

    @Test func doesNotCalculateSwolfForOpenWaterOrMissingLaps() {
        let start = Date(timeIntervalSince1970: 20_000)
        let report = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(600),
            duration: 600,
            location: .openWater,
            poolLengthMeters: nil,
            distanceMeters: 500,
            strokeCount: 300,
            laps: []
        )

        #expect(report.averagePaceSecondsPer100Meters == 120)
        #expect(report.swolfScore == nil)
        #expect(report.dominantStroke == nil)

        let invalidDistanceReport = SwimmingWorkoutReport(
            workoutID: UUID(),
            startDate: start,
            endDate: start,
            duration: 0,
            location: .pool,
            poolLengthMeters: nil,
            distanceMeters: 0,
            strokeCount: 0,
            laps: [SwimmingLapReport(index: 1, duration: 0, distanceMeters: 0, stroke: .unknown, strokeCount: 0)]
        )
        #expect(invalidDistanceReport.averagePaceSecondsPer100Meters == nil)
        #expect(invalidDistanceReport.laps[0].paceSecondsPer100Meters == nil)
        #expect(invalidDistanceReport.swolfScore == nil)
    }

}
