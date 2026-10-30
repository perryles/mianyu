import XCTest
@testable import BioBalance

nonisolated final class SleepTemporalEvidenceAdapterTests: XCTestCase {
    @MainActor private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor func testValidSessionBoundsProvideTimeInBedEvidence() {
        let evidence = SleepTemporalEvidenceAdapter().resolve(
            sleepInterval: SleepInterval(
                start: base,
                end: base.addingTimeInterval(9 * 3_600)
            ),
            durationMinutes: 480,
            stages: []
        )

        XCTAssertEqual(evidence.timeInBedMinutes, 540)
        XCTAssertNil(evidence.wakeAfterSleepOnsetMinutes)
    }

    @MainActor func testSessionShorterThanObservedSleepDoesNotBecomeEfficiencyEvidence() {
        let evidence = SleepTemporalEvidenceAdapter().resolve(
            sleepInterval: SleepInterval(
                start: base,
                end: base.addingTimeInterval(7 * 3_600)
            ),
            durationMinutes: 480,
            stages: []
        )

        XCTAssertNil(evidence.timeInBedMinutes)
        XCTAssertNil(evidence.wakeAfterSleepOnsetMinutes)
    }

    @MainActor func testWASOMergesOverlapsAndExcludesAwakeTimeOutsideAsleepBounds() {
        let stages = [
            stage("清醒", startMinute: 0, endMinute: 60, sourceType: ".awake"),
            stage("浅睡", startMinute: 60, endMinute: 180, sourceType: ".asleepCore"),
            stage("清醒", startMinute: 180, endMinute: 200, sourceType: ".awake"),
            stage("清醒", startMinute: 190, endMinute: 210, sourceType: ".awake"),
            stage("深睡", startMinute: 210, endMinute: 330, sourceType: ".asleepDeep"),
            stage("快速眼动", startMinute: 330, endMinute: 540, sourceType: ".asleepREM"),
            stage("清醒", startMinute: 540, endMinute: 600, sourceType: ".awake")
        ]

        let evidence = SleepTemporalEvidenceAdapter().resolve(
            sleepInterval: SleepInterval(
                start: base,
                end: base.addingTimeInterval(600 * 60)
            ),
            durationMinutes: 450,
            stages: stages
        )

        XCTAssertEqual(evidence.timeInBedMinutes, 600)
        XCTAssertEqual(evidence.wakeAfterSleepOnsetMinutes, 30)
    }

    @MainActor func testChineseREMWithoutSourceMetadataStillDefinesLastAsleepBoundary() {
        let stages = [
            stage("浅睡", startMinute: 0, endMinute: 60, sourceType: ""),
            stage("清醒", startMinute: 60, endMinute: 90, sourceType: ""),
            stage("快速眼动", startMinute: 90, endMinute: 180, sourceType: "")
        ]

        let evidence = SleepTemporalEvidenceAdapter().resolve(
            sleepInterval: SleepInterval(
                start: base,
                end: base.addingTimeInterval(180 * 60)
            ),
            durationMinutes: 150,
            stages: stages
        )

        XCTAssertEqual(evidence.wakeAfterSleepOnsetMinutes, 30)
    }

    @MainActor private func stage(
        _ name: String,
        startMinute: Int,
        endMinute: Int,
        sourceType: String
    ) -> SleepStage {
        SleepStage(
            stage: name,
            duration: endMinute - startMinute,
            startDate: base.addingTimeInterval(Double(startMinute * 60)),
            endDate: base.addingTimeInterval(Double(endMinute * 60)),
            sourceType: sourceType
        )
    }
}
