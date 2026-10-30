import CloudKit
import XCTest
@testable import BioBalance

nonisolated final class ReproductiveHealthRecordViewTests: XCTestCase {
    @MainActor func testBasalTemperatureEntryNormalizesCommaDecimalBeforeSaving() {
        let entry = PeriodBasalTemperatureEntry(text: "36,55")

        XCTAssertEqual(entry.normalizedText, "36.55")
    }

    @MainActor func testBasalTemperatureEntryAcceptsOnlyPlausibleCelsiusValues() {
        XCTAssertTrue(PeriodBasalTemperatureEntry(text: "36.5").isValid)
        XCTAssertTrue(PeriodBasalTemperatureEntry(text: "30").isValid)
        XCTAssertTrue(PeriodBasalTemperatureEntry(text: "45").isValid)
        XCTAssertFalse(PeriodBasalTemperatureEntry(text: "").isValid)
        XCTAssertFalse(PeriodBasalTemperatureEntry(text: "abc").isValid)
        XCTAssertFalse(PeriodBasalTemperatureEntry(text: "29.9").isValid)
        XCTAssertFalse(PeriodBasalTemperatureEntry(text: "45.1").isValid)
    }

    @MainActor func testPeriodSymptomIntensityNormalizesStoredLevelIntoVisibleTiers() {
        XCTAssertEqual(PeriodSymptomIntensity(level: -2), .none)
        XCTAssertEqual(PeriodSymptomIntensity(level: 1), .mild)
        XCTAssertEqual(PeriodSymptomIntensity(level: 2), .mild)
        XCTAssertEqual(PeriodSymptomIntensity(level: 3), .noticeable)
        XCTAssertEqual(PeriodSymptomIntensity(level: 4), .noticeable)
        XCTAssertEqual(PeriodSymptomIntensity(level: 5), .strong)
        XCTAssertEqual(PeriodSymptomIntensity(level: 9), .strong)
    }

    @MainActor func testPeriodProgressGeometryClampsDrawingToCardWidth() {
        XCTAssertEqual(
            PeriodProgressGeometry.filledWidth(progress: 0.5, availableWidth: 300),
            150,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PeriodProgressGeometry.filledWidth(progress: 2, availableWidth: 300),
            300,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PeriodProgressGeometry.filledWidth(progress: -1, availableWidth: 300),
            0,
            accuracy: 0.001
        )
    }

    @MainActor func testPeriodLearningStateStaysLearningUntilTwoCompletedCycles() {
        XCTAssertEqual(PeriodLearningState(completedCycleCount: 0), .learning)
        XCTAssertEqual(PeriodLearningState(completedCycleCount: 1), .learning)
    }

    @MainActor func testPeriodLearningStateRaisesConfidenceAsCyclesAccumulate() {
        XCTAssertEqual(PeriodLearningState(completedCycleCount: 2), .lowConfidence)
        XCTAssertEqual(PeriodLearningState(completedCycleCount: 3), .mediumConfidence)
        XCTAssertEqual(PeriodLearningState(completedCycleCount: 6), .stable)
    }

    @MainActor func testPeriodLearningStateCountsOnlyCompletedCycles() {
        let cycles = [
            PeriodCycle(idValue: 1, startDate: "2026-06-01", endDate: "2026-06-05"),
            PeriodCycle(idValue: 2, startDate: "2026-07-01", endDate: "2026-07-05"),
            PeriodCycle(idValue: 3, startDate: "2026-08-01", endDate: nil)
        ]

        XCTAssertEqual(PeriodLearningState(cycles: cycles), .lowConfidence)
    }

    @MainActor func testPregnancyStageGuidanceUsesTrimesterSpecificContent() {
        XCTAssertEqual(PregnancyStageGuidance(trimester: 1).title, "孕早期")
        XCTAssertEqual(PregnancyStageGuidance(trimester: 2).title, "孕中期")
        XCTAssertEqual(PregnancyStageGuidance(trimester: 3).title, "孕晚期")
    }

    @MainActor func testPregnancyStageGuidanceNormalizesUnexpectedTrimester() {
        XCTAssertEqual(PregnancyStageGuidance(trimester: 0), PregnancyStageGuidance(trimester: 1))
        XCTAssertEqual(PregnancyStageGuidance(trimester: 8), PregnancyStageGuidance(trimester: 3))
    }

    @MainActor func testFailedPregnancyLoadFallsBackToLocalPeriodContent() {
        let presentation = ReproductiveHealthSnapshotPresentation.resolve(
            hasLoadedSnapshot: false,
            hasLoadedPeriodSection: false,
            syncStatus: .failed("iCloud unavailable")
        )

        XCTAssertEqual(presentation, .localPeriodFallback)
    }

    @MainActor func testCloudRetryKeepsLocalPeriodContentVisible() {
        let presentation = ReproductiveHealthSnapshotPresentation.resolve(
            hasLoadedSnapshot: false,
            hasLoadedPeriodSection: true,
            syncStatus: .loading
        )

        XCTAssertEqual(presentation, .localPeriodFallback)
    }

    @MainActor func testInitialPregnancyCheckStillUsesLoadingPresentation() {
        let presentation = ReproductiveHealthSnapshotPresentation.resolve(
            hasLoadedSnapshot: false,
            hasLoadedPeriodSection: false,
            syncStatus: .loading
        )

        XCTAssertEqual(presentation, .loading)
    }

    @MainActor func testLoadedPregnancySnapshotWinsOverLaterSyncFailure() {
        let presentation = ReproductiveHealthSnapshotPresentation.resolve(
            hasLoadedSnapshot: true,
            hasLoadedPeriodSection: false,
            syncStatus: .failed("save failed")
        )

        XCTAssertEqual(presentation, .resolvedSnapshot)
    }

    @MainActor func testLegacyPregnancyChildrenNormalizeToCurrentPregnancyID() throws {
        let zoneID = CKRecordZone.ID(zoneName: PregnancyCloudSchema.zoneName)
        let weightRecord = CKRecord(
            recordType: PregnancyCloudSchema.weightRecordType,
            recordID: CKRecord.ID(recordName: "weight-1", zoneID: zoneID)
        )
        weightRecord["measuredAt"] = Date(timeIntervalSince1970: 1_000) as CKRecordValue
        weightRecord["weightKg"] = 60.5 as CKRecordValue

        let movementRecord = CKRecord(
            recordType: PregnancyCloudSchema.fetalMovementRecordType,
            recordID: CKRecord.ID(recordName: "movement-1", zoneID: zoneID)
        )
        movementRecord["pregnancyID"] = PregnancyCloudSchema.legacyPregnancyID as CKRecordValue
        movementRecord["occurredAt"] = Date(timeIntervalSince1970: 2_000) as CKRecordValue

        XCTAssertEqual(
            try XCTUnwrap(PregnancyCloudKitRepository.decodeWeightEntry(
                weightRecord,
                currentPregnancyID: "pregnancy-current"
            )).pregnancyID,
            "pregnancy-current"
        )
        XCTAssertEqual(
            try XCTUnwrap(PregnancyCloudKitRepository.decodeFetalMovementEntry(
                movementRecord,
                currentPregnancyID: "pregnancy-current"
            )).pregnancyID,
            "pregnancy-current"
        )
    }

    @MainActor func testLegacyPregnancyProfileGetsDeterministicCurrentID() throws {
        let record = CKRecord(
            recordType: PregnancyCloudSchema.profileRecordType,
            recordID: CKRecord.ID(recordName: PregnancyCloudSchema.profileRecordName)
        )
        record["dueDate"] = Date(timeIntervalSince1970: 20_000) as CKRecordValue
        record["lastMenstrualPeriod"] = Date(timeIntervalSince1970: 10_000) as CKRecordValue

        XCTAssertEqual(
            try XCTUnwrap(PregnancyCloudKitRepository.decodeProfile(record)).id,
            PregnancyCloudSchema.migratedPregnancyID
        )
    }
}
