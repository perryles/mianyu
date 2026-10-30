import XCTest
@testable import BioBalance

nonisolated final class HeartRelationshipAnalyzerTests: XCTestCase {
    @MainActor func testDailyPairingUsesNearestSampleWithinToleranceWithoutReusingIt() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let xPoints = [
            point(day, offset: 0, value: 40),
            point(day, offset: 60 * 60, value: 50),
            point(day, offset: 4 * 60 * 60, value: 60)
        ]
        let yPoints = [
            point(day, offset: 20 * 60, value: 70),
            point(day, offset: 5 * 60 * 60, value: 80)
        ]

        let result = HeartRelationshipAnalyzer.pairedPoints(
            xPoints: xPoints,
            yPoints: yPoints,
            range: .day
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].xValue, 40)
        XCTAssertEqual(result[0].yValue, 70)
        XCTAssertEqual(result[1].xValue, 60)
        XCTAssertEqual(result[1].yValue, 80)
    }

    @MainActor func testWeekPairingAveragesSamplesByNaturalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))

        let result = HeartRelationshipAnalyzer.pairedPoints(
            xPoints: [
                point(day, offset: 8 * 60 * 60, value: 40),
                point(day, offset: 12 * 60 * 60, value: 60),
                point(nextDay, offset: 8 * 60 * 60, value: 70)
            ],
            yPoints: [
                point(day, offset: 9 * 60 * 60, value: 80),
                point(day, offset: 13 * 60 * 60, value: 100)
            ],
            range: .week,
            calendar: calendar
        )

        let paired = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(paired.xValue, 50, accuracy: 0.001)
        XCTAssertEqual(paired.yValue, 90, accuracy: 0.001)
        XCTAssertEqual(paired.date, day)
    }

    @MainActor func testDailyPairingKeepsMaximumChronologicalMatches() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let result = HeartRelationshipAnalyzer.pairedPoints(
            xPoints: [
                point(day, offset: 0, value: 40),
                point(day, offset: 100 * 60, value: 50)
            ],
            yPoints: [
                point(day, offset: -80 * 60, value: 70),
                point(day, offset: 60 * 60, value: 80)
            ],
            range: .day
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.yValue), [70, 80])
    }

    @MainActor func testSummaryCalculatesPerfectInverseCorrelationAndRegression() throws {
        let points = [
            HeartRelationshipPoint(timestamp: 1, xValue: 1, yValue: 6),
            HeartRelationshipPoint(timestamp: 2, xValue: 2, yValue: 4),
            HeartRelationshipPoint(timestamp: 3, xValue: 3, yValue: 2)
        ]

        let summary = HeartRelationshipAnalyzer.summary(for: points)

        XCTAssertEqual(try XCTUnwrap(summary.correlation), -1, accuracy: 0.000_001)
        XCTAssertEqual(summary.meanX, 2)
        XCTAssertEqual(summary.meanY, 4)
        XCTAssertEqual(summary.regressionLine.count, 2)
        XCTAssertEqual(summary.regressionLine.first?.yValue, 6)
        XCTAssertEqual(summary.regressionLine.last?.yValue, 2)
    }

    @MainActor func testBaselineDeviationIsCenteredOnSeriesMean() {
        let values = [
            TimeSeriesPointDouble(timestamp: 1, value: 80),
            TimeSeriesPointDouble(timestamp: 2, value: 100),
            TimeSeriesPointDouble(timestamp: 3, value: 120)
        ]

        let result = HeartRelationshipAnalyzer.baselineDeviations(for: values)

        XCTAssertEqual(result, [-20, 0, 20])
        XCTAssertEqual(result.reduce(0, +), 0, accuracy: 0.000_001)
    }

    @MainActor func testTriplePointsPairsThreeDailySeriesWithoutReusingSamples() {
        // 两组三项读数均落在 90 分钟窗口内，应保持时间顺序且不重复消费 Z 样本。
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let result = HeartRelationshipAnalyzer.triplePoints(
            xPoints: [point(day, offset: 0, value: 40), point(day, offset: 3_600, value: 50)],
            yPoints: [point(day, offset: 300, value: 70), point(day, offset: 3_900, value: 80)],
            zPoints: [point(day, offset: 600, value: 90), point(day, offset: 4_200, value: 100)],
            range: .day
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.xValue), [40, 50])
        XCTAssertEqual(result.map(\.yValue), [70, 80])
        XCTAssertEqual(result.map(\.zValue), [90, 100])
    }

    @MainActor func testTriplePointsUsesOnlySharedNaturalDaysForWeekRange() throws {
        // 第二天缺少 Z 指标，因此周视图只能生成第一天的完整三维点。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))

        let result = HeartRelationshipAnalyzer.triplePoints(
            xPoints: [point(day, offset: 0, value: 40), point(nextDay, offset: 0, value: 50)],
            yPoints: [point(day, offset: 0, value: 70), point(nextDay, offset: 0, value: 80)],
            zPoints: [point(day, offset: 0, value: 90)],
            range: .week,
            calendar: calendar
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.date, day)
        XCTAssertEqual(result.first?.zValue, 90)
    }

    @MainActor private func point(_ base: Date, offset: TimeInterval, value: Double) -> TimeSeriesPointDouble {
        TimeSeriesPointDouble(
            timestamp: Int64(base.addingTimeInterval(offset).timeIntervalSince1970),
            value: value
        )
    }
}
