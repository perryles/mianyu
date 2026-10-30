import XCTest

/// 临时冒烟测试：验证健康 Tab 好友入口与压力情绪入口可见且可进。验证后删除。
nonisolated final class EntrySmokeUITests: XCTestCase {
    @MainActor func testHealthTabEntriesExist() {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        let healthTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "健康", "Health")
        ).firstMatch
        XCTAssertTrue(healthTab.waitForExistence(timeout: 10), "健康 Tab 未找到")
        healthTab.tap()
        sleep(2)

        // 好友入口（accessibilityIdentifier: health.friends.entry）
        let friends = app.buttons["health.friends.entry"]
        var found = friends.waitForExistence(timeout: 5)
        var swipes = 0
        while !found && swipes < 8 {
            app.swipeUp()
            found = friends.waitForExistence(timeout: 2)
            swipes += 1
        }
        XCTAssertTrue(found, "好友入口未找到")
        friends.tap()
        sleep(2)
        let addFriend = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "邀请", "Invite")
        ).firstMatch
        XCTAssertTrue(addFriend.waitForExistence(timeout: 8), "好友页未打开")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        // 压力与情绪入口（常用健康区）
        let stress = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "压力与情绪")).firstMatch
        var stressFound = stress.waitForExistence(timeout: 5)
        var stressSwipes = 0
        while !stressFound && stressSwipes < 6 {
            app.swipeUp()
            stressFound = stress.waitForExistence(timeout: 2)
            stressSwipes += 1
        }
        XCTAssertTrue(stressFound, "压力与情绪入口未找到")
        stress.tap()
        sleep(2)
        let tool = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "记录情绪")).firstMatch
        XCTAssertTrue(tool.waitForExistence(timeout: 8), "情绪压力页未打开")
    }
}
