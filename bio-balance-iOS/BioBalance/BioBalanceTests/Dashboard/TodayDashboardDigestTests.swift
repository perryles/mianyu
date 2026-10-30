import XCTest
@testable import BioBalance

nonisolated final class TodayDashboardDigestTests: XCTestCase {
    @MainActor func testTodayCardsLimitPatternCopyToTwoItems() {
        XCTAssertEqual(TodayDashboardContentPolicy.maximumVisiblePatterns, 2)
    }

    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    @MainActor func testEmptySummariesProduceWaitingPatternAndNoDataReview() throws {
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))

        let digest = TodayDashboardDigestBuilder.make(
            summaries: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(digest.patterns, [
            TodayDashboardPattern(title: "等待规律样本", systemImage: "clock", tone: .muted)
        ])
        XCTAssertEqual(digest.previousWeekReview.reliability, .noData)
        XCTAssertEqual(digest.previousWeekRangeText, "08/24–08/30")
    }

    @MainActor func testDigestUsesRecurringEvidenceAndComparesThePreviousCompleteWeek() throws {
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))
        let priorWeekScores = [66, 68, 67, 69, 70, 68, 69]
        let previousWeekScores = [78, 80, 79, 81, 82, 80, 81]
        var summaries: [ReportDaySummary] = []

        for (offset, score) in priorWeekScores.enumerated() {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: date(2026, 8, 17)))
            summaries.append(day(date: date, score: score, positive: .sleep, negative: .activity))
        }
        for (offset, score) in previousWeekScores.enumerated() {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: date(2026, 8, 24)))
            summaries.append(day(date: date, score: score, positive: .sleep, negative: .activity))
        }

        let digest = TodayDashboardDigestBuilder.make(
            summaries: summaries,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(digest.patterns.prefix(2).map(\.title), ["活动量偏少", "睡眠在托住恢复"])
        XCTAssertEqual(digest.previousWeekReview.direction, .improving)
        XCTAssertEqual(digest.previousWeekReview.scoreDelta, 12)
        XCTAssertEqual(digest.previousWeekReview.averageScore, 80)
        XCTAssertEqual(digest.previousWeekRangeText, "08/24–08/30")

        let presentation = TodayPreviousWeekCardPresentationBuilder.make(
            review: digest.previousWeekReview
        )
        XCTAssertEqual(presentation.primaryValue, "80")
        XCTAssertEqual(presentation.primaryLabel, "上周均分")
        XCTAssertEqual(presentation.comparisonText, "较前周 +12")
        XCTAssertEqual(presentation.coverageText, "7/7 天评分 · 指标覆盖 100%")
        XCTAssertEqual(presentation.supportKind, .sleep)
        XCTAssertEqual(presentation.attentionKind, .activity)
    }

    @MainActor func testPreviousWeekCardKeepsMissingComparisonExplicit() throws {
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))
        let digest = TodayDashboardDigestBuilder.make(
            summaries: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let presentation = TodayPreviousWeekCardPresentationBuilder.make(
            review: digest.previousWeekReview
        )

        XCTAssertEqual(presentation.primaryValue, "--")
        XCTAssertEqual(presentation.comparisonText, "等待可比样本")
        XCTAssertEqual(presentation.coverageText, "0/7 天评分 · 指标覆盖 0%")
    }

    @MainActor private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @MainActor private func day(
        date: Date,
        score: Int,
        positive: ReportMetricKind,
        negative: ReportMetricKind
    ) -> ReportDaySummary {
        let positiveItem = ReportScoreContribution(
            kind: positive,
            score: 86,
            valueText: "良好",
            detail: "本周持续提供支撑。",
            tone: .positive
        )
        let negativeItem = ReportScoreContribution(
            kind: negative,
            score: 52,
            valueText: "偏少",
            detail: "本周多次成为拖累项。",
            tone: .caution
        )
        return ReportDaySummary(
            id: Int64(date.timeIntervalSince1970),
            date: date,
            score: score,
            sleepHours: 7.5,
            stress: 35,
            hrv: 48,
            steps: 4_200,
            activeEnergy: 280,
            recoveryScriptPlan: nil,
            caffeineWeeklySummary: nil,
            scoreBreakdown: ReportScoreBreakdown(
                items: [positiveItem, negativeItem],
                leadingPositiveKind: positive,
                leadingNegativeKind: negative,
                headline: "测试摘要"
            ),
            adviceSummary: nil,
            trendContext: nil
        )
    }
}
