import XCTest
@testable import BioBalance

nonisolated final class WatchSnapshotArbitrationTests: XCTestCase {
    @MainActor func testUntypedRealtimePayloadNormalizesToTypedVitalsEnvelope() {
        let envelope = WatchSyncEnvelope.fromDictionary([
            "bpm": 72.0,
            "hrv": 48,
            "stress": 31.0,
            "timestamp": 1_000
        ])

        guard case let .realtimeVitals(vitals, requestId) = envelope else {
            return XCTFail("Expected typed realtime vitals")
        }
        XCTAssertNil(requestId)
        XCTAssertEqual(vitals.bpm, 72)
        XCTAssertEqual(vitals.hrv, 48)
        XCTAssertEqual(vitals.stress, 31)
        XCTAssertEqual(vitals.timestamp, 1_000)
    }

    @MainActor func testTypedRealtimeVitalsRoundTrip() {
        let original = WatchRealtimeVitals(bpm: 68, hrv: nil, stress: 22, timestamp: 2_000)
        let decoded = WatchSyncEnvelope.fromDictionary(
            WatchSyncEnvelope.realtimeVitals(original, requestId: "request-1").toDictionary()
        )

        XCTAssertEqual(decoded, .realtimeVitals(original, requestId: "request-1"))
    }

    @MainActor func testUntypedFullSnapshotStillUsesSnapshotEnvelope() {
        let envelope = WatchSyncEnvelope.fromDictionary([
            "bpm": 72,
            "hrv": 48.0,
            "stress": 31,
            "steps": 5_000
        ])

        guard case let .snapshot(snapshot, _) = envelope else {
            return XCTFail("Expected full snapshot")
        }
        XCTAssertEqual(snapshot.bpm, 72)
        XCTAssertEqual(snapshot.steps, 5_000)
    }

    @MainActor func testRemoteOrderingDoesNotCompareAgainstLocalSnapshotTimestamp() {
        XCTAssertTrue(
            WatchSnapshotArbitration.shouldAcceptRemoteSnapshot(
                incomingTimestamp: 100,
                lastAcceptedRemoteTimestamp: nil
            )
        )
        XCTAssertTrue(
            WatchSnapshotArbitration.shouldAcceptRemoteSnapshot(
                incomingTimestamp: 101,
                lastAcceptedRemoteTimestamp: 100
            )
        )
        XCTAssertFalse(
            WatchSnapshotArbitration.shouldAcceptRemoteSnapshot(
                incomingTimestamp: 99,
                lastAcceptedRemoteTimestamp: 100
            )
        )
    }

    @MainActor func testResolvedTimestampKeepsAppGroupWritesMonotonic() {
        XCTAssertEqual(
            WatchSnapshotArbitration.resolvedTimestamp(
                incomingTimestamp: 100,
                currentTimestamp: 105
            ),
            105
        )
    }

    @MainActor func testOnlyNewerLocalHeartRateIsPreserved() {
        XCTAssertTrue(
            WatchSnapshotArbitration.shouldPreserveLocalHeartRate(
                localPublishedAt: Date(timeIntervalSince1970: 101),
                incomingTimestamp: 100
            )
        )
        XCTAssertFalse(
            WatchSnapshotArbitration.shouldPreserveLocalHeartRate(
                localPublishedAt: Date(timeIntervalSince1970: 99),
                incomingTimestamp: 100
            )
        )
    }
}
