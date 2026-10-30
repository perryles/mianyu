import SwiftUI
import XCTest
@testable import BioBalance

nonisolated final class AdaptiveLayoutContextTests: XCTestCase {
    @MainActor func testWidePhoneWindowUsesExpandedLayoutWithoutDeviceIdiom() {
        let layout = AdaptiveLayoutContext(
            containerWidth: 900,
            containerHeight: 700,
            horizontalSizeClass: .regular
        )

        XCTAssertTrue(layout.usesExpandedLayout)
        XCTAssertTrue(layout.prefersTwoPaneLayout)
        XCTAssertEqual(layout.rootGridColumnCount, 2)
    }

    @MainActor func testNarrowSplitWindowStaysCompact() {
        let layout = AdaptiveLayoutContext(
            containerWidth: 540,
            containerHeight: 900,
            horizontalSizeClass: .compact
        )

        XCTAssertFalse(layout.usesExpandedLayout)
        XCTAssertFalse(layout.prefersTwoPaneLayout)
        XCTAssertEqual(layout.rootGridColumnCount, 2)
    }

    @MainActor func testVeryWideWindowSupportsThreeColumns() {
        let layout = AdaptiveLayoutContext(
            containerWidth: 1_180,
            containerHeight: 820,
            horizontalSizeClass: .regular
        )

        XCTAssertTrue(layout.supportsThreeColumns)
        XCTAssertEqual(layout.rootGridColumnCount, 3)
    }
}
