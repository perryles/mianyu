import Foundation

/// The actionable readiness band derived from a focus-capacity score.
///
/// `unavailable` is reserved for assessments that do not have a usable stress
/// score. The other cases map to an available score in the closed range
/// `0...100`.
nonisolated enum StressFocusCapacityBand: String, Codable, Sendable, CaseIterable {
    case unavailable
    case depleted
    case limited
    case available
    case strong
}

/// A point-in-time snapshot consumed by ``StressFocusCapacityEngine``.
///
/// Optional values mean "not observed". A measured zero remains valid for
/// score-like fields and counters (for example, `waterIntakeMl == 0`). The
/// engine clamps out-of-range scores and excludes invalid time relationships.
nonisolated struct StressFocusCapacityInput: Sendable, Equatable {
    let now: Date
    let stressScore: Int?
    let bodyBatteryScore: Int?
    let stressConfidence: Double?
    let stressQuality: StressDataQuality
    let sleepMinutes: Int?
    let sleepGoalMinutes: Int?
    let sleepScore: Int?
    let wakeDate: Date?
    let sedentaryMinutes: Int?
    let waterIntakeMl: Int?
    let waterTargetMl: Int?

    init(
        now: Date,
        stressScore: Int?,
        bodyBatteryScore: Int?,
        stressConfidence: Double?,
        stressQuality: StressDataQuality,
        sleepMinutes: Int? = nil,
        sleepGoalMinutes: Int? = nil,
        sleepScore: Int? = nil,
        wakeDate: Date? = nil,
        sedentaryMinutes: Int? = nil,
        waterIntakeMl: Int? = nil,
        waterTargetMl: Int? = nil
    ) {
        self.now = now
        self.stressScore = stressScore
        self.bodyBatteryScore = bodyBatteryScore
        self.stressConfidence = stressConfidence
        self.stressQuality = stressQuality
        self.sleepMinutes = sleepMinutes
        self.sleepGoalMinutes = sleepGoalMinutes
        self.sleepScore = sleepScore
        self.wakeDate = wakeDate
        self.sedentaryMinutes = sedentaryMinutes
        self.waterIntakeMl = waterIntakeMl
        self.waterTargetMl = waterTargetMl
    }
}

/// Deterministic output of the focus-capacity algorithm.
///
/// Dimension scores use `0...100`; `confidence` uses `0...1`. A nil `score`
/// always pairs with the `unavailable` band. `algorithmVersion` must be stored
/// with historical samples so results from different formulas are not mixed.
nonisolated struct StressFocusCapacityAssessment: Sendable, Equatable {
    let algorithmVersion: String
    let score: Int?
    let band: StressFocusCapacityBand
    let confidence: Double?
    let stressHeadroom: Int?
    let bodyBatteryScore: Int?
    let sleepReadiness: Int?
    let circadianReadiness: Int?
    let movementReadiness: Int?
    let hydrationReadiness: Int?
    let availableDimensionCount: Int

    var hasData: Bool { score != nil }
}

nonisolated struct StressFocusCapacityContentItem: Sendable, Equatable {
    let symbol: String
    let title: String
    let detail: String
}

nonisolated struct StressFocusCapacityScaleItem: Sendable, Equatable {
    let range: String
    let meaning: String
}

nonisolated struct StressFocusCapacityMetricItem: Sendable, Equatable {
    let title: String
    let valueText: String
    let note: String
}
