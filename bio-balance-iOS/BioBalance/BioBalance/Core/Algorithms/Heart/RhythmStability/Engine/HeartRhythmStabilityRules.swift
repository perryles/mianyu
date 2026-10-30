import Foundation

/// 心律稳定性评分的权重、阈值与扣分上限，集中定义避免散落到引擎逻辑里。
nonisolated enum HeartRhythmStabilityRules {
    static let maximumScore = 100.0
    static let minimumScore = 0.0

    // MARK: 分档阈值

    /// 分数不低于该值视为心律平稳。
    static let steadyScoreThreshold = 85
    /// 分数不低于该值视为需持续留意，低于则视为异常线索较多。
    static let watchScoreThreshold = 60

    // MARK: 观察窗口密度归一化

    /// 事件密度归一化的标准窗口天数：把被动事件计数折算到"每标准窗口"的密度。
    static let standardObservationWindowDays = 7.0
    /// 密度折算因子下限：长窗口最多把密度稀释到一半，避免归零。
    static let minimumDensityFactor = 0.5
    /// 密度折算因子上限：短窗口最多把密度放大 2 倍，避免极端窗口爆量。
    static let maximumDensityFactor = 2.0

    // MARK: 房颤通道（概率并集去重）
    //
    // 房颤负担、心律不齐通知、ECG 房颤结论三者高度相关（多指向同一房颤），
    // 采用概率并集 `1 - Π(1 - sᵢ)` 合成为单一严重度，避免同一房颤被重复扣分。

    /// 房颤通道合成后的最大扣分。
    static let atrialFibrillationChannelPenaltyCap = 60.0
    /// 房颤负担 → 严重度的分段线性断点：`(负担百分比, 严重度)`。
    ///
    /// 非线性映射：<2% 轻微、2–10% 低、10–30% 中、30–60% 高、≥60% 视为接近持续性。
    /// 相比旧版"10% 即饱和"，在高负担区间仍保留区分度。
    static let burdenSeverityBreakpoints: [(percent: Double, severity: Double)] = [
        (0, 0.0), (2, 0.20), (10, 0.50), (30, 0.80), (60, 1.0)
    ]
    /// 每次心律不齐通知（已密度归一化）贡献的严重度。
    static let irregularSeverityPerEvent = 0.2
    /// 心律不齐通知单通道严重度上限（0.75 → 单独最多扣 45）。
    static let irregularSeverityCap = 0.75
    /// 每条 ECG 房颤结论贡献的严重度（0.5 → 2 条即达满严重度）。
    static let ecgAtrialFibrillationSeverityPerReading = 0.5
    static let ecgAtrialFibrillationSeverityCap = 1.0

    // MARK: 疑似早搏（ECG 结果不确定，非 poor reading）

    /// 每条 ECG 不确定结论的扣分（异常搏动线索）。
    static let ecgInconclusivePenaltyPerReading = 6.0
    static let ecgInconclusivePenaltyCap = 24.0

    // MARK: 高/低心率事件

    static let heartRateEventPenaltyPerEvent = 4.0
    static let heartRateEventPenaltyCap = 20.0

    // MARK: 扣分乘子

    /// 施加到身体电量的最大扣分幅度（分数为 0 时的下限乘子）。
    static let minimumPenaltyMultiplier = 0.85
    /// 分数不低于该值时不施加扣分（保持乘子为 1）。
    static let penaltyFreeScoreThreshold = 85.0

    // MARK: 置信度加权
    //
    // 低数据质量（单条噪声证据）时，把身体电量扣分向"不扣分"收敛，避免一条差读数显著拉低电量。
    // 只影响施加到身体电量的乘子，不改变展示用的稳定性分数与分档。

    static let lowConfidenceWeight = 0.6
    static let mediumConfidenceWeight = 0.85
    static let highConfidenceWeight = 1.0

    static func clampScore(_ value: Double) -> Int {
        Int(min(maximumScore, max(minimumScore, value)).rounded())
    }

    /// 观察窗口密度折算因子：标准窗口 / 实际窗口，clamp 到 [0.5, 2.0]。
    ///
    /// 只用于被动自动检测的事件（心律不齐通知、高/低心率事件），
    /// 使"7 天内 2 次"与"1 天内 2 次"体现出密度差异；ECG 为用户主动测量，不折算。
    static func densityFactor(observationDays: Int) -> Double {
        let days = Double(max(1, observationDays))
        let raw = standardObservationWindowDays / days
        return min(maximumDensityFactor, max(minimumDensityFactor, raw))
    }

    /// 房颤负担百分比映射为严重度（0...1），按 `burdenSeverityBreakpoints` 做分段线性插值。
    static func burdenSeverity(percent: Double) -> Double {
        guard percent.isFinite, percent > 0 else { return 0 }
        let points = burdenSeverityBreakpoints
        guard let last = points.last else { return 0 }
        if percent >= last.percent { return last.severity }
        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            guard percent <= upper.percent else { continue }
            let span = upper.percent - lower.percent
            guard span > 0 else { return upper.severity }
            let fraction = (percent - lower.percent) / span
            return lower.severity + fraction * (upper.severity - lower.severity)
        }
        return last.severity
    }

    /// 心律不齐通知（已密度归一化的次数）映射为严重度（0...上限）。
    static func irregularSeverity(normalizedCount: Double) -> Double {
        guard normalizedCount > 0 else { return 0 }
        return min(irregularSeverityCap, normalizedCount * irregularSeverityPerEvent)
    }

    /// ECG 房颤结论条数映射为严重度（0...1）。
    static func ecgAtrialFibrillationSeverity(count: Int) -> Double {
        guard count > 0 else { return 0 }
        return min(ecgAtrialFibrillationSeverityCap, Double(count) * ecgAtrialFibrillationSeverityPerReading)
    }

    /// 概率并集合成多路相关严重度：`1 - Π(1 - sᵢ)`，输入越多合成越高但仍有界于 1。
    static func combinedSeverity(_ severities: [Double]) -> Double {
        let complement = severities.reduce(1.0) { partial, severity in
            partial * (1.0 - min(1.0, max(0.0, severity)))
        }
        return 1.0 - complement
    }

    /// 把分数映射为身体电量扣分乘子：85 分及以上不扣分，越低扣得越多，最多到 0.85。
    static func penaltyMultiplier(forScore score: Int) -> Double {
        guard Double(score) < penaltyFreeScoreThreshold else { return 1.0 }
        let severity = (penaltyFreeScoreThreshold - Double(score)) / penaltyFreeScoreThreshold
        let clampedSeverity = min(1.0, max(0.0, severity))
        return 1.0 - clampedSeverity * (1.0 - minimumPenaltyMultiplier)
    }

    /// 数据置信度权重：质量越低越接近 0，扣分越向"不扣分"收敛。
    static func confidenceWeight(for quality: HeartRhythmDataQuality) -> Double {
        switch quality {
        case .unavailable: return 0.0
        case .low: return lowConfidenceWeight
        case .medium: return mediumConfidenceWeight
        case .high: return highConfidenceWeight
        }
    }

    /// 结合数据置信度的有效扣分乘子：低置信度时把乘子向 1.0 收敛，仍恒在 `0.85...1.0`。
    ///
    /// 仅用于施加到身体电量的扣分，不影响展示用的稳定性分数与分档。
    static func effectivePenaltyMultiplier(forScore score: Int, dataQuality: HeartRhythmDataQuality) -> Double {
        let raw = penaltyMultiplier(forScore: score)
        let weight = confidenceWeight(for: dataQuality)
        let effective = 1.0 - (1.0 - raw) * weight
        return min(1.0, max(minimumPenaltyMultiplier, effective))
    }

    static func band(forScore score: Int) -> HeartRhythmStabilityBand {
        switch score {
        case steadyScoreThreshold...:
            return .steady
        case watchScoreThreshold..<steadyScoreThreshold:
            return .watch
        default:
            return .elevated
        }
    }
}
