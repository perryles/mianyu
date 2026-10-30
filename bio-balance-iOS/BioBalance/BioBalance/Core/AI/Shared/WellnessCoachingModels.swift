import Foundation

/// 恢复引擎输出的当天负荷分层。
enum RecoveryReadinessBand: String, Codable, CaseIterable, Sendable {
    case recover
    case balanced
    case pushLight = "push-light"
    case protect

    var title: String {
        switch self {
        case .recover:
            return "恢复优先"
        case .balanced:
            return String(localized: "平衡推进")
        case .pushLight:
            return String(localized: "轻推进")
        case .protect:
            return String(localized: "保护模式")
        }
    }
}

/// 恢复引擎生成的全天脚本、理由、风险和跨端摘要。
struct RecoveryScriptPlan: Codable, Equatable, Sendable {
    let readinessBand: RecoveryReadinessBand
    let readinessScore: Int
    let headline: String
    let recoveryFocus: String
    let keyReasons: [String]
    let immediateActions: [String]
    let riskFlags: [String]
    let morningScript: String
    let afternoonScript: String
    let eveningScript: String
    let avoidList: [String]
    let watchPrompt: String
    let widgetSummary: String
    let confidence: Double
    let generatedAt: Date

    init(
        readinessBand: RecoveryReadinessBand,
        readinessScore: Int = 50,
        headline: String,
        recoveryFocus: String = "稳住节律",
        keyReasons: [String] = [],
        immediateActions: [String] = [],
        riskFlags: [String] = [],
        morningScript: String,
        afternoonScript: String,
        eveningScript: String,
        avoidList: [String],
        watchPrompt: String,
        widgetSummary: String,
        confidence: Double,
        generatedAt: Date
    ) {
        self.readinessBand = readinessBand
        self.readinessScore = max(0, min(100, readinessScore))
        self.headline = headline
        self.recoveryFocus = recoveryFocus
        self.keyReasons = keyReasons
        self.immediateActions = immediateActions
        self.riskFlags = riskFlags
        self.morningScript = morningScript
        self.afternoonScript = afternoonScript
        self.eveningScript = eveningScript
        self.avoidList = avoidList
        self.watchPrompt = watchPrompt
        self.widgetSummary = widgetSummary
        self.confidence = confidence
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case readinessBand
        case readinessScore
        case headline
        case recoveryFocus
        case keyReasons
        case immediateActions
        case riskFlags
        case morningScript
        case afternoonScript
        case eveningScript
        case avoidList
        case watchPrompt
        case widgetSummary
        case confidence
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readinessBand = try container.decode(RecoveryReadinessBand.self, forKey: .readinessBand)
        readinessScore = max(0, min(100, try container.decodeIfPresent(Int.self, forKey: .readinessScore) ?? 50))
        headline = try container.decode(String.self, forKey: .headline)
        recoveryFocus = try container.decodeIfPresent(String.self, forKey: .recoveryFocus) ?? "稳住节律"
        keyReasons = try container.decodeIfPresent([String].self, forKey: .keyReasons) ?? []
        immediateActions = try container.decodeIfPresent([String].self, forKey: .immediateActions) ?? []
        riskFlags = try container.decodeIfPresent([String].self, forKey: .riskFlags) ?? []
        morningScript = try container.decode(String.self, forKey: .morningScript)
        afternoonScript = try container.decode(String.self, forKey: .afternoonScript)
        eveningScript = try container.decode(String.self, forKey: .eveningScript)
        avoidList = try container.decodeIfPresent([String].self, forKey: .avoidList) ?? []
        watchPrompt = try container.decode(String.self, forKey: .watchPrompt)
        widgetSummary = try container.decode(String.self, forKey: .widgetSummary)
        confidence = try container.decode(Double.self, forKey: .confidence)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    }
}

/// 从恢复脚本与业务候选建议中收敛出的每日行动预算。
struct DailyRecoveryOrchestrationPlan: Codable, Equatable, Sendable {
    let date: Date
    let mainGoal: String
    let mainGoalDetail: String
    let supportingActions: [String]
    let deferredSuggestions: [String]
    let readinessBand: RecoveryReadinessBand
    let reason: String
    let generatedAt: Date

    var completionBudgetText: String {
        "1 个主目标 · \(supportingActions.count) 个辅助行动"
    }

    var planID: String {
        DailyRecoveryOrchestrationIdentity.planID(for: date)
    }

    var mainActionID: String {
        DailyRecoveryOrchestrationIdentity.actionID(planID: planID, role: "main", title: mainGoal)
    }

    var supportingActionIDs: [String] {
        supportingActions.map {
            DailyRecoveryOrchestrationIdentity.actionID(planID: planID, role: "supporting", title: $0)
        }
    }

    var allActionIDs: [String] {
        [mainActionID] + supportingActionIDs
    }
}

/// 用户对每日恢复行动的处理状态。
enum DailyRecoveryActionState: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case snoozed
    case skipped
    case notApplicable
}

/// 用户完成恢复行动后的可选主观体感。它只用于个人回看，不代表行动疗效。
enum DailyRecoveryActionFeedback: String, Codable, CaseIterable, Sendable {
    case better
    case similar
    case harder

    var title: String {
        switch self {
        case .better:
            return String(localized: "更舒服")
        case .similar:
            return String(localized: "差不多")
        case .harder:
            return String(localized: "更吃力")
        }
    }

    var systemImage: String {
        switch self {
        case .better: return "face.smiling"
        case .similar: return "equal.circle"
        case .harder: return "tortoise"
        }
    }
}

/// 把相近建议归入稳定类别，用于去重和跳过冷却。
enum DailyRecoverySuggestionClassifier {
    static func category(for text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categories: [(String, [String])] = [
            ("water", ["水", "补水"]),
            ("move", ["起身", "久坐", "走动", "步行"]),
            ("light", ["自然光", "日照", "太阳"]),
            ("caffeine", ["咖啡", "刺激性饮品", "咖啡因"]),
            ("sleep", ["睡眠", "早睡", "入睡", "睡前"]),
            ("load", ["训练", "强度", "高压任务", "推进"])
        ]
        if let category = categories.first(where: { _, keywords in
            keywords.contains { normalized.contains($0) }
        })?.0 {
            return category
        }
        return "exact-\(stableHash(normalized))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

/// 某条被跳过行动的类别冷却记录。
struct DailyRecoverySuggestionCooldownRecord: Codable, Equatable, Sendable {
    let actionID: String
    let category: String
    let expiresAt: Date
}

extension Notification.Name {
    static let dailyRecoveryPlanDidChange = Notification.Name("daily.recovery.plan.did-change")
    static let dailyRecoveryActionStateDidChange = Notification.Name("daily.recovery.action-state.did-change")
}

/// 可持久化的行动处理记录。
struct DailyRecoveryActionStateRecord: Codable, Equatable, Sendable {
    let planID: String
    let actionID: String
    let state: DailyRecoveryActionState
    let reason: String?
    let actionTitle: String?
    let plannedFor: Date?
    let feedback: DailyRecoveryActionFeedback?
    let feedbackUpdatedAt: Date?
    let updatedAt: Date

    init(
        planID: String,
        actionID: String,
        state: DailyRecoveryActionState,
        reason: String?,
        actionTitle: String? = nil,
        plannedFor: Date? = nil,
        feedback: DailyRecoveryActionFeedback? = nil,
        feedbackUpdatedAt: Date? = nil,
        updatedAt: Date
    ) {
        self.planID = planID
        self.actionID = actionID
        self.state = state
        self.reason = reason
        self.actionTitle = actionTitle
        self.plannedFor = plannedFor
        self.feedback = feedback
        self.feedbackUpdatedAt = feedbackUpdatedAt
        self.updatedAt = updatedAt
    }
}

/// 为每日计划和行动生成跨启动稳定的标识。
enum DailyRecoveryOrchestrationIdentity {
    static func planID(for date: Date) -> String {
        "recovery-plan-\(Int64(date.timeIntervalSince1970.rounded(.down)))"
    }

    static func actionID(planID: String, role: String, title: String) -> String {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(planID)-\(role)-\(stableHash(normalized))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

/// 咖啡因剂量事件的录入来源。
enum CaffeineDoseSource: String, Codable, CaseIterable, Sendable {
    case quickAdd
    case drinkCheckin
    case manualLog
}

/// 一次带时间戳的咖啡因摄入事件。
struct CaffeineDoseEvent: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let amountMg: Int
    let consumedAt: Date
    let source: CaffeineDoseSource
    let note: String?

    init(
        id: UUID = UUID(),
        amountMg: Int,
        consumedAt: Date,
        source: CaffeineDoseSource,
        note: String? = nil
    ) {
        self.id = id
        self.amountMg = max(0, amountMg)
        self.consumedAt = consumedAt
        self.source = source
        self.note = note
    }
}

/// 咖啡因对当晚睡眠和恢复的风险分层。
enum CaffeineRiskLevel: String, Codable, CaseIterable, Sendable {
    case safe
    case watch
    case lateRisk = "late-risk"
    case recoveryRisk = "recovery-risk"

    var title: String {
        switch self {
        case .safe:
            return String(localized: "相对安全")
        case .watch:
            return String(localized: "继续观察")
        case .lateRisk:
            return String(localized: "晚间风险")
        case .recoveryRisk:
            return "恢复风险"
        }
    }
}

/// 某一时刻的咖啡因摄入量、估算残留和计算置信度。
struct CaffeineBurdenSnapshot: Codable, Equatable, Sendable {
    let consumedTodayMg: Int
    let estimatedRemainingMg: Int
    let lastDoseAt: Date?
    let timedDoseCount: Int
    let confidence: Double
}

/// 结合睡眠窗口与压力状态得出的咖啡因风险建议。
struct CaffeineSleepRiskAssessment: Codable, Equatable, Sendable {
    let currentRemainingMg: Int
    let riskLevel: CaffeineRiskLevel
    let sleepWindowRisk: String
    let stressAmplifierRisk: String
    let todayAdvice: String
    let confidence: Double
}

/// 基于一周剂量事件提取的消费模式与高风险时段。
struct CaffeineWeeklyCoachSummary: Codable, Equatable, Sendable {
    let headline: String
    let patterns: [String]
    let dangerousMoments: [String]
    let confidence: Double
}

/// 周期训练引擎使用的标准化生理周期阶段。
enum CyclePhaseKind: String, Codable, CaseIterable, Sendable {
    case menstruation
    case follicular
    case ovulation
    case luteal
    case unknown

    init(phaseRawValue: String?) {
        switch phaseRawValue {
        case "MENSTRUATION":
            self = .menstruation
        case "FOLLICULAR":
            self = .follicular
        case "OVULATION":
            self = .ovulation
        case "LUTEAL":
            self = .luteal
        default:
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .menstruation:
            return "经期"
        case .follicular:
            return "卵泡期"
        case .ovulation:
            return "排卵期"
        case .luteal:
            return "黄体期"
        case .unknown:
            return String(localized: "周期待确认")
        }
    }
}

/// 周期、睡眠和恢复共同约束后的训练模式。
enum CycleTrainingMode: String, Codable, CaseIterable, Sendable {
    case rest
    case recovery
    case lightTrain = "light-train"
    case normalTrain = "normal-train"

    var title: String {
        switch self {
        case .rest:
            return String(localized: "休息")
        case .recovery:
            return "轻恢复"
        case .lightTrain:
            return String(localized: "轻训练")
        case .normalTrain:
            return String(localized: "正常训练")
        }
    }
}

/// 三日训练节律中的单日安排。
struct CycleTrainingDayRhythm: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let dayLabel: String
    let mode: CycleTrainingMode
    let summary: String
}

/// 周期训练引擎输出的今日建议与未来三日节律。
struct CycleTrainingRhythmPlan: Codable, Equatable, Sendable {
    let phase: CyclePhaseKind
    let phaseLabel: String
    let todayTrainingMode: CycleTrainingMode
    let allowedIntensityBand: String
    let todayReason: String
    let recoveryFocus: String
    let warningFlags: [String]
    let nextThreeDayRhythm: [CycleTrainingDayRhythm]
    let confidence: Double
}
