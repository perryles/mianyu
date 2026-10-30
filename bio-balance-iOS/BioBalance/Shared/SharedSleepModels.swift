import Foundation

nonisolated enum SleepMonitoringPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case armed
    case monitoring
    case finalizing
    case synced
    case surfaced
}

nonisolated enum SleepMonitorActivationSource: String, Codable, Sendable, CaseIterable {
    case manual
    case sleepFocusAutomation
    case watchSignal
}

nonisolated enum SleepSnoreIntensity: String, Codable, Sendable, CaseIterable {
    case none
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .none: return String(localized: "未检出")
        case .low: return String(localized: "轻度")
        case .medium: return String(localized: "中等")
        case .high: return String(localized: "偏强")
        }
    }
}

nonisolated enum SleepInsightRiskFlag: String, Codable, Sendable, CaseIterable {
    case none
    case monitor
    case elevated

    var title: String {
        switch self {
        case .none: return String(localized: "稳定")
        case .monitor: return String(localized: "建议观察")
        case .elevated: return String(localized: "值得留意")
        }
    }
}

nonisolated struct SleepMonitoringState: Codable, Equatable, Sendable {
    let phase: SleepMonitoringPhase
    let activationSource: SleepMonitorActivationSource
    let startedAt: Date?
    let updatedAt: Date
    let watchConnected: Bool
    let watchConfidence: Double
    let isAudioMonitoringActive: Bool
    let lastErrorDescription: String?

    init(
        phase: SleepMonitoringPhase = .idle,
        activationSource: SleepMonitorActivationSource = .manual,
        startedAt: Date? = nil,
        updatedAt: Date = Date(),
        watchConnected: Bool = false,
        watchConfidence: Double = 0,
        isAudioMonitoringActive: Bool = false,
        lastErrorDescription: String? = nil
    ) {
        self.phase = phase
        self.activationSource = activationSource
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.watchConnected = watchConnected
        self.watchConfidence = watchConfidence
        self.isAudioMonitoringActive = isAudioMonitoringActive
        self.lastErrorDescription = lastErrorDescription
    }
}

nonisolated struct SleepStageInferenceSummary: Codable, Equatable, Sendable {
    let deepSleepMinutesEstimated: Double
    let lightSleepMinutesEstimated: Double
    let remSleepMinutesEstimated: Double
    let wakeCount: Int
    let sleepLatencyMinutes: Double
    let continuityScore: Int

    static let empty = SleepStageInferenceSummary(
        deepSleepMinutesEstimated: 0,
        lightSleepMinutesEstimated: 0,
        remSleepMinutesEstimated: 0,
        wakeCount: 0,
        sleepLatencyMinutes: 0,
        continuityScore: 0
    )
}

nonisolated struct SnoreSegmentSummary: Codable, Equatable, Sendable, Identifiable {
    var id: String {
        "\(Int(segmentStart.timeIntervalSince1970))-\(Int(segmentEnd.timeIntervalSince1970))-\(intensity.rawValue)"
    }

    let segmentStart: Date
    let segmentEnd: Date
    let durationSeconds: Double
    let intensity: SleepSnoreIntensity
    let peakDbfsBucket: Int
    let confidence: Double
    let disturbanceWeight: Double
}

nonisolated struct SnoreAnalysisSummary: Codable, Equatable, Sendable {
    let snoreDetected: Bool
    let snoreDurationMinutes: Double
    let snoreFrequencyPerHour: Double
    let intensity: SleepSnoreIntensity
    let disturbanceScore: Int
    let riskFlag: SleepInsightRiskFlag
    let segments: [SnoreSegmentSummary]
    let histogram: [Int]

    static let empty = SnoreAnalysisSummary(
        snoreDetected: false,
        snoreDurationMinutes: 0,
        snoreFrequencyPerHour: 0,
        intensity: .none,
        disturbanceScore: 0,
        riskFlag: .none,
        segments: [],
        histogram: Array(repeating: 0, count: 6)
    )
}

nonisolated struct SleepQualityBreakdown: Codable, Equatable, Sendable {
    let sleepScore: Int
    let snoreImpactScore: Int
    let continuityScore: Int
    let durationScore: Int
    let restorativeScore: Int
}

nonisolated struct SleepInsightSnapshot: Codable, Equatable, Sendable {
    let headline: String
    let summary: String
    let recommendationCode: String
    let recommendationText: String
    let riskFlag: SleepInsightRiskFlag
    let generatedAt: Date
    let modelVersion: String

    static let placeholder = SleepInsightSnapshot(
        headline: String(localized: "等待昨夜睡眠完成"),
        summary: String(localized: "当你完成一次完整睡眠后，这里会生成昨夜恢复结论与建议。"),
        recommendationCode: "sleep_waiting",
        recommendationText: String(localized: "今晚继续保持佩戴与睡眠监测开启。"),
        riskFlag: .none,
        generatedAt: Date(),
        modelVersion: "sleep-insight-v1"
    )
}

nonisolated struct SleepSessionSummary: Codable, Equatable, Sendable, Identifiable {
    let sessionId: String
    let sourceDate: Date
    let startTime: Date
    let endTime: Date
    let sleepDurationMinutes: Int
    let sleepScore: Int
    let sleepContinuityScore: Int
    let stageSummary: SleepStageInferenceSummary
    let snoreSummary: SnoreAnalysisSummary
    let insight: SleepInsightSnapshot
    let watchConfidence: Double
    let deviceSource: String
    let analysisVersion: String
    let createdAt: Date
    let updatedAt: Date
    let source: SleepMonitorActivationSource

    var id: String { sessionId }

    static func placeholder(now: Date = Date()) -> SleepSessionSummary {
        let start = Calendar.current.date(byAdding: .hour, value: -8, to: now) ?? now
        return SleepSessionSummary(
            sessionId: UUID().uuidString,
            sourceDate: Calendar.current.startOfDay(for: now),
            startTime: start,
            endTime: now,
            sleepDurationMinutes: 0,
            sleepScore: 0,
            sleepContinuityScore: 0,
            stageSummary: .empty,
            snoreSummary: .empty,
            insight: .placeholder,
            watchConfidence: 0,
            deviceSource: "iphone",
            analysisVersion: "sleep-analysis-v1",
            createdAt: now,
            updatedAt: now,
            source: .manual
        )
    }
}

nonisolated struct WatchSleepStatePayload: Codable, Equatable, Sendable {
    let phase: SleepMonitoringPhase
    let watchConnected: Bool
    let watchConfidence: Double
    let probableSleepStartAt: Date?
    let lastUpdatedAt: Date
    let summary: SleepSessionSummary?

    static let idle = WatchSleepStatePayload(
        phase: .idle,
        watchConnected: false,
        watchConfidence: 0,
        probableSleepStartAt: nil,
        lastUpdatedAt: Date(),
        summary: nil
    )
}
