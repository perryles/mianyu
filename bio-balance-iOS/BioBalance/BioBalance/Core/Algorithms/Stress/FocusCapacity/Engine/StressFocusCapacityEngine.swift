import Foundation

/// Estimates task-readiness from physiological load, recovery, sleep and daily context.
nonisolated enum StressFocusCapacityEngine {
    static let algorithmVersion = "2.0"

    private static let stressWeight = 0.45
    private static let bodyBatteryWeight = 0.20
    private static let sleepWeight = 0.15
    private static let circadianWeight = 0.10
    private static let movementWeight = 0.07
    private static let hydrationWeight = 0.03

    /// 评估传入的快照，不执行 I/O，也不读取全局状态。
    ///
    /// 压力是唯一必需维度；其他缺失维度会从
    /// 几何平均中移除，并通过证据覆盖率降低置信度。
    static func evaluate(input: StressFocusCapacityInput) -> StressFocusCapacityAssessment {
        guard let stressScore = input.stressScore else {
            return StressFocusCapacityAssessment(
                algorithmVersion: algorithmVersion,
                score: nil,
                band: .unavailable,
                confidence: nil,
                stressHeadroom: nil,
                bodyBatteryScore: input.bodyBatteryScore.map(clampScore),
                sleepReadiness: nil,
                circadianReadiness: nil,
                movementReadiness: nil,
                hydrationReadiness: nil,
                availableDimensionCount: 0
            )
        }

        let headroom = stressHeadroom(for: stressScore)
        let bodyBattery = input.bodyBatteryScore.map(clampScore)
        let sleep = sleepReadiness(
            sleepMinutes: input.sleepMinutes,
            sleepGoalMinutes: input.sleepGoalMinutes,
            sleepScore: input.sleepScore
        )
        let circadian = circadianReadiness(now: input.now, wakeDate: input.wakeDate)
        let movement = input.sedentaryMinutes.map(movementReadiness)
        let hydration = hydrationReadiness(
            now: input.now,
            wakeDate: input.wakeDate,
            waterIntakeMl: input.waterIntakeMl,
            waterTargetMl: input.waterTargetMl
        )

        var dimensions: [(score: Int, weight: Double)] = [(headroom, stressWeight)]
        if let bodyBattery { dimensions.append((bodyBattery, bodyBatteryWeight)) }
        if let sleep { dimensions.append((sleep, sleepWeight)) }
        if let circadian { dimensions.append((circadian, circadianWeight)) }
        if let movement { dimensions.append((movement, movementWeight)) }
        if let hydration { dimensions.append((hydration, hydrationWeight)) }

        let score: Int
        if headroom == 0 || dimensions.contains(where: { $0.score == 0 }) {
            score = 0
        } else {
            score = weightedGeometricMean(dimensions)
        }

        let stressConfidence = resolvedStressConfidence(
            input.stressConfidence,
            quality: input.stressQuality
        )
        let evidenceCoverage = dimensions.reduce(0) { $0 + $1.weight }
        let confidence = min(1, max(0, stressConfidence * 0.75 + evidenceCoverage * 0.25))

        return StressFocusCapacityAssessment(
            algorithmVersion: algorithmVersion,
            score: score,
            band: band(for: score),
            confidence: confidence,
            stressHeadroom: headroom,
            bodyBatteryScore: bodyBattery,
            sleepReadiness: sleep,
            circadianReadiness: circadian,
            movementReadiness: movement,
            hydrationReadiness: hydration,
            availableDimensionCount: dimensions.count
        )
    }

    static func estimatedScore(stressScore: Int) -> Int {
        stressHeadroom(for: stressScore)
    }

    private static func stressHeadroom(for stressScore: Int) -> Int {
        let normalizedStress = Double(clampScore(stressScore)) / 100
        let headroom = 100 * (1 - pow(normalizedStress, 1.35))
        return clampScore(Int(headroom.rounded()))
    }

    private static func sleepReadiness(
        sleepMinutes: Int?,
        sleepGoalMinutes: Int?,
        sleepScore: Int?
    ) -> Int? {
        var values: [(score: Double, weight: Double)] = []
        if let sleepMinutes, sleepMinutes > 0,
           let sleepGoalMinutes, sleepGoalMinutes > 0 {
            let durationRatio = min(1, max(0, Double(sleepMinutes) / Double(sleepGoalMinutes)))
            values.append((durationRatio * 100, 0.45))
        }
        // 零是有效实测分数，只有负值表示无效输入。
        if let sleepScore, sleepScore >= 0 {
            values.append((Double(clampScore(sleepScore)), 0.55))
        }
        guard !values.isEmpty else { return nil }
        let weight = values.reduce(0) { $0 + $1.weight }
        let total = values.reduce(0) { $0 + $1.score * $1.weight }
        return clampScore(Int((total / weight).rounded()))
    }

    private static func circadianReadiness(now: Date, wakeDate: Date?) -> Int? {
        guard let wakeDate else { return nil }
        let hoursSinceWake = now.timeIntervalSince(wakeDate) / 3_600
        guard hoursSinceWake >= 0, hoursSinceWake <= 24 else { return nil }
        let score: Double
        switch hoursSinceWake {
        case 0..<1:
            score = 70 + hoursSinceWake * 20
        case 1..<8:
            score = 90 + min(6, hoursSinceWake - 1)
        case 8..<12:
            score = 96 - (hoursSinceWake - 8) * 4.5
        case 12..<16:
            score = 78 - (hoursSinceWake - 12) * 8.25
        default:
            score = max(20, 45 - (hoursSinceWake - 16) * 5)
        }
        return clampScore(Int(score.rounded()))
    }

    private static func movementReadiness(sedentaryMinutes: Int) -> Int {
        let minutes = max(0, sedentaryMinutes)
        let score: Double
        switch minutes {
        case 0..<30:
            score = 96
        case 30..<60:
            score = 96 - Double(minutes - 30) * 0.7
        case 60..<90:
            score = 75 - Double(minutes - 60) * 0.85
        case 90..<120:
            score = 50 - Double(minutes - 90) * 0.67
        default:
            score = max(20, 30 - Double(minutes - 120) * 0.12)
        }
        return clampScore(Int(score.rounded()))
    }

    private static func hydrationReadiness(
        now: Date,
        wakeDate: Date?,
        waterIntakeMl: Int?,
        waterTargetMl: Int?
    ) -> Int? {
        guard let wakeDate,
              let waterIntakeMl, waterIntakeMl >= 0,
              let waterTargetMl, waterTargetMl > 0 else { return nil }
        let hoursSinceWake = now.timeIntervalSince(wakeDate) / 3_600
        guard hoursSinceWake >= 0, hoursSinceWake <= 24 else { return nil }
        let expectedFraction = min(1, max(0.15, hoursSinceWake / 16))
        let expectedIntake = Double(waterTargetMl) * expectedFraction
        let paceRatio = min(1, Double(waterIntakeMl) / max(expectedIntake, 1))
        return clampScore(Int((45 + paceRatio * 55).rounded()))
    }

    private static func weightedGeometricMean(
        _ values: [(score: Int, weight: Double)]
    ) -> Int {
        let totalWeight = values.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let logarithmicTotal = values.reduce(0.0) { partial, value in
            partial + log(Double(max(1, value.score))) * value.weight
        }
        return clampScore(Int(exp(logarithmicTotal / totalWeight).rounded()))
    }

    static func band(for score: Int) -> StressFocusCapacityBand {
        switch score {
        case 80...: return .strong
        case 55..<80: return .available
        case 30..<55: return .limited
        default: return .depleted
        }
    }

    private static func resolvedStressConfidence(
        _ confidence: Double?,
        quality: StressDataQuality
    ) -> Double {
        if let confidence, confidence.isFinite {
            return min(1, max(0, confidence))
        }
        switch quality {
        case .high: return 0.86
        case .medium: return 0.62
        case .low: return 0.38
        case .unavailable: return 0.25
        }
    }

    private static func clampScore(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}
