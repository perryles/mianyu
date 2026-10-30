import Foundation

/// 健康问答的结构化展示模型，同时保留原始 Markdown 作为降级内容。
nonisolated struct HealthAIAnswerPayload: Equatable, Sendable {
    let summary: String?
    let basis: [String]
    let actions: [String]
    let risks: [String]
    let followUps: [String]
    let rawMarkdown: String
    let source: AIResponseSource?

    init(
        summary: String?,
        basis: [String],
        actions: [String],
        risks: [String],
        followUps: [String],
        rawMarkdown: String,
        source: AIResponseSource? = nil
    ) {
        self.summary = summary
        self.basis = basis
        self.actions = actions
        self.risks = risks
        self.followUps = followUps
        self.rawMarkdown = rawMarkdown
        self.source = source
    }

    var displayText: String {
        rawMarkdown
    }

    var hasStructuredContent: Bool {
        summary != nil || !basis.isEmpty || !actions.isEmpty || !risks.isEmpty || !followUps.isEmpty
    }

    static func plain(_ text: String) -> HealthAIAnswerPayload {
        HealthAIAnswerPayload(
            summary: nil,
            basis: [],
            actions: [],
            risks: [],
            followUps: [],
            rawMarkdown: text
        )
    }

    /// Parser 和本地 responder 保持来源无关，由最终完成路由的 Service 写入真实来源。
    func withSource(_ source: AIResponseSource) -> HealthAIAnswerPayload {
        HealthAIAnswerPayload(
            summary: summary,
            basis: basis,
            actions: actions,
            risks: risks,
            followUps: followUps,
            rawMarkdown: rawMarkdown,
            source: source
        )
    }
}

/// 聊天列表中的单条消息及其加载、错误和结构化回答状态。
struct HealthAIChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
    var answerPayload: HealthAIAnswerPayload?
    var isLoading: Bool
    var isError: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = Date(),
        answerPayload: HealthAIAnswerPayload? = nil,
        isLoading: Bool = false,
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.answerPayload = answerPayload
        self.isLoading = isLoading
        self.isError = isError
    }
}

/// 当次问答允许使用的健康摘要；不包含原始 HealthKit 时间序列。
struct HealthAIContext: Sendable {
    struct SleepSummary: Sendable {
        let durationMinutes: Int?
        let score: Int?
        let startLocalTime: String?
        let endLocalTime: String?
        let awakeCount: Int?
        let deepMinutes: Int?
        let remMinutes: Int?

        var typedDuration: SleepDurationMinutes? {
            SleepDurationMinutes(durationMinutes)
        }
    }

    struct RecoveryVitals: Sendable {
        let nightlyHrvMs: Double?
        let nightlyAverageHeartRate: Int?
        let nightlyRespiratoryRate: Double?
        let wristTemperatureCelsius: Double?

        var typedNightlyHrv: HRVSDNNMilliseconds? {
            HRVSDNNMilliseconds(nightlyHrvMs)
        }

        var typedNightlyAverageHeartRate: HeartRateBPM? {
            HeartRateBPM(nightlyAverageHeartRate)
        }
    }

    struct TodayVitals: Sendable {
        let currentHeartRate: Int?
        let restingHeartRate: Int?
        let recentAverageRestingHeartRate: Int?
        let todayAverageHrv: Double?
        let recentAverageHrv: Double?

        var typedCurrentHeartRate: HeartRateBPM? {
            HeartRateBPM(currentHeartRate)
        }

        var typedRestingHeartRate: HeartRateBPM? {
            HeartRateBPM(restingHeartRate)
        }

        var typedRecentAverageRestingHeartRate: HeartRateBPM? {
            HeartRateBPM(recentAverageRestingHeartRate)
        }

        var typedTodayAverageHrv: HRVSDNNMilliseconds? {
            HRVSDNNMilliseconds(todayAverageHrv)
        }

        var typedRecentAverageHrv: HRVSDNNMilliseconds? {
            HRVSDNNMilliseconds(recentAverageHrv)
        }
    }

    struct StressSummary: Sendable {
        let score: Int?
        let currentScore: Int?
        let dailyScore: Int?
        let band: String
        let title: String
        let summary: String
    }

    struct ActivitySummary: Sendable {
        let stepsToday: Int?
        let exerciseMinutesToday: Int?
        let standHoursToday: Int?
        let walkingSpeedMpsToday: Double?
    }

    struct RecoveryBehavior: Sendable {
        let sedentaryElapsedMinutesCurrent: Int?
        let sedentaryTotalMinutesToday: Int?
        let sedentaryLongestSessionMinutesToday: Int?
        let activeBreakCountToday: Int?
    }

    let dateText: String
    let sleep: SleepSummary
    let recoveryVitals: RecoveryVitals
    let todayVitals: TodayVitals
    let stress: StressSummary
    let activity: ActivitySummary
    let recoveryBehavior: RecoveryBehavior
    let caffeineConsumedTodayMg: Int?
    let caffeineEstimatedRemainingMg: Int?
    let daylightMinutesToday: Int?
    let waterMlToday: Int?
    let sleepGoalMinutes: Int?
    let recoveryScriptPlan: RecoveryScriptPlan?
    let healthProfileSummary: HealthProfileAIDigest?
    let disclaimer: String

    init(
        dateText: String,
        sleep: SleepSummary,
        recoveryVitals: RecoveryVitals,
        todayVitals: TodayVitals,
        stress: StressSummary,
        activity: ActivitySummary,
        recoveryBehavior: RecoveryBehavior,
        caffeineConsumedTodayMg: Int?,
        caffeineEstimatedRemainingMg: Int?,
        daylightMinutesToday: Int?,
        waterMlToday: Int?,
        sleepGoalMinutes: Int?,
        recoveryScriptPlan: RecoveryScriptPlan?,
        healthProfileSummary: HealthProfileAIDigest? = nil,
        disclaimer: String
    ) {
        self.dateText = dateText
        self.sleep = sleep
        self.recoveryVitals = recoveryVitals
        self.todayVitals = todayVitals
        self.stress = stress
        self.activity = activity
        self.recoveryBehavior = recoveryBehavior
        self.caffeineConsumedTodayMg = caffeineConsumedTodayMg
        self.caffeineEstimatedRemainingMg = caffeineEstimatedRemainingMg
        self.daylightMinutesToday = daylightMinutesToday
        self.waterMlToday = waterMlToday
        self.sleepGoalMinutes = sleepGoalMinutes
        self.recoveryScriptPlan = recoveryScriptPlan
        self.healthProfileSummary = healthProfileSummary
        self.disclaimer = disclaimer
    }
}

/// 流式健康问答事件，ViewModel 通过 AsyncThrowingStream 消费。
enum HealthAIStreamingEvent: Sendable {
    /// 文本累积快照（用于 UI 逐字渲染）
    case textSnapshot(String)
    /// 最终结构化回答（流结束）
    case completed(HealthAIAnswerPayload)
}
