import Foundation
import XCTest
@testable import BioBalance

nonisolated final class StressPresentationStoreTests: XCTestCase {
    @MainActor func testUnavailablePresentationHasNoScore() {
        let assessment = StressPresentation.assessment(from: .unavailable(.staleHeartRate))
        XCTAssertNil(assessment.score)
        XCTAssertEqual(assessment.band, .waiting)
        XCTAssertEqual(assessment.quality, .unavailable)
        XCTAssertEqual(assessment.unavailableReason, .staleHeartRate)
    }

    @MainActor func testAdviceOnlyMentionsParticipatingDriver() {
        let descriptor = StressPresentation.descriptor(
            for: .mild,
            explanation: .heartRateAboveBaseline,
            availableDrivers: [.hrDeviation]
        )
        XCTAssertTrue(descriptor.adviceDetail.contains("心率"))
        XCTAssertFalse(descriptor.adviceDetail.contains("HRV"))
    }

    @MainActor func testStaleRealtimeResultIsNotPresentedAsCurrent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let realtime = RealtimeHealth(
            bpm: 72,
            stress_value: 42,
            stress_level: StressState.normal.rawValue,
            timestamp: Int64(now.addingTimeInterval(-StressRules.heartRateFreshness - 1).timeIntervalSince1970)
        )

        XCTAssertNil(StressPresentation.assessment(from: realtime, now: now))
        XCTAssertEqual(StressPresentation.evaluation(from: realtime, now: now), .unavailable(.staleResult))
    }

    @MainActor func testObsoleteAssessmentCacheIsRemoved() throws {
        let suite = "StressStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let obsolete: [String: Any] = [
            "score": 48,
            "band": "steady",
            "title": "平稳",
            "adviceTitle": "保持节奏",
            "adviceDetail": "历史数据",
            "tint": "mintGreen",
            "updatedAtSeconds": 1_800_000_000
        ]
        let obsoleteKey = "todayStressAssessment.v1"
        let contaminatedStressKey = "stressSnapshot.v2"
        defaults.set(try JSONSerialization.data(withJSONObject: obsolete), forKey: obsoleteKey)
        defaults.set(Data([0x01]), forKey: contaminatedStressKey)

        _ = StressStore(defaults: defaults)
        XCTAssertNil(defaults.data(forKey: obsoleteKey))
        XCTAssertNil(defaults.data(forKey: contaminatedStressKey))
    }
}
