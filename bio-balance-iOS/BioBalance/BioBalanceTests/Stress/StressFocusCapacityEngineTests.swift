import XCTest
@testable import BioBalance

nonisolated final class StressFocusCapacityEngineTests: XCTestCase {
    @MainActor func testZeroFilledSleepPlaceholderIsTreatedAsMissingEvidence() throws {
        let evidence = StressFocusCapacitySleepAdapter.evidence(
            durationMinutes: 0,
            score: 0
        )
        let withoutSleepEvidence = StressFocusCapacityEngine.evaluate(
            input: makeInput(stress: 20, battery: 80)
        )
        let withPlaceholder = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 20,
            battery: 80,
            sleepMinutes: evidence.minutes,
            sleepScore: evidence.score
        ))

        XCTAssertNil(evidence.minutes)
        XCTAssertNil(evidence.score)
        XCTAssertNil(withPlaceholder.sleepReadiness)
        XCTAssertEqual(withPlaceholder.score, withoutSleepEvidence.score)
        XCTAssertEqual(withPlaceholder.availableDimensionCount, withoutSleepEvidence.availableDimensionCount)
        XCTAssertGreaterThan(try XCTUnwrap(withPlaceholder.score), 0)
    }

    @MainActor func testMeasuredZeroSleepScoreRemainsEvidenceWhenDurationExists() throws {
        let evidence = StressFocusCapacitySleepAdapter.evidence(
            durationMinutes: 480,
            score: 0
        )
        let measuredZero = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 20,
            battery: 80,
            sleepMinutes: evidence.minutes,
            sleepScore: evidence.score
        ))
        let durationOnly = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 20,
            battery: 80,
            sleepMinutes: 480
        ))

        XCTAssertEqual(evidence.minutes, 480)
        XCTAssertEqual(evidence.score, 0)
        XCTAssertEqual(measuredZero.sleepReadiness, 45)
        XCTAssertLessThan(
            try XCTUnwrap(measuredZero.sleepReadiness),
            try XCTUnwrap(durationOnly.sleepReadiness)
        )
    }

    @MainActor func testMeasuredZeroSleepScoreIsNotTreatedAsMissing() throws {
        let withoutSleepEvidence = StressFocusCapacityEngine.evaluate(
            input: makeInput(stress: 20, battery: 80)
        )
        let measuredZeroSleep = StressFocusCapacityEngine.evaluate(
            input: makeInput(stress: 20, battery: 80, sleepScore: 0)
        )

        XCTAssertNil(withoutSleepEvidence.sleepReadiness)
        XCTAssertEqual(measuredZeroSleep.sleepReadiness, 0)
        XCTAssertEqual(measuredZeroSleep.score, 0)
        XCTAssertGreaterThan(measuredZeroSleep.availableDimensionCount, withoutSleepEvidence.availableDimensionCount)
    }

    @MainActor func testZeroWaterIntakeProducesLowReadinessInsteadOfMissingEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let assessment = StressFocusCapacityEngine.evaluate(input: StressFocusCapacityInput(
            now: now,
            stressScore: 20,
            bodyBatteryScore: 80,
            stressConfidence: 0.8,
            stressQuality: .high,
            wakeDate: now.addingTimeInterval(-8 * 3_600),
            waterIntakeMl: 0,
            waterTargetMl: 2_000
        ))

        XCTAssertEqual(assessment.hydrationReadiness, 45)
        XCTAssertEqual(assessment.availableDimensionCount, 4)
    }

    @MainActor private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor func testHigherStressReducesFocusCapacityNonlinearly() throws {
        let lowStress = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 20, battery: nil))
        let moderateStress = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 50, battery: nil))
        let highStress = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 85, battery: nil))

        XCTAssertGreaterThan(try XCTUnwrap(lowStress.score), try XCTUnwrap(moderateStress.score))
        XCTAssertGreaterThan(try XCTUnwrap(moderateStress.score), try XCTUnwrap(highStress.score))
        XCTAssertLessThan(try XCTUnwrap(highStress.score), 30)
    }

    @MainActor func testLowBodyBatteryLimitsOtherwiseStrongStressHeadroom() throws {
        let recovered = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 20, battery: 90))
        let depleted = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 20, battery: 20))

        XCTAssertGreaterThan(try XCTUnwrap(recovered.score), try XCTUnwrap(depleted.score))
        XCTAssertLessThan(try XCTUnwrap(depleted.score), 60)
    }

    @MainActor func testMissingStressDoesNotProduceFocusCapacity() {
        let assessment = StressFocusCapacityEngine.evaluate(input: makeInput(stress: nil, battery: 80))

        XCTAssertNil(assessment.score)
        XCTAssertEqual(assessment.band, .unavailable)
    }

    @MainActor func testScoresAreClampedForOutOfRangeInputs() {
        let low = StressFocusCapacityEngine.evaluate(input: makeInput(stress: -20, battery: 120))
        let high = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 140, battery: -10))

        XCTAssertEqual(low.score, 100)
        XCTAssertEqual(high.score, 0)
    }

    @MainActor func testFocusCapacityBandsUse805530Boundaries() {
        XCTAssertEqual(StressFocusCapacityEngine.band(for: 80), .strong)
        XCTAssertEqual(StressFocusCapacityEngine.band(for: 79), .available)
        XCTAssertEqual(StressFocusCapacityEngine.band(for: 55), .available)
        XCTAssertEqual(StressFocusCapacityEngine.band(for: 54), .limited)
        XCTAssertEqual(StressFocusCapacityEngine.band(for: 30), .limited)
        XCTAssertEqual(StressFocusCapacityEngine.band(for: 29), .depleted)
    }

    @MainActor func testSleepReadinessChangesFocusCapacity() throws {
        let recovered = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            sleepMinutes: 480,
            sleepScore: 92
        ))
        let sleepRestricted = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            sleepMinutes: 240,
            sleepScore: 45
        ))

        XCTAssertGreaterThan(try XCTUnwrap(recovered.score), try XCTUnwrap(sleepRestricted.score))
        XCTAssertGreaterThan(try XCTUnwrap(recovered.sleepReadiness), try XCTUnwrap(sleepRestricted.sleepReadiness))
    }

    @MainActor func testLateCircadianWindowReducesFocusCapacity() throws {
        let daytime = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            wakeDate: now.addingTimeInterval(-3 * 3_600)
        ))
        let late = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            wakeDate: now.addingTimeInterval(-18 * 3_600)
        ))

        XCTAssertGreaterThan(try XCTUnwrap(daytime.score), try XCTUnwrap(late.score))
        XCTAssertGreaterThan(try XCTUnwrap(daytime.circadianReadiness), try XCTUnwrap(late.circadianReadiness))
    }

    @MainActor func testLongSedentaryPeriodReducesMovementReadiness() throws {
        let recentlyActive = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 30, battery: 70, sedentaryMinutes: 10))
        let prolonged = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 30, battery: 70, sedentaryMinutes: 150))

        XCTAssertGreaterThan(try XCTUnwrap(recentlyActive.score), try XCTUnwrap(prolonged.score))
        XCTAssertGreaterThan(try XCTUnwrap(recentlyActive.movementReadiness), try XCTUnwrap(prolonged.movementReadiness))
    }

    @MainActor func testHydrationUsesProgressRelativeToTimeSinceWake() throws {
        let wakeDate = now.addingTimeInterval(-8 * 3_600)
        let onPace = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            wakeDate: wakeDate,
            waterIntakeMl: 1_000
        ))
        let behindPace = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            wakeDate: wakeDate,
            waterIntakeMl: 250
        ))

        XCTAssertGreaterThan(try XCTUnwrap(onPace.hydrationReadiness), try XCTUnwrap(behindPace.hydrationReadiness))
        XCTAssertGreaterThan(try XCTUnwrap(onPace.score), try XCTUnwrap(behindPace.score))
    }

    @MainActor func testMoreAvailableDimensionsIncreaseConfidence() throws {
        let sparse = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 30, battery: nil))
        let complete = StressFocusCapacityEngine.evaluate(input: makeInput(
            stress: 30,
            battery: 70,
            sleepMinutes: 480,
            sleepScore: 90,
            wakeDate: now.addingTimeInterval(-4 * 3_600),
            sedentaryMinutes: 15,
            waterIntakeMl: 500
        ))

        XCTAssertGreaterThan(try XCTUnwrap(complete.confidence), try XCTUnwrap(sparse.confidence))
        XCTAssertEqual(complete.availableDimensionCount, 6)
    }

    @MainActor func testTrendSnapshotPrecomputesTodayStatistics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = calendar.startOfDay(for: now)
        let assessment = StressFocusCapacityEngine.evaluate(input: makeInput(stress: 50, battery: nil))
        let snapshot = StressFocusCapacityTrendSnapshot(
            assessment: assessment,
            stressPoints: [
                TimeSeriesPoint(timestamp: Int64(dayStart.addingTimeInterval(-3_600).timeIntervalSince1970), value: 50),
                TimeSeriesPoint(timestamp: Int64(dayStart.addingTimeInterval(8 * 3_600).timeIntervalSince1970), value: 0),
                TimeSeriesPoint(timestamp: Int64(dayStart.addingTimeInterval(9 * 3_600).timeIntervalSince1970), value: 100)
            ],
            now: dayStart.addingTimeInterval(12 * 3_600),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.points.count, 3)
        XCTAssertEqual(snapshot.averageValue, 54)
        XCTAssertEqual(snapshot.peakPoint?.value, 100)
        XCTAssertEqual(snapshot.lowPoint?.value, 0)
        XCTAssertEqual(snapshot.highRangeSampleCount, 1)
        XCTAssertEqual(snapshot.midRangeSampleCount, 1)
        XCTAssertEqual(snapshot.lowRangeSampleCount, 1)
    }

    @MainActor private func makeInput(
        stress: Int?,
        battery: Int?,
        sleepMinutes: Int? = nil,
        sleepScore: Int? = nil,
        wakeDate: Date? = nil,
        sedentaryMinutes: Int? = nil,
        waterIntakeMl: Int? = nil
    ) -> StressFocusCapacityInput {
        StressFocusCapacityInput(
            now: now,
            stressScore: stress,
            bodyBatteryScore: battery,
            stressConfidence: 0.8,
            stressQuality: .high,
            sleepMinutes: sleepMinutes,
            sleepGoalMinutes: sleepMinutes == nil ? nil : 480,
            sleepScore: sleepScore,
            wakeDate: wakeDate,
            sedentaryMinutes: sedentaryMinutes,
            waterIntakeMl: waterIntakeMl,
            waterTargetMl: waterIntakeMl == nil ? nil : 2_000
        )
    }
}
