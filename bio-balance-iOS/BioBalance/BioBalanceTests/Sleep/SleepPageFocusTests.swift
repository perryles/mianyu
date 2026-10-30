import XCTest
@testable import BioBalance

nonisolated final class SleepPageFocusTests: XCTestCase {
    @MainActor private let inactiveRecovery = LateNightRecoverySummary(
        isActive: false,
        hasNoSleepData: false,
        plan: nil
    )

    @MainActor func testNoDataUsesBuildingStateWithoutClaimingAProblem() {
        let focus = SleepPageFocusBuilder.make(
            data: nil,
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480
        )

        XCTAssertEqual(focus.tone, .building)
        XCTAssertTrue(focus.title.contains("记录"))
        XCTAssertTrue(focus.reason.contains("没有读取到"))
        XCTAssertTrue(focus.context.contains("没有可用于比较"))
    }

    @MainActor func testLargeDurationDeficitIsPrioritizedBeforeStageRatio() {
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 72,
                duration_minutes: 340,
                stages: [SleepStage(stage: "Deep", duration: 30)]
            ),
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480
        )

        XCTAssertEqual(focus.tone, .recovery)
        XCTAssertEqual(focus.title, "昨夜睡眠时长偏短")
        XCTAssertTrue(focus.reason.contains("2 小时 20 分钟"))
    }

    @MainActor func testLowScoreIsPrioritizedWhenDurationIsAdequate() {
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 62,
                duration_minutes: 440,
                stages: [SleepStage(stage: "Deep", duration: 80)]
            ),
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480
        )

        XCTAssertEqual(focus.title, "昨夜恢复完成度偏低")
        XCTAssertTrue(focus.reason.contains("62"))
    }

    @MainActor func testSingleNightLowDeepSleepUsesObservingLanguage() {
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 78,
                duration_minutes: 450,
                stages: [
                    SleepStage(stage: "Deep", duration: 45),
                    SleepStage(stage: "Core", duration: 300),
                    SleepStage(stage: "REM", duration: 105)
                ]
            ),
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480
        )

        XCTAssertEqual(focus.tone, .attention)
        XCTAssertEqual(focus.title, "昨夜深睡占比较低")
        XCTAssertTrue(focus.reason.contains("暂不据此判断恢复问题"))
    }

    @MainActor func testAdequateSleepFallsBackToStableMaintenance() {
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 86,
                duration_minutes: 480,
                stages: [
                    SleepStage(stage: "Deep", duration: 90),
                    SleepStage(stage: "Core", duration: 285),
                    SleepStage(stage: "REM", duration: 105)
                ]
            ),
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480
        )

        XCTAssertEqual(focus.tone, .stable)
        XCTAssertEqual(focus.badgeText, "保持")
        XCTAssertTrue(focus.context.contains("连续趋势仍在积累"))
    }

    @MainActor func testRepeatedLowDeepSleepUsesContinuousTrendLanguage() {
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 78,
                duration_minutes: 450,
                stages: [
                    SleepStage(stage: "Deep", duration: 45),
                    SleepStage(stage: "Core", duration: 300),
                    SleepStage(stage: "REM", duration: 105)
                ]
            ),
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480,
            recentNights: [
                makeNight(dayOffset: -2, duration: 450, deep: 45),
                makeNight(dayOffset: -1, duration: 440, deep: 50),
                makeNight(dayOffset: 0, duration: 460, deep: 90)
            ]
        )

        XCTAssertEqual(focus.title, "近几晚深睡结构持续偏低")
        XCTAssertTrue(focus.reason.contains("近 3 晚有 2 晚"))
        XCTAssertTrue(focus.context.contains("近 3 晚平均"))
    }

    @MainActor func testRecentShortNightsPreventStableClaimFromOneGoodNight() {
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 86,
                duration_minutes: 480,
                stages: [
                    SleepStage(stage: "Deep", duration: 90),
                    SleepStage(stage: "Core", duration: 285),
                    SleepStage(stage: "REM", duration: 105)
                ]
            ),
            latestSummary: nil,
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480,
            recentNights: [
                makeNight(dayOffset: -3, duration: 420, deep: 75),
                makeNight(dayOffset: -2, duration: 430, deep: 75),
                makeNight(dayOffset: -1, duration: 480, deep: 90),
                makeNight(dayOffset: 0, duration: 450, deep: 80)
            ]
        )

        XCTAssertEqual(focus.tone, .attention)
        XCTAssertEqual(focus.title, "昨夜尚可，近期时长仍不稳")
        XCTAssertTrue(focus.reason.contains("暂不把单晚回升当作稳定改善"))
    }

    @MainActor func testOldSummaryWithSimilarDurationDoesNotReplaceCurrentNight() {
        let currentEnd = Date(timeIntervalSince1970: 1_800_000_000)
        let oldEnd = currentEnd.addingTimeInterval(-7 * 24 * 60 * 60)
        let focus = SleepPageFocusBuilder.make(
            data: SleepData(
                sleep_score: 86,
                duration_minutes: 480,
                stages: [SleepStage(stage: "Deep", duration: 90)],
                end_time: Int(currentEnd.timeIntervalSince1970)
            ),
            latestSummary: makeSummary(end: oldEnd, duration: 480),
            lateNightSummary: inactiveRecovery,
            goalMinutes: 480
        )

        XCTAssertNotEqual(focus.title, "旧睡眠结论")
        XCTAssertEqual(focus.title, "昨夜睡眠基础较稳")
    }

    @MainActor private func makeNight(dayOffset: Int, duration: Int, deep: Int) -> SleepTrendNightSummary {
        let day = Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(dayOffset * 86_400))
        let end = day.addingTimeInterval(8 * 60 * 60)
        return SleepTrendNightSummary(
            day: day,
            startTime: day,
            endTime: end,
            inBedMinutes: duration + 25,
            asleepMinutes: duration,
            awakeMinutes: 25,
            coreMinutes: max(0, duration - deep - 100),
            deepMinutes: deep,
            remMinutes: min(100, max(0, duration - deep))
        )
    }

    @MainActor private func makeSummary(end: Date, duration: Int) -> SleepSessionSummary {
        let start = end.addingTimeInterval(TimeInterval(-duration * 60))
        return SleepSessionSummary(
            sessionId: "old-summary",
            sourceDate: Calendar.current.startOfDay(for: end),
            startTime: start,
            endTime: end,
            sleepDurationMinutes: duration,
            sleepScore: 40,
            sleepContinuityScore: 40,
            stageSummary: .empty,
            snoreSummary: .empty,
            insight: SleepInsightSnapshot(
                headline: "旧睡眠结论",
                summary: "这条内容来自更早的睡眠会话。",
                recommendationCode: "old_summary",
                recommendationText: "不应展示",
                riskFlag: .elevated,
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
