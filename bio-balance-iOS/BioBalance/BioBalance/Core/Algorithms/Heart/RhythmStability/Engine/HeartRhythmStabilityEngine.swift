import Foundation

/// 基于 Apple 健康事件聚合口径的心律稳定性参考引擎。
///
/// 不做逐搏 RR 自算，也不复刻任何厂商私有算法；从房颤负担、心律不齐通知、
/// 高/低心率事件与 ECG 结论出发，给出可解释的稳定性参考分与有界扣分乘子。
/// 结果定位为参考、非医疗诊断。
nonisolated enum HeartRhythmStabilityEngine {
    static let algorithmVersion = "1.2"

    /// 对输入信号做确定性评估；无任何有效证据时返回 `.unavailable`（不影响其他指标）。
    ///
    /// 注意：ECG poor reading 属信号质量问题、不作为证据（单独出现仍视为无法评估）。
    static func evaluate(input: HeartRhythmStabilityInput) -> HeartRhythmStabilityResult {
        let hasEvidence = input.atrialFibrillationBurdenPercent != nil
            || input.irregularRhythmEventCount > 0
            || input.highHeartRateEventCount > 0
            || input.lowHeartRateEventCount > 0
            || input.ecgAtrialFibrillationCount > 0
            || input.ecgInconclusiveCount > 0
            || input.ecgSinusCount > 0

        guard hasEvidence else { return .unavailable }

        let densityFactor = HeartRhythmStabilityRules.densityFactor(observationDays: input.observationDays)

        var score = HeartRhythmStabilityRules.maximumScore
        var dominant: [(kind: HeartRhythmSignalKind, penalty: Double)] = []

        // 房颤通道：三路相关证据（负担 / 通知 / ECG 房颤）用概率并集去重，避免同一房颤重复扣分。
        let burdenSeverity: Double = {
            guard let burden = input.atrialFibrillationBurdenPercent else { return 0 }
            return HeartRhythmStabilityRules.burdenSeverity(percent: burden)
        }()
        let irregularSeverity = HeartRhythmStabilityRules.irregularSeverity(
            normalizedCount: Double(input.irregularRhythmEventCount) * densityFactor
        )
        let ecgAfibSeverity = HeartRhythmStabilityRules.ecgAtrialFibrillationSeverity(
            count: input.ecgAtrialFibrillationCount
        )

        let afibChannelCap = HeartRhythmStabilityRules.atrialFibrillationChannelPenaltyCap
        let afibSeverity = HeartRhythmStabilityRules.combinedSeverity([
            burdenSeverity, irregularSeverity, ecgAfibSeverity
        ])
        score -= afibSeverity * afibChannelCap

        // 主导信号按各子证据"单独等效扣分"（严重度 × 通道上限）排序，供详情页解释。
        if burdenSeverity > 0 { dominant.append((.atrialFibrillationBurden, burdenSeverity * afibChannelCap)) }
        if irregularSeverity > 0 { dominant.append((.irregularRhythmEvent, irregularSeverity * afibChannelCap)) }
        if ecgAfibSeverity > 0 { dominant.append((.ecgAtrialFibrillation, ecgAfibSeverity * afibChannelCap)) }

        // 疑似早搏：ECG 结果不确定（不含 poor reading），独立通道，为用户主动测量故不做密度折算。
        if input.ecgInconclusiveCount > 0 {
            let penalty = min(
                HeartRhythmStabilityRules.ecgInconclusivePenaltyCap,
                Double(input.ecgInconclusiveCount) * HeartRhythmStabilityRules.ecgInconclusivePenaltyPerReading
            )
            score -= penalty
            dominant.append((.ecgInconclusive, penalty))
        }

        // 高/低心率事件：被动自动检测，按密度折算后扣分。
        let highLowCount = input.highHeartRateEventCount + input.lowHeartRateEventCount
        if highLowCount > 0 {
            let penalty = min(
                HeartRhythmStabilityRules.heartRateEventPenaltyCap,
                Double(highLowCount) * densityFactor * HeartRhythmStabilityRules.heartRateEventPenaltyPerEvent
            )
            score -= penalty
            if input.highHeartRateEventCount > 0 {
                dominant.append((.highHeartRateEvent, Double(input.highHeartRateEventCount)))
            }
            if input.lowHeartRateEventCount > 0 {
                dominant.append((.lowHeartRateEvent, Double(input.lowHeartRateEventCount)))
            }
        }

        let finalScore = HeartRhythmStabilityRules.clampScore(score)
        let band = HeartRhythmStabilityRules.band(forScore: finalScore)
        let quality = dataQuality(for: input)
        let dominantSignals = dominant
            .sorted { $0.penalty > $1.penalty }
            .map(\.kind)

        return HeartRhythmStabilityResult(
            score: finalScore,
            band: band,
            dataQuality: quality,
            suspectedAtrialFibrillationCount: input.irregularRhythmEventCount + input.ecgAtrialFibrillationCount,
            suspectedEctopicCount: input.ecgInconclusiveCount,
            normalCount: input.ecgSinusCount,
            heartRateEventCount: highLowCount,
            poorReadingCount: input.ecgPoorReadingCount,
            dominantSignals: dominantSignals,
            penaltyMultiplier: HeartRhythmStabilityRules.effectivePenaltyMultiplier(
                forScore: finalScore,
                dataQuality: quality
            ),
            lastEventDate: resolveLastEventDate(input: input)
        )
    }

    /// 用心律结果对已算出的身体电量施加有界扣分；结果无数据时原值返回。
    static func applyPenalty(bodyIndex: Int?, result: HeartRhythmStabilityResult) -> Int? {
        guard let bodyIndex, result.hasData else { return bodyIndex }
        let adjusted = Double(bodyIndex) * result.penaltyMultiplier
        return Int(adjusted.rounded())
    }

    /// 对同一条身体电量轨迹逐点应用相同的心律修正，保证卡片值与详情末点一致。
    static func applyPenalty(
        trajectory: [TimeSeriesPoint],
        result: HeartRhythmStabilityResult
    ) -> [TimeSeriesPoint] {
        guard result.hasData else { return trajectory }
        return trajectory.map { point in
            TimeSeriesPoint(
                timestamp: point.timestamp,
                value: applyPenalty(bodyIndex: point.value, result: result) ?? point.value
            )
        }
    }

    private static func dataQuality(for input: HeartRhythmStabilityInput) -> HeartRhythmDataQuality {
        let ecgTotal = input.ecgAtrialFibrillationCount + input.ecgInconclusiveCount + input.ecgSinusCount
        let hasBurden = input.atrialFibrillationBurdenPercent != nil
        var sources = 0
        if hasBurden { sources += 1 }
        if input.irregularRhythmEventCount > 0 { sources += 1 }
        if ecgTotal > 0 { sources += 1 }
        if input.highHeartRateEventCount + input.lowHeartRateEventCount > 0 { sources += 1 }

        switch sources {
        case 0:
            return .unavailable
        case 1:
            return .low
        case 2:
            return .medium
        default:
            return .high
        }
    }

    private static func resolveLastEventDate(input: HeartRhythmStabilityInput) -> Date? {
        [input.lastIrregularRhythmDate, input.lastEcgDate]
            .compactMap { $0 }
            .max()
    }
}
