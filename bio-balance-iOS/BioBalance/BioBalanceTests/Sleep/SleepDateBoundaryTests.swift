import HealthKit
import XCTest
@testable import BioBalance

nonisolated final class SleepDateBoundaryTests: XCTestCase {
    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor func testPrimarySleepClusterIgnoresLongerClusterFromPreviousDay() throws {
        let previousNight = [
            try sleepSample(start: "2026-08-09T22:00:00Z", end: "2026-08-10T08:00:00Z")
        ]
        let targetNight = [
            try sleepSample(start: "2026-08-10T23:00:00Z", end: "2026-08-11T06:00:00Z")
        ]
        let targetDate = try date("2026-08-11T12:00:00Z")

        let selected = HealthKitManager.shared.primarySleepCluster(
            in: [previousNight, targetNight],
            on: targetDate,
            calendar: calendar
        )

        XCTAssertEqual(selected?.first?.startDate, targetNight[0].startDate)
        XCTAssertEqual(selected?.first?.endDate, targetNight[0].endDate)
    }

    @MainActor func testPrimarySleepClusterReturnsNilWhenOnlyPreviousDayHasSleep() throws {
        let previousNight = [
            try sleepSample(start: "2026-08-09T22:00:00Z", end: "2026-08-10T08:00:00Z")
        ]

        let selected = HealthKitManager.shared.primarySleepCluster(
            in: [previousNight],
            on: try date("2026-08-11T12:00:00Z"),
            calendar: calendar
        )

        XCTAssertNil(selected)
    }

    @MainActor func testDailySelectorDoesNotUsePreviousNightAsTodayFallback() throws {
        let oldVital = HealthKitManager.NightlyAverageVital(
            date: try date("2026-08-10T00:00:00Z"),
            start: try date("2026-08-09T23:00:00Z"),
            end: try date("2026-08-10T07:00:00Z"),
            averageValue: 58,
            sampleCount: 20
        )

        let selected = SleepDayDataSelector.latest(
            in: [oldVital],
            matching: try date("2026-08-11T12:00:00Z"),
            calendar: calendar,
            date: \.date
        )

        XCTAssertNil(selected)
    }

    @MainActor func testDurationFallbackDoesNotUsePreviousDayValue() throws {
        let previousDuration = TimeSeriesPointDouble(
            timestamp: Int64(try date("2026-08-10T00:00:00Z").timeIntervalSince1970),
            value: 480
        )

        let selected = SleepDayDataSelector.latest(
            in: [previousDuration],
            matching: try date("2026-08-11T12:00:00Z"),
            calendar: calendar,
            date: \.date
        )

        XCTAssertNil(selected)
    }

    @MainActor func testDailySelectorReturnsOnlyTargetNightWhenHistoryContainsNewerItems() throws {
        let targetVital = HealthKitManager.NightlyAverageVital(
            date: try date("2026-08-11T00:00:00Z"),
            start: try date("2026-08-10T23:00:00Z"),
            end: try date("2026-08-11T07:00:00Z"),
            averageValue: 61,
            sampleCount: 20
        )
        let futureVital = HealthKitManager.NightlyAverageVital(
            date: try date("2026-08-12T00:00:00Z"),
            start: try date("2026-08-11T23:00:00Z"),
            end: try date("2026-08-12T07:00:00Z"),
            averageValue: 64,
            sampleCount: 20
        )

        let selected = SleepDayDataSelector.latest(
            in: [targetVital, futureVital],
            matching: try date("2026-08-11T12:00:00Z"),
            calendar: calendar,
            date: \.date
        )

        XCTAssertEqual(selected?.averageValue, 61)
    }

    @MainActor private func sleepSample(start: String, end: String) throws -> HKCategorySample {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw XCTSkip("Sleep Analysis is unavailable")
        }
        return HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: try date(start),
            end: try date(end)
        )
    }

    @MainActor private func date(_ value: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            XCTFail("Invalid test date: \(value)")
            throw TestDateError.invalidDate
        }
        return date
    }

    private enum TestDateError: Error {
        case invalidDate
    }
}
