import Foundation
import XCTest
@testable import BioBalance

/// TrendsViewModel 拆出的纯计算子模块（PEN-14）+ 日期/聚合纯逻辑测试。
///
/// 不依赖 HealthKit / CloudKit，全部使用本地构造的输入，离线运行：
/// - 趋势聚合（averagedValuesByKey）
/// - 健康样本 → 压力估计序列转换（estimateStressSeriesByTimestamp）
/// - 压力时隙矩阵（buildPressureSlotMatrix：measured / estimated / inferred / empty）
/// - TrendsRange 日期计算
nonisolated final class PressureMatrixMathTests: XCTestCase {

    @MainActor private var calendar: Calendar { Calendar.current }

    @MainActor private func point(_ date: Date, _ value: Double) -> TimeSeriesPointDouble {
        TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
    }

    @MainActor private func hour(_ hour: Int, on day: Date) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    @MainActor private func today() -> Date {
        calendar.startOfDay(for: Date())
    }

    @MainActor private func dayOffset(_ offset: Int, from day: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day)!
    }

    // MARK: - 趋势聚合

    @MainActor func testAveragedValuesByKeyAveragesPerGroup() {
        let day = today()
        let points = [
            point(hour(8, on: day), 30),
            point(hour(9, on: day), 50),
            point(hour(8, on: dayOffset(1, from: day)), 90)
        ]

        let byDay = PressureMatrixMath.averagedValuesByKey(points) { calendar.startOfDay(for: $0.date) }
        XCTAssertEqual(try! XCTUnwrap(byDay[day]), 40, accuracy: 0.001)
        XCTAssertEqual(try! XCTUnwrap(byDay[dayOffset(1, from: day)]), 90, accuracy: 0.001)
    }

    @MainActor func testAveragedValuesByKeyEmptyInputReturnsEmpty() {
        XCTAssertTrue(PressureMatrixMath.averagedValuesByKey([]) { $0.timestamp }.isEmpty)
    }

    // MARK: - 健康样本 → 压力估计序列

    @MainActor func testEstimatedStressSeriesDropsNonPositiveHRV() {
        let day = today()
        let hrv = [
            point(hour(8, on: day), 0),
            point(hour(9, on: day), -5),
            point(hour(10, on: day), 45)
        ]
        let result = PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: hrv,
            heartRate: [],
            restingHeartRate: []
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].timestamp, Int64(calendar.startOfHour(for: hour(10, on: day)).timeIntervalSince1970))
    }

    @MainActor func testEstimatedStressSeriesUsesHourlyHeartRateAverage() {
        let day = today()
        let hrv = [point(hour(10, on: day).addingTimeInterval(30 * 60), 60)]
        // 同一小时内的两个心率样本 → 取均值 80。
        let heartRate = [
            point(hour(10, on: day), 70),
            point(hour(10, on: day).addingTimeInterval(45 * 60), 90)
        ]
        let expected = StressDailyEngine.instantaneousStress(
            hrv: 60,
            heartRate: 80,
            restingHeartRate: nil
        )

        let result = PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: hrv,
            heartRate: heartRate,
            restingHeartRate: []
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Int(result[0].value), expected)
    }

    @MainActor func testEstimatedStressSeriesFallsBackToRestingHeartRateForDay() {
        let day = today()
        let hrv = [point(hour(22, on: day), 60)]
        let resting = [point(day.addingTimeInterval(6 * 3600), 58)]
        let expected = StressDailyEngine.instantaneousStress(
            hrv: 60,
            heartRate: 58,
            restingHeartRate: 58
        )

        let result = PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: hrv,
            heartRate: [],
            restingHeartRate: resting
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Int(result[0].value), expected)
    }

    @MainActor func testEstimatedStressSeriesUsesDefaultBaselineWhenNoHRData() {
        let day = today()
        let hrv = [point(hour(8, on: day), 50)]
        let expected = StressDailyEngine.instantaneousStress(
            hrv: 50,
            heartRate: 62,
            restingHeartRate: nil
        )

        let result = PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: hrv,
            heartRate: [],
            restingHeartRate: []
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Int(result[0].value), expected)
    }

    @MainActor func testEstimatedStressSeriesSupportsHeartRateWithoutHrv() throws {
        let day = today()
        let result = PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: [],
            heartRate: [point(hour(10, on: day), 90)],
            restingHeartRate: [point(hour(7, on: day), 60)]
        )

        let point = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertGreaterThanOrEqual(point.value, 70)
    }

    @MainActor func testEstimatedStressSeriesEmptyInputsReturnEmpty() {
        XCTAssertTrue(PressureMatrixMath.estimateStressSeriesByTimestamp(
            hrv: [],
            heartRate: [],
            restingHeartRate: []
        ).isEmpty)
    }

    // MARK: - 压力时隙矩阵

    @MainActor func testBuildPressureSlotMatrixWeekProducesExpectedStructure() {
        let today = today()
        let history = [point(hour(10, on: dayOffset(-1, from: today)), 40)]

        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .week,
            historyEvents: history,
            estimatedHourly: []
        )

        XCTAssertEqual(result.rows.count, TrendsRange.week.windowDays)
        for row in result.rows {
            XCTAssertEqual(row.cells.count, 8, "week 每行应有 8 个 3 小时时隙")
            XCTAssertEqual(Set(row.cells.map(\.slotDurationHours)), [3])
        }
    }

    @MainActor func testBuildPressureSlotMatrixAggregatesMeasuredValuesInSlot() {
        let today = today()
        let yesterday = dayOffset(-1, from: today)
        let history = [
            point(hour(10, on: yesterday), 30),
            point(hour(11, on: yesterday), 50)
        ]

        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .week,
            historyEvents: history,
            estimatedHourly: []
        )
        let row = try! XCTUnwrap(result.rows.first { calendar.isDate($0.date, inSameDayAs: yesterday) })
        let cell = try! XCTUnwrap(row.cells.first { $0.slotStartHour == 9 })
        XCTAssertEqual(cell.value ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(cell.source, .measured)
    }

    @MainActor func testBuildPressureSlotMatrixUsesEstimatedWhenNoHistory() {
        let today = today()
        let yesterday = dayOffset(-1, from: today)
        let estimated = [point(hour(14, on: yesterday), 70)]

        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .week,
            historyEvents: [],
            estimatedHourly: estimated
        )
        let row = try! XCTUnwrap(result.rows.first { calendar.isDate($0.date, inSameDayAs: yesterday) })
        let cell = try! XCTUnwrap(row.cells.first { $0.slotStartHour == 12 })
        XCTAssertEqual(cell.value ?? -1, 70, accuracy: 0.001)
        XCTAssertEqual(cell.source, .estimated)
    }

    @MainActor func testBuildPressureSlotMatrixInfersDayBaselineForGaps() {
        let today = today()
        let yesterday = dayOffset(-1, from: today)
        let history = [point(hour(10, on: yesterday), 30)]

        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .week,
            historyEvents: history,
            estimatedHourly: []
        )
        let row = try! XCTUnwrap(result.rows.first { calendar.isDate($0.date, inSameDayAs: yesterday) })
        // 10 点那条记录之外的时隙用当日基线（30）推断。
        let gapCell = try! XCTUnwrap(row.cells.first { $0.slotStartHour == 0 })
        XCTAssertEqual(gapCell.value ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(gapCell.source, .inferred)
    }

    @MainActor func testBuildPressureSlotMatrixEmptyWhenNoData() {
        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .week,
            historyEvents: [],
            estimatedHourly: []
        )
        for row in result.rows {
            XCTAssertTrue(row.cells.allSatisfy { $0.source == .empty && $0.value == nil })
        }
        XCTAssertTrue(result.samples.isEmpty)
    }

    @MainActor func testBuildPressureSlotMatrixDayUsesIntradaySlots() {
        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .day,
            historyEvents: [],
            estimatedHourly: []
        )

        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].cells.count, 24)
        XCTAssertEqual(Set(result.rows[0].cells.map(\.slotDurationHours)), [1])
        XCTAssertEqual(result.rows[0].cells.map(\.slotStartHour), Array(0..<24))
    }

    @MainActor func testBuildPressureSlotMatrixSamplesMatchFilledCells() {
        let today = today()
        let yesterday = dayOffset(-1, from: today)
        let history = [point(hour(10, on: yesterday), 30)]

        let result = PressureMatrixMath.buildPressureSlotMatrix(
            range: .week,
            historyEvents: history,
            estimatedHourly: []
        )
        let filledCells = result.rows.flatMap(\.cells).filter { $0.value != nil }
        XCTAssertEqual(result.samples.count, filledCells.count)
        XCTAssertTrue(result.samples.allSatisfy { $0.value > 0 })
    }

    // MARK: - TrendsRange 日期计算

    @MainActor func testTrendsRangeWindowDaysAndIntraday() {
        XCTAssertEqual(TrendsRange.day.windowDays, 1)
        XCTAssertEqual(TrendsRange.week.windowDays, 7)
        XCTAssertEqual(TrendsRange.month.windowDays, 30)
        XCTAssertTrue(TrendsRange.day.isIntraday)
        XCTAssertFalse(TrendsRange.week.isIntraday)
        XCTAssertFalse(TrendsRange.month.isIntraday)
    }

    @MainActor func testTrendsRangeStartDateAnchorsAtStartOfDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expectedWeekStart = calendar.date(byAdding: .day, value: -6, to: today)
        let expectedMonthStart = calendar.date(byAdding: .day, value: -29, to: today)

        XCTAssertEqual(TrendsRange.day.startDate, today)
        XCTAssertEqual(TrendsRange.week.startDate, expectedWeekStart)
        XCTAssertEqual(TrendsRange.month.startDate, expectedMonthStart)
    }

    @MainActor func testTrendsRangeDateDomainCoversWindow() {
        let domain = TrendsRange.week.dateDomain
        XCTAssertEqual(domain.lowerBound, TrendsRange.week.startDate)
        XCTAssertEqual(
            domain.upperBound,
            Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        )
    }

    @MainActor func testCalendarStartOfHourRounding() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 10, minute: 42))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 10))!
        XCTAssertEqual(calendar.startOfHour(for: date), expected)
    }
}
