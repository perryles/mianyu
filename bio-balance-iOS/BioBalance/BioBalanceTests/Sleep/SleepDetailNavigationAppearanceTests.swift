import XCTest

nonisolated final class SleepDetailNavigationAppearanceTests: XCTestCase {
    @MainActor func testSedentaryDetailUsesContinuousReportLayoutAndKeepsActions() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("BioBalance/Views/Health/Sedentary/SedentaryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AdaptivePageScrollView(style: .reading"))
        XCTAssertTrue(source.contains("reportSection { standingDistribution }"))
        XCTAssertTrue(source.contains("reportSection { todayLogCard }"))
        XCTAssertTrue(source.contains("reportSection { settingsCard }"))
        XCTAssertFalse(source.contains("ModernReportHero("), "久坐页应使用与鼾声报告一致的连续摘要，避免装饰卡片叠加")
        XCTAssertFalse(source.contains("private var todayStatsCard:"), "指标只汇总一次，避免重复统计")
        XCTAssertTrue(source.contains("Button(action: performHeroAction)"))
        XCTAssertTrue(source.contains("SedentaryTimelineChartView(summary: summary)"))
        XCTAssertTrue(source.contains("SedentaryHistoryView(viewModel: viewModel)"))
        XCTAssertTrue(source.contains("dynamicTypeSize.isAccessibilitySize ? 1 : 2"))
    }

    @MainActor func testNavigationStackUsesSameTintAsModalDismissControl() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("BioBalance")
            .appendingPathComponent("Views/Health/Sleep/SleepDetailSheetView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                "        }\n        .tint(Theme.Colors.textPrimary)\n        .offset"
            ),
            "睡眠详情的系统返回按钮应与模态返回按钮共用 textPrimary 色"
        )
    }

    @MainActor func testTodaySedentarySheetUsesSameTintAsModalDismissControl() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("BioBalance")
            .appendingPathComponent("Views/Today/Dashboard/DashboardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                "            }\n            .tint(Theme.Colors.textPrimary)\n            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)"
            ),
            "今日久坐提醒的系统返回按钮应与模态返回按钮共用 textPrimary 色"
        )
    }
}
