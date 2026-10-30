import XCTest
@testable import BioBalance

nonisolated final class SnoreAnalysisLayoutMetricsTests: XCTestCase {
    @MainActor func testCompactWidthKeepsWeekSelectorInsideContentBounds() {
        let metrics = SnoreAnalysisLayoutMetrics(containerWidth: 320)

        XCTAssertFalse(metrics.usesWideSummary)
        XCTAssertEqual(metrics.distributionColumnCount, 2)
        XCTAssertLessThanOrEqual(
            metrics.weekSelectorRequiredWidth,
            metrics.contentWidth + 0.001
        )
        XCTAssertLessThanOrEqual(metrics.scoreRingDiameter, 188)
    }

    @MainActor func testRegularWidthUsesExpandedSummaryWithoutOversizingContent() {
        let metrics = SnoreAnalysisLayoutMetrics(containerWidth: 720)

        XCTAssertTrue(metrics.usesWideSummary)
        XCTAssertEqual(metrics.distributionColumnCount, 4)
        XCTAssertEqual(metrics.dayIndicatorDiameter, 52, accuracy: 0.001)
        XCTAssertEqual(metrics.maximumContentWidth, 720, accuracy: 0.001)
    }

    @MainActor func testInvalidContainerWidthFallsBackToSafeCompactWidth() {
        let metrics = SnoreAnalysisLayoutMetrics(containerWidth: .infinity)

        XCTAssertEqual(metrics.containerWidth, 320, accuracy: 0.001)
        XCTAssertLessThanOrEqual(metrics.weekSelectorRequiredWidth, metrics.contentWidth)
    }
}
