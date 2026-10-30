import XCTest
@testable import BioBalance

nonisolated final class ActivityTrendDataTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    func testVolumeMetricsUseBarsWithZeroBaselineEvenForConstantData() {
        let points = [ActivityTrendReading(timestamp: 0, value: 8000)]
        for metric: ActivityTrendMetric in [.steps, .exercise, .energy, .stand] {
            XCTAssertTrue(metric.usesBars)
            XCTAssertEqual(ActivityTrendData.yDomain(points, metric: metric).lowerBound, 0)
            XCTAssertGreaterThan(ActivityTrendData.yDomain(points, metric: metric).upperBound, 8000)
        }
        XCTAssertFalse(ActivityTrendMetric.speed.usesBars)
        XCTAssertGreaterThan(ActivityTrendData.yDomain(points, metric: .speed).lowerBound, 0)
    }

    func testPreparationSortsConvertsSpeedAndPreservesRealZero() {
        let values = [
            ActivityTrendReading(timestamp: 20, value: 1.5),
            ActivityTrendReading(timestamp: 10, value: 0),
            ActivityTrendReading(timestamp: 30, value: .nan),
            ActivityTrendReading(timestamp: 40, value: .infinity),
            ActivityTrendReading(timestamp: 50, value: -1),
            ActivityTrendReading(timestamp: 100, value: 5)
        ]
        let domain = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 60)
        let result = ActivityTrendData.prepare(values, metric: .speed, domain: domain)
        XCTAssertEqual(result.map(\.timestamp), [10, 20])
        XCTAssertEqual(result[0].value, 0)
        XCTAssertEqual(result[1].value, 5.4, accuracy: 0.0001)
        let steps = ActivityTrendData.prepare(values, metric: .steps, domain: domain)
        XCTAssertEqual(steps.last?.value, 1.5)
    }

    func testMissingDayDoesNotBorrowAdjacentRecordAndSplitsLine() {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let points = [0, 1, 3].map {
            ActivityTrendReading(timestamp: Int64(start.addingTimeInterval(Double($0) * 86400).timeIntervalSince1970), value: Double($0))
        }
        XCTAssertEqual(ActivityTrendData.segments(points, calendar: calendar).map(\.count), [2, 1])
        XCTAssertNil(ActivityTrendData.selected(on: start.addingTimeInterval(2 * 86400), in: points, calendar: calendar))
        XCTAssertEqual(ActivityTrendData.selected(on: start.addingTimeInterval(3600), in: points, calendar: calendar)?.value, 0)
    }

    func testEmptyAndZeroDataProduceValidScales() {
        XCTAssertEqual(ActivityTrendData.yDomain([], metric: .steps), 0...1)
        let zero = [ActivityTrendReading(timestamp: 0, value: 0)]
        XCTAssertEqual(ActivityTrendData.yDomain(zero, metric: .speed), 0...1)
        XCTAssertTrue(ActivityTrendData.segments([], calendar: calendar).isEmpty)
    }

    func testContinuityUsesCalendarDaysAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(next.timeIntervalSince(start), 23 * 3600)
        let points = [start, next].map { ActivityTrendReading(timestamp: Int64($0.timeIntervalSince1970), value: 3) }
        XCTAssertEqual(ActivityTrendData.segments(points, calendar: calendar).count, 1)
        XCTAssertEqual(ActivityTrendData.plotDate(for: points[0], metric: .steps, calendar: calendar).timeIntervalSince(start), 11.5 * 3600)
        XCTAssertEqual(ActivityTrendData.plotDate(for: points[0], metric: .speed, calendar: calendar), start)
    }
}
