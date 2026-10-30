import Foundation

nonisolated enum StressState: String, Codable, Sendable, CaseIterable {
    case recovery
    case relaxed
    case normal
    case strained
    case highStress
    case overloaded
}

nonisolated enum StressBand: String, Codable, Sendable, CaseIterable {
    case waiting
    case relaxed
    case steady
    case mild
    case caution
    case high
}

nonisolated enum StressTint: String, Codable, Sendable {
    case tertiary
    case mintGreen
    case orange
    case orangeDeep
    case accentRed
}

nonisolated enum StressDataQuality: String, Codable, Sendable, Hashable, Comparable {
    case unavailable
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .unavailable: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    static func < (lhs: StressDataQuality, rhs: StressDataQuality) -> Bool {
        lhs.rank < rhs.rank
    }
}

nonisolated enum StressUnavailableReason: String, Codable, Sendable {
    case noPhysiologicalSignal
    case staleHeartRate
    case staleHrv
    case staleResult
    case baselineCalibrating
    case insufficientDailyCoverage
    case noDailySamples
}

nonisolated enum StressDominantDriver: String, Codable, Sendable, Hashable, CaseIterable {
    case hrvDeviation
    case hrDeviation
    case hrvTrend
    case hrTrend
    case recoveryDebt
    case circadian
    case workoutLoad
}

nonisolated enum StressExplanationCode: String, Codable, Sendable {
    case physicalWorkoutLoad = "physical_workout_load"
    case recoveryDebtElevated = "recovery_debt_elevated"
    case hrvBelowBaseline = "hrv_below_baseline"
    case heartRateAboveBaseline = "heart_rate_above_baseline"
    case hrvTrendingDown = "hrv_trending_down"
    case heartRateTrendingUp = "heart_rate_trending_up"
    case circadianLoadWindow = "circadian_load_window"
    case stablePhysiology = "stable_physiology"
    case insufficientBaseline = "insufficient_baseline"
    case dailyAverageElevated = "daily_average_elevated"
    case dailyPeakElevated = "daily_peak_elevated"
    case stableDailyLoad = "stable_daily_load"
    /// 没有可用解释码时的展示兜底；raw value 保持不变以解码历史快照。
    case fallback = "legacy"
}

nonisolated struct StressMetricSample: Codable, Sendable, Equatable, Hashable {
    let value: Double
    let measuredAt: Date

    func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(measuredAt))
    }
}

nonisolated struct StressBaseline: Codable, Sendable, Equatable {
    let value: Double?
    let sampleCount: Int
    let minimumSampleCount: Int
    let trustedSampleCount: Int

    var isUsable: Bool {
        value != nil && sampleCount >= minimumSampleCount
    }

    var confidence: Double {
        guard value != nil else { return 0 }
        guard trustedSampleCount > 0 else { return isUsable ? 1 : 0 }
        return min(1, Double(sampleCount) / Double(trustedSampleCount))
    }
}

nonisolated struct StressDateInterval: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
}

nonisolated enum StressWorkoutKind: String, Codable, Sendable {
    case running
    case cycling
    case strength
    case highIntensityIntervalTraining
    case other
    case none
}

nonisolated struct StressWorkoutContext: Codable, Sendable, Equatable {
    let isActive: Bool
    let kind: StressWorkoutKind
    let typeTitle: String?
    let intensity: Double
    let workoutBlend: Double
    let minutesSinceEnd: Int?

    static let inactive = StressWorkoutContext(
        isActive: false,
        kind: .none,
        typeTitle: nil,
        intensity: 0,
        workoutBlend: 0,
        minutesSinceEnd: nil
    )
}

nonisolated struct StressRecoverySnapshot: Codable, Sendable, Equatable {
    let recoveryScore: Int
    let recoveryDebt: Int
    let sleepMinutes: Int?
    let sleepEfficiency: Double?
    let nightlyHrv: Double?
    let overnightMinHeartRate: Double?
}

nonisolated struct StressComponentScores: Codable, Sendable, Equatable {
    let hrvDeviation: Int
    let hrDeviation: Int
    let hrvTrend: Int
    let hrTrend: Int
    let recoveryDebt: Int
    let circadian: Int
    let workoutLoad: Int
    let mentalRaw: Int
    let physicalRaw: Int
    let rawScore: Int
    let smoothedScore: Int
}

nonisolated struct StressResult: Codable, Sendable, Equatable {
    static let currentAlgorithmVersion = "3.1"

    let timestamp: Int64
    let rawScore: Int
    let smoothedScore: Int
    let state: StressState
    let band: StressBand
    let dominantDriver: StressDominantDriver
    let dominantDrivers: [StressDominantDriver]
    let explanationCode: StressExplanationCode
    let confidence: Double
    let quality: StressDataQuality
    let algorithmVersion: String
    let recovery: StressRecoverySnapshot
    let workout: StressWorkoutContext
    let components: StressComponentScores

    var score: Int { smoothedScore }
    var updatedAt: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

nonisolated enum StressEvaluation: Codable, Sendable, Equatable {
    case available(StressResult)
    case unavailable(StressUnavailableReason)

    var result: StressResult? {
        guard case let .available(result) = self else { return nil }
        return result
    }
}

nonisolated struct StressRealtimeInput: Sendable {
    let now: Date
    let heartRate: StressMetricSample?
    let hrv: StressMetricSample?
    let restingHeartRate: Double?
    let restingHeartRateBaseline: StressBaseline
    let hrvBaseline: StressBaseline
    let hrvPoints30m: [StressMetricSample]
    let heartRatePoints30m: [StressMetricSample]
    let sleepInterval: StressDateInterval?
    let sleepMinutes: Int?
    let sleepEfficiency: Double?
    let nightlyHrv: Double?
    let overnightMinHeartRate: Double?
    let workout: StressWorkoutContext
    let chronologicalAge: Int?
    let habitualSleepWindow: StressHabitualSleepWindow
}

nonisolated struct StressHabitualSleepWindow: Codable, Sendable, Equatable {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    static let fallback = StressHabitualSleepWindow(startHour: 23, startMinute: 0, endHour: 7, endMinute: 0)
}

nonisolated enum StressDailySampleSource: String, Codable, Sendable, Equatable, Hashable {
    case realtime
    case reconstructed
}

nonisolated struct StressDailySample: Codable, Sendable, Equatable, Hashable {
    let timestamp: Int64
    let score: Int
    let confidence: Double
    let quality: StressDataQuality
    let algorithmVersion: String
    let source: StressDailySampleSource
    let dominantDriver: StressDominantDriver?

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

nonisolated struct StressDailyInput: Sendable {
    let now: Date
    let samples: [StressDailySample]
}

nonisolated struct StressPresentationAssessment: Codable, Equatable, Sendable {
    let score: Int?
    let band: StressBand
    let title: String
    let adviceTitle: String
    let adviceDetail: String
    let tint: StressTint
    let updatedAtSeconds: Int64?
    let confidence: Double?
    let quality: StressDataQuality
    let unavailableReason: StressUnavailableReason?

    init(
        score: Int?,
        band: StressBand,
        title: String,
        adviceTitle: String,
        adviceDetail: String,
        tint: StressTint,
        updatedAtSeconds: Int64?,
        confidence: Double? = nil,
        quality: StressDataQuality = .unavailable,
        unavailableReason: StressUnavailableReason? = nil
    ) {
        self.score = score
        self.band = band
        self.title = title
        self.adviceTitle = adviceTitle
        self.adviceDetail = adviceDetail
        self.tint = tint
        self.updatedAtSeconds = updatedAtSeconds
        self.confidence = confidence
        self.quality = quality
        self.unavailableReason = unavailableReason
    }

    private enum CodingKeys: String, CodingKey {
        case score
        case band
        case title
        case adviceTitle
        case adviceDetail
        case tint
        case updatedAtSeconds
        case confidence
        case quality
        case unavailableReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decodeIfPresent(Int.self, forKey: .score)
        band = try container.decode(StressBand.self, forKey: .band)
        title = try container.decode(String.self, forKey: .title)
        adviceTitle = try container.decode(String.self, forKey: .adviceTitle)
        adviceDetail = try container.decode(String.self, forKey: .adviceDetail)
        tint = try container.decode(StressTint.self, forKey: .tint)
        updatedAtSeconds = try container.decodeIfPresent(Int64.self, forKey: .updatedAtSeconds)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        quality = try container.decodeIfPresent(StressDataQuality.self, forKey: .quality) ?? .unavailable
        unavailableReason = try container.decodeIfPresent(StressUnavailableReason.self, forKey: .unavailableReason)
    }

    var hasData: Bool { score != nil }
    var valueText: String { score.map(String.init) ?? "--" }
}

nonisolated struct StressSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 3

    let schemaVersion: Int
    let current: StressEvaluation
    let daily: StressEvaluation
    let dailySamples: [StressDailySample]
    let savedAt: Date
}

nonisolated protocol StressRealtimeEvaluating {
    func evaluate(input: StressRealtimeInput, previous: StressResult?) -> StressEvaluation
}
