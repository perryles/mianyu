import XCTest
@testable import BioBalance

nonisolated final class BodySignalRollingRangeTests: XCTestCase {
    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor func testRollingRangesIncludeAnchorDayWithExpectedDayCounts() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 1, hour: 12)))

        for (range, expectedDays) in [
            (BodySignalRollingRange.day, 1),
            (.week, 7),
            (.month, 30),
            (.year, 365)
        ] {
            let interval = range.interval(anchorDate: anchor, calendar: calendar)
            let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day
            XCTAssertEqual(dayCount, expectedDays)
            XCTAssertTrue(interval.contains(calendar.startOfDay(for: anchor)))
        }
    }

    @MainActor func testCurrentRangeQueryEndStopsAtNow() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 16)))

        XCTAssertEqual(
            BodySignalRollingRange.year.queryEnd(anchorDate: anchor, now: now, calendar: calendar),
            now
        )
    }

    @MainActor func testHistoricalRangeQueryEndNeverExtendsIntoFuture() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 12)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 16)))
        let interval = BodySignalRollingRange.month.interval(anchorDate: anchor, calendar: calendar)

        XCTAssertEqual(
            BodySignalRollingRange.month.queryEnd(anchorDate: anchor, now: now, calendar: calendar),
            interval.end
        )
    }
}
