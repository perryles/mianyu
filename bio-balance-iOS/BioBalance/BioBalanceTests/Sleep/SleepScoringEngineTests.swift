import XCTest
@testable import BioBalance

nonisolated final class SleepScoringEngineTests: XCTestCase {
    @MainActor private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor func testSummaryUsesInjectedClockAndIsDeterministic() {
        let interval = SleepInterval(
            start: now.addingTimeInterval(-8 * 3_600),
            end: now
        )
        let first = makeSummary(interval: interval, duration: 480)
        let second = makeSummary(interval: interval, duration: 480)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.insight.generatedAt, now)
        XCTAssertEqual(first.createdAt, now)
        XCTAssertEqual(first.updatedAt, now)
    }

    @MainActor func testSummaryUsesVersionThreeEvidenceAwareScore() {
        let summary = makeSummary(interval: nil, duration: 480)

        XCTAssertEqual(summary.analysisVersion, "sleep-scoring-3.3.0")
        XCTAssertEqual(summary.sleepScore, 97)
    }

    @MainActor func testHistoryBackedRegularityDistinguishesStableAndShiftedBedtimes() throws {
        let interval = SleepInterval(
            start: now.addingTimeInterval(-8 * 3_600),
            end: now
        )
        let stableHistory = try priorBedtimes(
            relativeTo: interval.start,
            minuteOffsets: [-10, 0, 10]
        )
        let shiftedHistory = try priorBedtimes(
            relativeTo: interval.start,
            minuteOffsets: [-190, -180, -170]
        )

        let stable = makeSummary(
            interval: interval,
            duration: 480,
            recentBedtimes: stableHistory
        )
        let shifted = makeSummary(
            interval: interval,
            duration: 480,
            recentBedtimes: shiftedHistory
        )

        XCTAssertGreaterThan(stable.sleepScore, shifted.sleepScore)
    }

    @MainActor func testValidSessionBoundsUseMeasuredEfficiencyInsteadOfFallbackContinuity() {
        let interval = SleepInterval(
            start: now.addingTimeInterval(-9 * 3_600),
            end: now
        )

        let summary = makeSummary(interval: interval, duration: 480)

        XCTAssertEqual(summary.sleepScore, 99)
    }

    @MainActor func testInvalidSessionBoundsFallBackToDerivedContinuity() {
        let interval = SleepInterval(
            start: now.addingTimeInterval(-7 * 3_600),
            end: now
        )

        let summary = makeSummary(interval: interval, duration: 480)

        XCTAssertEqual(summary.sleepScore, 97)
    }

    @MainActor func testInferredStagesNeverExceedShortSleepDuration() {
        let summary = makeSummary(interval: nil, duration: 30)
        let stages = summary.stageSummary
        let total = stages.deepSleepMinutesEstimated
            + stages.lightSleepMinutesEstimated
            + stages.remSleepMinutesEstimated

        XCTAssertEqual(total, 30, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(stages.deepSleepMinutesEstimated, 0)
        XCTAssertGreaterThanOrEqual(stages.lightSleepMinutesEstimated, 0)
        XCTAssertGreaterThanOrEqual(stages.remSleepMinutesEstimated, 0)
    }

    @MainActor func testZeroDurationProducesZeroStageDurations() {
        let summary = makeSummary(interval: nil, duration: -30)

        XCTAssertEqual(summary.sleepDurationMinutes, 0)
        XCTAssertEqual(summary.stageSummary.deepSleepMinutesEstimated, 0)
        XCTAssertEqual(summary.stageSummary.lightSleepMinutesEstimated, 0)
        XCTAssertEqual(summary.stageSummary.remSleepMinutesEstimated, 0)
    }

    @MainActor func testExistingStageSegmentsAreAggregatedAndNormalized() {
        let stages = [
            SleepStage(stage: "Deep", duration: 30),
            SleepStage(stage: "深睡", duration: 20),
            SleepStage(stage: "Core", duration: 80),
            SleepStage(stage: "REM", duration: 25),
            SleepStage(stage: "快速眼动", duration: 15),
            SleepStage(stage: "Deep", duration: -10)
        ]
        let summary = makeSummary(interval: nil, duration: 180, stages: stages)

        XCTAssertEqual(summary.stageSummary.deepSleepMinutesEstimated, 50, accuracy: 0.001)
        XCTAssertEqual(summary.stageSummary.remSleepMinutesEstimated, 40, accuracy: 0.001)
        XCTAssertEqual(summary.stageSummary.lightSleepMinutesEstimated, 90, accuracy: 0.001)
    }

    @MainActor func testNegativeWakeCountIsClamped() {
        let summary = makeSummary(interval: nil, duration: 480, awakeCount: -4)

        XCTAssertEqual(summary.stageSummary.wakeCount, 0)
        XCTAssertEqual(summary.stageSummary.continuityScore, 94)
    }

    @MainActor private func makeSummary(
        interval: SleepInterval?,
        duration: Int,
        stages: [SleepStage] = [],
        awakeCount: Int = 0,
        recentBedtimes: [Date] = []
    ) -> SleepSessionSummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return SleepScoringEngine().makeSummary(
            sleepInterval: interval,
            sleepDurationMinutes: duration,
            watchConfidence: 0.8,
            existingStages: stages,
            nightlyHrv: nil,
            awakeCount: awakeCount,
            snoreSummary: .empty,
            source: .manual,
            recentBedtimes: recentBedtimes,
            sleepGoalMinutes: 480,
            now: now,
            calendar: calendar
        )
    }

    @MainActor private func priorBedtimes(
        relativeTo current: Date,
        minuteOffsets: [Int]
    ) throws -> [Date] {
        try minuteOffsets.enumerated().map { index, offset in
            try XCTUnwrap(
                Calendar(identifier: .gregorian).date(
                    byAdding: .minute,
                    value: offset - ((index + 1) * 24 * 60),
                    to: current
                )
            )
        }
    }
}
