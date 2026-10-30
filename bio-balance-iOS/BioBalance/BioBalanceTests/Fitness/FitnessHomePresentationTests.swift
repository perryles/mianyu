import XCTest
@testable import BioBalance

nonisolated final class FitnessHomePresentationTests: XCTestCase {
    @MainActor func testScreenConfigurationPreservesQuickActionVisibility() {
        XCTAssertTrue(FitnessCalendarScreen(showsQuickActions: true).showsQuickActions)
        XCTAssertFalse(FitnessCalendarScreen(showsQuickActions: false).showsQuickActions)
    }

    @MainActor func testEmbeddedScreenConfigurationPreservesSpacing() {
        let screen = FitnessCalendarScreen(
            showsHeroTitle: false,
            contentInset: 12,
            bottomPadding: 48
        )

        XCTAssertFalse(screen.showsHeroTitle)
        XCTAssertEqual(screen.contentInset, 12)
        XCTAssertEqual(screen.bottomPadding, 48)
    }
}
