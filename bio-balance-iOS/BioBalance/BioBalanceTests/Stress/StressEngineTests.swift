import Foundation
import XCTest
@testable import BioBalance

nonisolated final class StressEngineTests: XCTestCase {
    @MainActor private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor func testNoSignalDoesNotReturnFallbackScore() {
        let evaluation = StressRealtimeEngine().evaluate(
            input: makeInput(heartRate: nil, hrv: nil),
            previous: nil
        )
        XCTAssertEqual(evaluation, .unavailable(.noPhysiologicalSignal))
    }

    @MainActor func testFreshSignalWithoutMatchingBaselineIsUnavailable() {
        let evaluation = StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: StressMetricSample(value: 76, measuredAt: now),
                hrv: nil,
                restingBaseline: StressBaseline(value: nil, sampleCount: 0, minimumSampleCount: 4, trustedSampleCount: 14)
            ),
            previous: nil
        )
        XCTAssertEqual(evaluation, .unavailable(.baselineCalibrating))
    }

    @MainActor func testHeartRateOlderThanTenMinutesIsUnavailable() {
        let evaluation = StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: StressMetricSample(value: 76, measuredAt: now.addingTimeInterval(-601)),
                hrv: nil
            ),
            previous: nil
        )
        XCTAssertEqual(evaluation, .unavailable(.staleHeartRate))
    }

    @MainActor func testHrvExpiresAfterFourHours() {
        let evaluation = StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: nil,
                hrv: StressMetricSample(value: 45, measuredAt: now.addingTimeInterval(-(4 * 60 * 60 + 1)))
            ),
            previous: nil
        )
        XCTAssertEqual(evaluation, .unavailable(.staleHrv))
    }

    @MainActor func testEMAProducesValueBetweenPreviousAndNewRawScore() throws {
        let engine = StressRealtimeEngine()
        let previous = try XCTUnwrap(engine.evaluate(
            input: makeInput(heartRate: StressMetricSample(value: 105, measuredAt: now), hrv: nil),
            previous: nil
        ).result)
        let next = try XCTUnwrap(engine.evaluate(
            input: makeInput(heartRate: StressMetricSample(value: 62, measuredAt: now.addingTimeInterval(60)), hrv: nil),
            previous: previous
        ).result)

        XCTAssertNotEqual(next.smoothedScore, next.rawScore)
        XCTAssertGreaterThanOrEqual(next.smoothedScore, min(previous.smoothedScore, next.rawScore))
        XCTAssertLessThanOrEqual(next.smoothedScore, max(previous.smoothedScore, next.rawScore))
    }

    @MainActor func testInactiveWorkoutWithZeroBlendDoesNotBecomeDominant() throws {
        let result = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: StressMetricSample(value: 78, measuredAt: now),
                hrv: nil,
                workout: .inactive
            ),
            previous: nil
        ).result)
        XCTAssertFalse(result.dominantDrivers.contains(.workoutLoad))
        XCTAssertEqual(result.workout.workoutBlend, 0)
    }

    @MainActor func testUnavailableRecoveryDataDoesNotBecomeDominantOrDriveExplanation() throws {
        let result = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: StressMetricSample(value: 62, measuredAt: now),
                hrv: nil
            ),
            previous: nil
        ).result)

        XCTAssertFalse(result.dominantDrivers.contains(.recoveryDebt))
        XCTAssertNotEqual(result.explanationCode, .recoveryDebtElevated)
    }

    @MainActor func testProtectiveSignalDoesNotProduceElevatedDriverAdvice() throws {
        let result = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: nil,
                hrv: StressMetricSample(value: 65, measuredAt: now)
            ),
            previous: nil
        ).result)

        XCTAssertFalse(result.dominantDrivers.contains(.hrvDeviation))
        XCTAssertEqual(result.explanationCode, .stablePhysiology)
    }

    @MainActor func testRecoveryConfidenceReflectsAvailableDataCompleteness() throws {
        let signal = StressMetricSample(value: 78, measuredAt: now)
        let withoutRecovery = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(heartRate: signal, hrv: nil),
            previous: nil
        ).result)
        let withPartialRecovery = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(heartRate: signal, hrv: nil, sleepMinutes: 420),
            previous: nil
        ).result)
        let withFullRecovery = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: signal,
                hrv: nil,
                sleepMinutes: 420,
                sleepEfficiency: 0.9,
                nightlyHrv: 50,
                overnightMinHeartRate: 58
            ),
            previous: nil
        ).result)

        XCTAssertGreaterThan(withPartialRecovery.confidence, withoutRecovery.confidence)
        XCTAssertGreaterThan(withFullRecovery.confidence, withPartialRecovery.confidence)
    }

    @MainActor func testHeartRateOnlyCanReachHighStressWithoutHrv() throws {
        let result = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: StressMetricSample(value: 92, measuredAt: now),
                hrv: nil,
                restingBaseline: StressBaseline(value: 60, sampleCount: 14, minimumSampleCount: 4, trustedSampleCount: 14)
            ),
            previous: nil
        ).result)

        XCTAssertGreaterThanOrEqual(result.score, 70)
        XCTAssertFalse(result.dominantDrivers.contains(.hrvDeviation))
    }

    @MainActor func testHeartRateTrendCanEvaluateWithoutHrvOrRestingBaseline() throws {
        let current = StressMetricSample(value: 90, measuredAt: now)
        let prior = StressMetricSample(value: 62, measuredAt: now.addingTimeInterval(-20 * 60))
        let result = try XCTUnwrap(StressRealtimeEngine().evaluate(
            input: makeInput(
                heartRate: current,
                hrv: nil,
                restingBaseline: StressBaseline(value: nil, sampleCount: 0, minimumSampleCount: 4, trustedSampleCount: 14),
                heartRatePoints30m: [prior, current]
            ),
            previous: nil
        ).result)

        XCTAssertGreaterThanOrEqual(result.score, 70)
        XCTAssertEqual(result.dominantDriver, .hrTrend)
        XCTAssertFalse(result.dominantDrivers.contains(.hrvDeviation))
    }

    @MainActor func testHistoricalHeartRateOnlyEstimateDoesNotAddNeutralHrv() {
        XCTAssertEqual(
            StressDailyEngine.instantaneousStress(
                hrv: 0,
                heartRate: 90,
                restingHeartRate: 60
            ),
            100
        )
    }

    @MainActor func testHistoricalHeartRateWithoutBaselineOrTrendDoesNotInventDefault() {
        XCTAssertEqual(
            StressDailyEngine.instantaneousStress(
                hrv: 0,
                heartRate: 90,
                restingHeartRate: nil
            ),
            0
        )
    }

    @MainActor private func makeInput(
        heartRate: StressMetricSample?,
        hrv: StressMetricSample?,
        restingBaseline: StressBaseline = StressBaseline(value: 62, sampleCount: 14, minimumSampleCount: 4, trustedSampleCount: 14),
        hrvBaseline: StressBaseline = StressBaseline(value: 50, sampleCount: 14, minimumSampleCount: 4, trustedSampleCount: 14),
        workout: StressWorkoutContext = .inactive,
        sleepMinutes: Int? = nil,
        sleepEfficiency: Double? = nil,
        nightlyHrv: Double? = nil,
        overnightMinHeartRate: Double? = nil,
        heartRatePoints30m: [StressMetricSample]? = nil
    ) -> StressRealtimeInput {
        StressRealtimeInput(
            now: now,
            heartRate: heartRate,
            hrv: hrv,
            restingHeartRate: restingBaseline.value,
            restingHeartRateBaseline: restingBaseline,
            hrvBaseline: hrvBaseline,
            hrvPoints30m: hrv.map { [$0] } ?? [],
            heartRatePoints30m: heartRatePoints30m ?? (heartRate.map { [$0] } ?? []),
            sleepInterval: nil,
            sleepMinutes: sleepMinutes,
            sleepEfficiency: sleepEfficiency,
            nightlyHrv: nightlyHrv,
            overnightMinHeartRate: overnightMinHeartRate,
            workout: workout,
            chronologicalAge: 30,
            habitualSleepWindow: .fallback
        )
    }
}

nonisolated final class StressDailyEngineTests: XCTestCase {
    @MainActor private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor func testRequiresFourBucketsAndThirtyMinuteSpan() {
        let samples = [0, 10, 20].map { sample(minutes: $0, score: 40) }
        XCTAssertEqual(
            StressDailyEngine.evaluate(input: StressDailyInput(now: day, samples: samples)),
            .unavailable(.insufficientDailyCoverage)
        )
    }

    @MainActor func testDuplicateSamplingInOneBucketDoesNotChangeDailyScore() throws {
        let sparse = [0, 10, 20, 30].map { sample(minutes: $0, score: 40) }
        let dense = sparse + (1...20).map { sample(minutes: 10, seconds: $0, score: 40) }
        let sparseResult = try XCTUnwrap(StressDailyEngine.evaluate(input: .init(now: day, samples: sparse)).result)
        let denseResult = try XCTUnwrap(StressDailyEngine.evaluate(input: .init(now: day, samples: dense)).result)
        XCTAssertEqual(sparseResult.score, denseResult.score)
    }

    @MainActor func testSinglePeakDoesNotDominateDailyAggregate() throws {
        let samples = [
            sample(minutes: 0, score: 40),
            sample(minutes: 10, score: 40),
            sample(minutes: 20, score: 40),
            sample(minutes: 30, score: 40),
            sample(minutes: 40, score: 100)
        ]
        let result = try XCTUnwrap(StressDailyEngine.evaluate(input: .init(now: day, samples: samples)).result)
        XCTAssertLessThan(result.score, 70)
    }

    @MainActor func testLegacyAlgorithmSamplesAreExcluded() {
        let legacy = [0, 10, 20, 30].map { sample(minutes: $0, score: 40, version: "2.0") }
        XCTAssertEqual(
            StressDailyEngine.evaluate(input: .init(now: day, samples: legacy)),
            .unavailable(.noDailySamples)
        )
    }

    @MainActor func testReconstructedSamplesAreExcludedFromDailyTruth() {
        let reconstructed = [0, 10, 20, 30].map {
            sample(minutes: $0, score: 50, source: .reconstructed)
        }
        XCTAssertEqual(
            StressDailyEngine.evaluate(input: .init(now: day, samples: reconstructed)),
            .unavailable(.noDailySamples)
        )
    }

    @MainActor func testSustainedRealtimeHighStressReachesHighBand() throws {
        let samples = [0, 10, 20, 30, 40].map { sample(minutes: $0, score: 88) }
        let result = try XCTUnwrap(StressDailyEngine.evaluate(input: .init(now: day, samples: samples)).result)

        XCTAssertGreaterThanOrEqual(result.score, 85)
        XCTAssertEqual(result.band, .high)
    }

    @MainActor private func sample(
        minutes: Int,
        seconds: Int = 0,
        score: Int,
        version: String = StressResult.currentAlgorithmVersion,
        source: StressDailySampleSource = .realtime
    ) -> StressDailySample {
        let start = Calendar.current.startOfDay(for: day)
        return StressDailySample(
            timestamp: Int64(start.addingTimeInterval(TimeInterval(minutes * 60 + seconds)).timeIntervalSince1970),
            score: score,
            confidence: 0.8,
            quality: .high,
            algorithmVersion: version,
            source: source,
            dominantDriver: .hrDeviation
        )
    }
}
