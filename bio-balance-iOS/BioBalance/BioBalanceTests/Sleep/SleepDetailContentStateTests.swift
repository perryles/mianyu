import XCTest
@testable import BioBalance

nonisolated final class SleepDetailContentStateTests: XCTestCase {
    @MainActor func testMissingInitialValueKeepsLoadingState() {
        XCTAssertEqual(
            SleepDetailContentState.resolve(
                sleepDurationMinutes: nil,
                summaryDurationMinutes: nil
            ),
            .loading
        )
    }

    @MainActor func testCompletedQueryWithoutSleepUsesEmptyState() {
        XCTAssertEqual(
            SleepDetailContentState.resolve(
                sleepDurationMinutes: 0,
                summaryDurationMinutes: nil
            ),
            .empty
        )
    }

    @MainActor func testPersistedSummaryCanProvideContentDuringHealthKitRefresh() {
        XCTAssertEqual(
            SleepDetailContentState.resolve(
                sleepDurationMinutes: nil,
                summaryDurationMinutes: 472
            ),
            .content
        )
    }

    @MainActor func testDuplicateNightSummariesKeepLatestEndingSession() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_730_000_000)
        let earlier = SleepTrendNightSummary(
            day: day,
            startTime: day.addingTimeInterval(-8 * 3600),
            endTime: day,
            inBedMinutes: nil,
            asleepMinutes: 400,
            awakeMinutes: 0,
            coreMinutes: 0,
            deepMinutes: 0,
            remMinutes: 0
        )
        let later = SleepTrendNightSummary(
            day: day.addingTimeInterval(3600),
            startTime: day.addingTimeInterval(-7 * 3600),
            endTime: day.addingTimeInterval(3600),
            inBedMinutes: nil,
            asleepMinutes: 420,
            awakeMinutes: 0,
            coreMinutes: 0,
            deepMinutes: 0,
            remMinutes: 0
        )

        let selected = SleepNightSummarySelection.latestByDay([later, earlier], calendar: calendar)

        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected[calendar.startOfDay(for: day)], later)
    }
}
