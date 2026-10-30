import XCTest
@testable import BioBalance

nonisolated final class HRVPenGeometryTests: XCTestCase {
    func testPointerExitCannotClearAnActiveTouch() {
        var state = HRVPenInspection()
        state.select(1, input: .pointer)
        state.select(2, input: .touch)
        state.end(.pointer)
        XCTAssertEqual(state.index, 2)
        state.end(.touch)
        XCTAssertNil(state.index)
        XCTAssertEqual(state.lastIndex, 2, "The fading tooltip retains the last readout")
    }

    func testTouchCancellationDoesNotClearVoiceOverSelection() {
        var state = HRVPenInspection()
        state.adjust(by: -1, count: 4)
        XCTAssertEqual(state.index, 2)
        state.end(.touch)
        state.end(.pointer)
        XCTAssertEqual(state.index, 2)
        state.end(.accessibility)
        XCTAssertNil(state.index)
    }

    func testAccessibleSelectionClampsAndResetsForLiveUpdates() {
        var state = HRVPenInspection()
        state.adjust(by: 1, count: 2)
        XCTAssertEqual(state.index, 1)
        state.adjust(by: -1, count: 2)
        state.adjust(by: -1, count: 2)
        XCTAssertEqual(state.index, 0)
        state.reset()
        XCTAssertNil(state.index)
        XCTAssertNil(state.input)
        XCTAssertEqual(state.lastIndex, 0)
        state.adjust(by: 1, count: 0)
        XCTAssertNil(state.index)
    }

    func testSelectionIgnoresInvalidGeometry() {
        XCTAssertNil(HRVPenGeometry.nearestIndex(x: .nan, positions: [.zero]))
        XCTAssertNil(HRVPenGeometry.nearestIndex(x: 0, positions: [CGPoint(x: CGFloat.infinity, y: 0)]))
        XCTAssertEqual(HRVPenGeometry.nearestIndex(x: 0, positions: [CGPoint(x: CGFloat.nan, y: 0), .zero]), 1)
    }

    func testStrokeAndFillShareAnExactPartialTip() throws {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), CGPoint(x: 9, y: 4)]
        let visible = HRVPenGeometry.revealedPoints(points, progress: 0.5)
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(try XCTUnwrap(visible.last).x, 3.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(visible.last).y, 4, accuracy: 0.0001)
    }

    func testProgressHandlesEmptySingleAndRepeatedSamples() {
        XCTAssertTrue(HRVPenGeometry.revealedPoints([], progress: 1).isEmpty)
        let point = CGPoint(x: 2, y: 5)
        XCTAssertEqual(HRVPenGeometry.revealedPoints([point], progress: 0.5), [point])
        XCTAssertEqual(HRVPenGeometry.revealedPoints([point, point], progress: 0.5), [point])
    }

    func testEntranceStartsEmptyAndFinishesAtTheRealEndpoint() {
        let points = [CGPoint(x: 1, y: 1), CGPoint(x: 10, y: 4)]
        XCTAssertTrue(HRVPenGeometry.revealedPoints(points, progress: 0).isEmpty)
        XCTAssertTrue(HRVPenGeometry.revealedPoints(points, progress: -1).isEmpty)
        XCTAssertEqual(HRVPenGeometry.revealedPoints(points, progress: 1), points)
        XCTAssertEqual(HRVPenGeometry.revealedPoints(points, progress: 2), points)
    }

    func testTouchAndMouseSnapToRealSamplesIncludingEdges() {
        let points = [CGPoint(x: 5, y: 2), CGPoint(x: 45, y: 9), CGPoint(x: 90, y: 3)]
        XCTAssertNil(HRVPenGeometry.nearestIndex(x: 0, positions: []))
        XCTAssertEqual(HRVPenGeometry.nearestIndex(x: -100, positions: points), 0)
        XCTAssertEqual(HRVPenGeometry.nearestIndex(x: 53, positions: points), 1)
        XCTAssertEqual(HRVPenGeometry.nearestIndex(x: 500, positions: points), 2)
    }
}
