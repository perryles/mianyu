import XCTest
@testable import BioBalance

nonisolated final class HealthKitReadLogTests: XCTestCase {
    @MainActor func testMessageContainsOnlyStableReadFields() {
        let message = HealthKitReadLog.message(
            metric: "heartRate.latest",
            status: .dataAvailable
        )

        XCTAssertEqual(
            message,
            "[HealthKit] operation=read technicalID=heartRate.latest"
        )
        XCTAssertFalse(message.contains("count="))
        XCTAssertFalse(message.contains("range="))
        XCTAssertFalse(message.contains("value="))
        XCTAssertFalse(message.contains("status="))
    }

    @MainActor func testNoDataResultKeepsStableFields() {
        XCTAssertEqual(
            HealthKitReadLog.message(metric: "vo2Max.latest", status: .noData),
            "[HealthKit] operation=read technicalID=vo2Max.latest"
        )
    }

    @MainActor func testFailureResultDoesNotIncludeErrorDescription() {
        XCTAssertEqual(
            HealthKitReadLog.message(metric: "height.latest", status: .queryFailed),
            "[HealthKit] operation=read technicalID=height.latest"
        )
    }
}
