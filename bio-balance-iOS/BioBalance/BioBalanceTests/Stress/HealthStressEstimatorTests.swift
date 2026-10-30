import XCTest
@testable import BioBalance

nonisolated final class HealthStressEstimatorTests: XCTestCase {
    @MainActor func testTodayStressPointsUsesRealtimeSnapshotWhenHistoryIsEmpty() async throws {
        let timestamp = Int64(Date().timeIntervalSince1970)
        let realtime = RealtimeHealth(
            bpm: 72,
            hrv_sdnn: 48,
            stress_value: 63,
            timestamp: timestamp
        )

        let result = await HealthStressEstimator.todayStressPoints(
            realtime: realtime,
            history: HealthHistory()
        )

        let point = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(point.timestamp, timestamp)
        XCTAssertEqual(point.value, 63)
    }

    @MainActor func testStressChartGapInterpolatorFillsSixtyMinuteGapOnRealTimeAxis() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let points = [
            stressPoint(on: day, minute: 8 * 60, value: 20, calendar: calendar),
            stressPoint(on: day, minute: 9 * 60, value: 80, calendar: calendar)
        ]

        let result = StressChartGapInterpolator.interpolate(
            points: points,
            bucketSeconds: 10 * 60,
            maximumGapSeconds: 120 * 60,
            domain: day...end,
            now: end
        )

        XCTAssertEqual(result.points.map(\.timestamp), [
            timestamp(on: day, minute: 8 * 60, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 10, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 20, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 30, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 40, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 50, calendar: calendar),
            timestamp(on: day, minute: 9 * 60, calendar: calendar)
        ])
        XCTAssertEqual(result.points.map(\.value), [20, 30, 40, 50, 60, 70, 80])
        XCTAssertEqual(result.estimatedTimestamps, Set([
            timestamp(on: day, minute: 8 * 60 + 10, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 20, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 30, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 40, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 50, calendar: calendar)
        ]))
        XCTAssertTrue(result.points.allSatisfy { (1...100).contains($0.value) })
    }

    @MainActor func testStressChartGapInterpolatorFillsGapAtOneHundredTwentyMinuteLimit() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let points = [
            stressPoint(on: day, minute: 8 * 60, value: 20, calendar: calendar),
            stressPoint(on: day, minute: 10 * 60, value: 80, calendar: calendar)
        ]

        let result = StressChartGapInterpolator.interpolate(
            points: points,
            bucketSeconds: 10 * 60,
            maximumGapSeconds: 120 * 60,
            domain: day...end,
            now: end
        )

        XCTAssertEqual(result.points.count, 13)
        XCTAssertEqual(result.estimatedTimestamps.count, 11)
        XCTAssertEqual(result.points.first?.timestamp, points.first?.timestamp)
        XCTAssertEqual(result.points.last?.timestamp, points.last?.timestamp)
    }

    @MainActor func testStressChartGapInterpolatorLeavesLongGapEmpty() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let points = [
            stressPoint(on: day, minute: 8 * 60, value: 30, calendar: calendar),
            stressPoint(on: day, minute: 10 * 60 + 20, value: 70, calendar: calendar)
        ]

        let result = StressChartGapInterpolator.interpolate(
            points: points,
            bucketSeconds: 10 * 60,
            maximumGapSeconds: 120 * 60,
            domain: day...end,
            now: end
        )

        XCTAssertEqual(result.points.map(\.timestamp), points.map(\.timestamp))
        XCTAssertTrue(result.estimatedTimestamps.isEmpty)
    }

    @MainActor func testStressChartGapInterpolatorDoesNotExtrapolateOrUseFutureEndpoint() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let now = calendar.date(byAdding: .hour, value: 10, to: day) ?? day
        let points = [
            stressPoint(on: day, minute: 8 * 60, value: 30, calendar: calendar),
            stressPoint(on: day, minute: 8 * 60 + 40, value: 50, calendar: calendar),
            stressPoint(on: day, minute: 10 * 60 + 20, value: 90, calendar: calendar)
        ]

        let result = StressChartGapInterpolator.interpolate(
            points: points,
            bucketSeconds: 10 * 60,
            maximumGapSeconds: 120 * 60,
            domain: day...end,
            now: now
        )

        XCTAssertEqual(result.points.map(\.timestamp), [
            timestamp(on: day, minute: 8 * 60, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 10, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 20, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 30, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 40, calendar: calendar)
        ])
        XCTAssertEqual(result.estimatedTimestamps, Set([
            timestamp(on: day, minute: 8 * 60 + 10, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 20, calendar: calendar),
            timestamp(on: day, minute: 8 * 60 + 30, calendar: calendar)
        ]))
    }

    @MainActor func testStressChartGapInterpolatorDoesNotBridgeAcrossDays() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let domainEnd = calendar.date(byAdding: .day, value: 1, to: nextDay) ?? nextDay.addingTimeInterval(86_400)
        let points = [
            stressPoint(on: day, minute: 23 * 60 + 40, value: 30, calendar: calendar),
            stressPoint(on: nextDay, minute: 20, value: 70, calendar: calendar)
        ]

        let result = StressChartGapInterpolator.interpolate(
            points: points,
            bucketSeconds: 10 * 60,
            maximumGapSeconds: 120 * 60,
            domain: day...domainEnd,
            now: domainEnd
        )

        XCTAssertEqual(result.points.map(\.timestamp), points.map(\.timestamp))
        XCTAssertTrue(result.estimatedTimestamps.isEmpty)
    }

    @MainActor func testSevenMinuteStressPointsSupportsHeartRateOnlyWithRestingBaseline() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let interval = DateInterval(
            start: day,
            end: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        )
        let heartRate = [8, 16, 24].map { minute in
            let date = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
            return TimeSeriesPoint(timestamp: Int64(date.timeIntervalSince1970), value: 90)
        }

        let result = StressDailyEngine.sevenMinuteStressPoints(
            hrv: [],
            heartRate: heartRate,
            restingHeartRate: 60,
            in: interval
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.value > 0 })
    }

    @MainActor func testSevenMinuteStressPointsEstimatesRestingBaselineForHeartRateOnlyData() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let interval = DateInterval(
            start: day,
            end: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        )
        let heartRate = [
            heartRatePoint(on: day, hour: 8, value: 55, calendar: calendar),
            heartRatePoint(on: day, hour: 9, value: 68, calendar: calendar),
            heartRatePoint(on: day, hour: 10, value: 75, calendar: calendar),
            heartRatePoint(on: day, hour: 11, value: 82, calendar: calendar)
        ]

        let result = StressDailyEngine.sevenMinuteStressPoints(
            hrv: [],
            heartRate: heartRate,
            restingHeartRate: nil,
            in: interval
        )

        XCTAssertEqual(result.count, heartRate.count)
        XCTAssertTrue(result.allSatisfy { $0.value > 0 })
    }

    @MainActor func testResolvedRestingHeartRateBaselinePrefersMeasuredValue() {
        let heartRate = [
            TimeSeriesPoint(timestamp: 1, value: 50),
            TimeSeriesPoint(timestamp: 2, value: 55),
            TimeSeriesPoint(timestamp: 3, value: 60)
        ]

        let result = StressDailyEngine.resolvedRestingHeartRateBaseline(
            measured: 64,
            historical: 58,
            heartRate: heartRate
        )

        XCTAssertEqual(result, 64)
    }

    @MainActor func testResolvedRestingHeartRateBaselinePrefersHistoricalValueOverEstimate() {
        let heartRate = [
            TimeSeriesPoint(timestamp: 1, value: 50),
            TimeSeriesPoint(timestamp: 2, value: 55),
            TimeSeriesPoint(timestamp: 3, value: 60)
        ]

        let result = StressDailyEngine.resolvedRestingHeartRateBaseline(
            measured: nil,
            historical: 58,
            heartRate: heartRate
        )

        XCTAssertEqual(result, 58)
    }

    @MainActor func testResolvedRestingHeartRateBaselineRequiresThreeHeartRateSamplesForEstimate() {
        let result = StressDailyEngine.resolvedRestingHeartRateBaseline(
            measured: nil,
            historical: nil,
            heartRate: [
                TimeSeriesPoint(timestamp: 1, value: 55),
                TimeSeriesPoint(timestamp: 2, value: 60)
            ]
        )

        XCTAssertNil(result)
    }

    @MainActor func testSevenMinuteStressPointsSupportsHrvOnlyWithPersonalBaseline() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let interval = DateInterval(
            start: day,
            end: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        )
        let sampleDate = calendar.date(byAdding: .hour, value: 8, to: day) ?? day

        let result = StressDailyEngine.sevenMinuteStressPoints(
            hrv: [TimeSeriesPointDouble(
                timestamp: Int64(sampleDate.timeIntervalSince1970),
                value: 35
            )],
            heartRate: [],
            restingHeartRate: nil,
            hrvBaseline: 50,
            in: interval
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertGreaterThan(result[0].value, 0)
    }

    @MainActor func testEstimateDailyStressAveragesDuplicateSamplesWithinSameDay() throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

        let result = HealthStressEstimator.estimateDailyStress(
            hrv: [
                point(on: day, hour: 8, value: 40, calendar: calendar),
                point(on: day, hour: 12, value: 60, calendar: calendar)
            ],
            heartRate: [
                point(on: day, hour: 9, value: 70, calendar: calendar),
                point(on: day, hour: 13, value: 90, calendar: calendar)
            ],
            restingHeartRate: [
                point(on: day, hour: 7, value: 55, calendar: calendar),
                point(on: day, hour: 14, value: 65, calendar: calendar)
            ]
        )

        let dailyPoint = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(dailyPoint.date, day)
        XCTAssertEqual(
            dailyPoint.value,
            Double(HealthStressEstimator.estimate(hrv: 50, heartRate: 80, restingHeartRate: 60))
        )
    }

    @MainActor func testEstimateDailyStressSupportsHeartRateOnlyDevices() throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

        let result = HealthStressEstimator.estimateDailyStress(
            hrv: [],
            heartRate: [point(on: day, hour: 12, value: 90, calendar: calendar)],
            restingHeartRate: [point(on: day, hour: 7, value: 60, calendar: calendar)]
        )

        let dailyPoint = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertGreaterThanOrEqual(dailyPoint.value, 70)
    }

    @MainActor func testEstimateDailyStressUsesFallbackRestingBaselineForHeartRateOnlyRange() {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let heartRates = [67.1, 74.3, 74.52, 76.35, 69.33, 69.75, 65.19]
            .enumerated()
            .compactMap { offset, value -> TimeSeriesPointDouble? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
                return point(on: day, hour: 12, value: value, calendar: calendar)
            }

        let result = HealthStressEstimator.estimateDailyStress(
            hrv: [],
            heartRate: heartRates,
            restingHeartRate: [],
            restingHeartRateBaseline: 59
        )

        XCTAssertEqual(result.count, 7)
        XCTAssertTrue(result.allSatisfy { $0.value > 0 })
    }

    @MainActor func testEstimateDailyStressDerivesRangeBaselineWhenRestingSamplesAreMissing() {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let heartRates = [67.1, 74.3, 74.52, 76.35, 69.33, 69.75, 65.19]
            .enumerated()
            .compactMap { offset, value -> TimeSeriesPointDouble? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
                return point(on: day, hour: 12, value: value, calendar: calendar)
            }

        let result = HealthStressEstimator.estimateDailyStress(
            hrv: [],
            heartRate: heartRates,
            restingHeartRate: []
        )

        XCTAssertEqual(result.count, 7)
        XCTAssertTrue(result.allSatisfy { $0.value > 0 })
    }

    @MainActor private func point(
        on day: Date,
        hour: Int,
        value: Double,
        calendar: Calendar
    ) -> TimeSeriesPointDouble {
        let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        return TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
    }

    @MainActor private func heartRatePoint(
        on day: Date,
        hour: Int,
        value: Int,
        calendar: Calendar
    ) -> TimeSeriesPoint {
        let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        return TimeSeriesPoint(timestamp: Int64(date.timeIntervalSince1970), value: value)
    }

    @MainActor private func stressPoint(
        on day: Date,
        minute: Int,
        value: Int,
        calendar: Calendar
    ) -> TimeSeriesPoint {
        TimeSeriesPoint(
            timestamp: timestamp(on: day, minute: minute, calendar: calendar),
            value: value
        )
    }

    @MainActor private func timestamp(on day: Date, minute: Int, calendar: Calendar) -> Int64 {
        let date = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
        return Int64(date.timeIntervalSince1970)
    }
}
