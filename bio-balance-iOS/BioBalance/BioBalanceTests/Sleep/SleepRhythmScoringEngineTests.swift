import XCTest
@testable import BioBalance

nonisolated final class SleepRhythmScoringEngineTests: XCTestCase {
    @MainActor private let engine = SleepRhythmScoringEngine()

    @MainActor func testMissingDurationCannotProduceCompositeScore() {
        let result = engine.evaluate(
            SleepRhythmScoreInput(
                durationMinutes: nil,
                goalMinutes: 480,
                fallbackContinuityScore: 90
            )
        )

        XCTAssertNil(result.score)
        XCTAssertEqual(result.confidence, 0, accuracy: 0.0001)
        XCTAssertTrue(result.components.isEmpty)
    }

    @MainActor func testDurationAloneDoesNotMeetMinimumEvidenceContract() {
        let result = engine.evaluate(
            SleepRhythmScoreInput(durationMinutes: 480, goalMinutes: 480)
        )

        XCTAssertNil(result.score)
        XCTAssertEqual(result.confidence, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.components.map(\.kind), [.duration])
    }

    @MainActor func testMissingDimensionsAreRemovedAndAvailableWeightsAreRenormalized() {
        let result = engine.evaluate(
            SleepRhythmScoreInput(
                durationMinutes: 480,
                goalMinutes: 480,
                fallbackContinuityScore: 80
            )
        )

        XCTAssertEqual(result.score, 90)
        XCTAssertEqual(result.confidence, 0.4125, accuracy: 0.0001)
        XCTAssertEqual(result.components.map(\.kind), [.duration, .continuity])
    }

    @MainActor func testInferredStageDistributionDoesNotContributeToScore() {
        let result = engine.evaluate(
            SleepRhythmScoreInput(
                durationMinutes: 480,
                goalMinutes: 480,
                fallbackContinuityScore: 80,
                deepSleepMinutes: 105.6,
                remSleepMinutes: 115.2,
                stageEvidence: .inferred
            )
        )

        XCTAssertEqual(result.score, 90)
        XCTAssertFalse(result.components.contains { $0.kind == .stageDistribution })
    }

    @MainActor func testCompleteMeasuredEvidenceProducesBoundedTransparentScore() throws {
        let result = engine.evaluate(
            SleepRhythmScoreInput(
                durationMinutes: 480,
                goalMinutes: 480,
                timeInBedMinutes: 540,
                wakeAfterSleepOnsetMinutes: 30,
                sleepLatencyMinutes: 20,
                deepSleepMinutes: 96,
                remSleepMinutes: 110.4,
                stageEvidence: .measured,
                bedtimeDeviationMinutes: 30,
                disturbanceScore: 10
            )
        )

        XCTAssertEqual(result.score, 96)
        XCTAssertEqual(result.confidence, 1, accuracy: 0.0001)
        XCTAssertEqual(
            result.components.map(\.kind),
            [.duration, .continuity, .latency, .stageDistribution, .regularity, .disturbance]
        )
        XCTAssertTrue(result.components.allSatisfy { (0...100).contains($0.score) })
    }

    @MainActor func testInvalidOptionalMetricsAreOmittedInsteadOfClampedIntoEvidence() {
        let result = engine.evaluate(
            SleepRhythmScoreInput(
                durationMinutes: 420,
                goalMinutes: 480,
                fallbackContinuityScore: 75,
                sleepLatencyMinutes: -1,
                deepSleepMinutes: .nan,
                remSleepMinutes: 80,
                stageEvidence: .measured,
                bedtimeDeviationMinutes: -.infinity,
                disturbanceScore: 120
            )
        )

        XCTAssertNotNil(result.score)
        XCTAssertEqual(result.components.map(\.kind), [.duration, .continuity])
        XCTAssertTrue((0...100).contains(result.score ?? -1))
    }

    @MainActor func testHistoryDerivedRegularityUsesDerivedConfidence() throws {
        let result = engine.evaluate(
            SleepRhythmScoreInput(
                durationMinutes: 480,
                goalMinutes: 480,
                fallbackContinuityScore: 80,
                bedtimeDeviationMinutes: 20,
                regularityEvidence: .derived
            )
        )

        let regularity = try XCTUnwrap(
            result.components.first { $0.kind == .regularity }
        )
        XCTAssertEqual(regularity.evidence, .derived)
        XCTAssertEqual(result.confidence, 0.5425, accuracy: 0.0001)
    }
}
