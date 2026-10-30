import Foundation

nonisolated enum StressRules {
    static let heartRateFreshness: TimeInterval = 10 * 60
    static let hrvFullWeightFreshness: TimeInterval = 60 * 60
    static let hrvMaximumFreshness: TimeInterval = 4 * 60 * 60
    static let dailyBucketSeconds: Int64 = 7 * 60
    static let minimumDailyBuckets = 4
    static let minimumDailySpan: TimeInterval = 30 * 60
    static let downwardHysteresis = 5

    static func state(for score: Int) -> StressState {
        switch clamp(score) {
        case ..<15: return .recovery
        case 15..<30: return .relaxed
        case 30..<50: return .normal
        case 50..<70: return .strained
        case 70..<85: return .highStress
        default: return .overloaded
        }
    }

    static func band(for score: Int) -> StressBand {
        switch clamp(score) {
        case ..<30: return .relaxed
        case 30..<50: return .steady
        case 50..<70: return .mild
        case 70..<85: return .caution
        default: return .high
        }
    }

    static func band(for state: StressState) -> StressBand {
        switch state {
        case .recovery, .relaxed: return .relaxed
        case .normal: return .steady
        case .strained: return .mild
        case .highStress: return .caution
        case .overloaded: return .high
        }
    }

    static func thresholdLowerBound(for state: StressState) -> Int {
        switch state {
        case .recovery: return 0
        case .relaxed: return 15
        case .normal: return 30
        case .strained: return 50
        case .highStress: return 70
        case .overloaded: return 85
        }
    }

    static func rank(of state: StressState) -> Int {
        StressState.allCases.firstIndex(of: state) ?? 0
    }

    static func quality(for confidence: Double) -> StressDataQuality {
        switch confidence {
        case ..<0.35: return .low
        case ..<0.72: return .medium
        default: return .high
        }
    }

    static func clamp(_ score: Int) -> Int {
        min(max(score, 0), 100)
    }

    static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        min(max(value, lower), upper)
    }
}

/// Shared, stateless signal scoring rules. Realtime evaluation, historical
/// reconstruction and future device adapters keep separate orchestration while
/// consuming the same component formulas.
nonisolated enum StressSignalScoring {
    static func hrvDeviation(current: Double, baseline: Double) -> Double? {
        guard current > 0, baseline > 0 else { return nil }
        let dropRatio = StressRules.clamp((baseline - current) / baseline, lower: -0.30, upper: 1)
        return StressRules.clamp(50 + dropRatio * 120)
    }

    static func heartRateDeviation(current: Double, baseline: Double) -> Double? {
        guard current > 0, baseline > 0 else { return nil }
        return StressRules.clamp(35 + (current - baseline) * 2.2)
    }

    static func heartRateTrend(recent: Double, prior: Double) -> Double? {
        guard recent > 0, prior > 0 else { return nil }
        return StressRules.clamp(50 + (recent - prior) * 4)
    }

    static func historicalHrvWithoutBaseline(_ hrv: Double) -> Double? {
        guard hrv > 0 else { return nil }
        return StressRules.clamp(86 - hrv)
    }

    static func weightedMean(_ components: [(score: Double?, weight: Double)]) -> Double? {
        var weightedScore = 0.0
        var availableWeight = 0.0
        for component in components {
            guard let score = component.score, score.isFinite, component.weight > 0 else { continue }
            weightedScore += StressRules.clamp(score) * component.weight
            availableWeight += component.weight
        }
        return availableWeight > 0 ? weightedScore / availableWeight : nil
    }
}
