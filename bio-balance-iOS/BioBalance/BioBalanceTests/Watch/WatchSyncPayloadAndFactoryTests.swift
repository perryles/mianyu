import XCTest
import WatchConnectivity
import Synchronization
@testable import BioBalance

nonisolated final class WatchSyncPayloadAndFactoryTests: XCTestCase {
    @MainActor func testBackgroundDelegateDeliversDecodedVitalsOnMainActor() async throws {
        let service = WatchConnectivitySyncService()
        var received: WatchRealtimeVitals?
        service.onRealtimeVitalsReceived = { received = $0 }
        await Task.detached {
            service.session(WCSession.default, didReceiveMessage: ["type": "realtime_vitals", "bpm": 72])
        }.value
        for _ in 0..<50 where received == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(received?.bpm, 72)
    }

    @MainActor func testBackgroundHabitDelegateRepliesOnlyOnceWhenCompletionRepeats() async throws {
        let service = WatchConnectivitySyncService()
        let replies = Mutex(0)
        service.onRecordHabit = { _, _, complete in
            complete(["ok": true])
            complete(["ok": true])
        }
        await Task.detached {
            service.session(
                WCSession.default,
                didReceiveMessage: ["type": "record_habit", "habitType": "water", "amount": 200],
                replyHandler: { _ in replies.withLock { $0 += 1 } }
            )
        }.value
        for _ in 0..<50 where replies.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(replies.withLock { $0 }, 1)
    }

    @MainActor func testPaceSecondsPerKilometerConvertsSpeed() {
        XCTAssertNil(WatchSyncMetrics.paceSecondsPerKilometer(from: nil))
        XCTAssertNil(WatchSyncMetrics.paceSecondsPerKilometer(from: 0))
        XCTAssertEqual(WatchSyncMetrics.paceSecondsPerKilometer(from: 1.25), 800)
        XCTAssertEqual(WatchSyncMetrics.paceSecondsPerKilometer(from: 2.0), 500)
    }

    @MainActor func testWatchMascotContentPolicyTrimsAndLimitsCustomMessage() {
        XCTAssertEqual(WatchMascotContentPolicy.normalize("  今天也要照顾好自己  \n"), "今天也要照顾好自己")
        XCTAssertEqual(
            WatchMascotContentPolicy.normalize(String(repeating: "好", count: 30)),
            String(repeating: "好", count: WatchMascotContentPolicy.maximumLength)
        )
        XCTAssertNil(WatchMascotContentPolicy.normalize("  \n "))
    }

    @MainActor func testWatchMascotInteractionMotionMatchesEmotionBallGestureContract() {
        XCTAssertEqual(WatchMascotInteractionMotion.normalizedDrag(translation: 80, extent: 40), 1)
        XCTAssertEqual(WatchMascotInteractionMotion.normalizedDrag(translation: -80, extent: 40), -1)
        XCTAssertEqual(WatchMascotInteractionMotion.normalizedDrag(translation: 10, extent: 40), 0.25)

        XCTAssertEqual(WatchMascotInteractionMotion.bounceOffset(elapsed: 0), 0, accuracy: 0.001)
        XCTAssertLessThan(WatchMascotInteractionMotion.bounceOffset(elapsed: 0.25), 0)
        XCTAssertEqual(WatchMascotInteractionMotion.bounceOffset(elapsed: 1.35), 0, accuracy: 0.001)
        XCTAssertEqual(WatchMascotInteractionMotion.spinDegrees(elapsed: 0.65), 720, accuracy: 0.001)
        XCTAssertEqual(WatchMascotInteractionMotion.burstProgress(elapsed: 0.3), 0.5, accuracy: 0.001)
        XCTAssertTrue(WatchMascotInteractionMotion.shouldCelebrate(travel: 0, didLongPress: false, reduceMotion: false))
        XCTAssertFalse(WatchMascotInteractionMotion.shouldCelebrate(travel: 0, didLongPress: true, reduceMotion: false))
        XCTAssertFalse(WatchMascotInteractionMotion.shouldCelebrate(travel: 0, didLongPress: false, reduceMotion: true))
    }

    @MainActor func testWatchMascotMessageUpdatePolicyPreservesLegacyValueAndSupportsExplicitClear() {
        XCTAssertEqual(
            WatchMascotMessageUpdatePolicy.resolve(current: "原来的陪伴语", incoming: nil, isConfigured: nil),
            "原来的陪伴语"
        )
        XCTAssertNil(
            WatchMascotMessageUpdatePolicy.resolve(current: "原来的陪伴语", incoming: nil, isConfigured: true)
        )
        XCTAssertEqual(
            WatchMascotMessageUpdatePolicy.resolve(current: nil, incoming: "慢一点", isConfigured: true),
            "慢一点"
        )
    }

    @MainActor func testTypedSnapshotWireRoundTripPreservesOptionalFields() {
        let original = WatchSyncEnvelope.fromDictionary(makeTypedSnapshotDictionary())

        guard case let .snapshot(snapshot, requestId) = original else {
            return XCTFail("Expected typed snapshot")
        }
        XCTAssertEqual(requestId, "request-9")

        let decoded = WatchSyncEnvelope.fromDictionary(
            WatchSyncEnvelope.snapshot(snapshot, requestId: requestId)
                .toDictionary(now: Date(timeIntervalSince1970: 1_234))
        )

        XCTAssertEqual(decoded, .snapshot(snapshot, requestId: requestId))
    }

    @MainActor func testUntypedSnapshotPreservesRecoveryPlanAndMapsToWidgetPlan() {
        let dict: [String: Any] = [
            "bpm": 70,
            "hrv": 40.0,
            "stress": 25,
            "stressTrend": "稳定",
            "timestamp": 1_000,
            "steps": 0,
            "activeEnergy": 0,
            "exerciseMinutes": 0,
            "standHours": 0,
            "stepsGoal": 8_000,
            "activeEnergyGoal": 500,
            "exerciseMinutesGoal": 30,
            "standHoursGoal": 12,
            "sleepDurationMinutes": 0,
            "sleepScore": 0,
            "waterIntakeMl": 0,
            "waterTargetMl": 2_000,
            "waterCompletionRate": 0.0,
            "caffeineRemainedMg": 0,
            "sedentaryElapsedMinutes": 0,
            "sedentaryIsCounting": false,
            "sedentaryPausedBySleep": false,
            "sedentaryBreakIsActive": false,
            "sedentaryBreakDurationMinutes": 0,
            "stressHistory": [],
            "watchThemeId": "joey",
            "watchMascotEnabled": false,
            "watchMascotMessage": "慢一点，也很好",
            "watchMascotMessageConfigured": true,
            "recoveryPlan": [
                "planID": "plan-1",
                "dayStart": 1_000,
                "actions": [
                    ["actionID": "main-1", "title": "喝水", "role": "main", "state": "completed"],
                    ["actionID": "support-1", "title": "走动", "role": "supporting", "state": "pending"]
                ]
            ]
        ]

        guard case let .snapshot(snapshot, requestId) = WatchSyncEnvelope.fromDictionary(dict) else {
            return XCTFail("Expected typed snapshot")
        }
        XCTAssertNil(requestId)
        XCTAssertEqual(snapshot.watchThemeId, "joey")
        XCTAssertEqual(snapshot.watchMascotEnabled, false)
        XCTAssertEqual(snapshot.watchMascotMessage, "慢一点，也很好")
        XCTAssertEqual(snapshot.watchMascotMessageConfigured, true)
        XCTAssertEqual(snapshot.recoveryPlan?.planID, "plan-1")
        XCTAssertEqual(
            snapshot.recoveryPlan?.actions.first,
            WatchRecoveryPlanActionSnapshot(actionID: "main-1", title: "喝水", role: "main", state: "completed")
        )

        let widgetPlan = snapshot.widgetRecoveryPlan
        XCTAssertEqual(widgetPlan?.planID, "plan-1")
        XCTAssertEqual(widgetPlan?.actions.count, 2)
        XCTAssertEqual(widgetPlan?.actions.first?.role, .main)
        XCTAssertEqual(widgetPlan?.actions.first?.state, .completed)
        XCTAssertEqual(widgetPlan?.processedActionCount, 1)
        XCTAssertEqual(widgetPlan?.nextAction?.actionID, "support-1")
    }

    @MainActor func testRecoveryPlanProjectionUsesActionStateDefaults() {
        let date = Date(timeIntervalSince1970: 1_000)
        let plan = DailyRecoveryOrchestrationPlan(
            date: date,
            mainGoal: "喝水",
            mainGoalDetail: "补充水分",
            supportingActions: ["起身走动", "短暂休息"],
            deferredSuggestions: [],
            readinessBand: .balanced,
            reason: "测试",
            generatedAt: date
        )
        let states = [
            plan.mainActionID: DailyRecoveryActionStateRecord(
                planID: plan.planID,
                actionID: plan.mainActionID,
                state: .completed,
                reason: nil,
                updatedAt: date
            ),
            plan.supportingActionIDs[0]: DailyRecoveryActionStateRecord(
                planID: plan.planID,
                actionID: plan.supportingActionIDs[0],
                state: .snoozed,
                reason: nil,
                updatedAt: date
            )
        ]

        let projection = WatchSyncSnapshotFactory.makeRecoveryPlanProjection(
            plan: plan,
            actionStates: states
        )

        XCTAssertEqual(projection.planID, plan.planID)
        XCTAssertEqual(projection.actions.count, 3)
        XCTAssertEqual(projection.actions.first?.role, "main")
        XCTAssertEqual(projection.actions.first?.state, "completed")
        XCTAssertEqual(projection.actions[1].state, "snoozed")
        XCTAssertEqual(projection.actions[2].state, "pending")
    }

    @MainActor private func makeTypedSnapshotDictionary() -> [String: Any] {
        [
            "type": WatchSyncMessageType.snapshot.rawValue,
            "requestId": "request-9",
            "bpm": 72,
            "hrv": 48.5,
            "stress": 31,
            "stressState": "normal",
            "stressExplanationCode": "hrv-deviation",
            "stressConfidence": 0.9,
            "stressTrend": "稳定",
            "timestamp": 2_000,
            "steps": 5_000,
            "activeEnergy": 240,
            "exerciseMinutes": 30,
            "standHours": 8,
            "walkingSpeedMps": 1.25,
            "walkingPaceSecondsPerKm": 800,
            "stepsGoal": 8_000,
            "activeEnergyGoal": 500,
            "exerciseMinutesGoal": 30,
            "standHoursGoal": 12,
            "sleepDurationMinutes": 420,
            "sleepScore": 82,
            "waterIntakeMl": 800,
            "waterTargetMl": 2_000,
            "waterCompletionRate": 0.4,
            "caffeineRemainedMg": 60,
            "sedentaryElapsedMinutes": 35,
            "sedentaryIsCounting": true,
            "sedentaryPausedBySleep": false,
            "sedentaryBreakIsActive": false,
            "sedentaryBreakDurationMinutes": 0,
            "stressHistory": [
                ["timestamp": 1_900, "value": 30],
                ["timestamp": 2_000, "value": 31]
            ],
            "watchThemeId": "joey",
            "watchMascotEnabled": false,
            "watchMascotMessage": "慢一点，也很好",
            "watchMascotMessageConfigured": true,
            "bodyAgeValueYears": 28.0,
            "bodyAgeStatusText": "良好",
            "recoveryPlan": [
                "planID": "plan-1",
                "dayStart": 1_000,
                "actions": [
                    ["actionID": "main-1", "title": "喝水", "role": "main", "state": "completed"],
                    ["actionID": "support-1", "title": "走动", "role": "supporting", "state": "pending"]
                ]
            ]
        ]
    }
}
