/// Health Models 定义业务数据模型，负责承载页面渲染、状态计算或模块通信所需的数据结构。
import Foundation

nonisolated struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let code: Int?
    let msg: String?
    let data: T?
}

nonisolated struct MembershipEntitlementDTO: Codable, Sendable {
    let pro: Bool?
    let lifetime: Bool?
    let expires_at: Int64?
}

nonisolated struct MembershipOrderDTO: Codable, Sendable {
    let order_id: String
    let pay_url: String?
    let pay_data: String?
    let pay_order_no: String?
    let pay_channel: String?
}

nonisolated struct AppMemberMeDTO: Codable, Sendable {
    let nickname: String?
    let username: String?
}

nonisolated struct RealtimeHealth: Codable, Equatable, Sendable {
    let bpm: Int
    let hrv_sdnn: Double
    let stress_value: Int
    let stress_level: String?
    let stress_explanation_code: String?
    let stress_confidence: Double?
    let stress_quality: String?
    let stress_algorithm_version: String?
    let stress_unavailable_reason: String?
    let daily_stress_value: Int?
    let daily_stress_quality: String?
    let daily_stress_algorithm_version: String?
    let timestamp: Int64
    let hr_abnormal: Bool?
    let hr_abnormal_type: String?
    
    var hrv: Double { hrv_sdnn }
    
    init(
        bpm: Int,
        hrv_sdnn: Double = 0.0,
        stress_value: Int = 0,
        stress_level: String? = nil,
        stress_explanation_code: String? = nil,
        stress_confidence: Double? = nil,
        stress_quality: String? = nil,
        stress_algorithm_version: String? = nil,
        stress_unavailable_reason: String? = nil,
        daily_stress_value: Int? = nil,
        daily_stress_quality: String? = nil,
        daily_stress_algorithm_version: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970),
        hr_abnormal: Bool? = nil,
        hr_abnormal_type: String? = nil
    ) {
        self.bpm = bpm
        self.hrv_sdnn = hrv_sdnn
        self.stress_value = stress_value
        self.stress_level = stress_level
        self.stress_explanation_code = stress_explanation_code
        self.stress_confidence = stress_confidence
        self.stress_quality = stress_quality
        self.stress_algorithm_version = stress_algorithm_version
        self.stress_unavailable_reason = stress_unavailable_reason
        self.daily_stress_value = daily_stress_value
        self.daily_stress_quality = daily_stress_quality
        self.daily_stress_algorithm_version = daily_stress_algorithm_version
        self.timestamp = timestamp
        self.hr_abnormal = hr_abnormal
        self.hr_abnormal_type = hr_abnormal_type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try container.decodeIfPresent(Int.self, forKey: .bpm) ?? 0
        hrv_sdnn = try container.decodeIfPresent(Double.self, forKey: .hrv_sdnn)
            ?? (try container.decodeIfPresent(Double.self, forKey: .hrv) ?? 0.0)
        stress_value = try container.decodeIfPresent(Int.self, forKey: .stress_value) ?? 0
        stress_level = try container.decodeIfPresent(String.self, forKey: .stress_level)
        stress_explanation_code = try container.decodeIfPresent(String.self, forKey: .stress_explanation_code)
        stress_confidence = try container.decodeIfPresent(Double.self, forKey: .stress_confidence)
        stress_quality = try container.decodeIfPresent(String.self, forKey: .stress_quality)
        stress_algorithm_version = try container.decodeIfPresent(String.self, forKey: .stress_algorithm_version)
        stress_unavailable_reason = try container.decodeIfPresent(String.self, forKey: .stress_unavailable_reason)
        daily_stress_value = try container.decodeIfPresent(Int.self, forKey: .daily_stress_value)
        daily_stress_quality = try container.decodeIfPresent(String.self, forKey: .daily_stress_quality)
        daily_stress_algorithm_version = try container.decodeIfPresent(String.self, forKey: .daily_stress_algorithm_version)
        hr_abnormal = try container.decodeIfPresent(Bool.self, forKey: .hr_abnormal)
        hr_abnormal_type = try container.decodeIfPresent(String.self, forKey: .hr_abnormal_type)
        if let ts = try container.decodeIfPresent(Int64.self, forKey: .timestamp) {
            timestamp = ts
        } else if let ts = try container.decodeIfPresent(Int.self, forKey: .timestamp) {
            timestamp = Int64(ts)
        } else {
            timestamp = Int64(Date().timeIntervalSince1970)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(hrv_sdnn, forKey: .hrv_sdnn)
        try container.encode(stress_value, forKey: .stress_value)
        try container.encodeIfPresent(stress_level, forKey: .stress_level)
        try container.encodeIfPresent(stress_explanation_code, forKey: .stress_explanation_code)
        try container.encodeIfPresent(stress_confidence, forKey: .stress_confidence)
        try container.encodeIfPresent(stress_quality, forKey: .stress_quality)
        try container.encodeIfPresent(stress_algorithm_version, forKey: .stress_algorithm_version)
        try container.encodeIfPresent(stress_unavailable_reason, forKey: .stress_unavailable_reason)
        try container.encodeIfPresent(daily_stress_value, forKey: .daily_stress_value)
        try container.encodeIfPresent(daily_stress_quality, forKey: .daily_stress_quality)
        try container.encodeIfPresent(daily_stress_algorithm_version, forKey: .daily_stress_algorithm_version)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(hr_abnormal, forKey: .hr_abnormal)
        try container.encodeIfPresent(hr_abnormal_type, forKey: .hr_abnormal_type)
    }
    
    private enum CodingKeys: String, CodingKey {
        case bpm
        case hrv_sdnn
        case hrv
        case stress_value
        case stress_level
        case stress_explanation_code
        case stress_confidence
        case stress_quality
        case stress_algorithm_version
        case stress_unavailable_reason
        case daily_stress_value
        case daily_stress_quality
        case daily_stress_algorithm_version
        case timestamp
        case hr_abnormal
        case hr_abnormal_type
    }
}

nonisolated struct HealthHistory: Codable, Sendable {
    let bpmHistory: [BpmHistoryPoint]
    let stressHistory: [StressHistoryPoint]
    let hrvHistory: [HrvHistoryPoint]
    let emotionHistory: [EmotionHistoryItem]
    
    var hrPoints: [TimeSeriesPoint] {
        bpmHistory.compactMap { item in
            guard let ts = item.timestamp else { return nil }
            return TimeSeriesPoint(timestamp: ts, value: item.heartRate)
        }
    }
    
    var stressPoints: [TimeSeriesPoint] {
        stressHistory.compactMap { item in
            guard let ts = item.timestamp else { return nil }
            return TimeSeriesPoint(timestamp: ts, value: item.stressLevel)
        }
    }
    
    init(
        bpmHistory: [BpmHistoryPoint] = [],
        stressHistory: [StressHistoryPoint] = [],
        hrvHistory: [HrvHistoryPoint] = [],
        emotionHistory: [EmotionHistoryItem] = []
    ) {
        self.bpmHistory = bpmHistory
        self.stressHistory = stressHistory
        self.hrvHistory = hrvHistory
        self.emotionHistory = emotionHistory
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bpmHistory = try container.decodeIfPresent([BpmHistoryPoint].self, forKey: .bpmHistory) ?? []
        stressHistory = try container.decodeIfPresent([StressHistoryPoint].self, forKey: .stressHistory) ?? []
        hrvHistory = try container.decodeIfPresent([HrvHistoryPoint].self, forKey: .hrvHistory) ?? []
        emotionHistory = try container.decodeIfPresent([EmotionHistoryItem].self, forKey: .emotionHistory) ?? []
    }
}

nonisolated struct BpmHistoryPoint: Codable, Identifiable, Sendable {
    var id: Int64 { timestamp ?? 0 }
    let heartRate: Int
    let timestamp: Int64?
}

nonisolated struct StressHistoryPoint: Codable, Identifiable, Sendable {
    var id: Int64 { timestamp ?? 0 }
    let stressLevel: Int
    let analysis: String?
    let timestamp: Int64?
}

nonisolated struct HrvHistoryPoint: Codable, Identifiable, Sendable {
    var id: Int64 { timestamp ?? 0 }
    let sdnn: Double?
    let timestamp: Int64?
}

nonisolated struct EmotionHistoryItem: Codable, Identifiable, Sendable {
    var id: String { "\(timestamp ?? 0)-\(emotionType ?? "")-\(intensity ?? 0)" }
    let emotionType: String?
    let intensity: Int?
    let timestamp: Int64?
    let source: String?
}

nonisolated struct TimeSeriesPoint: Codable, Identifiable, Sendable {
    var id: Int64 { timestamp }
    let timestamp: Int64
    let value: Int
    
    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

nonisolated struct TimeSeriesPointDouble: Codable, Identifiable, Sendable, Hashable {
    var id: Int64 { timestamp }
    let timestamp: Int64
    let value: Double
    
    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
}

nonisolated struct SleepData: Codable, Sendable {
    let sleep_score: Int
    let duration_minutes: Int
    let stages: [SleepStage]
    var avg_heart_rate: Int?
    var avg_respiration_rate: Double?
    var awake_count: Int?
    var start_time: Int?
    var end_time: Int?

    /// 睡眠阶段分布展示使用的总分钟数。
    /// 这里优先累加 `stages` 里的各阶段时长，因为它可能同时包含 Awake / Core / Deep / REM，
    /// 更适合拿来给“阶段占比”或阶段带状图做分母。
    /// 如果当前还没有阶段样本，再回退到 `duration_minutes`，避免 UI 因分母为 0 无法展示。
    /// 注意：这个值不等同于主睡眠时长；`duration_minutes` 仍然表示业务上的主睡眠分钟数。
    var stageDistributionTotalMinutes: Int {
        let total = stages.reduce(0) { partialResult, stage in
            partialResult + Swift.max(0, stage.duration)
        }
        return total > 0 ? total : duration_minutes
    }
}

nonisolated struct SleepStage: Codable, Identifiable, Sendable, Hashable {
    var id: String {
        let start = startDate?.timeIntervalSince1970 ?? 0
        let end = endDate?.timeIntervalSince1970 ?? 0
        return "\(stage)-\(Int(start))-\(Int(end))-\(duration)"
    }
    let stage: String
    let duration: Int
    let startDate: Date?
    let endDate: Date?
    let sourceType: String?

    init(stage: String, duration: Int, startDate: Date? = nil, endDate: Date? = nil, sourceType: String? = nil) {
        self.stage = stage
        self.duration = duration
        self.startDate = startDate
        self.endDate = endDate
        self.sourceType = sourceType
    }
}

extension Array where Element == SleepStage {
    /// 阶段样本自身的总分钟数。
    /// 只累加非负时长，不夹带 `SleepData.duration_minutes` 的回退语义，
    /// 适合时间轴、阶段分布条等“只关心阶段样本本身”的场景复用。
    var totalDurationMinutes: Int {
        reduce(0) { partialResult, stage in
            partialResult + Swift.max(0, stage.duration)
        }
    }
}

nonisolated struct SleepSummary: Codable, Sendable {
    let startTime: Int64?
    let endTime: Int64?
    let inBedMinutes: Int?
    let asleepMinutes: Int?
    let deepMinutes: Int?
    let coreMinutes: Int?
    let remMinutes: Int?
    let awakeCount: Int?
    let sleepScore: Int?
    let recoveryScore: Int?
    let efficiency: Double?
    let deepRatio: Double?
    let remRatio: Double?
    let timestamp: Int64?
}

nonisolated struct SleepTrendNightSummary: Codable, Sendable, Hashable, Identifiable {
    var id: Int64 { Int64(day.timeIntervalSince1970) }
    let day: Date
    let startTime: Date
    let endTime: Date
    let inBedMinutes: Int?
    let asleepMinutes: Int
    let awakeMinutes: Int
    let coreMinutes: Int
    let deepMinutes: Int
    let remMinutes: Int

    /// 睡眠效率需要先确定分母“在床时长”。
    /// 1. 优先使用 HealthKit 的 inBedMinutes，表示用户被系统明确记录为“在床”的分钟数。
    /// 2. 如果没有 inBed 样本，就退回到 startTime 到 endTime 的整段睡眠会话时长，作为近似的在床时长。
    /// 3. 只有当分母大于 0 且不少于 asleepMinutes 时，才认为这次估算有效。
    var effectiveInBedMinutes: Int? {
        if let inBedMinutes, inBedMinutes > 0 {
            return inBedMinutes
        }

        let sessionMinutes = Int(endTime.timeIntervalSince(startTime) / 60.0)
        guard sessionMinutes > 0, sessionMinutes >= asleepMinutes else { return nil }
        return sessionMinutes
    }

    /// 睡眠效率的计算公式是：asleepMinutes / effectiveInBedMinutes。
    /// 这里返回 0...1 的小数，例如 0.85 表示 85%；
    /// 趋势页展示时会再乘以 100，转成百分比文本和图表值。
    var efficiency: Double? {
        guard let effectiveInBedMinutes else { return nil }
        return Double(asleepMinutes) / Double(effectiveInBedMinutes)
    }

    var deepRatio: Double? {
        guard asleepMinutes > 0, deepMinutes > 0 else { return nil }
        return Double(deepMinutes) / Double(asleepMinutes)
    }

    var remRatio: Double? {
        guard asleepMinutes > 0, remMinutes > 0 else { return nil }
        return Double(remMinutes) / Double(asleepMinutes)
    }

    /// 睡眠评分估算值用于趋势页睡眠恢复模块的长期趋势展示。
    /// 这里优先保证口径稳定：综合时长、效率、深睡与 REM 结构，输出 0...100 的近似评分。
    var sleepScoreEstimate: Int {
        let durationHours = Double(asleepMinutes) / 60.0
        let durationScore = min(100.0, max(0.0, durationHours / 8.0 * 100.0))
        let efficiencyScore = min(100.0, max(0.0, (efficiency ?? 0.78) * 100.0))
        let deepScore = min(100.0, max(0.0, (deepRatio ?? 0.16) / 0.2 * 100.0))
        let remScore = min(100.0, max(0.0, (remRatio ?? 0.2) / 0.24 * 100.0))
        let blended = durationScore * 0.34 + efficiencyScore * 0.26 + deepScore * 0.22 + remScore * 0.18
        return Int(blended.rounded())
    }
}

nonisolated struct HabitCheckinDTO: Codable, Sendable {
    let habitType: String
    let streakDays: Int
    let recordTimestamp: Int64
}

nonisolated struct InsightData: Codable, Sendable {
    let overall_score: Int
    let analysis: String
    let reason: String
}

nonisolated struct HabitData: Codable, Sendable {
    let water_intake: Double
    let caffeine_intake: Double
    var water_target: Int?
    var water_completion_rate: Double?
}

nonisolated struct EmotionRecord: Codable, Identifiable, Sendable {
    var id: String { "\(timestamp ?? 0)-\(emotion)" }
    let emotion: String
    let intensity: Int
    let source: String?
    let timestamp: Int?
}

nonisolated struct ActivityData: Codable, Sendable {
    let steps: Int
    let active_energy: Int
    let exercise_time: Int
    let stand_hours: Int
    let walking_speed_mps: Double?
    let environmental_audio_exposure_db: Double?
    let headphone_audio_exposure_db: Double?
}

nonisolated struct StressData: Codable, Sendable {
    let current_stress: Int
    let average_stress: Int
    let history: [TimeSeriesPoint]
}

nonisolated struct StressCorrelationPointDTO: Codable, Identifiable, Sendable {
    var id: String { "\(timestamp)-\(stress)" }
    let stress: Int
    let metric: Double
    let timestamp: Int
}

nonisolated struct DailySleepStressAnalytics: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let sleep_score: Int?
    let asleep_minutes: Int?
    let in_bed_minutes: Int?
    let deep_minutes: Int?
    let core_minutes: Int?
    let rem_minutes: Int?
    let awake_count: Int?
    let efficiency: Double?
    let avg_stress: Int?
    let avg_hrv: Double?
    let caffeine_remained_mg: Double?
    let water_intake_ml: Double?
    let water_target_ml: Int?
    let water_completion_rate: Double?
    let top_emotion: String?
}

nonisolated struct HabitAnalyticsItem: Codable, Identifiable, Sendable {
    var id: String { habitType }
    let habitType: String
    let target: Int?
    let completedDays: Int?
    let completionRate: Double?
    let currentStreak: Int?
    let longestStreak: Int?
    let days: [HabitDailyStatus]?
}

nonisolated struct HabitDailyStatus: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let completed: Bool?
    let water_intake_ml: Double?
}

nonisolated struct PeriodSummary: Codable, Sendable, Hashable {
    let current: PeriodCurrent?
    let predictions: PeriodPredictions?
    let overlayRanges: [PeriodOverlayRange]?
    let dayLogs: [PeriodDayLog]?
    let cycles: [PeriodCycle]?
}

nonisolated struct PeriodCurrent: Codable, Sendable, Hashable {
    let cycleId: Int64?
    let startDate: String?
    let endDate: String?
    let phase: String?
    let dayIndex: Int?
    let isFertile: Bool?
    let isPredicted: Bool?
}

nonisolated struct PeriodPredictions: Codable, Sendable, Hashable {
    let cycleLength: Int?
    let periodLength: Int?
    let ovulationDate: String?
    let fertileStart: String?
    let fertileEnd: String?
    let nextPeriodStart: String?
    let nextPeriodEnd: String?
    let source: String?
}

nonisolated struct PeriodOverlayRange: Codable, Identifiable, Sendable, Hashable {
    var id: String { "\(type ?? "UNKNOWN")-\(startDate ?? "")-\(endDate ?? "")" }
    let startDate: String?
    let endDate: String?
    let type: String?
}

nonisolated struct PeriodDayLog: Codable, Identifiable, Sendable, Hashable {
    var id: Int64 { self.idValue ?? 0 }
    private let idValue: Int64?
    let date: String?
    let flowLevel: Int?
    let painLevel: Int?
    let moodLevel: Int?
    let hasSexualActivity: Bool?
    let hasIntermenstrualBleeding: Bool?
    let pregnancyTestResult: String?
    let ovulationTestResult: String?
    let cervicalMucusQuality: String?
    let note: String?

    init(
        idValue: Int64?,
        date: String?,
        flowLevel: Int?,
        painLevel: Int?,
        moodLevel: Int?,
        hasSexualActivity: Bool? = nil,
        hasIntermenstrualBleeding: Bool? = nil,
        pregnancyTestResult: String? = nil,
        ovulationTestResult: String? = nil,
        cervicalMucusQuality: String? = nil,
        note: String?
    ) {
        self.idValue = idValue
        self.date = date
        self.flowLevel = flowLevel
        self.painLevel = painLevel
        self.moodLevel = moodLevel
        self.hasSexualActivity = hasSexualActivity
        self.hasIntermenstrualBleeding = hasIntermenstrualBleeding
        self.pregnancyTestResult = pregnancyTestResult
        self.ovulationTestResult = ovulationTestResult
        self.cervicalMucusQuality = cervicalMucusQuality
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case idValue = "id"
        case date
        case flowLevel
        case painLevel
        case moodLevel
        case hasSexualActivity
        case hasIntermenstrualBleeding
        case pregnancyTestResult
        case ovulationTestResult
        case cervicalMucusQuality
        case note
    }
}

nonisolated struct PeriodCycle: Codable, Identifiable, Sendable, Hashable {
    var id: Int64 { self.idValue ?? 0 }
    private let idValue: Int64?
    let startDate: String?
    let endDate: String?

    init(idValue: Int64?, startDate: String?, endDate: String?) {
        self.idValue = idValue
        self.startDate = startDate
        self.endDate = endDate
    }

    private enum CodingKeys: String, CodingKey {
        case idValue = "id"
        case startDate
        case endDate
    }
}

nonisolated struct PeriodOperationResult: Codable, Sendable {
    let status: String?
    let cycleId: Int64?
    let dayLogId: Int64?
    let timestamp: Int64?
}
