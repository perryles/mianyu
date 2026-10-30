import XCTest
import SwiftData
@testable import BioBalance

nonisolated final class RecoveryActionLoopEngineTests: XCTestCase {
    @MainActor func testCountsPendingActionsInPlannedDenominatorAndFeedbackOnlyOnCompleted() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let records = [
            record("pending", state: .pending, feedback: nil, date: now),
            record("done", state: .completed, feedback: .better, date: now),
            record("skip", state: .skipped, feedback: nil, date: now)
        ]

        let review = RecoveryActionLoopEngine.make(records: records, referenceDate: now)

        XCTAssertEqual(review.plannedCount, 3)
        XCTAssertEqual(review.processedCount, 2)
        XCTAssertEqual(review.completedCount, 1)
        XCTAssertEqual(review.betterCount, 1)
        XCTAssertEqual(try XCTUnwrap(review.completionRate), 1.0 / 3.0, accuracy: 0.001)
    }

    @MainActor func testExcludesRecordsBeforeSevenDayWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let old = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        let review = RecoveryActionLoopEngine.make(
            records: [record("old", state: .completed, feedback: .similar, date: old)],
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertEqual(review.plannedCount, 0)
        XCTAssertNil(review.completionRate)
    }

    @MainActor private func record(
        _ id: String,
        state: DailyRecoveryActionState,
        feedback: DailyRecoveryActionFeedback?,
        date: Date
    ) -> DailyRecoveryActionStateRecord {
        DailyRecoveryActionStateRecord(
            planID: "plan",
            actionID: id,
            state: state,
            reason: nil,
            actionTitle: id,
            plannedFor: date,
            feedback: feedback,
            feedbackUpdatedAt: feedback == nil ? nil : date,
            updatedAt: date
        )
    }
}

nonisolated final class DailyRecoveryOrchestrationStoreTests: XCTestCase {
    @MainActor func testPlanCreatesPendingRecordsAndFeedbackFollowsCompletedState() throws {
        let suite = "DailyRecoveryOrchestrationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try MianyuModelContainer.make(isStoredInMemoryOnly: true)
        let store = DailyRecoveryOrchestrationStore(defaults: defaults, container: container)
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let plan = DailyRecoveryOrchestrationPlan(
            date: date,
            mainGoal: "主行动",
            mainGoalDetail: "详情",
            supportingActions: ["辅助一", "辅助二"],
            deferredSuggestions: [],
            readinessBand: .balanced,
            reason: "测试",
            generatedAt: date
        )

        store.save(plan)
        XCTAssertEqual(store.allActionStateRecords().filter { $0.state == .pending }.count, 3)
        _ = store.setActionState(.completed, actionID: plan.mainActionID, planID: plan.planID, updatedAt: date)
        XCTAssertEqual(store.setFeedback(.better, actionID: plan.mainActionID, updatedAt: date)?.feedback, .better)
        _ = store.setActionState(.skipped, actionID: plan.mainActionID, planID: plan.planID, updatedAt: date)
        XCTAssertNil(store.actionState(for: plan.mainActionID)?.feedback)
        store.undoActionState(for: plan.mainActionID, updatedAt: date)
        XCTAssertEqual(store.actionState(for: plan.mainActionID)?.state, .pending)
        XCTAssertEqual(store.allActionStateRecords().count, 3)
    }

    @MainActor func testLegacyActionStateWithoutNewOptionalFieldsDecodes() throws {
        struct LegacyRecord: Encodable {
            let planID: String
            let actionID: String
            let state: DailyRecoveryActionState
            let reason: String?
            let updatedAt: Date
        }
        let data = try JSONEncoder().encode(
            LegacyRecord(planID: "plan", actionID: "action", state: .completed, reason: nil, updatedAt: Date())
        )
        let decoded = try JSONDecoder().decode(DailyRecoveryActionStateRecord.self, from: data)
        XCTAssertNil(decoded.actionTitle)
        XCTAssertNil(decoded.feedback)
        XCTAssertEqual(decoded.state, .completed)
    }
}
