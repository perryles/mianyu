import XCTest
@testable import BioBalance

nonisolated final class StressRulesTests: XCTestCase {
    @MainActor func testRealtimeStateBoundaries() {
        XCTAssertEqual(StressRules.state(for: 0), .recovery)
        XCTAssertEqual(StressRules.state(for: 14), .recovery)
        XCTAssertEqual(StressRules.state(for: 15), .relaxed)
        XCTAssertEqual(StressRules.state(for: 29), .relaxed)
        XCTAssertEqual(StressRules.state(for: 30), .normal)
        XCTAssertEqual(StressRules.state(for: 49), .normal)
        XCTAssertEqual(StressRules.state(for: 50), .strained)
        XCTAssertEqual(StressRules.state(for: 69), .strained)
        XCTAssertEqual(StressRules.state(for: 70), .highStress)
        XCTAssertEqual(StressRules.state(for: 84), .highStress)
        XCTAssertEqual(StressRules.state(for: 85), .overloaded)
        XCTAssertEqual(StressRules.state(for: 100), .overloaded)
    }

    @MainActor func testPresentationBandBoundaries() {
        XCTAssertEqual(StressRules.band(for: 29), .relaxed)
        XCTAssertEqual(StressRules.band(for: 30), .steady)
        XCTAssertEqual(StressRules.band(for: 49), .steady)
        XCTAssertEqual(StressRules.band(for: 50), .mild)
        XCTAssertEqual(StressRules.band(for: 69), .mild)
        XCTAssertEqual(StressRules.band(for: 70), .caution)
        XCTAssertEqual(StressRules.band(for: 84), .caution)
        XCTAssertEqual(StressRules.band(for: 85), .high)
    }
}
