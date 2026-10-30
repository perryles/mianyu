import XCTest
@testable import BioBalance

nonisolated final class DashboardRefreshPolicyTests: XCTestCase {
    @MainActor private let policy = DashboardRefreshPolicy(minimumInterval: .seconds(30))

    @MainActor func testFirstLoadAlwaysRefreshes() {
        XCTAssertTrue(policy.shouldRefresh(
            requestedDate: Date(),
            lastLoadedDate: nil,
            lastLoadedAt: nil,
            now: ContinuousClock().now,
            calendar: calendar(),
            force: false
        ))
    }

    @MainActor func testRecentSameDayLoadUsesCache() {
        let clock = ContinuousClock()
        let now = clock.now
        let date = makeDate(year: 2026, month: 7, day: 26, hour: 12)

        XCTAssertFalse(policy.shouldRefresh(
            requestedDate: date,
            lastLoadedDate: date,
            lastLoadedAt: now.advanced(by: .seconds(-10)),
            now: now,
            calendar: calendar(),
            force: false
        ))
    }

    @MainActor func testExpiredSameDayLoadRefreshes() {
        let clock = ContinuousClock()
        let now = clock.now
        let date = makeDate(year: 2026, month: 7, day: 26, hour: 12)

        XCTAssertTrue(policy.shouldRefresh(
            requestedDate: date,
            lastLoadedDate: date,
            lastLoadedAt: now.advanced(by: .seconds(-31)),
            now: now,
            calendar: calendar(),
            force: false
        ))
    }

    @MainActor func testDifferentCalendarDayRefreshesAcrossDSTBoundary() {
        let cal = calendar()
        let beforeDST = makeDate(year: 2026, month: 3, day: 28, hour: 23, calendar: cal)
        let afterDST = makeDate(year: 2026, month: 3, day: 29, hour: 1, calendar: cal)
        let clock = ContinuousClock()
        let now = clock.now

        XCTAssertTrue(policy.shouldRefresh(
            requestedDate: afterDST,
            lastLoadedDate: beforeDST,
            lastLoadedAt: now,
            now: now,
            calendar: cal,
            force: false
        ))
    }

    @MainActor func testForceBypassesFreshCache() {
        let clock = ContinuousClock()
        let now = clock.now
        let date = Date()

        XCTAssertTrue(policy.shouldRefresh(
            requestedDate: date,
            lastLoadedDate: date,
            lastLoadedAt: now,
            now: now,
            calendar: calendar(),
            force: true
        ))
    }

    @MainActor private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    @MainActor private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar? = nil
    ) -> Date {
        (calendar ?? self.calendar()).date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
