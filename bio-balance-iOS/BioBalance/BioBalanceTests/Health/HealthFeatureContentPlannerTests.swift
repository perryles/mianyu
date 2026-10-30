import XCTest
@testable import BioBalance

nonisolated final class HealthFeatureContentPlannerTests: XCTestCase {
    @MainActor func testMotionPolicyKeepsGraphicMotionButDisablesItForReduceMotion() {
        let animated = HealthFeatureMotionPolicy(reduceMotion: false)
        XCTAssertEqual(animated.floatingOffset, 4)
        XCTAssertEqual(animated.pressedScale, 0.975)
        XCTAssertTrue(animated.animatesProgress)
        XCTAssertEqual(animated.celebrationScale, 1.22)

        let reduced = HealthFeatureMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.floatingOffset, 0)
        XCTAssertEqual(reduced.pressedScale, 1)
        XCTAssertFalse(reduced.animatesProgress)
        XCTAssertEqual(reduced.celebrationScale, 1)
    }

    @MainActor func testDailyActionPrioritizesTheNextIncompleteAction() {
        let focus = HealthFeatureContentPlanner.dailyAction(
            completed: 2,
            total: 5,
            nextActionTitle: "补水"
        )

        XCTAssertEqual(focus.eyebrow, "今日优先")
        XCTAssertEqual(focus.title, "先完成“补水”")
        XCTAssertEqual(focus.actionTitle, "开始记录")
        XCTAssertEqual(focus.progress, 0.4, accuracy: 0.001)
    }

    @MainActor func testMealFocusNamesTheNextMissingMeal() {
        let focus = HealthFeatureContentPlanner.meal(
            recorded: 1,
            total: 3,
            nextMealTitle: "午餐"
        )

        XCTAssertEqual(focus.title, "补记午餐")
        XCTAssertEqual(focus.actionTitle, "拍照识别")
        XCTAssertEqual(focus.progress, 1.0 / 3.0, accuracy: 0.001)
    }

    @MainActor func testMedicationFocusPrioritizesOverduePlan() {
        let focus = HealthFeatureContentPlanner.medication(
            completed: 1,
            total: 3,
            overdue: 1,
            todaySymptomCount: 0
        )

        XCTAssertEqual(focus.title, "先补记 1 项用药")
        XCTAssertEqual(focus.actionTitle, "补记用药")
        XCTAssertEqual(focus.progress, 1.0 / 3.0, accuracy: 0.001)
    }

    @MainActor func testCompletedDailyActionsSwitchToReview() {
        let focus = HealthFeatureContentPlanner.dailyAction(
            completed: 5,
            total: 5,
            nextActionTitle: nil
        )

        XCTAssertEqual(focus.title, "今天的基础行动已完成")
        XCTAssertEqual(focus.actionTitle, "回看今日节奏")
        XCTAssertEqual(focus.progress, 1)
    }
}
