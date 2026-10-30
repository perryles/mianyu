import XCTest
@testable import BioBalance

/// 心律稳定性引擎与适配器的确定性测试。
///
/// 覆盖：高房颤负担扣分、事件密度扣分、ECG 房颤分类、缺失数据返回 nil 且不扣分、
/// penaltyMultiplier 边界（不低于 0.85）、三分类计数正确性；
/// v1.1：房颤三路证据概率并集去重、观察窗口密度归一化、ECG poor reading 不扣分不计早搏。
nonisolated final class HeartRhythmStabilityEngineTests: XCTestCase {
    @MainActor private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 缺失数据

    @MainActor func testNoEvidenceReturnsUnavailableAndDoesNotPenalize() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput())

        XCTAssertNil(result.score)
        XCTAssertEqual(result.band, .unavailable)
        XCTAssertEqual(result.dataQuality, .unavailable)
        XCTAssertEqual(result.penaltyMultiplier, 1.0)
        XCTAssertFalse(result.hasData)
    }

    @MainActor func testUnavailableResultKeepsBodyBatteryUnchanged() {
        let adjusted = HeartRhythmStabilityEngine.applyPenalty(
            bodyIndex: 72,
            result: .unavailable
        )

        XCTAssertEqual(adjusted, 72)
    }

    @MainActor func testAdapterWithoutSignalsReturnsUnavailable() {
        let result = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: .empty,
            referenceDate: referenceDate
        )

        XCTAssertNil(result.score)
        XCTAssertEqual(result.band, .unavailable)
    }

    // MARK: 房颤负担

    @MainActor func testHighAtrialFibrillationBurdenProducesElevatedBand() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 30
        ))

        // 30% 负担 → 分段映射严重度 0.80 → 扣 48 → 得分 52，仍落 elevated。
        XCTAssertEqual(result.score, 52)
        XCTAssertEqual(result.band, .elevated)
        XCTAssertEqual(result.dominantSignals.first, .atrialFibrillationBurden)
    }

    @MainActor func testAtrialFibrillationBurdenDiscriminatesHighFromModerate() {
        let moderate = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 10
        ))
        let high = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 60
        ))
        let extreme = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 90
        ))

        // 非线性映射：10% → 严重度 0.50 → 扣 30 → 70；60% → 严重度 1.0 → 扣 60 → 40。
        XCTAssertEqual(moderate.score, 70)
        XCTAssertEqual(high.score, 40)
        // 高负担比中等负担扣得更多（旧版会在 10% 即饱和、二者同分）。
        XCTAssertLessThan(try XCTUnwrap(high.score), try XCTUnwrap(moderate.score))
        // 60% 起严重度封顶，90% 不再进一步扣分。
        XCTAssertEqual(extreme.score, high.score)
    }

    // MARK: 事件密度

    @MainActor func testIrregularRhythmEventDensityReducesScoreMonotonically() {
        let single = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            irregularRhythmEventCount: 1
        ))
        let several = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            irregularRhythmEventCount: 3
        ))

        XCTAssertEqual(single.score, 88)
        XCTAssertGreaterThan(try XCTUnwrap(single.score), try XCTUnwrap(several.score))
    }

    @MainActor func testIrregularRhythmPenaltyIsCapped() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            irregularRhythmEventCount: 20
        ))

        // 20 × 12 = 240，封顶 45，得分 55。
        XCTAssertEqual(result.score, 55)
    }

    @MainActor func testHighLowHeartRateEventPenaltyIsCapped() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            highHeartRateEventCount: 10,
            lowHeartRateEventCount: 10
        ))

        // 20 × 4 = 80，封顶 20，得分 80。
        XCTAssertEqual(result.score, 80)
        XCTAssertEqual(result.heartRateEventCount, 20)
    }

    // MARK: ECG 分类

    @MainActor func testECGAtrialFibrillationCountsAsSuspectedAFibAndPenalizes() {
        let signals = makeSignals(ecgReadings: [
            HeartRhythmECGReading(classification: .atrialFibrillation, date: referenceDate)
        ])
        let result = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: signals,
            referenceDate: referenceDate
        )

        // 1 条房颤结论 × 30 = 30，得分 70。
        XCTAssertEqual(result.score, 70)
        XCTAssertEqual(result.suspectedAtrialFibrillationCount, 1)
        XCTAssertTrue(result.dominantSignals.contains(.ecgAtrialFibrillation))
    }

    @MainActor func testClassificationCountsMapCorrectly() {
        let signals = makeSignals(
            irregularRhythmEventCount: 2,
            ecgReadings: [
                HeartRhythmECGReading(classification: .sinusRhythm, date: referenceDate),
                HeartRhythmECGReading(classification: .sinusRhythm, date: referenceDate),
                HeartRhythmECGReading(classification: .sinusRhythm, date: referenceDate),
                HeartRhythmECGReading(classification: .atrialFibrillation, date: referenceDate),
                HeartRhythmECGReading(classification: .inconclusive, date: referenceDate),
                HeartRhythmECGReading(classification: .unclassified, date: referenceDate)
            ]
        )
        let result = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: signals,
            referenceDate: referenceDate
        )

        // 疑似房颤 = 心律不齐通知 2 + ECG 房颤 1 = 3。
        XCTAssertEqual(result.suspectedAtrialFibrillationCount, 3)
        // 疑似早搏 = ECG 不确定 1。
        XCTAssertEqual(result.suspectedEctopicCount, 1)
        // 未见异常 = ECG 窦性 3。unclassified 不计入任何分类。
        XCTAssertEqual(result.normalCount, 3)
        XCTAssertEqual(result.classifiedTotal, 7)
    }

    // MARK: penaltyMultiplier 边界

    @MainActor func testPenaltyMultiplierNeverBelowFloor() {
        let worst = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 100,
            irregularRhythmEventCount: 50,
            highHeartRateEventCount: 50,
            lowHeartRateEventCount: 50,
            ecgAtrialFibrillationCount: 50,
            ecgInconclusiveCount: 50
        ))

        XCTAssertEqual(worst.score, 0)
        XCTAssertGreaterThanOrEqual(worst.penaltyMultiplier, 0.85)
        XCTAssertLessThanOrEqual(worst.penaltyMultiplier, 1.0)
    }

    @MainActor func testSteadyScoreDoesNotPenalizeBodyBattery() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            ecgSinusCount: 3
        ))

        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.band, .steady)
        XCTAssertEqual(result.penaltyMultiplier, 1.0)
        XCTAssertEqual(HeartRhythmStabilityEngine.applyPenalty(bodyIndex: 80, result: result), 80)
    }

    @MainActor func testLowScoreLowersBodyBatteryWithinBound() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 100
        ))
        let adjusted = HeartRhythmStabilityEngine.applyPenalty(bodyIndex: 100, result: result)

        XCTAssertNotNil(adjusted)
        // 得分 40，但仅房颤负担单一来源（低置信度）→ 扣分被弱化，乘子约 0.95，100 → 95。始终 ≥ 85。
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(adjusted), 85)
        XCTAssertLessThan(try XCTUnwrap(adjusted), 100)
    }

    @MainActor func testPenaltyAdjustsEveryTrajectoryPointAndKeepsEndpointAligned() throws {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 100,
            irregularRhythmEventCount: 50,
            highHeartRateEventCount: 50,
            ecgAtrialFibrillationCount: 50
        ))
        let rawTrajectory = [
            TimeSeriesPoint(timestamp: 100, value: 92),
            TimeSeriesPoint(timestamp: 200, value: 71),
            TimeSeriesPoint(timestamp: 300, value: 48)
        ]

        let adjustedTrajectory = HeartRhythmStabilityEngine.applyPenalty(
            trajectory: rawTrajectory,
            result: result
        )
        let expectedValues = rawTrajectory.map {
            HeartRhythmStabilityEngine.applyPenalty(bodyIndex: $0.value, result: result) ?? $0.value
        }

        XCTAssertEqual(adjustedTrajectory.map(\.timestamp), rawTrajectory.map(\.timestamp))
        XCTAssertEqual(adjustedTrajectory.map(\.value), expectedValues)
        XCTAssertEqual(
            adjustedTrajectory.last?.value,
            HeartRhythmStabilityEngine.applyPenalty(
                bodyIndex: rawTrajectory.last?.value,
                result: result
            )
        )
        XCTAssertTrue(zip(adjustedTrajectory, rawTrajectory).allSatisfy { adjusted, raw in
            adjusted.value < raw.value
        })
    }

    @MainActor func testUnavailableRhythmResultKeepsTrajectoryUnchanged() {
        let rawTrajectory = [
            TimeSeriesPoint(timestamp: 100, value: 92),
            TimeSeriesPoint(timestamp: 200, value: 71)
        ]

        let adjustedTrajectory = HeartRhythmStabilityEngine.applyPenalty(
            trajectory: rawTrajectory,
            result: .unavailable
        )

        XCTAssertEqual(adjustedTrajectory.map(\.timestamp), rawTrajectory.map(\.timestamp))
        XCTAssertEqual(adjustedTrajectory.map(\.value), rawTrajectory.map(\.value))
    }

    // MARK: v1.1 房颤证据概率并集去重

    @MainActor func testCorrelatedAtrialFibrillationEvidenceIsDeduplicatedNotStacked() {
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 5,   // 分段映射严重度 0.3125
            irregularRhythmEventCount: 1,          // 严重度 0.2
            ecgAtrialFibrillationCount: 1          // 严重度 0.5
        ))

        // 概率并集：1 - (0.6875)(0.8)(0.5) = 0.725 → 扣 43.5 → 得分 57。
        // 若三路加性叠加会扣更多、得分明显更低，此处应显著更宽松。
        XCTAssertEqual(result.score, 57)
        XCTAssertGreaterThan(try XCTUnwrap(result.score), 40)
        XCTAssertEqual(result.band, .elevated)
    }

    @MainActor func testCombinedAtrialFibrillationChannelStaysBounded() {
        // 三路都拉满，房颤通道合成严重度封顶为 1，扣分不超过通道上限 60。
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 50,
            irregularRhythmEventCount: 10,
            ecgAtrialFibrillationCount: 5
        ))

        // 仅房颤通道扣分，封顶 60 → 得分 40。
        XCTAssertEqual(result.score, 40)
    }

    // MARK: v1.1 观察窗口密度归一化

    @MainActor func testShortObservationWindowRaisesEventDensity() {
        let weekWindow = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            observationDays: 7,
            irregularRhythmEventCount: 2
        ))
        let dayWindow = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            observationDays: 1,
            irregularRhythmEventCount: 2
        ))

        // 7 天 2 次：折算因子 1 → 严重度 0.4 → 扣 24 → 76。
        XCTAssertEqual(weekWindow.score, 76)
        // 1 天 2 次：折算因子封顶 2 → 归一化 4 → 严重度封顶 0.75 → 扣 45 → 55，密度更高扣得更多。
        XCTAssertEqual(dayWindow.score, 55)
        XCTAssertLessThan(try XCTUnwrap(dayWindow.score), try XCTUnwrap(weekWindow.score))
    }

    @MainActor func testLongObservationWindowDilutesEventDensity() {
        let weekWindow = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            observationDays: 7,
            irregularRhythmEventCount: 4
        ))
        let fortnightWindow = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            observationDays: 14,
            irregularRhythmEventCount: 4
        ))

        // 14 天窗口折算因子封顶下限 0.5 → 密度稀释，扣分更少、得分更高。
        XCTAssertGreaterThan(try XCTUnwrap(fortnightWindow.score), try XCTUnwrap(weekWindow.score))
    }

    // MARK: v1.1 ECG poor reading 语义

    @MainActor func testPoorReadingAloneReturnsUnavailable() {
        let signals = makeSignals(ecgReadings: [
            HeartRhythmECGReading(classification: .inconclusivePoorReading, date: referenceDate)
        ])
        let result = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: signals,
            referenceDate: referenceDate
        )

        // 信号质量不足不构成证据：单独出现视为无法评估。
        XCTAssertNil(result.score)
        XCTAssertEqual(result.band, .unavailable)
    }

    @MainActor func testPoorReadingDoesNotPenalizeOrCountAsEctopic() {
        let signals = makeSignals(ecgReadings: [
            HeartRhythmECGReading(classification: .sinusRhythm, date: referenceDate),
            HeartRhythmECGReading(classification: .sinusRhythm, date: referenceDate),
            HeartRhythmECGReading(classification: .sinusRhythm, date: referenceDate),
            HeartRhythmECGReading(classification: .inconclusivePoorReading, date: referenceDate),
            HeartRhythmECGReading(classification: .inconclusivePoorReading, date: referenceDate)
        ])
        let result = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: signals,
            referenceDate: referenceDate
        )

        // poor reading 不扣分、不计疑似早搏，只单独透明化计数。
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.band, .steady)
        XCTAssertEqual(result.suspectedEctopicCount, 0)
        XCTAssertEqual(result.poorReadingCount, 2)
        XCTAssertEqual(result.normalCount, 3)
    }

    @MainActor func testInconclusiveNonPoorReadingStillCountsAsEctopic() {
        let signals = makeSignals(ecgReadings: [
            HeartRhythmECGReading(classification: .inconclusive, date: referenceDate)
        ])
        let result = HeartRhythmStabilityHealthKitAdapter.evaluate(
            signals: signals,
            referenceDate: referenceDate
        )

        // 心率过高/过低/其它的不确定仍属异常搏动线索：每条扣 6 → 94，计入疑似早搏。
        XCTAssertEqual(result.score, 94)
        XCTAssertEqual(result.suspectedEctopicCount, 1)
        XCTAssertEqual(result.poorReadingCount, 0)
    }

    // MARK: v1.2 置信度加权扣分

    @MainActor func testConfidenceWeightingOrdersMultiplierByDataQuality() {
        let low = HeartRhythmStabilityRules.effectivePenaltyMultiplier(forScore: 40, dataQuality: .low)
        let medium = HeartRhythmStabilityRules.effectivePenaltyMultiplier(forScore: 40, dataQuality: .medium)
        let high = HeartRhythmStabilityRules.effectivePenaltyMultiplier(forScore: 40, dataQuality: .high)

        // 置信度越低，扣分越向"不扣分"收敛（乘子越接近 1）。
        XCTAssertGreaterThan(low, medium)
        XCTAssertGreaterThan(medium, high)
        // 高置信度等于纯分数乘子；三档均恒在 0.85...1.0。
        XCTAssertEqual(high, HeartRhythmStabilityRules.penaltyMultiplier(forScore: 40), accuracy: 1e-9)
        for multiplier in [low, medium, high] {
            XCTAssertGreaterThanOrEqual(multiplier, 0.85)
            XCTAssertLessThanOrEqual(multiplier, 1.0)
        }
    }

    @MainActor func testLowQualitySingleSourcePenalizesBodyBatteryLessThanScoreAlone() throws {
        // 仅房颤负担单一来源 → dataQuality .low。
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 30
        ))
        let scoreOnly = HeartRhythmStabilityRules.penaltyMultiplier(forScore: try XCTUnwrap(result.score))

        XCTAssertEqual(result.dataQuality, .low)
        // 低置信度下有效乘子被抬高（扣分更轻），不等于纯分数乘子。
        XCTAssertGreaterThan(result.penaltyMultiplier, scoreOnly)
        XCTAssertGreaterThanOrEqual(result.penaltyMultiplier, 0.85)
    }

    @MainActor func testHighQualityLowScoreStillHitsFullPenalty() {
        // 多来源（高置信度）+ 低分 → 不弱化，可触及 0.85 下限。
        let result = HeartRhythmStabilityEngine.evaluate(input: HeartRhythmStabilityInput(
            referenceDate: referenceDate,
            atrialFibrillationBurdenPercent: 100,
            irregularRhythmEventCount: 50,
            highHeartRateEventCount: 50,
            lowHeartRateEventCount: 50,
            ecgAtrialFibrillationCount: 50,
            ecgInconclusiveCount: 50
        ))

        XCTAssertEqual(result.dataQuality, .high)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.penaltyMultiplier, 0.85, accuracy: 1e-9)
    }

    // MARK: 辅助

    @MainActor private func makeSignals(
        atrialFibrillationBurdenPercent: Double? = nil,
        irregularRhythmEventCount: Int = 0,
        highHeartRateEventCount: Int = 0,
        lowHeartRateEventCount: Int = 0,
        ecgReadings: [HeartRhythmECGReading] = []
    ) -> HeartRhythmSignals {
        HeartRhythmSignals(
            atrialFibrillationBurdenPercent: atrialFibrillationBurdenPercent,
            atrialFibrillationBurdenDate: atrialFibrillationBurdenPercent == nil ? nil : referenceDate,
            irregularRhythmEventCount: irregularRhythmEventCount,
            lastIrregularRhythmDate: irregularRhythmEventCount > 0 ? referenceDate : nil,
            highHeartRateEventCount: highHeartRateEventCount,
            lowHeartRateEventCount: lowHeartRateEventCount,
            ecgReadings: ecgReadings,
            observationDays: 7
        )
    }
}
