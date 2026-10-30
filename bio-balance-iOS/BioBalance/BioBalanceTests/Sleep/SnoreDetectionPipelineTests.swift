import XCTest
@testable import BioBalance

nonisolated final class SnoreDetectionPipelineTests: XCTestCase {
    @MainActor private let pipeline = SnoreDetectionPipeline()
    @MainActor private let sessionStart = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor func testAdjacentActiveWindowsMergeUsingMeasuredTimestamps() throws {
        let results = [
            result(offset: 10, rms: 0.04),
            result(offset: 11, rms: 0.05)
        ]

        let summary = analyze(results)
        let segment = try XCTUnwrap(summary.segments.first)

        XCTAssertTrue(summary.snoreDetected)
        XCTAssertEqual(summary.segments.count, 1)
        XCTAssertEqual(segment.segmentStart, sessionStart.addingTimeInterval(10))
        XCTAssertEqual(segment.segmentEnd, sessionStart.addingTimeInterval(12))
        XCTAssertEqual(segment.durationSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(summary.snoreDurationMinutes, 2.0 / 60.0, accuracy: 0.001)
    }

    @MainActor func testSingleLoudImpulseIsRejectedAsInsufficientEventEvidence() {
        let summary = analyze([result(offset: 10, rms: 0.08)])

        XCTAssertEqual(summary, .empty)
    }

    @MainActor func testShortGapMergesEventsWithoutInflatingDirectEvidenceDuration() throws {
        let summary = analyze([
            result(offset: 10, rms: 0.04),
            result(offset: 14, rms: 0.05)
        ])
        let segment = try XCTUnwrap(summary.segments.first)

        XCTAssertEqual(summary.segments.count, 1)
        XCTAssertEqual(segment.segmentStart, sessionStart.addingTimeInterval(10))
        XCTAssertEqual(segment.segmentEnd, sessionStart.addingTimeInterval(15))
        XCTAssertEqual(segment.durationSeconds, 2, accuracy: 0.001)
    }

    @MainActor func testSpeechLikeWindowsAreExcludedEvenWhenLoud() {
        let summary = analyze([
            result(offset: 10, rms: 0.08, activity: .speechLike),
            result(offset: 11, rms: 0.08, activity: .speechLike)
        ], wakeCount: 6)

        XCTAssertEqual(summary, .empty)
    }

    @MainActor func testSeparatedCandidateRunsCreateSeparateMeasuredSegmentsAndBuckets() {
        let results = [
            result(offset: 10, rms: 0.04),
            result(offset: 11, rms: 0.05),
            result(offset: 7_210, rms: 0.05),
            result(offset: 7_211, rms: 0.06)
        ]

        let summary = analyze(results)

        XCTAssertEqual(summary.segments.count, 2)
        XCTAssertEqual(summary.segments[0].segmentStart, sessionStart.addingTimeInterval(10))
        XCTAssertEqual(summary.segments[1].segmentStart, sessionStart.addingTimeInterval(7_210))
        XCTAssertEqual(summary.histogram, [1, 1, 0, 0, 0, 0])
        XCTAssertEqual(summary.snoreFrequencyPerHour, 0.25, accuracy: 0.001)
    }

    @MainActor func testNoQualifyingAudioEvidenceReturnsEmptyRegardlessOfWakeCount() {
        let summary = analyze([
            result(offset: 10, rms: 0.001, activity: .quiet),
            result(offset: 11, rms: 0.04, activity: .steadyNoise)
        ], wakeCount: 8)

        XCTAssertEqual(summary, .empty)
    }

    @MainActor func testEmptyInferenceResultsReturnEmpty() {
        XCTAssertEqual(analyze([], wakeCount: 8), .empty)
    }

    @MainActor func testInvalidAndOutOfSessionWindowsAreRejected() {
        let summary = analyze([
            result(offset: -10, rms: 0.08),
            result(offset: -9, rms: 0.08),
            result(offset: 10, rms: .nan),
            result(offset: 11, rms: .infinity)
        ])

        XCTAssertEqual(summary, .empty)
    }

    @MainActor func testLowFrequencyVoicedSoundRemainsEligibleForSnoreDetection() {
        let sampleRate = 16_000.0
        let samples = (0..<16_000).map { index in
            Float(sin(2 * Double.pi * 120 * Double(index) / sampleRate) * 0.05)
        }

        let activity = BaselineSleepAudioInferenceProvider().classify(samples: samples)

        XCTAssertEqual(activity, .active)
    }

    @MainActor func testExtremelyLowFrequencyHumRemainsSteadyNoise() {
        let sampleRate = 16_000.0
        let samples = (0..<16_000).map { index in
            Float(sin(2 * Double.pi * 20 * Double(index) / sampleRate) * 0.05)
        }

        let activity = BaselineSleepAudioInferenceProvider().classify(samples: samples)

        XCTAssertEqual(activity, .steadyNoise)
    }

    @MainActor private func analyze(
        _ results: [SleepAudioInferenceResult],
        wakeCount: Int = 0
    ) -> SnoreAnalysisSummary {
        pipeline.analyze(
            inferenceResults: results,
            durationHours: 8,
            stageSummary: SleepStageInferenceSummary(
                deepSleepMinutesEstimated: 100,
                lightSleepMinutesEstimated: 260,
                remSleepMinutesEstimated: 100,
                wakeCount: wakeCount,
                sleepLatencyMinutes: 15,
                continuityScore: 90
            ),
            interval: SleepInterval(
                start: sessionStart,
                end: sessionStart.addingTimeInterval(8 * 3_600)
            )
        )
    }

    @MainActor private func result(
        offset: TimeInterval,
        duration: TimeInterval = 1,
        rms: Double,
        activity: SleepAudioActivity = .active
    ) -> SleepAudioInferenceResult {
        SleepAudioInferenceResult(
            startDate: sessionStart.addingTimeInterval(offset),
            durationSeconds: duration,
            rootMeanSquare: rms,
            decibelsFullScale: 20 * log10(max(rms, 0.000_01)),
            zeroCrossingRate: 0.04,
            activity: activity,
            providerName: "test"
        )
    }
}
