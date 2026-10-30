import XCTest
@testable import BioBalance

nonisolated final class SnoreAnalysisSummarySelectorTests: XCTestCase {
    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor func testReturnsMeasuredSummaryForMatchingDate() {
        let sourceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let session = makeSession(sourceDate: sourceDate)

        let selected = SnoreAnalysisSummarySelector.resolve(
            selectedDate: sourceDate,
            latestSummary: session,
            calendar: calendar
        )

        XCTAssertEqual(selected, session.snoreSummary)
    }

    @MainActor func testDoesNotReuseLatestSummaryForDifferentDate() {
        let sourceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let session = makeSession(sourceDate: sourceDate)

        let selected = SnoreAnalysisSummarySelector.resolve(
            selectedDate: sourceDate.addingTimeInterval(-86_400),
            latestSummary: session,
            calendar: calendar
        )

        XCTAssertNil(selected)
    }

    @MainActor func testEmptySummaryIsPresentedAsMissingEvidence() {
        let sourceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let emptySession = makeSession(sourceDate: sourceDate, snoreSummary: .empty)

        let selected = SnoreAnalysisSummarySelector.resolve(
            selectedDate: sourceDate,
            latestSummary: emptySession,
            calendar: calendar
        )

        XCTAssertNil(selected)
    }

    @MainActor private func makeSession(
        sourceDate: Date,
        snoreSummary: SnoreAnalysisSummary? = nil
    ) -> SleepSessionSummary {
        let resolvedSnoreSummary = snoreSummary ?? SnoreAnalysisSummary(
            snoreDetected: true,
            snoreDurationMinutes: 2,
            snoreFrequencyPerHour: 0.5,
            intensity: .low,
            disturbanceScore: 18,
            riskFlag: .monitor,
            segments: [],
            histogram: Array(repeating: 0, count: 6)
        )
        return SleepSessionSummary(
            sessionId: "snore-summary",
            sourceDate: sourceDate,
            startTime: sourceDate,
            endTime: sourceDate.addingTimeInterval(8 * 3_600),
            sleepDurationMinutes: 480,
            sleepScore: 80,
            sleepContinuityScore: 80,
            stageSummary: .empty,
            snoreSummary: resolvedSnoreSummary,
            insight: .placeholder,
            watchConfidence: 0.8,
            deviceSource: "test",
            analysisVersion: "test",
            createdAt: sourceDate,
            updatedAt: sourceDate,
            source: .manual
        )
    }
}
