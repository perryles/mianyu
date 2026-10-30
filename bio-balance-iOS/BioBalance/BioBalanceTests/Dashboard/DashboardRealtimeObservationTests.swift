import XCTest
@testable import BioBalance

nonisolated final class DashboardRealtimeObservationTests: XCTestCase {
    @MainActor func testRealtimeHealthMutationPublishesChangeNotification() async {
        let notification = expectation(
            forNotification: .healthDataManagerRealtimeHealthDidChange,
            object: HealthDataManager.shared
        )
        let realtime = RealtimeHealth(
            bpm: 72,
            hrv_sdnn: 48,
            stress_value: 31,
            timestamp: 1_765_000_000
        )

        HealthDataManager.shared.realtimeHealth = realtime

        await fulfillment(of: [notification], timeout: 1)
    }

    @MainActor func testPartialVitalsPreserveCanonicalStressBundleAndEvaluationTime() {
        let existing = RealtimeHealth(
            bpm: 70,
            hrv_sdnn: 42,
            stress_value: 36,
            stress_level: StressState.normal.rawValue,
            stress_explanation_code: StressExplanationCode.fallback.rawValue,
            stress_confidence: 0.8,
            stress_quality: StressDataQuality.high.rawValue,
            stress_algorithm_version: StressResult.currentAlgorithmVersion,
            daily_stress_value: 40,
            daily_stress_quality: StressDataQuality.high.rawValue,
            daily_stress_algorithm_version: StressResult.currentAlgorithmVersion,
            timestamp: 1_765_000_000
        )
        let partialVitals = RealtimeHealth(
            bpm: 82,
            hrv_sdnn: 55,
            stress_value: 91,
            timestamp: 1_765_000_600
        )

        let merged = HealthDataManager.mergingRealtimeVitals(
            partialVitals,
            preservingCanonicalStressFrom: existing
        )

        XCTAssertEqual(merged.bpm, 82)
        XCTAssertEqual(merged.hrv, 55)
        XCTAssertEqual(merged.stress_value, existing.stress_value)
        XCTAssertEqual(merged.stress_level, existing.stress_level)
        XCTAssertEqual(merged.stress_algorithm_version, StressResult.currentAlgorithmVersion)
        XCTAssertEqual(merged.daily_stress_value, existing.daily_stress_value)
        XCTAssertEqual(merged.timestamp, existing.timestamp)
    }

    @MainActor func testCurrentAlgorithmSnapshotReplacesCanonicalStressBundle() {
        let existing = RealtimeHealth(
            bpm: 70,
            hrv_sdnn: 42,
            stress_value: 36,
            stress_level: StressState.normal.rawValue,
            stress_algorithm_version: StressResult.currentAlgorithmVersion,
            timestamp: 1_765_000_000
        )
        let current = RealtimeHealth(
            bpm: 76,
            hrv_sdnn: 48,
            stress_value: 58,
            stress_level: StressState.strained.rawValue,
            stress_confidence: 0.72,
            stress_quality: StressDataQuality.medium.rawValue,
            stress_algorithm_version: StressResult.currentAlgorithmVersion,
            timestamp: 1_765_000_600
        )

        let merged = HealthDataManager.mergingRealtimeVitals(
            current,
            preservingCanonicalStressFrom: existing
        )

        XCTAssertEqual(merged, current)
    }
}
