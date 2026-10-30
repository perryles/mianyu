import XCTest
@testable import BioBalance

nonisolated final class HeartBaselineTimePolicyTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private var start: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }

    func testWeeklyReadoutNeverBorrowsAnAdjacentDay() {
        let dates = [start, start.addingTimeInterval(2 * 86400)]
        XCTAssertNil(HeartBaselineTimePolicy.matchingIndex(on: start.addingTimeInterval(86400), dates: dates, intraday: false, calendar: calendar))
        XCTAssertEqual(HeartBaselineTimePolicy.matchingIndex(on: start.addingTimeInterval(3600), dates: dates, intraday: false, calendar: calendar), 0)
    }

    func testIntradayMatchingKeepsToleranceButDoesNotCrossMidnight() {
        let dates = [start.addingTimeInterval(3600)]
        XCTAssertEqual(HeartBaselineTimePolicy.matchingIndex(on: start.addingTimeInterval(2.5 * 3600), dates: dates, intraday: true, calendar: calendar), 0)
        XCTAssertNil(HeartBaselineTimePolicy.matchingIndex(on: start.addingTimeInterval(2.5 * 3600 + 1), dates: dates, intraday: true, calendar: calendar))
        XCTAssertNil(HeartBaselineTimePolicy.matchingIndex(on: start, dates: [start.addingTimeInterval(-60)], intraday: true, calendar: calendar))
    }

    func testMissingDaysAndLongIntradayGapsBreakLines() {
        let days = [start, start.addingTimeInterval(86400), start.addingTimeInterval(3 * 86400)]
        XCTAssertEqual(HeartBaselineTimePolicy.segments(dates: days, intraday: false, calendar: calendar), [[0, 1], [2]])
        let hours = [start, start.addingTimeInterval(3600), start.addingTimeInterval(4 * 3600)]
        XCTAssertEqual(HeartBaselineTimePolicy.segments(dates: hours, intraday: true, calendar: calendar), [[0, 1], [2]])
    }

    func testEmptyAndUnsortedInputPreserveOriginalIndices() {
        XCTAssertNil(HeartBaselineTimePolicy.matchingIndex(on: start, dates: [], intraday: false, calendar: calendar))
        XCTAssertTrue(HeartBaselineTimePolicy.segments(dates: [], intraday: false, calendar: calendar).isEmpty)
        XCTAssertEqual(HeartBaselineTimePolicy.segments(dates: [start.addingTimeInterval(86400), start], intraday: false, calendar: calendar), [[1, 0]])
    }

    func testDayContinuityHandlesFallDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: first))
        XCTAssertEqual(next.timeIntervalSince(first), 25 * 3600)
        XCTAssertEqual(HeartBaselineTimePolicy.segments(dates: [first, next], intraday: false, calendar: calendar), [[0, 1]])
    }
}
