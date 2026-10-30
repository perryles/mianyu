import XCTest
@testable import BioBalance

nonisolated final class HealthProfilePagePresentationTests: XCTestCase {
    @MainActor func testPagePutsTheStrongestFocusFirstAndLimitsSupportingFocus() {
        let summary = makeSummary(
            dimensions: [],
            recommendations: [
                .init(title: "保持散步", detail: "继续当前安排", reason: "活动稳定", priority: .low, module: .activity),
                .init(title: "先补睡眠", detail: "今晚提前收尾", reason: "睡眠不足", priority: .high, module: .sleep),
                .init(title: "减少久坐", detail: "下午起身活动", reason: "久坐偏长", priority: .medium, module: .sedentary),
                .init(title: "保持饮水", detail: "继续分次饮水", reason: "记录稳定", priority: .low, module: .habits)
            ]
        )

        let presentation = HealthProfilePagePresentation.make(summary: summary)

        XCTAssertEqual(presentation.primaryFocus?.title, "先补睡眠")
        XCTAssertEqual(presentation.supportingFocus.map(\.title), ["减少久坐", "保持散步"])
    }

    @MainActor func testPageOrdersDimensionsByAttentionBeforeStableAndImproving() {
        let summary = makeSummary(
            dimensions: [
                dimension(.sleepRhythm, trend: .improving),
                dimension(.activityBase, trend: .stable),
                dimension(.stressStability, trend: .declining),
                dimension(.recoveryVitals, trend: .observing),
                dimension(.habitConsistency, trend: .missing)
            ],
            recommendations: []
        )

        let presentation = HealthProfilePagePresentation.make(summary: summary)

        XCTAssertEqual(
            presentation.dimensions.map(\.kind),
            [.stressStability, .recoveryVitals, .activityBase, .sleepRhythm, .habitConsistency]
        )
    }

    @MainActor private func dimension(
        _ kind: HealthProfileDimensionKind,
        trend: HealthProfileTrend
    ) -> HealthProfileDimension {
        HealthProfileDimension(
            kind: kind,
            title: kind.title,
            statusText: trend.title,
            score: trend == .missing ? nil : 72,
            trend: trend,
            detail: "用于验证健康档案维度排序。"
        )
    }

    @MainActor private func makeSummary(
        dimensions: [HealthProfileDimension],
        recommendations: [HealthProfileActionRecommendation]
    ) -> HealthProfileSummary {
        HealthProfileSummary(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            range: .thirtyDays,
            headline: "长期状态稳定",
            status: .growing,
            growthScore: 78,
            dimensions: dimensions,
            changes: [],
            tags: [],
            milestones: [],
            riskTendencies: [],
            actionRecommendations: recommendations,
            dataCompleteness: [
                .init(title: "睡眠", state: .synced, detail: "已同步", sampleCount: 7),
                .init(title: "活动", state: .synced, detail: "已同步", sampleCount: 7)
            ]
        )
    }
}
