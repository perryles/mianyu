import Foundation

/// 本地确定性健康计算的样本门槛。
/// 只有积累足够多的独立夜间样本后，中位数才能作为个人基线。
nonisolated enum HealthBaselineMetric: String, Codable, Sendable {
    case hrvSDNN
    case restingHeartRate
    case sleepDuration
    case sleepScore

    var validRange: ClosedRange<Double> {
        switch self {
        case .hrvSDNN:
            return 5...250
        case .restingHeartRate:
            return 25...220
        case .sleepDuration:
            return 60...960
        case .sleepScore:
            return 1...100
        }
    }
}

/// 单项个人基线的样本进度、可用性和置信度状态。
nonisolated struct HealthBaselineState: Codable, Equatable, Sendable {
    let metric: HealthBaselineMetric
    let value: Double?
    let sampleCount: Int
    let minimumSampleCount: Int
    let trustedSampleCount: Int

    var isUsable: Bool {
        sampleCount >= minimumSampleCount && value != nil
    }

    var isTrusted: Bool {
        sampleCount >= trustedSampleCount && value != nil
    }

    /// 个人基线仍在校准时主动限制置信度上限。
    var confidence: Double {
        guard value != nil else { return 0 }
        if sampleCount >= trustedSampleCount { return 1 }
        return min(0.65, Double(sampleCount) / Double(max(trustedSampleCount, 1)))
    }

    var remainingSamplesUntilUsable: Int {
        max(0, minimumSampleCount - sampleCount)
    }

    var remainingSamplesUntilTrusted: Int {
        max(0, trustedSampleCount - sampleCount)
    }

    var calibrationProgress: Double {
        min(1, Double(sampleCount) / Double(max(trustedSampleCount, 1)))
    }
}

/// 过滤异常值并以中位数生成个人健康基线。
nonisolated enum HealthBaselineStrategy {
    static let minimumUsableSamples = 4
    static let trustedSamples = 14

    static func state(
        for values: [Double],
        metric: HealthBaselineMetric,
        minimumSampleCount: Int = minimumUsableSamples,
        trustedSampleCount: Int = trustedSamples
    ) -> HealthBaselineState {
        let range = metric.validRange
        let normalizedMinimum = max(1, minimumSampleCount)
        let normalizedTrusted = max(normalizedMinimum, trustedSampleCount)
        let validValues = values.filter { value in
            value.isFinite && range.contains(value)
        }.sorted()

        return HealthBaselineState(
            metric: metric,
            value: median(validValues),
            sampleCount: validValues.count,
            minimumSampleCount: normalizedMinimum,
            trustedSampleCount: normalizedTrusted
        )
    }

    static func usableValue(
        for values: [Double],
        metric: HealthBaselineMetric
    ) -> Double? {
        let state = state(for: values, metric: metric)
        return state.isUsable ? state.value : nil
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

/// 睡眠评分允许使用的可选确定性输入。
nonisolated struct DeterministicSleepInput: Equatable, Sendable {
    let durationMinutes: Int?
    let goalMinutes: Int?
    let continuityScore: Int?
    let restorativeScore: Int?
    let disturbanceScore: Int?
}

/// 按现有样本动态归一权重的睡眠评分策略。
nonisolated enum DeterministicSleepStrategy {
    /// 只有实测且为正数的睡眠时长才参与评分；缺失项直接从加权平均中移除，不填默认值。
    static func score(for input: DeterministicSleepInput) -> Int? {
        guard let duration = input.durationMinutes, duration > 0 else { return nil }
        var weightedTotal = 0.0
        var totalWeight = 0.0

        let target = max(input.goalMinutes ?? 480, 1)
        let durationScore = min(100, max(0, Int((Double(duration) / Double(target) * 100).rounded())))
        weightedTotal += Double(durationScore) * 0.34
        totalWeight += 0.34
        if let continuity = input.continuityScore, (0...100).contains(continuity) {
            weightedTotal += Double(continuity) * 0.24
            totalWeight += 0.24
        }
        if let restorative = input.restorativeScore, (0...100).contains(restorative) {
            weightedTotal += Double(restorative) * 0.24
            totalWeight += 0.24
        }
        if let disturbance = input.disturbanceScore, (0...100).contains(disturbance) {
            weightedTotal += Double(100 - disturbance) * 0.18
            totalWeight += 0.18
        }

        guard totalWeight > 0 else { return nil }
        return min(100, max(0, Int((weightedTotal / totalWeight).rounded())))
    }
}
