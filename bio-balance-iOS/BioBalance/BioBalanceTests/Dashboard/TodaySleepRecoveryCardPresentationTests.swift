import XCTest
@testable import BioBalance

nonisolated final class TodaySleepRecoveryCardPresentationTests: XCTestCase {
    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor func testPrimarySleepBuildsRecoverySummaryAndPriorityMetrics() throws {
        let start = try date(2026, 8, 31, 22, 30)
        let end = try date(2026, 9, 1, 6, 0)
        let data = SleepData(
            sleep_score: 82,
            duration_minutes: 450,
            stages: [
                SleepStage(stage: "Deep", duration: 75),
                SleepStage(stage: "Core", duration: 270),
                SleepStage(stage: "REM", duration: 105)
            ],
            start_time: Int(start.timeIntervalSince1970),
            end_time: Int(end.timeIntervalSince1970)
        )

        let presentation = TodaySleepRecoveryCardPresentationBuilder.make(
            primaryData: data,
            fallbackSummary: nil,
            primaryInterval: SleepInterval(start: start, end: end),
            goalMinutes: 480,
            nightlyHrv: 52,
            nightlyRespirationRate: 14.6,
            recentNights: [],
            calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")
        )

        XCTAssertEqual(presentation.state, .content)
        XCTAssertEqual(presentation.durationMinutes, 450)
        XCTAssertEqual(presentation.timeRangeText, "22:30–06:00")
        XCTAssertEqual(presentation.headline, "昨夜睡眠基础较稳")
        XCTAssertEqual(presentation.badgeText, "保持")
        XCTAssertEqual(presentation.metrics.map(\.title), ["夜间 HRV"])
        XCTAssertEqual(presentation.metrics.map(\.value), ["52"])
    }

    @MainActor func testFallbackSummaryUsesItsOwnNightInsteadOfUnrelatedPrimaryInterval() throws {
        let fallbackStart = try date(2026, 8, 30, 23, 0)
        let fallbackEnd = try date(2026, 8, 31, 7, 0)
        let unrelatedStart = try date(2026, 9, 1, 1, 0)
        let unrelatedEnd = try date(2026, 9, 1, 6, 0)
        let summary = makeSummary(start: fallbackStart, end: fallbackEnd, duration: 480, score: 86)

        let presentation = TodaySleepRecoveryCardPresentationBuilder.make(
            primaryData: nil,
            fallbackSummary: summary,
            primaryInterval: SleepInterval(start: unrelatedStart, end: unrelatedEnd),
            goalMinutes: 480,
            nightlyHrv: nil,
            nightlyRespirationRate: 14.8,
            recentNights: [],
            calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")
        )

        XCTAssertEqual(presentation.state, .content)
        XCTAssertEqual(presentation.timeRangeText, "23:00–07:00")
        XCTAssertEqual(presentation.sourceDate, calendar.startOfDay(for: fallbackEnd))
        XCTAssertTrue(presentation.metrics.isEmpty)
    }

    @MainActor func testMissingSleepKeepsLoadingAndEmptyStatesDistinct() {
        let loading = TodaySleepRecoveryCardPresentationBuilder.make(
            primaryData: nil,
            fallbackSummary: nil,
            primaryInterval: nil,
            goalMinutes: 480,
            nightlyHrv: nil,
            nightlyRespirationRate: nil,
            recentNights: [],
            calendar: calendar
        )
        let empty = TodaySleepRecoveryCardPresentationBuilder.make(
            primaryData: SleepData(sleep_score: 0, duration_minutes: 0, stages: []),
            fallbackSummary: nil,
            primaryInterval: nil,
            goalMinutes: 480,
            nightlyHrv: nil,
            nightlyRespirationRate: nil,
            recentNights: [],
            calendar: calendar
        )

        XCTAssertEqual(loading.state, .loading)
        XCTAssertEqual(empty.state, .empty)
    }

    @MainActor func testLateNightPlanDoesNotTakeOverTodayCardHeadline() throws {
        let start = try date(2026, 8, 31, 23, 40)
        let end = try date(2026, 9, 1, 5, 20)
        let data = SleepData(
            sleep_score: 72,
            duration_minutes: 340,
            stages: [SleepStage(stage: "Deep", duration: 30)],
            start_time: Int(start.timeIntervalSince1970),
            end_time: Int(end.timeIntervalSince1970)
        )

        let presentation = TodaySleepRecoveryCardPresentationBuilder.make(
            primaryData: data,
            fallbackSummary: nil,
            primaryInterval: SleepInterval(start: start, end: end),
            goalMinutes: 480,
            nightlyHrv: nil,
            nightlyRespirationRate: nil,
            recentNights: [],
            calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")
        )

        XCTAssertEqual(presentation.state, .content)
        XCTAssertNotEqual(presentation.headline, "昨晚睡得偏晚，今天温和恢复")
        XCTAssertEqual(presentation.badgeText, "优先补足")
        XCTAssertEqual(presentation.headline, "昨夜睡眠时长偏短")
    }

    @MainActor private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    @MainActor private func makeSummary(start: Date, end: Date, duration: Int, score: Int) -> SleepSessionSummary {
        SleepSessionSummary(
            sessionId: "fallback-summary",
            sourceDate: calendar.startOfDay(for: end),
            startTime: start,
            endTime: end,
            sleepDurationMinutes: duration,
            sleepScore: score,
            sleepContinuityScore: 82,
            stageSummary: .empty,
            snoreSummary: .empty,
            insight: SleepInsightSnapshot(
                headline: "昨夜恢复稳定",
                summary: "睡眠时长和连续性较稳定。",
                recommendationCode: "keep_rhythm",
                recommendationText: "继续保持当前作息。",
                riskFlag: .none,
                generatedAt: end,
                modelVersion: "test"
            ),
            watchConfidence: 1,
            deviceSource: "test",
            analysisVersion: "test",
            createdAt: end,
            updatedAt: end,
            source: .manual
        )
    }
}
