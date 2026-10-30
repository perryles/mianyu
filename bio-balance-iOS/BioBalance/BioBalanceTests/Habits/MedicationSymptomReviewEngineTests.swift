import XCTest
@testable import BioBalance

nonisolated final class MedicationSymptomReviewEngineTests: XCTestCase {
    @MainActor func testDerivesCountsCoverageStableSymptomAndTwentyFourHourOverlap() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let entries = [
            medication("a", at: now.addingTimeInterval(-23 * 3600), reaction: .uncomfortable),
            medication("b", at: now.addingTimeInterval(-2 * 86400), reaction: nil)
        ]
        let symptoms = [
            symptom("s1", at: now, symptoms: [.headache, .fatigue], severity: 2),
            symptom("s2", at: now.addingTimeInterval(-3600), symptoms: [.fatigue], severity: 2)
        ]

        let review = MedicationSymptomReviewEngine.make(entries: entries, symptomRecords: symptoms, referenceDate: now)

        XCTAssertEqual(review.medicationEntryCount, 2)
        XCTAssertEqual(review.reactionTrackedCount, 1)
        XCTAssertEqual(review.pendingReactionCount, 1)
        XCTAssertEqual(review.reactionCoverage, 0.5)
        XCTAssertEqual(review.mostFrequentSymptom, .fatigue)
        XCTAssertEqual(review.overlapCount, 2)
    }

    @MainActor func testTwentyFourHourBoundaryAndSafetyThreshold() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let entries = [medication("edge", at: now.addingTimeInterval(-24 * 3600), reaction: nil)]
        let symptoms = [symptom("chest", at: now, symptoms: [.chest], severity: 3)]
        let review = MedicationSymptomReviewEngine.make(entries: entries, symptomRecords: symptoms, referenceDate: now)
        XCTAssertEqual(review.overlapCount, 1)
        XCTAssertTrue(review.requiresMedicalAttention)
    }

    @MainActor func testEmptyInputKeepsAnHonestEmptySummary() {
        let review = MedicationSymptomReviewEngine.make(
            entries: [],
            symptomRecords: [],
            referenceDate: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(review.medicationEntryCount, 0)
        XCTAssertEqual(review.symptomRecordCount, 0)
        XCTAssertEqual(review.overlapCount, 0)
        XCTAssertNil(review.reactionCoverage)
        XCTAssertNil(review.mostFrequentSymptom)
        XCTAssertFalse(review.requiresMedicalAttention)
    }

    @MainActor func testFourteenDayWindowExcludesOlderAndFutureRecords() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
        let insideStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 0))!
        let beforeStart = insideStart.addingTimeInterval(-1)

        let review = MedicationSymptomReviewEngine.make(
            entries: [
                medication("inside", at: insideStart, reaction: .neutral),
                medication("old", at: beforeStart, reaction: .uncomfortable),
                medication("future", at: now.addingTimeInterval(1), reaction: .uncomfortable)
            ],
            symptomRecords: [
                symptom("inside", at: now, symptoms: [.fatigue], severity: 2),
                symptom("old", at: beforeStart, symptoms: [.chest], severity: 5)
            ],
            referenceDate: now,
            calendar: calendar
        )

        XCTAssertEqual(review.medicationEntryCount, 1)
        XCTAssertEqual(review.medicationActiveDays, 1)
        XCTAssertEqual(review.symptomRecordCount, 1)
        XCTAssertEqual(review.symptomActiveDays, 1)
        XCTAssertFalse(review.requiresMedicalAttention)
    }

    @MainActor func testReviewLayoutUsesOneMetricColumnForAccessibilitySizes() {
        XCTAssertEqual(MedicationSymptomReviewLayout.metricColumnCount(isAccessibilitySize: false), 2)
        XCTAssertEqual(MedicationSymptomReviewLayout.metricColumnCount(isAccessibilitySize: true), 1)
    }

    @MainActor private func medication(_ id: String, at date: Date, reaction: MedicationReactionState?) -> MedicationEntry {
        MedicationEntry(id: id, name: "测试", amount: 1, unit: "片", reactionState: reaction, takenAt: date)
    }

    @MainActor private func symptom(
        _ id: String,
        at date: Date,
        symptoms: [SelfObservationSymptom],
        severity: Int
    ) -> SelfObservationRecord {
        SelfObservationRecord(
            id: id,
            recordedAt: date,
            symptomIDs: symptoms.map(\.rawValue),
            symptomSeverity: severity,
            selfRating: 3,
            energy: 3,
            stressLoad: 3,
            sleepQuality: 3,
            note: "",
            answeredFieldIDs: SelfObservationAnswerField.allCases.map(\.rawValue),
            source: .symptomObservation
        )
    }
}
