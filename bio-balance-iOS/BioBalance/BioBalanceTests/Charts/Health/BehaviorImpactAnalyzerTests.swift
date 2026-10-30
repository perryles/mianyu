import XCTest
@testable import BioBalance

nonisolated final class BehaviorImpactAnalyzerTests: XCTestCase {
    @MainActor func testSummaryCalculatesPerfectInverseRelationship() throws {
        let summary = BehaviorImpactAnalyzer.summary(for: [
            point("1", x: 1, y: 6),
            point("2", x: 2, y: 4),
            point("3", x: 3, y: 2)
        ])

        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertEqual(try XCTUnwrap(summary.correlation), -1, accuracy: 0.000_001)
        XCTAssertEqual(summary.meanX, 2)
        XCTAssertEqual(summary.meanY, 4)
        XCTAssertEqual(summary.regressionLine.first?.y, 6)
        XCTAssertEqual(summary.regressionLine.last?.y, 2)
    }

    @MainActor func testSummaryDoesNotInferRelationshipFromTwoSamples() {
        // 两个不同点必然落在一条直线上，不应据此向用户展示“完全相关”。
        let summary = BehaviorImpactAnalyzer.summary(for: [
            point("1", x: 1, y: 2),
            point("2", x: 2, y: 4)
        ])

        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertNil(summary.correlation)
        XCTAssertTrue(summary.regressionLine.isEmpty)
    }

    @MainActor func testSummaryRejectsConstantAndNonFiniteSeries() {
        // X 没有变化时 Pearson 分母为零；无穷值也不应进入样本计数。
        let summary = BehaviorImpactAnalyzer.summary(for: [
            point("1", x: 1, y: 3),
            point("2", x: 1, y: 4),
            point("3", x: 1, y: 5),
            point("invalid", x: .infinity, y: 9)
        ])

        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertNil(summary.correlation)
        XCTAssertTrue(summary.regressionLine.isEmpty)
    }

    @MainActor private func point(_ date: String, x: Double, y: Double) -> BehaviorImpactPoint {
        BehaviorImpactPoint(date: date, x: x, y: y)
    }
}
