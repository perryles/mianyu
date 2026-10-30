/// Watch Sync Payload 负责手表同步相关的数据结构或管理逻辑，用于在 iPhone 与 Apple Watch 之间同步关键状态。
import Foundation

/// 手表同步消息枚举 作为手表同步能力层里的状态与分类定义。
/// 负责描述手机与手表之间的数据同步过程中会用到的状态、分类或分支。
nonisolated enum WatchSyncMessageType: String, Sendable {
    case requestSnapshot = "request_snapshot"
    case snapshot = "snapshot"
    case realtimeVitals = "realtime_vitals"
    case recordHabit = "record_habit"
    case complicationTemplate = "complication_template"
    case sleepMonitoringCommand = "sleep_monitoring_command"
    case sleepStateChanged = "sleep_state_changed"
    case sleepSessionSummary = "sleep_session_summary"
    case sleepDeviceStatus = "sleep_device_status"
    case aiQuestion = "ai_question"
    case aiAnswer = "ai_answer"
    case ack = "ack"
}

/// Watch 端传来的局部实时指标更新。字段保持可选，避免旧设备只传一项时覆盖手机上的其他最新值。
nonisolated struct WatchRealtimeVitals: Equatable, Sendable {
    let bpm: Int?
    let hrv: Double?
    let stress: Int?
    let timestamp: Int?
}

nonisolated struct WatchRecoveryPlanActionSnapshot: Equatable, Sendable {
    let actionID: String
    let title: String
    let role: String
    let state: String
}

nonisolated struct WatchRecoveryPlanSnapshot: Equatable, Sendable {
    let planID: String
    let dayStart: Int
    let actions: [WatchRecoveryPlanActionSnapshot]
}

/// 手表同步数据模型 作为手表同步能力层里的数据载体。
/// 负责手机与手表之间的数据同步。
nonisolated struct WatchSyncSnapshot: Equatable, Sendable {
    let bpm: Int
    let hrv: Double
    let stress: Int
    let stressState: String?
    let stressExplanationCode: String?
    let stressConfidence: Double?
    var stressQuality: String? = nil
    var stressAlgorithmVersion: String? = nil
    var dailyStress: Int? = nil
    var dailyStressQuality: String? = nil
    var dailyStressAlgorithmVersion: String? = nil
    let stressTrend: String
    let timestamp: Int
    let steps: Int
    let activeEnergy: Int
    let exerciseMinutes: Int
    let standHours: Int
    let walkingSpeedMps: Double?
    let walkingPaceSecondsPerKm: Int?
    let stepsGoal: Int
    let activeEnergyGoal: Int
    let exerciseMinutesGoal: Int
    let standHoursGoal: Int
    let sleepDurationMinutes: Int
    let sleepScore: Int
    let lateNightRecoveryPrompt: String?
    let lateNightRecoverySeverity: String?
    let sleepEnvironmentCompletionRate: Double?
    let sleepEnvironmentPrompt: String?
    let waterIntakeMl: Int
    let waterTargetMl: Int
    let waterCompletionRate: Double
    let caffeineRemainedMg: Int
    let sedentaryElapsedMinutes: Int
    let sedentaryIsCounting: Bool
    let sedentaryPausedBySleep: Bool
    let sedentarySeatedStartAtSeconds: Int?
    let sedentaryLastActivityAtSeconds: Int?
    let sedentaryUpdatedAtSeconds: Int?
    let sedentaryBreakIsActive: Bool
    let sedentaryBreakDurationMinutes: Int
    let sedentaryBreakStartedAtSeconds: Int?
    let periodPhase: String?
    let periodCycleDay: Int?
    let periodIsFertile: Bool?
    let periodNextStart: String?
    let periodFertileStart: String?
    let periodFertileEnd: String?
    let periodPredictionSource: String?
    let defaultComplicationTemplate: String?
    let watchThemeId: String?
    let watchMascotEnabled: Bool?
    let watchMascotMessage: String?
    let watchMascotMessageConfigured: Bool?
    let watchCustomThemeId: String?
    let bodyAgeValueYears: Double?
    let bodyAgeStatusText: String?
    let bodyAgeComparisonText: String?
    let bodyAgeSuggestionText: String?
    let bodyAgeCoverageText: String?
    let bodyAgeDirectionText: String?
    let vo2MaxValue: Double?
    let vo2MaxConfidence: Int?
    let vo2MaxTrend: String?
    let vo2MaxFitnessLevel: String?
    let vo2MaxSource: String?
    let vo2MaxDriverSummary: String?
    let stressHistory: [WatchStressHistoryPoint]
    let sleepMonitoringPhase: String?
    let sleepMonitoringActive: Bool
    let sleepSnoreIntensity: String?
    let sleepSnoreDurationMinutes: Double?
    let sleepInsightHeadline: String?
    let sleepWatchConfidence: Double?
    let recoveryPlan: WatchRecoveryPlanSnapshot?
}

extension WatchSyncSnapshot: HealthSnapshotSource {
    var widgetRecoveryPlan: SharedWidgetRecoveryPlan? {
        guard let recoveryPlan else { return nil }
        let actions = recoveryPlan.actions.compactMap { action -> SharedWidgetRecoveryAction? in
            guard let role = SharedWidgetRecoveryActionRole(rawValue: action.role),
                  let state = SharedWidgetRecoveryActionState(rawValue: action.state) else {
                return nil
            }
            return SharedWidgetRecoveryAction(
                actionID: action.actionID,
                title: action.title,
                role: role,
                state: state
            )
        }
        guard actions.contains(where: { $0.role == .main }) else { return nil }
        return SharedWidgetRecoveryPlan(
            planID: recoveryPlan.planID,
            dayStart: recoveryPlan.dayStart,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(max(timestamp, recoveryPlan.dayStart))),
            actions: Array(actions.prefix(3))
        )
    }
}


/// 手表同步Envelope枚举 作为手表同步能力层里的能力或分类定义。
/// 负责描述手机与手表之间的数据同步过程中会用到的状态、分类或分支。
nonisolated enum WatchSyncEnvelope: Equatable, Sendable {
    // 本次只增加可选消息类型，现有 snapshot wire schema 保持 v1，
    // 避免未同时升级的 Watch 将其误判为不兼容协议。
    static let schemaVersion: Int = 1

    case requestSnapshot(requestId: String?)
    case snapshot(WatchSyncSnapshot, requestId: String?)
    case realtimeVitals(WatchRealtimeVitals, requestId: String?)
    case recordHabit(type: String, amount: Int, requestId: String?)
    case complicationTemplate(template: String, requestId: String?)
    case sleepMonitoringCommand(action: String, requestId: String?)
    case sleepStateChanged(WatchSleepStatePayload, requestId: String?)
    case sleepSessionSummary(SleepSessionSummary, requestId: String?)
    case sleepDeviceStatus(WatchSleepStatePayload, requestId: String?)
    case aiQuestion(question: String, requestId: String?)
    case aiAnswer(requestId: String?)
    case ack(requestId: String?)

    func toDictionary(now: Date = Date()) -> [String: Any] {
        var dict: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "sentAt": Int(now.timeIntervalSince1970)
        ]

        switch self {
        case .requestSnapshot(let requestId):
            dict["type"] = WatchSyncMessageType.requestSnapshot.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }

        case .snapshot(let snapshot, let requestId):
            dict["type"] = WatchSyncMessageType.snapshot.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict.merge(Self.snapshotDictionary(snapshot)) { _, new in new }

        case .realtimeVitals(let vitals, let requestId):
            dict["type"] = WatchSyncMessageType.realtimeVitals.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            if let bpm = vitals.bpm { dict["bpm"] = bpm }
            if let hrv = vitals.hrv { dict["hrv"] = hrv }
            if let stress = vitals.stress { dict["stress"] = stress }
            if let timestamp = vitals.timestamp { dict["timestamp"] = timestamp }

        case .recordHabit(let type, let amount, let requestId):
            dict["type"] = WatchSyncMessageType.recordHabit.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict["habitType"] = type
            dict["amount"] = amount

        case .complicationTemplate(let template, let requestId):
            dict["type"] = WatchSyncMessageType.complicationTemplate.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict["defaultComplicationTemplate"] = template

        case .sleepMonitoringCommand(let action, let requestId):
            dict["type"] = WatchSyncMessageType.sleepMonitoringCommand.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict["sleepAction"] = action

        case .sleepStateChanged(let payload, let requestId),
             .sleepDeviceStatus(let payload, let requestId):
            dict["type"] = Self.typeRawValue(for: self)
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict.merge(Self.watchSleepPayloadDictionary(payload)) { _, new in new }

        case .sleepSessionSummary(let summary, let requestId):
            dict["type"] = WatchSyncMessageType.sleepSessionSummary.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict.merge(Self.sleepSummaryDictionary(summary)) { _, new in new }

        case .aiQuestion(let question, let requestId):
            dict["type"] = WatchSyncMessageType.aiQuestion.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
            dict["question"] = question

        case .aiAnswer(let requestId):
            dict["type"] = WatchSyncMessageType.aiAnswer.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }

        case .ack(let requestId):
            dict["type"] = WatchSyncMessageType.ack.rawValue
            if let requestId, !requestId.isEmpty { dict["requestId"] = requestId }
        }

        return dict
    }

    static func fromDictionary(_ dict: [String: Any]) -> WatchSyncEnvelope {
        let typeRaw = (dict["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requestId = (dict["requestId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if typeRaw == "requestrealtime" {
            return .requestSnapshot(requestId: requestId)
        }

        if let typeRaw, let type = WatchSyncMessageType(rawValue: typeRaw) {
            switch type {
            case .requestSnapshot:
                return .requestSnapshot(requestId: requestId)
            case .snapshot:
                return .snapshot(parseSnapshot(dict), requestId: requestId)
            case .realtimeVitals:
                return .realtimeVitals(parseRealtimeVitals(dict), requestId: requestId)
            case .recordHabit:
                let habitType = (dict["habitType"] as? String) ?? ""
                let amount = intValue(dict["amount"]) ?? 0
                return .recordHabit(type: habitType, amount: amount, requestId: requestId)
            case .complicationTemplate:
                let template = (dict["defaultComplicationTemplate"] as? String) ?? ""
                return .complicationTemplate(template: template, requestId: requestId)
            case .sleepMonitoringCommand:
                return .sleepMonitoringCommand(action: (dict["sleepAction"] as? String) ?? "", requestId: requestId)
            case .sleepStateChanged:
                return .sleepStateChanged(parseWatchSleepPayload(dict), requestId: requestId)
            case .sleepSessionSummary:
                if let summary = parseSleepSummary(dict) {
                    return .sleepSessionSummary(summary, requestId: requestId)
                }
                return .ack(requestId: requestId)
            case .sleepDeviceStatus:
                return .sleepDeviceStatus(parseWatchSleepPayload(dict), requestId: requestId)
            case .aiQuestion:
                return .aiQuestion(
                    question: (dict["question"] as? String) ?? "",
                    requestId: requestId
                )
            case .aiAnswer:
                return .aiAnswer(requestId: requestId)
            case .ack:
                return .ack(requestId: requestId)
            }
        }

        // 旧版 Watch 没有 type，只发 bpm/hrv/stress。在协议边界转成新的强类型模型，
        // 业务层不再处理原始字典。
        let snapshotSpecificKeys = [
            "steps", "activeEnergy", "exerciseMinutes", "standHours",
            "sleepDurationMinutes", "sleepScore", "waterIntakeMl", "stressHistory"
        ]
        let isPartialRealtimeUpdate = !snapshotSpecificKeys.contains { dict[$0] != nil }
            && (dict["bpm"] != nil || dict["hrv"] != nil || dict["stress"] != nil)
        if isPartialRealtimeUpdate {
            return .realtimeVitals(parseRealtimeVitals(dict), requestId: requestId)
        }
        return .snapshot(parseSnapshot(dict), requestId: requestId)
    }

    private static func parseRealtimeVitals(_ dict: [String: Any]) -> WatchRealtimeVitals {
        WatchRealtimeVitals(
            bpm: intValue(dict["bpm"]),
            hrv: doubleValue(dict["hrv"]),
            stress: intValue(dict["stress"]),
            timestamp: intValue(dict["timestamp"])
        )
    }

    private static func snapshotDictionary(_ snapshot: WatchSyncSnapshot) -> [String: Any] {
        var dict: [String: Any] = [
            "bpm": snapshot.bpm,
            "hrv": snapshot.hrv,
            "stress": snapshot.stress,
            "stressTrend": snapshot.stressTrend,
            "timestamp": snapshot.timestamp,
            "steps": snapshot.steps,
            "activeEnergy": snapshot.activeEnergy,
            "exerciseMinutes": snapshot.exerciseMinutes,
            "standHours": snapshot.standHours,
            "stepsGoal": snapshot.stepsGoal,
            "activeEnergyGoal": snapshot.activeEnergyGoal,
            "exerciseMinutesGoal": snapshot.exerciseMinutesGoal,
            "standHoursGoal": snapshot.standHoursGoal,
            "sleepDurationMinutes": snapshot.sleepDurationMinutes,
            "sleepScore": snapshot.sleepScore,
            "waterIntakeMl": snapshot.waterIntakeMl,
            "waterTargetMl": snapshot.waterTargetMl,
            "waterCompletionRate": snapshot.waterCompletionRate,
            "caffeineRemainedMg": snapshot.caffeineRemainedMg,
            "sedentaryElapsedMinutes": snapshot.sedentaryElapsedMinutes,
            "sedentaryIsCounting": snapshot.sedentaryIsCounting,
            "sedentaryPausedBySleep": snapshot.sedentaryPausedBySleep,
            "sedentaryBreakIsActive": snapshot.sedentaryBreakIsActive,
            "sedentaryBreakDurationMinutes": snapshot.sedentaryBreakDurationMinutes,
            "stressHistory": snapshot.stressHistory.map {
                [
                    "timestamp": $0.timestamp,
                    "value": $0.value
                ]
            }
        ]
        if let value = snapshot.stressState { dict["stressState"] = value }
        if let value = snapshot.stressExplanationCode { dict["stressExplanationCode"] = value }
        if let value = snapshot.stressConfidence { dict["stressConfidence"] = value }
        if let value = snapshot.stressQuality { dict["stressQuality"] = value }
        if let value = snapshot.stressAlgorithmVersion { dict["stressAlgorithmVersion"] = value }
        if let value = snapshot.dailyStress { dict["dailyStress"] = value }
        if let value = snapshot.dailyStressQuality { dict["dailyStressQuality"] = value }
        if let value = snapshot.dailyStressAlgorithmVersion { dict["dailyStressAlgorithmVersion"] = value }
        if let value = snapshot.walkingSpeedMps { dict["walkingSpeedMps"] = value }
        if let value = snapshot.walkingPaceSecondsPerKm { dict["walkingPaceSecondsPerKm"] = value }
        if let value = snapshot.sedentarySeatedStartAtSeconds { dict["sedentarySeatedStartAt"] = value }
        if let value = snapshot.sedentaryLastActivityAtSeconds { dict["sedentaryLastActivityAt"] = value }
        if let value = snapshot.sedentaryUpdatedAtSeconds { dict["sedentaryUpdatedAt"] = value }
        if let value = snapshot.sedentaryBreakStartedAtSeconds { dict["sedentaryBreakStartedAt"] = value }
        if let value = snapshot.periodPhase { dict["periodPhase"] = value }
        if let value = snapshot.periodCycleDay { dict["periodCycleDay"] = value }
        if let value = snapshot.periodIsFertile { dict["periodIsFertile"] = value }
        if let value = snapshot.periodNextStart { dict["periodNextStart"] = value }
        if let value = snapshot.periodFertileStart { dict["periodFertileStart"] = value }
        if let value = snapshot.periodFertileEnd { dict["periodFertileEnd"] = value }
        if let value = snapshot.periodPredictionSource { dict["periodPredictionSource"] = value }
        if let value = snapshot.defaultComplicationTemplate { dict["defaultComplicationTemplate"] = value }
        if let value = snapshot.watchThemeId { dict["watchThemeId"] = value }
        if let value = snapshot.watchMascotEnabled { dict["watchMascotEnabled"] = value }
        if let value = snapshot.watchMascotMessage { dict["watchMascotMessage"] = value }
        if let value = snapshot.watchMascotMessageConfigured { dict["watchMascotMessageConfigured"] = value }
        if let value = snapshot.watchCustomThemeId { dict["watchCustomThemeId"] = value }
        if let value = snapshot.bodyAgeValueYears { dict["bodyAgeValueYears"] = value }
        if let value = snapshot.bodyAgeStatusText { dict["bodyAgeStatusText"] = value }
        if let value = snapshot.bodyAgeComparisonText { dict["bodyAgeComparisonText"] = value }
        if let value = snapshot.bodyAgeSuggestionText { dict["bodyAgeSuggestionText"] = value }
        if let value = snapshot.bodyAgeCoverageText { dict["bodyAgeCoverageText"] = value }
        if let value = snapshot.bodyAgeDirectionText { dict["bodyAgeDirectionText"] = value }
        if let value = snapshot.vo2MaxValue { dict["vo2MaxValue"] = value }
        if let value = snapshot.vo2MaxConfidence { dict["vo2MaxConfidence"] = value }
        if let value = snapshot.vo2MaxTrend { dict["vo2MaxTrend"] = value }
        if let value = snapshot.vo2MaxFitnessLevel { dict["vo2MaxFitnessLevel"] = value }
        if let value = snapshot.vo2MaxSource { dict["vo2MaxSource"] = value }
        if let value = snapshot.vo2MaxDriverSummary { dict["vo2MaxDriverSummary"] = value }
        if let value = snapshot.sleepMonitoringPhase { dict["sleepMonitoringPhase"] = value }
        dict["sleepMonitoringActive"] = snapshot.sleepMonitoringActive
        if let value = snapshot.sleepSnoreIntensity { dict["sleepSnoreIntensity"] = value }
        if let value = snapshot.sleepSnoreDurationMinutes { dict["sleepSnoreDurationMinutes"] = value }
        if let value = snapshot.sleepInsightHeadline { dict["sleepInsightHeadline"] = value }
        if let value = snapshot.sleepWatchConfidence { dict["sleepWatchConfidence"] = value }
        if let value = snapshot.lateNightRecoveryPrompt { dict["lateNightRecoveryPrompt"] = value }
        if let value = snapshot.lateNightRecoverySeverity { dict["lateNightRecoverySeverity"] = value }
        if let value = snapshot.sleepEnvironmentCompletionRate { dict["sleepEnvironmentCompletionRate"] = value }
        if let value = snapshot.sleepEnvironmentPrompt { dict["sleepEnvironmentPrompt"] = value }
        if let recoveryPlan = snapshot.recoveryPlan {
            dict["recoveryPlan"] = recoveryPlanDictionary(recoveryPlan)
        }
        return dict
    }

    private static func parseSnapshot(_ dict: [String: Any]) -> WatchSyncSnapshot {
        let bpm = intValue(dict["bpm"]) ?? 0
        let hrv = doubleValue(dict["hrv"]) ?? 0
        let stress = intValue(dict["stress"]) ?? 0
        let stressState = dict["stressState"] as? String
        let stressExplanationCode = dict["stressExplanationCode"] as? String
        let stressConfidence = doubleValue(dict["stressConfidence"])
        let stressTrend = (dict["stressTrend"] as? String) ?? "稳定"
        let timestamp = intValue(dict["timestamp"]) ?? Int(Date().timeIntervalSince1970)

        let steps = intValue(dict["steps"]) ?? 0
        let activeEnergy = intValue(dict["activeEnergy"]) ?? 0
        let exerciseMinutes = intValue(dict["exerciseMinutes"]) ?? 0
        let standHours = intValue(dict["standHours"]) ?? 0
        let walkingSpeedMps = doubleValue(dict["walkingSpeedMps"])
        let walkingPaceSecondsPerKm = intValue(dict["walkingPaceSecondsPerKm"])

        let stepsGoal = intValue(dict["stepsGoal"]) ?? 8000
        let activeEnergyGoal = intValue(dict["activeEnergyGoal"]) ?? 500
        let exerciseMinutesGoal = intValue(dict["exerciseMinutesGoal"]) ?? 30
        let standHoursGoal = intValue(dict["standHoursGoal"]) ?? 12

        let sleepDurationMinutes = intValue(dict["sleepDurationMinutes"]) ?? 0
        let sleepScore = intValue(dict["sleepScore"]) ?? 0
        let lateNightRecoveryPrompt = dict["lateNightRecoveryPrompt"] as? String
        let lateNightRecoverySeverity = dict["lateNightRecoverySeverity"] as? String
        let sleepEnvironmentCompletionRate = doubleValue(dict["sleepEnvironmentCompletionRate"])
        let sleepEnvironmentPrompt = dict["sleepEnvironmentPrompt"] as? String

        let waterIntakeMl = intValue(dict["waterIntakeMl"]) ?? 0
        let waterTargetMl = intValue(dict["waterTargetMl"]) ?? 2000
        let waterCompletionRate = doubleValue(dict["waterCompletionRate"]) ?? 0
        let caffeineRemainedMg = intValue(dict["caffeineRemainedMg"]) ?? 0

        let sedentaryElapsedMinutes = intValue(dict["sedentaryElapsedMinutes"]) ?? 0
        let sedentaryIsCounting = boolValue(dict["sedentaryIsCounting"]) ?? false
        let sedentaryPausedBySleep = boolValue(dict["sedentaryPausedBySleep"]) ?? false
        let sedentarySeatedStartAt = intValue(dict["sedentarySeatedStartAt"])
        let sedentaryLastActivityAt = intValue(dict["sedentaryLastActivityAt"])
        let sedentaryUpdatedAt = intValue(dict["sedentaryUpdatedAt"])
        let sedentaryBreakIsActive = boolValue(dict["sedentaryBreakIsActive"]) ?? false
        let sedentaryBreakDurationMinutes = intValue(dict["sedentaryBreakDurationMinutes"]) ?? 0
        let sedentaryBreakStartedAt = intValue(dict["sedentaryBreakStartedAt"])
        let periodPhase = dict["periodPhase"] as? String
        let periodCycleDay = intValue(dict["periodCycleDay"])
        let periodIsFertile = boolValue(dict["periodIsFertile"])
        let periodNextStart = dict["periodNextStart"] as? String
        let periodFertileStart = dict["periodFertileStart"] as? String
        let periodFertileEnd = dict["periodFertileEnd"] as? String
        let periodPredictionSource = dict["periodPredictionSource"] as? String
        let defaultComplicationTemplate = dict["defaultComplicationTemplate"] as? String
        let watchThemeId = dict["watchThemeId"] as? String
        let watchMascotEnabled = boolValue(dict["watchMascotEnabled"])
        let watchMascotMessage = WatchMascotContentPolicy.normalize(dict["watchMascotMessage"] as? String)
        let watchMascotMessageConfigured = boolValue(dict["watchMascotMessageConfigured"])
        let watchCustomThemeId = dict["watchCustomThemeId"] as? String
        let bodyAgeValueYears = doubleValue(dict["bodyAgeValueYears"])
        let bodyAgeStatusText = dict["bodyAgeStatusText"] as? String
        let bodyAgeComparisonText = dict["bodyAgeComparisonText"] as? String
        let bodyAgeSuggestionText = dict["bodyAgeSuggestionText"] as? String
        let bodyAgeCoverageText = dict["bodyAgeCoverageText"] as? String
        let bodyAgeDirectionText = dict["bodyAgeDirectionText"] as? String
        let vo2MaxValue = doubleValue(dict["vo2MaxValue"])
        let vo2MaxConfidence = intValue(dict["vo2MaxConfidence"])
        let vo2MaxTrend = dict["vo2MaxTrend"] as? String
        let vo2MaxFitnessLevel = dict["vo2MaxFitnessLevel"] as? String
        let vo2MaxSource = dict["vo2MaxSource"] as? String
        let vo2MaxDriverSummary = dict["vo2MaxDriverSummary"] as? String
        let stressHistory = parseStressHistory(dict["stressHistory"])
        let sleepMonitoringPhase = dict["sleepMonitoringPhase"] as? String
        let sleepMonitoringActive = boolValue(dict["sleepMonitoringActive"]) ?? false
        let sleepSnoreIntensity = dict["sleepSnoreIntensity"] as? String
        let sleepSnoreDurationMinutes = doubleValue(dict["sleepSnoreDurationMinutes"])
        let sleepInsightHeadline = dict["sleepInsightHeadline"] as? String
        let sleepWatchConfidence = doubleValue(dict["sleepWatchConfidence"])
        let recoveryPlan = parseRecoveryPlan(dict["recoveryPlan"])

        return WatchSyncSnapshot(
            bpm: bpm,
            hrv: hrv,
            stress: stress,
            stressState: stressState,
            stressExplanationCode: stressExplanationCode,
            stressConfidence: stressConfidence,
            stressQuality: dict["stressQuality"] as? String,
            stressAlgorithmVersion: dict["stressAlgorithmVersion"] as? String,
            dailyStress: intValue(dict["dailyStress"]),
            dailyStressQuality: dict["dailyStressQuality"] as? String,
            dailyStressAlgorithmVersion: dict["dailyStressAlgorithmVersion"] as? String,
            stressTrend: stressTrend,
            timestamp: timestamp,
            steps: steps,
            activeEnergy: activeEnergy,
            exerciseMinutes: exerciseMinutes,
            standHours: standHours,
            walkingSpeedMps: walkingSpeedMps,
            walkingPaceSecondsPerKm: walkingPaceSecondsPerKm,
            stepsGoal: stepsGoal,
            activeEnergyGoal: activeEnergyGoal,
            exerciseMinutesGoal: exerciseMinutesGoal,
            standHoursGoal: standHoursGoal,
            sleepDurationMinutes: sleepDurationMinutes,
            sleepScore: sleepScore,
            lateNightRecoveryPrompt: lateNightRecoveryPrompt,
            lateNightRecoverySeverity: lateNightRecoverySeverity,
            sleepEnvironmentCompletionRate: sleepEnvironmentCompletionRate,
            sleepEnvironmentPrompt: sleepEnvironmentPrompt,
            waterIntakeMl: waterIntakeMl,
            waterTargetMl: waterTargetMl,
            waterCompletionRate: waterCompletionRate,
            caffeineRemainedMg: caffeineRemainedMg,
            sedentaryElapsedMinutes: sedentaryElapsedMinutes,
            sedentaryIsCounting: sedentaryIsCounting,
            sedentaryPausedBySleep: sedentaryPausedBySleep,
            sedentarySeatedStartAtSeconds: sedentarySeatedStartAt,
            sedentaryLastActivityAtSeconds: sedentaryLastActivityAt,
            sedentaryUpdatedAtSeconds: sedentaryUpdatedAt,
            sedentaryBreakIsActive: sedentaryBreakIsActive,
            sedentaryBreakDurationMinutes: sedentaryBreakDurationMinutes,
            sedentaryBreakStartedAtSeconds: sedentaryBreakStartedAt,
            periodPhase: periodPhase,
            periodCycleDay: periodCycleDay,
            periodIsFertile: periodIsFertile,
            periodNextStart: periodNextStart,
            periodFertileStart: periodFertileStart,
            periodFertileEnd: periodFertileEnd,
            periodPredictionSource: periodPredictionSource,
            defaultComplicationTemplate: defaultComplicationTemplate,
            watchThemeId: watchThemeId,
            watchMascotEnabled: watchMascotEnabled,
            watchMascotMessage: watchMascotMessage,
            watchMascotMessageConfigured: watchMascotMessageConfigured,
            watchCustomThemeId: watchCustomThemeId,
            bodyAgeValueYears: bodyAgeValueYears,
            bodyAgeStatusText: bodyAgeStatusText,
            bodyAgeComparisonText: bodyAgeComparisonText,
            bodyAgeSuggestionText: bodyAgeSuggestionText,
            bodyAgeCoverageText: bodyAgeCoverageText,
            bodyAgeDirectionText: bodyAgeDirectionText,
            vo2MaxValue: vo2MaxValue,
            vo2MaxConfidence: vo2MaxConfidence,
            vo2MaxTrend: vo2MaxTrend,
            vo2MaxFitnessLevel: vo2MaxFitnessLevel,
            vo2MaxSource: vo2MaxSource,
            vo2MaxDriverSummary: vo2MaxDriverSummary,
            stressHistory: stressHistory,
            sleepMonitoringPhase: sleepMonitoringPhase,
            sleepMonitoringActive: sleepMonitoringActive,
            sleepSnoreIntensity: sleepSnoreIntensity,
            sleepSnoreDurationMinutes: sleepSnoreDurationMinutes,
            sleepInsightHeadline: sleepInsightHeadline,
            sleepWatchConfidence: sleepWatchConfidence,
            recoveryPlan: recoveryPlan
        )
    }

    private static func recoveryPlanDictionary(_ plan: WatchRecoveryPlanSnapshot) -> [String: Any] {
        [
            "planID": plan.planID,
            "dayStart": plan.dayStart,
            "actions": plan.actions.map { action -> [String: Any] in
                [
                    "actionID": action.actionID,
                    "title": action.title,
                    "role": action.role,
                    "state": action.state
                ]
            }
        ]
    }

    private static func parseRecoveryPlan(_ value: Any?) -> WatchRecoveryPlanSnapshot? {
        guard let dictionary = value as? [String: Any],
              let planID = nonEmptyString(dictionary["planID"]),
              let dayStart = intValue(dictionary["dayStart"]),
              dayStart > 0,
              let rawActions = dictionary["actions"] as? [Any] else {
            return nil
        }

        let validRoles: Set<String> = ["main", "supporting"]
        let validStates: Set<String> = ["pending", "completed", "snoozed", "skipped", "notApplicable"]
        var seenActionIDs: Set<String> = []
        let actions = rawActions.compactMap { rawAction -> WatchRecoveryPlanActionSnapshot? in
            guard let action = rawAction as? [String: Any],
                  let actionID = nonEmptyString(action["actionID"]),
                  seenActionIDs.insert(actionID).inserted,
                  let title = nonEmptyString(action["title"]),
                  let role = nonEmptyString(action["role"]),
                  validRoles.contains(role) else {
                return nil
            }
            let stateCandidate = nonEmptyString(action["state"])
            let state = stateCandidate.flatMap { validStates.contains($0) ? $0 : nil }
                ?? "pending"
            return WatchRecoveryPlanActionSnapshot(
                actionID: actionID,
                title: title,
                role: role,
                state: state
            )
        }

        let boundedActions = Array(actions.prefix(3))
        guard boundedActions.contains(where: { $0.role == "main" }) else { return nil }

        return WatchRecoveryPlanSnapshot(
            planID: planID,
            dayStart: dayStart,
            actions: boundedActions
        )
    }

    private static func typeRawValue(for envelope: WatchSyncEnvelope) -> String {
        switch envelope {
        case .sleepStateChanged:
            return WatchSyncMessageType.sleepStateChanged.rawValue
        case .sleepDeviceStatus:
            return WatchSyncMessageType.sleepDeviceStatus.rawValue
        default:
            return ""
        }
    }

    private static func watchSleepPayloadDictionary(_ payload: WatchSleepStatePayload) -> [String: Any] {
        var dict: [String: Any] = [
            "sleepMonitoringPhase": payload.phase.rawValue,
            "sleepMonitoringActive": payload.phase == .monitoring,
            "sleepWatchConnected": payload.watchConnected,
            "sleepWatchConfidence": payload.watchConfidence,
            "sleepUpdatedAt": Int(payload.lastUpdatedAt.timeIntervalSince1970)
        ]
        if let probableSleepStartAt = payload.probableSleepStartAt {
            dict["probableSleepStartAt"] = Int(probableSleepStartAt.timeIntervalSince1970)
        }
        if let summary = payload.summary {
            dict.merge(sleepSummaryDictionary(summary)) { _, new in new }
        }
        return dict
    }

    private static func sleepSummaryDictionary(_ summary: SleepSessionSummary) -> [String: Any] {
        [
            "sleepSummarySessionId": summary.sessionId,
            "sleepSummaryStartAt": Int(summary.startTime.timeIntervalSince1970),
            "sleepSummaryEndAt": Int(summary.endTime.timeIntervalSince1970),
            "sleepSummaryDurationMinutes": summary.sleepDurationMinutes,
            "sleepSummaryScore": summary.sleepScore,
            "sleepSummaryContinuityScore": summary.sleepContinuityScore,
            "sleepSummarySnoreDetected": summary.snoreSummary.snoreDetected,
            "sleepSummarySnoreDurationMinutes": summary.snoreSummary.snoreDurationMinutes,
            "sleepSummarySnoreIntensity": summary.snoreSummary.intensity.rawValue,
            "sleepSummaryInsightHeadline": summary.insight.headline,
            "sleepSummaryWatchConfidence": summary.watchConfidence
        ]
    }

    private static func parseWatchSleepPayload(_ dict: [String: Any]) -> WatchSleepStatePayload {
        let phaseRaw = (dict["sleepMonitoringPhase"] as? String) ?? SleepMonitoringPhase.idle.rawValue
        let phase = SleepMonitoringPhase(rawValue: phaseRaw) ?? .idle
        let watchConnected = boolValue(dict["sleepWatchConnected"]) ?? boolValue(dict["sleepMonitoringActive"]) ?? false
        let watchConfidence = doubleValue(dict["sleepWatchConfidence"]) ?? doubleValue(dict["sleepSummaryWatchConfidence"]) ?? 0
        let probableSleepStartAt = intValue(dict["probableSleepStartAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let updatedAt = intValue(dict["sleepUpdatedAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        let summary = parseSleepSummary(dict)
        return WatchSleepStatePayload(
            phase: phase,
            watchConnected: watchConnected,
            watchConfidence: watchConfidence,
            probableSleepStartAt: probableSleepStartAt,
            lastUpdatedAt: updatedAt,
            summary: summary
        )
    }

    private static func parseSleepSummary(_ dict: [String: Any]) -> SleepSessionSummary? {
        guard let sessionId = dict["sleepSummarySessionId"] as? String,
              let startTs = intValue(dict["sleepSummaryStartAt"]),
              let endTs = intValue(dict["sleepSummaryEndAt"]),
              let duration = intValue(dict["sleepSummaryDurationMinutes"]),
              let score = intValue(dict["sleepSummaryScore"]) else {
            return nil
        }
        let snoreIntensity = SleepSnoreIntensity(rawValue: (dict["sleepSummarySnoreIntensity"] as? String) ?? "none") ?? .none
        let snoreDuration = doubleValue(dict["sleepSummarySnoreDurationMinutes"]) ?? 0
        let snoreDetected = boolValue(dict["sleepSummarySnoreDetected"]) ?? (snoreDuration > 0)
        let continuityScore = intValue(dict["sleepSummaryContinuityScore"]) ?? max(0, min(100, score - 6))
        let watchConfidence = doubleValue(dict["sleepSummaryWatchConfidence"]) ?? 0
        let headline = (dict["sleepSummaryInsightHeadline"] as? String) ?? "昨夜睡眠已完成"
        let start = Date(timeIntervalSince1970: TimeInterval(startTs))
        let end = Date(timeIntervalSince1970: TimeInterval(endTs))
        return SleepSessionSummary(
            sessionId: sessionId,
            sourceDate: Calendar.current.startOfDay(for: end),
            startTime: start,
            endTime: end,
            sleepDurationMinutes: duration,
            sleepScore: score,
            sleepContinuityScore: continuityScore,
            stageSummary: .empty,
            snoreSummary: SnoreAnalysisSummary(
                snoreDetected: snoreDetected,
                snoreDurationMinutes: snoreDuration,
                snoreFrequencyPerHour: 0,
                intensity: snoreIntensity,
                disturbanceScore: max(0, min(100, Int((snoreDuration * 3.5).rounded()))),
                riskFlag: snoreIntensity == .high ? .elevated : (snoreDetected ? .monitor : .none),
                segments: [],
                histogram: Array(repeating: 0, count: 6)
            ),
            insight: SleepInsightSnapshot(
                headline: headline,
                summary: headline,
                recommendationCode: "watch_snapshot",
                recommendationText: "打开 iPhone 睡眠页面查看完整结果。",
                riskFlag: snoreIntensity == .high ? .elevated : .none,
                generatedAt: Date(),
                modelVersion: "watch-snapshot-v1"
            ),
            watchConfidence: watchConfidence,
            deviceSource: "watch",
            analysisVersion: "watch-snapshot-v1",
            createdAt: Date(),
            updatedAt: Date(),
            source: .watchSignal
        )
    }

    private static func parseStressHistory(_ value: Any?) -> [WatchStressHistoryPoint] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let timestamp = intValue(item["timestamp"]),
                  let pointValue = intValue(item["value"]) else {
                return nil
            }
            return WatchStressHistoryPoint(timestamp: timestamp, value: pointValue)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let double = value as? Double { return Int(double.rounded()) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let int64 = value as? Int64 { return Double(int64) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let double = value as? Double { return double != 0 }
        if let string = value as? String {
            let normalized = string.lowercased()
            if normalized == "true" { return true }
            if normalized == "false" { return false }
            if let int = Int(normalized) { return int != 0 }
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
