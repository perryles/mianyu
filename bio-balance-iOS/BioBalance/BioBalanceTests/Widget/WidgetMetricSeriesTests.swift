import XCTest
@testable import BioBalance

nonisolated final class WidgetMetricSeriesTests: XCTestCase {
    @MainActor func testNormalizedClampsInvalidValuesAndPreservesRelativeScale() {
        let values = WidgetMetricSeries.normalized([-20, 25, 50, 120, .infinity])

        XCTAssertEqual(values, [0, 0.25, 0.5, 1, 0])
    }

    @MainActor func testRecentNormalizedKeepsNewestSamplesInChronologicalOrder() {
        let values = WidgetMetricSeries.recentNormalized([10, 20, 30, 40, 50], limit: 3)

        XCTAssertEqual(values, [0.3, 0.4, 0.5])
    }

    @MainActor func testRecentNormalizedReturnsFallbackForEmptyInput() {
        XCTAssertEqual(
            WidgetMetricSeries.recentNormalized([], limit: 4, fallback: [0.15, 0.3]),
            [0.15, 0.3]
        )
    }
}
