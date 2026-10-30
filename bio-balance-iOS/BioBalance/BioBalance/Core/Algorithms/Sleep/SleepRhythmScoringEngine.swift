import Foundation

/// Describes how directly a score component is supported by sensor evidence.
nonisolated enum SleepRhythmEvidence: String, Codable, Equatable, Sendable {
    case measured
    case derived
    case inferred

    var reliability: Double {
        switch self {
        case .measured: return 1
        case .derived: return 0.65
        case .inferred: return 0.35
        }
    }
}

nonisolated enum SleepRhythmScoreComponentKind: String, Codable, Equatable, Sendable {
    case duration
    case continuity
    case latency
    case stageDistribution
    case regularity
    case disturbance
}

nonisolated struct SleepRhythmScoreComponent: Codable, Equatable, Sendable {
    let kind: SleepRhythmScoreComponentKind
    let score: Int
    let weight: Double
    let evidence: SleepRhythmEvidence
}

/// Normalized inputs for sleep-scoring-3.3.0.
///
/// `nil` means that a dimension was not observed. Invalid values are treated as
/// missing; the engine never replaces them with zero or a neutral score.
nonisolated struct SleepRhythmScoreInput: Equatable, Sendable {
    let durationMinutes: Int?
    let goalMinutes: Int?
    let timeInBedMinutes: Int?
    let wakeAfterSleepOnsetMinutes: Int?
    let fallbackContinuityScore: Int?
    let sleepLatencyMinutes: Double?
    let deepSleepMinutes: Double?
    let remSleepMinutes: Double?
    let stageEvidence: SleepRhythmEvidence
    let bedtimeDeviationMinutes: Double?
    let regularityEvidence: SleepRhythmEvidence
    let disturbanceScore: Int?

    init(
        durationMinutes: Int?,
        goalMinutes: Int?,
        timeInBedMinutes: Int? = nil,
        wakeAfterSleepOnsetMinutes: Int? = nil,
        fallbackContinuityScore: Int? = nil,
        sleepLatencyMinutes: Double? = nil,
        deepSleepMinutes: Double? = nil,
        remSleepMinutes: Double? = nil,
        stageEvidence: SleepRhythmEvidence = .inferred,
        bedtimeDeviationMinutes: Double? = nil,
        regularityEvidence: SleepRhythmEvidence = .measured,
        disturbanceScore: Int? = nil
    ) {
        self.durationMinutes = durationMinutes
        self.goalMinutes = goalMinutes
        self.timeInBedMinutes = timeInBedMinutes
        self.wakeAfterSleepOnsetMinutes = wakeAfterSleepOnsetMinutes
        self.fallbackContinuityScore = fallbackContinuityScore
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.stageEvidence = stageEvidence
        self.bedtimeDeviationMinutes = bedtimeDeviationMinutes
        self.regularityEvidence = regularityEvidence
        self.disturbanceScore = disturbanceScore
    }
}

nonisolated struct SleepRhythmScoreResult: Codable, Equatable, Sendable {
    let score: Int?
    let confidence: Double
    let components: [SleepRhythmScoreComponent]
}

/// Evidence-aware deterministic sleep quality and rhythm scoring.
///
/// The score is only available when duration and at least one independent
/// dimension provide 50% of the configured evidence weight. Missing dimensions
/// leave the calculation and lower confidence instead of becoming a synthetic
/// normal value.
nonisolated struct SleepRhythmScoringEngine {
    static let algorithmVersion = "sleep-scoring-3.3.0"

    private enum Weight {
        static let duration = 0.25
        static let continuity = 0.25
        static let latency = 0.10
        static let stageDistribution = 0.15
        static let regularity = 0.20
        static let disturbance = 0.05
        static let minimumAvailable = 0.50
    }

    func evaluate(_ input: SleepRhythmScoreInput) -> SleepRhythmScoreResult {
        guard let duration = input.durationMinutes,
              let goal = input.goalMinutes,
              duration > 0,
              goal > 0 else {
            return SleepRhythmScoreResult(score: nil, confidence: 0, components: [])
        }

        var components = [
            component(
                .duration,
                score: durationScore(durationMinutes: duration, goalMinutes: goal),
                weight: Weight.duration,
                evidence: .measured
            )
        ]

        if let continuity = continuityComponent(input: input, durationMinutes: duration) {
            components.append(continuity)
        }
        if let latency = input.sleepLatencyMinutes,
           latency.isFinite,
           latency >= 0 {
            components.append(
                component(
                    .latency,
                    score: latencyScore(minutes: latency),
                    weight: Weight.latency,
                    evidence: .measured
                )
            )
        }
        if input.stageEvidence == .measured,
           let stageScore = stageDistributionScore(
               durationMinutes: duration,
               deepSleepMinutes: input.deepSleepMinutes,
               remSleepMinutes: input.remSleepMinutes
           ) {
            components.append(
                component(
                    .stageDistribution,
                    score: stageScore,
                    weight: Weight.stageDistribution,
                    evidence: .measured
                )
            )
        }
        if let deviation = input.bedtimeDeviationMinutes,
           deviation.isFinite,
           deviation >= 0 {
            components.append(
                component(
                    .regularity,
                    score: regularityScore(deviationMinutes: deviation),
                    weight: Weight.regularity,
                    evidence: input.regularityEvidence
                )
            )
        }
        if let disturbance = input.disturbanceScore,
           (0...100).contains(disturbance) {
            components.append(
                component(
                    .disturbance,
                    score: Double(100 - disturbance),
                    weight: Weight.disturbance,
                    evidence: .measured
                )
            )
        }

        let availableWeight = components.reduce(0) { $0 + $1.weight }
        let confidence = min(
            1,
            max(0, components.reduce(0) { $0 + $1.weight * $1.evidence.reliability })
        )
        guard availableWeight >= Weight.minimumAvailable else {
            return SleepRhythmScoreResult(
                score: nil,
                confidence: confidence,
                components: components
            )
        }

        let weightedScore = components.reduce(0) {
            $0 + Double($1.score) * $1.weight
        } / availableWeight
        return SleepRhythmScoreResult(
            score: boundedInt(weightedScore),
            confidence: confidence,
            components: components
        )
    }

    private func continuityComponent(
        input: SleepRhythmScoreInput,
        durationMinutes: Int
    ) -> SleepRhythmScoreComponent? {
        let efficiencyScore: Double? = {
            guard let timeInBed = input.timeInBedMinutes,
                  timeInBed >= durationMinutes,
                  timeInBed > 0 else { return nil }
            let percent = Double(durationMinutes) / Double(timeInBed) * 100
            return scoreOnCurve(
                percent,
                points: [(0, 0), (65, 30), (75, 60), (85, 90), (90, 100), (100, 100)]
            )
        }()
        let wasoScore: Double? = {
            guard let waso = input.wakeAfterSleepOnsetMinutes, waso >= 0 else { return nil }
            return scoreOnCurve(
                Double(waso),
                points: [(0, 100), (20, 100), (30, 90), (60, 60), (120, 20), (240, 0)]
            )
        }()

        let exactScore: Double?
        switch (efficiencyScore, wasoScore) {
        case let (.some(efficiency), .some(waso)):
            exactScore = efficiency * 0.60 + waso * 0.40
        case let (.some(efficiency), .none):
            exactScore = efficiency
        case let (.none, .some(waso)):
            exactScore = waso
        case (.none, .none):
            exactScore = nil
        }
        if let exactScore {
            return component(
                .continuity,
                score: exactScore,
                weight: Weight.continuity,
                evidence: .measured
            )
        }
        if let fallback = input.fallbackContinuityScore,
           (0...100).contains(fallback) {
            return component(
                .continuity,
                score: Double(fallback),
                weight: Weight.continuity,
                evidence: .derived
            )
        }
        return nil
    }

    private func durationScore(durationMinutes: Int, goalMinutes: Int) -> Double {
        let ratio = Double(durationMinutes) / Double(goalMinutes)
        return scoreOnCurve(
            ratio,
            points: [(0, 0), (0.5, 20), (0.75, 70), (0.9, 90), (1, 100), (2, 100)]
        )
    }

    private func latencyScore(minutes: Double) -> Double {
        scoreOnCurve(
            minutes,
            points: [(0, 80), (5, 90), (10, 100), (30, 100), (60, 50), (120, 10), (240, 0)]
        )
    }

    private func regularityScore(deviationMinutes: Double) -> Double {
        scoreOnCurve(
            deviationMinutes,
            points: [(0, 100), (15, 100), (30, 90), (60, 70), (120, 30), (180, 0), (360, 0)]
        )
    }

    private func stageDistributionScore(
        durationMinutes: Int,
        deepSleepMinutes: Double?,
        remSleepMinutes: Double?
    ) -> Double? {
        guard let deep = deepSleepMinutes,
              let rem = remSleepMinutes,
              deep.isFinite,
              rem.isFinite,
              deep >= 0,
              rem >= 0,
              deep + rem <= Double(durationMinutes) else { return nil }
        let total = Double(durationMinutes)
        let deepRatio = deep / total
        let remRatio = rem / total
        let deepScore = bandScore(deepRatio, lower: 0.13, upper: 0.25)
        let remScore = bandScore(remRatio, lower: 0.18, upper: 0.30)
        return (deepScore + remScore) / 2
    }

    private func bandScore(_ value: Double, lower: Double, upper: Double) -> Double {
        if value < lower {
            return lower > 0 ? max(0, value / lower * 100) : 0
        }
        if value <= upper { return 100 }
        let maximum = 0.60
        guard value < maximum else { return 0 }
        return max(0, (maximum - value) / (maximum - upper) * 100)
    }

    private func scoreOnCurve(_ value: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.0 { return first.1 }
        if value >= last.0 { return last.1 }
        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            guard value <= upper.0 else { continue }
            let progress = (value - lower.0) / max(upper.0 - lower.0, .leastNonzeroMagnitude)
            return lower.1 + (upper.1 - lower.1) * progress
        }
        return last.1
    }

    private func component(
        _ kind: SleepRhythmScoreComponentKind,
        score: Double,
        weight: Double,
        evidence: SleepRhythmEvidence
    ) -> SleepRhythmScoreComponent {
        SleepRhythmScoreComponent(
            kind: kind,
            score: boundedInt(score),
            weight: weight,
            evidence: evidence
        )
    }

    private func boundedInt(_ value: Double) -> Int {
        min(100, max(0, Int(value.rounded())))
    }
}
