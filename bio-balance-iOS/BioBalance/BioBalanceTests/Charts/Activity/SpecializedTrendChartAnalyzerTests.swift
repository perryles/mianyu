import XCTest
@testable import BioBalance

nonisolated final class SpecializedTrendChartAnalyzerTests: XCTestCase {
    @MainActor func testBodyMetricChartTypesMatchTotalsAndReadings() {
        for kind: HabitBodyMetricKind in [.basal, .active, .stand, .sunlight] {
            XCTAssertTrue(BodyMetricChartPolicy.usesBars(kind))
        }
        for kind: HabitBodyMetricKind in [.hrv, .restingHeartRate, .wristTemperature, .walkingAsymmetry] {
            XCTAssertFalse(BodyMetricChartPolicy.usesBars(kind))
        }
    }

    @MainActor func testBodyMetricSegmentsBreakAtMissingDaysAndKeepZero() throws {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let missing = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
        let last = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))
        let points = [HabitTrendPoint(date: last, value: 2), HabitTrendPoint(date: start, value: 0), HabitTrendPoint(date: next, value: 1)]
        let segments = BodyMetricChartPolicy.segments(points, calendar: calendar)
        XCTAssertEqual(segments.map(\.count), [2, 1])
        XCTAssertEqual(segments.first?.first?.value, 0)
        XCTAssertNil(BodyMetricChartPolicy.point(on: missing, in: points, calendar: calendar))
        XCTAssertEqual(BodyMetricChartPolicy.point(on: start.addingTimeInterval(3600), in: points, calendar: calendar)?.value, 0)
    }

    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor func testSportDaysAlignsMetricsByNaturalDayWithoutFillingMissingValues() throws {
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let metrics = [
            metric("跑步总时长", "分钟", [point(firstDay, 30), point(secondDay, 45)]),
            metric("跑步距离", "km", [point(secondDay, 8.2)]),
            metric("平均配速", "分/公里", [point(firstDay, 5.5)])
        ]

        let result = SpecializedTrendChartAnalyzer.sportDays(
            metrics: metrics,
            kind: .running,
            calendar: calendar
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].date, firstDay)
        XCTAssertEqual(result[0].duration, 30)
        XCTAssertNil(result[0].distance)
        XCTAssertEqual(result[0].efficiency, 5.5)
        XCTAssertEqual(result[1].date, secondDay)
        XCTAssertEqual(result[1].duration, 45)
        XCTAssertEqual(result[1].distance, 8.2)
        XCTAssertNil(result[1].efficiency)
    }

    @MainActor func testSportDaysSumsVolumeAndAveragesEfficiencyForDuplicateDaySamples() throws {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let later = try XCTUnwrap(calendar.date(byAdding: .hour, value: 8, to: day))
        let metrics = [
            metric("骑行距离", "km", [point(day, 12), point(later, 8)]),
            metric("平均速度", "km/h", [point(day, 20), point(later, 24)])
        ]

        let result = SpecializedTrendChartAnalyzer.sportDays(
            metrics: metrics,
            kind: .cycling,
            calendar: calendar
        )

        let combined = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(combined.distance, 20)
        XCTAssertEqual(combined.efficiency, 22)
        XCTAssertNil(combined.duration)
    }

    @MainActor func testSportDaysPreservesSevenAndThirtyDaySeries() throws {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let sevenPoints = try makeDailyPoints(count: 7, start: start)
        let thirtyPoints = try makeDailyPoints(count: 30, start: start)

        let sevenDays = SpecializedTrendChartAnalyzer.sportDays(
            metrics: [metric("游泳总时长", "分钟", sevenPoints)],
            kind: .swimming,
            calendar: calendar
        )
        let thirtyDays = SpecializedTrendChartAnalyzer.sportDays(
            metrics: [metric("游泳总时长", "分钟", thirtyPoints)],
            kind: .swimming,
            calendar: calendar
        )

        XCTAssertEqual(sevenDays.count, 7)
        XCTAssertEqual(thirtyDays.count, 30)
        XCTAssertEqual(SpecializedTrendChartAnalyzer.total(sevenDays, metric: .duration), 28)
        XCTAssertEqual(SpecializedTrendChartAnalyzer.total(thirtyDays, metric: .duration), 465)
    }

    @MainActor func testMindfulnessDaysSumsMinutesAveragesStateAndKeepsMissingDayValueNil() throws {
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let later = try XCTUnwrap(calendar.date(byAdding: .hour, value: 6, to: firstDay))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let metrics = [
            metric("正念时长", "分钟", [point(firstDay, 10), point(later, 5)]),
            metric("心理状态", "分", [point(firstDay, 40), point(later, 60), point(secondDay, 75)])
        ]

        let result = SpecializedTrendChartAnalyzer.mindfulnessDays(metrics: metrics, calendar: calendar)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].mindfulMinutes, 15)
        XCTAssertEqual(result[0].stateScore, 50)
        XCTAssertNil(result[1].mindfulMinutes)
        XCTAssertEqual(result[1].stateScore, 75)
    }

    @MainActor func testSportValueFormatterUsesPaceAndSpeedSpecificFormats() {
        XCTAssertEqual(TrendMetricValueFormatter.string(for: 5.5, unit: "分/公里"), "5'30\"/km")
        XCTAssertEqual(TrendMetricValueFormatter.string(for: 21.36, unit: "km/h"), "21.4km/h")
    }

    @MainActor func testSegmentedValuesBreaksLineAtNilAndMissingNaturalDay() throws {
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let thirdDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let fifthDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: firstDay))

        let result = SpecializedTrendChartAnalyzer.segmentedValues(
            [
                (firstDay, 42),
                (secondDay, nil),
                (thirdDay, 55),
                (fifthDay, 64)
            ],
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.value), [42, 55, 64])
        XCTAssertEqual(Set(result.map(\.segment)).count, 3)
    }

    @MainActor private func makeDailyPoints(count: Int, start: Date) throws -> [TimeSeriesPointDouble] {
        try (0..<count).map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            return point(date, Double(offset + 1))
        }
    }

    @MainActor private func metric(
        _ title: String,
        _ unit: String,
        _ points: [TimeSeriesPointDouble]
    ) -> TrendCategoryMetricModel {
        TrendCategoryMetricModel(
            title: title,
            unit: unit,
            points: points,
            secondaryPoints: [],
            status: points.isEmpty ? .noData : .ready,
            emptyMessage: "暂无数据",
            accentHex: "5E5CE6",
            summary: "测试"
        )
    }

    @MainActor private func point(_ date: Date, _ value: Double) -> TimeSeriesPointDouble {
        TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
    }
}
