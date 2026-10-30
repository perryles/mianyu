import XCTest
@testable import BioBalance

nonisolated final class SedentaryReminderSettingsTests: XCTestCase {
    @MainActor func testNextReminderUsesConfiguredInterval() {
        XCTAssertEqual(
            DashboardSedentaryState.nextReminderMinute(elapsedMinutes: 61, intervalMinutes: 60),
            120
        )
        XCTAssertEqual(
            DashboardSedentaryState.nextReminderMinute(elapsedMinutes: 120, intervalMinutes: 60),
            180
        )
    }
}
