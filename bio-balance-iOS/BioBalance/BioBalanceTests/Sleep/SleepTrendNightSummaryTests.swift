import Foundation
import XCTest
@testable import BioBalance

/// SleepTrendNightSummary（核心业务：在床时长/效率/深睡 REM 占比/评分估算）单元测试。
///
/// 纯日期与比例计算，离线运行，不依赖 HealthKit。
nonisolated final class SleepTrendNightSummaryTests: XCTestCase {

    @MainActor private let day = Date(timeIntervalSince1970: 1_730_000_000)

    @MainActor private func summary(
        startTime: Date,
        endTime: Date,
        inBedMinutes: Int? = nil,
        asleepMinutes: Int,
        awakeMinutes: Int = 0,
        coreMinutes: Int = 0,
        deepMinutes: Int = 0,
        remMinutes: Int = 0
    ) -> SleepTrendNightSummary {
        SleepTrendNightSummary(
            day: day,
            startTime: startTime,
            endTime: endTime,
            inBedMinutes: inBedMinutes,
            asleepMinutes: asleepMinutes,
            awakeMinutes: awakeMinutes,
            coreMinutes: coreMinutes,
            deepMinutes: deepMinutes,
            remMinutes: remMinutes
        )
    }

    // MARK: - 在床时长

    @MainActor func testEffectiveInBedPrefersProvidedInBedMinutes() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(8 * 3600),
            inBedMinutes: 400,
            asleepMinutes: 380
        )
        XCTAssertEqual(item.effectiveInBedMinutes, 400)
    }

    @MainActor func testEffectiveInBedFallsBackToSessionMinutes() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(7.5 * 3600),
            inBedMinutes: nil,
            asleepMinutes: 420
        )
        XCTAssertEqual(item.effectiveInBedMinutes, 450)
    }

    @MainActor func testEffectiveInBedNilWhenSessionShorterThanAsleep() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(5 * 3600),
            inBedMinutes: nil,
            asleepMinutes: 420
        )
        XCTAssertNil(item.effectiveInBedMinutes)
    }

    // MARK: - 效率与占比

    @MainActor func testEfficiencyUsesEffectiveInBed() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(8 * 3600),
            asleepMinutes: 400
        )
        XCTAssertEqual(item.efficiency ?? -1, 400.0 / 480.0, accuracy: 0.0001)
    }

    @MainActor func testEfficiencyNilWhenNoInBed() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(3 * 3600),
            asleepMinutes: 420
        )
        XCTAssertNil(item.efficiency)
    }

    @MainActor func testDeepAndRemRatios() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(8 * 3600),
            asleepMinutes: 400,
            deepMinutes: 80,
            remMinutes: 100
        )
        XCTAssertEqual(item.deepRatio ?? -1, 0.2, accuracy: 0.0001)
        XCTAssertEqual(item.remRatio ?? -1, 0.25, accuracy: 0.0001)
    }

    @MainActor func testDeepRatioNilWhenAsleepZero() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(8 * 3600),
            asleepMinutes: 0,
            deepMinutes: 0
        )
        XCTAssertNil(item.deepRatio)
        XCTAssertNil(item.remRatio)
    }

    // MARK: - 睡眠评分估算

    @MainActor func testSleepScoreEstimateExactKnownCase() {
        // 8 小时睡眠、效率 100%、深睡 20%、REM 20%。
        // duration 100 * 0.34 + efficiency 100 * 0.26 + deep 100 * 0.22 + rem (0.2/0.24*100) * 0.18
        // = 34 + 26 + 22 + 15 = 97。
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(8 * 3600),
            asleepMinutes: 480,
            deepMinutes: 96,
            remMinutes: 96
        )
        XCTAssertEqual(item.sleepScoreEstimate, 97)
    }

    @MainActor func testSleepScoreEstimateBoundedToHundred() {
        // 超长睡眠 + 超高深睡/REM 也不会突破 100。
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(12 * 3600),
            asleepMinutes: 720,
            deepMinutes: 300,
            remMinutes: 300
        )
        XCTAssertEqual(item.sleepScoreEstimate, 100)
    }

    @MainActor func testSleepScoreEstimateHandlesZeroAsleep() {
        let item = summary(
            startTime: day,
            endTime: day.addingTimeInterval(1 * 3600),
            asleepMinutes: 0
        )
        // 使用回退比例（0.78 / 0.16 / 0.2）与 0 时长评分，仍应落在 0...100。
        XCTAssertTrue((0...100).contains(item.sleepScoreEstimate))
    }
}
