import Foundation
import OSLog

struct StressPresentationDescriptor: Equatable, Sendable {
    let title: String
    let adviceTitle: String
    let adviceDetail: String
    let tint: StressTint
    let accentHex: String
    let secondaryHex: String
    let assetName: String
}

enum StressPresentation {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "StressPresentation")

    static func assessment(from evaluation: StressEvaluation) -> StressPresentationAssessment {
        switch evaluation {
        case let .available(result):
            return assessment(from: result)
        case let .unavailable(reason):
            return unavailableAssessment(reason: reason)
        }
    }

    static func evaluation(from realtime: RealtimeHealth?, now: Date = Date()) -> StressEvaluation {
        guard let realtime else { return .unavailable(.noPhysiologicalSignal) }
        if let rawReason = realtime.stress_unavailable_reason,
           let reason = StressUnavailableReason(rawValue: rawReason) {
            return .unavailable(reason)
        }
        guard realtime.stress_level != nil || realtime.stress_value > 0 else {
            return .unavailable(.noPhysiologicalSignal)
        }
        let calculatedAt = Date(timeIntervalSince1970: TimeInterval(realtime.timestamp))
        guard now.timeIntervalSince(calculatedAt) <= StressRules.heartRateFreshness else {
            return .unavailable(.staleResult)
        }
        let score = StressRules.clamp(realtime.stress_value)
        let state = StressState(rawValue: realtime.stress_level ?? "") ?? StressRules.state(for: score)
        let confidence = StressRules.clamp(realtime.stress_confidence ?? 0.5, lower: 0, upper: 1)
        let driver = driver(for: realtime.stress_explanation_code)
        let recovery = StressRecoverySnapshot(
            recoveryScore: 50,
            recoveryDebt: 50,
            sleepMinutes: nil,
            sleepEfficiency: nil,
            nightlyHrv: nil,
            overnightMinHeartRate: nil
        )
        return .available(StressResult(
            timestamp: realtime.timestamp,
            rawScore: score,
            smoothedScore: score,
            state: state,
            band: StressRules.band(for: state),
            dominantDriver: driver,
            dominantDrivers: [driver],
            explanationCode: StressExplanationCode(rawValue: realtime.stress_explanation_code ?? "") ?? .fallback,
            confidence: confidence,
            quality: StressDataQuality(rawValue: realtime.stress_quality ?? "") ?? StressRules.quality(for: confidence),
            algorithmVersion: realtime.stress_algorithm_version ?? StressResult.currentAlgorithmVersion,
            recovery: recovery,
            workout: .inactive,
            components: StressComponentScores(
                hrvDeviation: 0,
                hrDeviation: 0,
                hrvTrend: 0,
                hrTrend: 0,
                recoveryDebt: 0,
                circadian: 0,
                workoutLoad: 0,
                mentalRaw: score,
                physicalRaw: score,
                rawScore: score,
                smoothedScore: score
            )
        ))
    }

    static func assessment(from result: StressResult) -> StressPresentationAssessment {
        let descriptor = descriptor(
            for: result.band,
            explanation: result.explanationCode,
            availableDrivers: Set(result.dominantDrivers)
        )
        return StressPresentationAssessment(
            score: result.score,
            band: result.band,
            title: descriptor.title,
            adviceTitle: descriptor.adviceTitle,
            adviceDetail: descriptor.adviceDetail,
            tint: descriptor.tint,
            updatedAtSeconds: result.timestamp,
            confidence: result.confidence,
            quality: result.quality,
            unavailableReason: nil
        )
    }

    static func assessment(from realtime: RealtimeHealth?, now: Date) -> StressPresentationAssessment? {
        guard let result = evaluation(from: realtime, now: now).result else { return nil }
        let assessment = assessment(from: result)
        Self.logger.info("[StressPresentation] operation=buildAssessment")
        return assessment
    }

    static func assessmentFromScore(_ score: Int, now: Date, updatedAtSeconds: Int64?) -> StressPresentationAssessment {
        let score = StressRules.clamp(score)
        let band = StressRules.band(for: score)
        let descriptor = descriptor(for: band, explanation: .fallback, availableDrivers: [])
        return StressPresentationAssessment(
            score: score,
            band: band,
            title: descriptor.title,
            adviceTitle: descriptor.adviceTitle,
            adviceDetail: descriptor.adviceDetail,
            tint: descriptor.tint,
            updatedAtSeconds: updatedAtSeconds ?? Int64(now.timeIntervalSince1970),
            confidence: nil,
            quality: .low,
            unavailableReason: nil
        )
    }

    static func unavailableAssessment(reason: StressUnavailableReason) -> StressPresentationAssessment {
        let title: String
        let detail: String
        switch reason {
        case .baselineCalibrating:
            title = "个人基线校准中"
            detail = "继续佩戴并同步数据；积累个人基线或连续心率趋势后再生成压力分数。"
        case .staleHeartRate:
            title = "等待新的心率数据"
            detail = "最近的心率样本已经过期，获取新样本后会自动更新。"
        case .staleHrv:
            title = "等待新的 HRV 数据"
            detail = "最近的 HRV 样本已经过期，暂不使用旧数据估算当前状态。"
        case .staleResult:
            title = "当前结果已过期"
            detail = "上次有效结果仅保留为历史信息，等待新样本后再显示当前压力。"
        case .insufficientDailyCoverage:
            title = "今日样本还不够"
            detail = "至少需要 4 个有效时间桶并覆盖 30 分钟，才能生成今日综合压力。"
        case .noDailySamples:
            title = "等待今日压力样本"
            detail = "当前压力开始稳定记录后，这里会生成今日综合结果。"
        case .noPhysiologicalSignal:
            title = "等待健康数据"
            detail = "需要新的心率或 HRV 数据以及可用的个人基线。"
        }
        return StressPresentationAssessment(
            score: nil,
            band: .waiting,
            title: "等待数据",
            adviceTitle: title,
            adviceDetail: detail,
            tint: .tertiary,
            updatedAtSeconds: nil,
            confidence: nil,
            quality: .unavailable,
            unavailableReason: reason
        )
    }

    static func descriptor(
        for band: StressBand,
        explanation: StressExplanationCode,
        availableDrivers: Set<StressDominantDriver>
    ) -> StressPresentationDescriptor {
        let base = baseDescriptor(for: band)
        let detail = explanationDetail(
            explanation,
            availableDrivers: availableDrivers,
            fallback: base.adviceDetail
        )
        return StressPresentationDescriptor(
            title: base.title,
            adviceTitle: base.adviceTitle,
            adviceDetail: detail,
            tint: base.tint,
            accentHex: base.accentHex,
            secondaryHex: base.secondaryHex,
            assetName: base.assetName
        )
    }

    private static func baseDescriptor(for band: StressBand) -> StressPresentationDescriptor {
        switch band {
        case .waiting:
            return .init(title: "等待数据", adviceTitle: "正在等待健康数据。", adviceDetail: "同步后会自动更新。", tint: .tertiary, accentHex: "6C6C70", secondaryHex: "B9C0FF", assetName: "TodayPressureWaiting")
        case .relaxed:
            return .init(title: "放松", adviceTitle: "身体压力较低，恢复状态比较好。", adviceDetail: "当前没有明显高压信号，可以保持现在的节奏。", tint: .mintGreen, accentHex: "34C759", secondaryHex: "8DE5C4", assetName: "TodayPressureRelaxed")
        case .steady:
            return .init(title: "平稳", adviceTitle: "身体压力处于可控范围。", adviceDetail: "整体状态平稳，继续观察后半天的变化。", tint: .mintGreen, accentHex: "007F79", secondaryHex: "2FD1D8", assetName: "TodayPressureSteady")
        case .mild:
            return .init(title: "轻度压力", adviceTitle: "身体已经出现一定压力负荷。", adviceDetail: "建议安排短暂休息、补水，并放慢当前节奏。", tint: .orange, accentHex: "FF9F0A", secondaryHex: "FFB347", assetName: "TodayPressureMild")
        case .caution:
            return .init(title: "注意压力", adviceTitle: "身体压力偏高，建议主动降负荷。", adviceDetail: "暂停高强度安排，优先放松、拉伸或提前休息。", tint: .orangeDeep, accentHex: "FF7A00", secondaryHex: "FFA45A", assetName: "TodayPressureCaution")
        case .high:
            return .init(title: "压力偏高", adviceTitle: "身体压力处于高位，请认真休息。", adviceDetail: "建议停止高强度活动并观察后续变化；如持续不适，请及时寻求专业帮助。", tint: .accentRed, accentHex: "D70015", secondaryHex: "FF8A80", assetName: "TodayPressureHigh")
        }
    }

    private static func explanationDetail(
        _ code: StressExplanationCode,
        availableDrivers: Set<StressDominantDriver>,
        fallback: String
    ) -> String {
        switch code {
        case .physicalWorkoutLoad:
            return String(localized: "当前更像运动带来的身体负荷，不完全等同于精神压力。")
        case .recoveryDebtElevated:
            return String(localized: "昨夜恢复不足使今天更容易承压，建议优先补充恢复。")
        case .hrvBelowBaseline where availableDrivers.isEmpty || availableDrivers.contains(.hrvDeviation):
            return String(localized: "当前 HRV 低于个人近期基线，恢复节律偏紧。")
        case .heartRateAboveBaseline where availableDrivers.isEmpty || availableDrivers.contains(.hrDeviation):
            return String(localized: "当前心率高于个人静息基线，身体负荷正在抬升。")
        case .hrvTrendingDown where availableDrivers.isEmpty || availableDrivers.contains(.hrvTrend):
            return String(localized: "近 30 分钟 HRV 呈下降趋势，建议放慢节奏。")
        case .heartRateTrendingUp where availableDrivers.isEmpty || availableDrivers.contains(.hrTrend):
            return String(localized: "近 30 分钟心率呈上升趋势，建议观察是否回落。")
        case .circadianLoadWindow:
            return String(localized: "当前处在更容易承压的昼夜时段，身体对刺激可能更敏感。")
        case .stablePhysiology:
            return String(localized: "当前生理信号接近或优于个人近期基线，可以保持现在的节奏。")
        case .dailyAverageElevated:
            return String(localized: "今天多个时段的压力均值偏高，适合主动降低后续负荷。")
        case .dailyPeakElevated:
            return String(localized: "今天出现过明显压力峰值，建议结合当时活动回看原因。")
        case .stableDailyLoad:
            return String(localized: "今天的有效样本整体稳定，可以继续保持当前节奏。")
        case .insufficientBaseline:
            return String(localized: "个人基线仍在校准，当前结果只作趋势参考。")
        default:
            return fallback
        }
    }

    private static func driver(for explanationCode: String?) -> StressDominantDriver {
        switch StressExplanationCode(rawValue: explanationCode ?? "") {
        case .physicalWorkoutLoad: return .workoutLoad
        case .recoveryDebtElevated: return .recoveryDebt
        case .heartRateAboveBaseline: return .hrDeviation
        case .hrvTrendingDown: return .hrvTrend
        case .heartRateTrendingUp: return .hrTrend
        case .circadianLoadWindow: return .circadian
        default: return .hrvDeviation
        }
    }
}
