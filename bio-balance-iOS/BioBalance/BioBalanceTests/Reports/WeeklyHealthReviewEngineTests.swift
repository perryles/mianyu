import XCTest
@testable import BioBalance

nonisolated final class WeeklyHealthReviewEngineTests: XCTestCase {
    @MainActor func testChartSelectionOnlyUsesTheSelectedCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let thirdDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
        let missingDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let dates = [start, thirdDay]
        XCTAssertEqual(WeeklyReportTrendData.selectedIndex(for: start.addingTimeInterval(3_600), dates: dates, calendar: calendar), 0)
        XCTAssertNil(WeeklyReportTrendData.selectedIndex(for: missingDay, dates: dates, calendar: calendar))
        XCTAssertNil(WeeklyReportTrendData.selectedIndex(for: nil, dates: dates, calendar: calendar))
        XCTAssertEqual(WeeklyReportTrendData.selectedIndex(for: thirdDay.addingTimeInterval(80_000), dates: dates, calendar: calendar), 1)
    }

    @MainActor func testRawReadoutPreservesMinuteAndStepPrecision() throws {
        let days = [summary(day: 1, score: 80, sleepHours: 7 + 23.0 / 60, steps: 8_123)]
        let sleep = try XCTUnwrap(WeeklyReportTrendData.points(for: .sleep, in: days).first)
        let activity = try XCTUnwrap(WeeklyReportTrendData.points(for: .activity, in: days).first)
        XCTAssertEqual(sleep.rawValueText, String(localized: "\(7) 小时 \(23) 分钟"))
        XCTAssertEqual(activity.rawValueText, String(localized: "\(8_123.formatted()) 步"))
        XCTAssertFalse(activity.rawValueText.contains("k"))
    }

    @MainActor func testTrendTypesMatchOriginalUnitsAndDoNotClampMeasurementsToScores() {
        let days = [summary(day: 1, score: 80, sleepHours: 9, stress: 30, steps: 18_000)]
        XCTAssertEqual(WeeklyReportTrendData.points(for: .sleep, in: days).first?.value, 9)
        XCTAssertEqual(WeeklyReportTrendData.points(for: .activity, in: days).first?.value, 18_000)
        XCTAssertEqual(WeeklyReportTrendData.points(for: .stress, in: days).first?.value, 30)
        XCTAssertTrue(WeeklyReportTrendData.usesBars(for: .sleep))
        XCTAssertTrue(WeeklyReportTrendData.usesBars(for: .activity))
        XCTAssertFalse(WeeklyReportTrendData.usesBars(for: .stress))
        XCTAssertGreaterThanOrEqual(WeeklyReportTrendData.domain(for: .activity, values: [18_000]).upperBound, 18_000)
        XCTAssertEqual(WeeklyReportTrendData.domain(for: .stress, values: [30]), 0...100)
    }

    @MainActor func testRawTrendsKeepRecordedZeroButRejectMissingAndInvalidMeasurements() {
        let days = [
            summary(day: 1, score: 80, sleepHours: nil, stress: nil, steps: nil),
            summary(day: 2, score: 80, sleepHours: 0, stress: 0, steps: 0),
            summary(day: 3, score: 80, sleepHours: .nan, stress: .infinity, steps: -1)
        ]
        XCTAssertTrue(WeeklyReportTrendData.points(for: .sleep, in: days).isEmpty)
        XCTAssertEqual(WeeklyReportTrendData.points(for: .activity, in: days).map(\.value), [0])
        XCTAssertEqual(WeeklyReportTrendData.points(for: .stress, in: days).map(\.value), [0])
    }

    @MainActor func testWeekNavigationMovesInCorrectDirectionAndStopsAtBoundaries() {
        XCTAssertEqual(WeeklyReportView.WeekRange.lastWeek.shifted(by: -1), .twoWeeksAgo)
        XCTAssertEqual(WeeklyReportView.WeekRange.lastWeek.shifted(by: 1), .thisWeek)
        XCTAssertNil(WeeklyReportView.WeekRange.thisWeek.shifted(by: 1))
        XCTAssertNil(WeeklyReportView.WeekRange.threeWeeksAgo.shifted(by: -1))
    }

    @MainActor func testReportLayoutUsesContinuousSectionsAndKeepsNavigationAndSharing() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("BioBalance/Views/Health/Reports/WeeklyReportView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("reportSection { overallTrendCard }"))
        XCTAssertTrue(source.contains("reportSection { metricBreakdownCard }"))
        XCTAssertTrue(source.contains("reportSection { personalizedAdviceCard }"))
        XCTAssertTrue(source.contains("isContinuous: true"))
        XCTAssertTrue(source.contains("size: 84, weight: .heavy"))
        XCTAssertFalse(source.contains("HealthDetailPageBackground()"))
        XCTAssertTrue(source.contains("weekNavigationBar"))
        XCTAssertTrue(source.contains("segmentPicker"))
        XCTAssertTrue(source.contains("ReportShareView("))
        XCTAssertTrue(source.contains(".chartXSelection(value: $inspectedOverallDate)"))
        XCTAssertTrue(source.contains("dynamicTypeSize.isAccessibilitySize ? 2 : 5"))
        XCTAssertTrue(source.contains("dynamicTypeSize.isAccessibilitySize ? 1 : 3"))
        XCTAssertTrue(source.contains("reportValue(metric.score.map(String.init)"))
        XCTAssertTrue(source.contains("seen.insert($0).inserted"))
        XCTAssertTrue(source.contains("metric.observedDays == 0 ? \"--\""))
    }

    @MainActor func testEmptyWeekStaysHonestAndDoesNotCreateComparison() {
        let review = WeeklyHealthReviewEngine.make(
            current: [],
            previous: [],
            expectedDays: 4,
            scope: "本周"
        )

        XCTAssertEqual(review.reliability, .noData)
        XCTAssertEqual(review.direction, .unavailable)
        XCTAssertNil(review.averageScore)
        XCTAssertNil(review.scoreDelta)
        XCTAssertEqual(review.observedDays, 0)
        XCTAssertEqual(review.expectedDays, 4)
    }

    @MainActor func testComparisonRequiresThreeScoredDaysOnBothSides() {
        let current = [summary(day: 1, score: 80), summary(day: 2, score: 82)]
        let previous = [summary(day: -1, score: 60), summary(day: -2, score: 62), summary(day: -3, score: 64)]

        let review = WeeklyHealthReviewEngine.make(
            current: current,
            previous: previous,
            expectedDays: 2,
            scope: "本周"
        )

        XCTAssertEqual(review.direction, .unavailable)
        XCTAssertNil(review.scoreDelta)
        XCTAssertEqual(review.scoredDays, 2)
    }

    @MainActor func testFirstTwoDaysRemainSampleAccumulationEvenWhenCoverageIsComplete() {
        let current = [summary(day: 1, score: 80), summary(day: 2, score: 82)]

        let review = WeeklyHealthReviewEngine.make(
            current: current,
            previous: [],
            expectedDays: 2,
            scope: "本周"
        )

        XCTAssertEqual(review.reliability, .limited)
        XCTAssertEqual(review.overallCoveragePercent, 100)
    }

    @MainActor func testReportsImprovementOnlyAfterComparableSamples() {
        let current = [78, 82, 84].enumerated().map { summary(day: $0.offset, score: $0.element) }
        let previous = [68, 72, 70].enumerated().map { summary(day: $0.offset - 7, score: $0.element) }

        let review = WeeklyHealthReviewEngine.make(
            current: current,
            previous: previous,
            expectedDays: 3,
            scope: "本周"
        )

        XCTAssertEqual(review.direction, .improving)
        XCTAssertEqual(review.averageScore, 81)
        XCTAssertEqual(review.previousAverageScore, 70)
        XCTAssertEqual(review.scoreDelta, 11)
    }

    @MainActor func testSmallWeeklyDeltaIsStable() {
        let current = [76, 78, 77].enumerated().map { summary(day: $0.offset, score: $0.element) }
        let previous = [74, 76, 75].enumerated().map { summary(day: $0.offset - 7, score: $0.element) }

        let review = WeeklyHealthReviewEngine.make(
            current: current,
            previous: previous,
            expectedDays: 3,
            scope: "本周"
        )

        XCTAssertEqual(review.direction, .stable)
        XCTAssertEqual(review.scoreDelta, 2)
    }

    @MainActor func testCoverageAndAttentionUseOnlyRealAvailableMetricsAndCautionTone() throws {
        let sleepPositive = contribution(kind: .sleep, score: 90, tone: .positive)
        let stressCaution = contribution(kind: .stress, score: 45, tone: .caution)
        let breakdown = ReportScoreBreakdown(
            items: [sleepPositive, stressCaution],
            leadingPositiveKind: .sleep,
            leadingNegativeKind: .stress,
            headline: "测试"
        )
        let current = (0..<3).map { day in
            summary(
                day: day,
                score: 70,
                sleepHours: 7.5,
                stress: 55,
                hrv: day == 0 ? 42 : nil,
                steps: 8_000,
                breakdown: breakdown
            )
        }

        let review = WeeklyHealthReviewEngine.make(
            current: current,
            previous: [],
            expectedDays: 3,
            scope: "本周"
        )

        XCTAssertEqual(review.supportKind, .sleep)
        XCTAssertEqual(review.attentionKind, .stress)
        XCTAssertEqual(try coverage(.sleep, in: review).availableCount, 3)
        XCTAssertEqual(try coverage(.hrv, in: review).availableCount, 1)
        XCTAssertEqual(try coverage(.activity, in: review).availableCount, 3)
        XCTAssertEqual(review.reliability, .readable)
    }

    @MainActor private func coverage(
        _ kind: ReportMetricKind,
        in review: WeeklyHealthReview
    ) throws -> ReportMetricCoverageItem {
        try XCTUnwrap(review.metricCoverage.first { $0.kind == kind })
    }

    @MainActor private func contribution(
        kind: ReportMetricKind,
        score: Int,
        tone: ReportContributionTone
    ) -> ReportScoreContribution {
        ReportScoreContribution(
            kind: kind,
            score: score,
            valueText: "测试",
            detail: "测试",
            tone: tone
        )
    }

    @MainActor private func summary(
        day: Int,
        score: Int,
        sleepHours: Double? = 7.0,
        stress: Double? = 50,
        hrv: Double? = 40,
        steps: Double? = 8_000,
        breakdown: ReportScoreBreakdown? = nil
    ) -> ReportDaySummary {
        let date = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: day,
            to: Date(timeIntervalSince1970: 1_760_000_000)
        ) ?? Date(timeIntervalSince1970: 1_760_000_000)
        return ReportDaySummary(
            id: Int64(date.timeIntervalSince1970),
            date: date,
            score: score,
            sleepHours: sleepHours,
            stress: stress,
            hrv: hrv,
            steps: steps,
            activeEnergy: nil,
            recoveryScriptPlan: nil,
            caffeineWeeklySummary: nil,
            scoreBreakdown: breakdown,
            adviceSummary: nil,
            trendContext: nil
        )
    }
}
