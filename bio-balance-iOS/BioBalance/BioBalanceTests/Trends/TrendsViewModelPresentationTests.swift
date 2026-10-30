import Foundation
import XCTest
@testable import BioBalance

/// TrendsViewModel 展示派生逻辑（PEN-14 拆分后）单元测试。
///
/// 覆盖 primaryMetric 选择顺序与 buildFeaturedCategoryCards 的
/// 精选分类过滤 / 支持指标截断 / 字段透传。纯本地数据，离线运行。
nonisolated final class TrendsViewModelPresentationTests: XCTestCase {

    @MainActor private func metric(_ title: String) -> TrendCategoryMetricModel {
        TrendCategoryMetricModel(
            title: title,
            unit: "测试",
            points: [],
            secondaryPoints: [],
            status: .ready,
            emptyMessage: "暂无数据",
            accentHex: "5E5CE6",
            summary: "测试"
        )
    }

    @MainActor private func detail(
        _ category: TrendCategoryID,
        metrics: [TrendCategoryMetricModel],
        sleepNightSummaries: [SleepTrendNightSummary] = [],
        sleepRecoveryMetrics: [TrendCategoryMetricModel] = []
    ) -> TrendCategoryDetailModel {
        TrendCategoryDetailModel(
            category: category,
            headerSummary: "header",
            metrics: metrics,
            status: metrics.isEmpty ? .noData : .ready,
            sleepStages: [],
            sleepClinicalSummary: nil,
            sleepAIInsight: nil,
            sleepCompositeScores: [],
            sleepNightSummaries: sleepNightSummaries,
            sleepCoreMetrics: [],
            sleepRecoveryMetrics: sleepRecoveryMetrics,
            genericAIInsight: nil,
            mobilityAIInsight: nil,
            reproductiveDetail: nil,
            heartECGSummary: nil,
            heartECGRecords: [],
            heartClinicalMonitorSummary: nil
        )
    }

    // MARK: - primaryMetric

    @MainActor func testPrimaryMetricPrefersOrderedTitles() {
        let detail = self.detail(
            .sleepRecovery,
            metrics: [metric("睡眠评分"), metric("睡眠总时长"), metric("睡眠 HRV")]
        )
        XCTAssertEqual(TrendsViewModel.primaryMetric(for: .sleepRecovery, detail: detail)?.title, "睡眠总时长")
    }

    @MainActor func testPrimaryMetricForHeartCardio() {
        let detail = self.detail(
            .heartCardio,
            metrics: [metric("静息心率"), metric("心率"), metric("心率变异性（HRV）")]
        )
        XCTAssertEqual(TrendsViewModel.primaryMetric(for: .heartCardio, detail: detail)?.title, "心率")
    }

    @MainActor func testPrimaryMetricForDailyActivity() {
        let detail = self.detail(.dailyActivity, metrics: [metric("步数"), metric("步行速度")])
        XCTAssertEqual(TrendsViewModel.primaryMetric(for: .dailyActivity, detail: detail)?.title, "步行速度")
    }

    @MainActor func testPrimaryMetricFallsBackToFirstMetric() {
        let detail = self.detail(.bodyMetrics, metrics: [metric("体重"), metric("BMI")])
        XCTAssertEqual(TrendsViewModel.primaryMetric(for: .bodyMetrics, detail: detail)?.title, "体重")
    }

    @MainActor func testPrimaryMetricNilWhenNoMetrics() {
        let detail = self.detail(.bodyMetrics, metrics: [])
        XCTAssertNil(TrendsViewModel.primaryMetric(for: .bodyMetrics, detail: detail))
    }

    // MARK: - buildFeaturedCategoryCards

    @MainActor func testFeaturedCardsIncludeOnlyFeaturedCategoriesInOrder() {
        let details: [TrendCategoryID: TrendCategoryDetailModel] = [
            .bodyMetrics: detail(.bodyMetrics, metrics: [metric("体重")]),
            .heartCardio: detail(.heartCardio, metrics: [metric("心率")]),
            .sleepRecovery: detail(.sleepRecovery, metrics: [metric("睡眠总时长")]),
            .dailyActivity: detail(.dailyActivity, metrics: [metric("步行速度")])
        ]

        let cards = TrendsViewModel.buildFeaturedCategoryCards(from: details)
        XCTAssertEqual(cards.map(\.category), [.sleepRecovery, .heartCardio, .dailyActivity])
    }

    @MainActor func testFeaturedCardsExcludeDetailWithoutPrimaryMetric() {
        let details: [TrendCategoryID: TrendCategoryDetailModel] = [
            .sleepRecovery: detail(.sleepRecovery, metrics: []),
            .heartCardio: detail(.heartCardio, metrics: [metric("心率")])
        ]

        let cards = TrendsViewModel.buildFeaturedCategoryCards(from: details)
        XCTAssertEqual(cards.map(\.category), [.heartCardio])
    }

    @MainActor func testFeaturedCardsCapSupportingMetricsAtTwo() {
        let metrics = ["睡眠总时长", "睡眠评分", "睡眠 HRV", "睡眠效率"].map(metric)
        let details: [TrendCategoryID: TrendCategoryDetailModel] = [
            .sleepRecovery: detail(.sleepRecovery, metrics: metrics)
        ]

        let cards = TrendsViewModel.buildFeaturedCategoryCards(from: details)
        let card = try! XCTUnwrap(cards.first)
        XCTAssertEqual(card.primaryMetric.title, "睡眠总时长")
        XCTAssertEqual(card.supportingMetrics.count, 2)
        XCTAssertFalse(card.supportingMetrics.contains { $0.title == "睡眠总时长" })
    }

    @MainActor func testFeaturedCardsPassThroughSleepFields() {
        let day = Date(timeIntervalSince1970: 1_730_000_000)
        let nightSummary = SleepTrendNightSummary(
            day: day,
            startTime: day,
            endTime: day.addingTimeInterval(7 * 3600),
            inBedMinutes: 450,
            asleepMinutes: 420,
            awakeMinutes: 30,
            coreMinutes: 300,
            deepMinutes: 80,
            remMinutes: 40
        )
        let recoveryMetric = metric("睡眠恢复")
        let details: [TrendCategoryID: TrendCategoryDetailModel] = [
            .sleepRecovery: detail(
                .sleepRecovery,
                metrics: [metric("睡眠总时长")],
                sleepNightSummaries: [nightSummary],
                sleepRecoveryMetrics: [recoveryMetric]
            )
        ]

        let cards = TrendsViewModel.buildFeaturedCategoryCards(from: details)
        let card = try! XCTUnwrap(cards.first)
        XCTAssertEqual(card.sleepNightSummaries, [nightSummary])
        XCTAssertEqual(card.sleepRecoveryMetrics, [recoveryMetric])
    }
}
