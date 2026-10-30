import Foundation

enum SharedWidgetFocusMode: String, CaseIterable, Sendable {
    case automatic
    case recovery
    case sleep
    case stress
    case activity
    case hydration
}

enum SharedWidgetDescriptorSource: String, Sendable {
    case recovery
    case stress
    case activity
    case hydration
    case empty
    case stale
}

enum SharedWidgetDescriptorTone: String, Sendable {
    case waiting
    case relaxed
    case steady
    case mild
    case caution
    case high
}

enum SharedWidgetDataState: Sendable {
    case missing
    case stale
    case fresh
}

struct SharedOverallWidgetSnapshot: Sendable, Hashable {
    let heartRate: Double?
    let hrv: Double?
    let stress: Double?
    let stressState: String?
    let stressExplanationCode: String?
    let stressConfidence: Double?
    let stressTrend: String?
    let lastSyncTime: Date?
    let waterIntakeMl: Double?
    let waterTargetMl: Int?
    let waterCompletionRate: Double?
    let caffeineRemainedMg: Double?
    let steps: Int?
    let activeEnergy: Int?
    let activityCompletionRate: Double?
    let sleepDurationMinutes: Int?
    let sleepScore: Int?
    let sleepDurationCompletionRate: Double?
    let lateNightRecoveryPrompt: String?
    let lateNightRecoverySeverity: String?
    let sleepEnvironmentCompletionRate: Double?
    let sleepEnvironmentPrompt: String?

    init(
        heartRate: Double?,
        hrv: Double?,
        stress: Double?,
        stressState: String?,
        stressExplanationCode: String?,
        stressConfidence: Double?,
        stressTrend: String?,
        lastSyncTime: Date?,
        waterIntakeMl: Double?,
        waterTargetMl: Int?,
        waterCompletionRate: Double?,
        caffeineRemainedMg: Double?,
        steps: Int?,
        activeEnergy: Int?,
        activityCompletionRate: Double?,
        sleepDurationMinutes: Int?,
        sleepScore: Int?,
        sleepDurationCompletionRate: Double?,
        lateNightRecoveryPrompt: String? = nil,
        lateNightRecoverySeverity: String? = nil,
        sleepEnvironmentCompletionRate: Double? = nil,
        sleepEnvironmentPrompt: String? = nil
    ) {
        self.heartRate = heartRate
        self.hrv = hrv
        self.stress = stress
        self.stressState = stressState
        self.stressExplanationCode = stressExplanationCode
        self.stressConfidence = stressConfidence
        self.stressTrend = stressTrend
        self.lastSyncTime = lastSyncTime
        self.waterIntakeMl = waterIntakeMl
        self.waterTargetMl = waterTargetMl
        self.waterCompletionRate = waterCompletionRate
        self.caffeineRemainedMg = caffeineRemainedMg
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.activityCompletionRate = activityCompletionRate
        self.sleepDurationMinutes = sleepDurationMinutes
        self.sleepScore = sleepScore
        self.sleepDurationCompletionRate = sleepDurationCompletionRate
        self.lateNightRecoveryPrompt = lateNightRecoveryPrompt
        self.lateNightRecoverySeverity = lateNightRecoverySeverity
        self.sleepEnvironmentCompletionRate = sleepEnvironmentCompletionRate
        self.sleepEnvironmentPrompt = sleepEnvironmentPrompt
    }
}

struct SharedWidgetResolvedDescriptor: Sendable, Hashable {
    let source: SharedWidgetDescriptorSource
    let title: String
    let summary: String
    let detail: String
    let primaryMetricTitle: String
    let primaryMetricValue: String
    let secondaryMetricTitle: String
    let secondaryMetricValue: String
    let tertiaryMetricTitle: String
    let tertiaryMetricValue: String
    let tone: SharedWidgetDescriptorTone
    let symbolName: String
    let progress: Double
}

enum WidgetOverallResolver {
    static func dataState(for lastSyncTime: Date?, now: Date = .now) -> SharedWidgetDataState {
        guard let lastSyncTime else { return .missing }
        return now.timeIntervalSince(lastSyncTime) > AppGroupSchema.Freshness.generalStaleAfter ? .stale : .fresh
    }

    static func resolve(
        snapshot: SharedOverallWidgetSnapshot,
        focus: SharedWidgetFocusMode = .automatic,
        now: Date = .now
    ) -> SharedWidgetResolvedDescriptor {
        let state = dataState(for: snapshot.lastSyncTime, now: now)
        if state == .missing {
            return emptyDescriptor
        }
        if state == .stale {
            return staleDescriptor(snapshot: snapshot)
        }

        let preferred = descriptor(for: focus, snapshot: snapshot)
        if preferred.source != .empty {
            return preferred
        }

        let candidates = [
            recoveryDescriptor(snapshot: snapshot),
            sleepDescriptor(snapshot: snapshot),
            stressDescriptor(snapshot: snapshot),
            activityDescriptor(snapshot: snapshot),
            hydrationDescriptor(snapshot: snapshot)
        ]

        return candidates.first(where: { $0.source != .empty }) ?? emptyDescriptor
    }

    private static func descriptor(for focus: SharedWidgetFocusMode, snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        switch focus {
        case .automatic:
            return emptyDescriptor
        case .recovery:
            return recoveryDescriptor(snapshot: snapshot)
        case .sleep:
            return sleepDescriptor(snapshot: snapshot)
        case .stress:
            return stressDescriptor(snapshot: snapshot)
        case .activity:
            return activityDescriptor(snapshot: snapshot)
        case .hydration:
            return hydrationDescriptor(snapshot: snapshot)
        }
    }

    private static func recoveryDescriptor(snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        guard snapshot.hrv != nil || snapshot.heartRate != nil else { return emptyDescriptor }
        let score = recoveryScore(hrv: snapshot.hrv, stress: snapshot.stress)
        let tone: SharedWidgetDescriptorTone
        let title: String
        switch score {
        case 80...:
            tone = .relaxed
            title = String(localized: "体征稳定")
        case 60..<80:
            tone = .steady
            title = String(localized: "状态平稳")
        case 40..<60:
            tone = .mild
            title = String(localized: "轻微波动")
        default:
            tone = .caution
            title = String(localized: "需要调整")
        }

        return SharedWidgetResolvedDescriptor(
            source: .recovery,
            title: title,
            summary: String(localized: "恢复分数 \(score)"),
            detail: String(localized: "基于 HRV 与压力粗略估算"),
            primaryMetricTitle: String(localized: "恢复"),
            primaryMetricValue: "\(score)",
            secondaryMetricTitle: "HRV",
            secondaryMetricValue: intText(snapshot.hrv),
            tertiaryMetricTitle: String(localized: "心率"),
            tertiaryMetricValue: intText(snapshot.heartRate),
            tone: tone,
            symbolName: "waveform.path.ecg",
            progress: progress(Double(score), max: 100)
        )
    }

    private static func sleepDescriptor(snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        guard snapshot.sleepDurationMinutes != nil
            || snapshot.sleepScore != nil
            || snapshot.lateNightRecoveryPrompt != nil
            || snapshot.sleepEnvironmentPrompt != nil else { return emptyDescriptor }
        let score = snapshot.sleepScore ?? Int((snapshot.sleepDurationCompletionRate ?? 0) * 100)
        let tone: SharedWidgetDescriptorTone
        let title: String
        switch score {
        case 85...:
            tone = .relaxed
            title = String(localized: "睡眠充足")
        case 70..<85:
            tone = .steady
            title = String(localized: "睡眠平稳")
        case 50..<70:
            tone = .mild
            title = String(localized: "睡眠偏少")
        default:
            tone = .caution
            title = String(localized: "睡眠不足")
        }

        let detail = snapshot.lateNightRecoveryPrompt
            ?? snapshot.sleepEnvironmentPrompt
            ?? String(localized: "优先关注睡眠时长和质量")

        return SharedWidgetResolvedDescriptor(
            source: .recovery,
            title: title,
            summary: String(localized: "睡眠得分 \(score)"),
            detail: detail,
            primaryMetricTitle: String(localized: "睡眠"),
            primaryMetricValue: durationText(snapshot.sleepDurationMinutes),
            secondaryMetricTitle: String(localized: "得分"),
            secondaryMetricValue: "\(score)",
            tertiaryMetricTitle: snapshot.sleepEnvironmentCompletionRate == nil ? String(localized: "完成度") : String(localized: "环境"),
            tertiaryMetricValue: percentText(snapshot.sleepEnvironmentCompletionRate ?? snapshot.sleepDurationCompletionRate),
            tone: tone,
            symbolName: "bed.double.fill",
            progress: progress(Double(score), max: 100)
        )
    }

    private static func stressDescriptor(snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        guard let stress = snapshot.stress else { return emptyDescriptor }
        let rounded = Int(stress.rounded())
        let tone: SharedWidgetDescriptorTone
        let title: String
        if let state = snapshot.stressState {
            switch state {
            case "recovery":
                tone = .relaxed
                title = String(localized: "恢复中")
            case "relaxed":
                tone = .relaxed
                title = String(localized: "比较放松")
            case "normal":
                tone = .steady
                title = String(localized: "压力正常")
            case "strained":
                tone = .mild
                title = String(localized: "有些紧张")
            case "highStress":
                tone = .caution
                title = String(localized: "压力较高")
            case "overloaded":
                tone = .high
                title = String(localized: "接近过载")
            default:
                tone = .steady
                title = String(localized: "压力平稳")
            }
        } else {
            switch stress {
            case ..<30:
                tone = .relaxed
                title = String(localized: "压力较低")
            case 30..<50:
                tone = .steady
                title = String(localized: "压力平稳")
            case 50..<70:
                tone = .mild
                title = String(localized: "压力偏高")
            case 70..<85:
                tone = .caution
                title = String(localized: "压力较高")
            default:
                tone = .high
                title = String(localized: "压力过高")
            }
        }

        return SharedWidgetResolvedDescriptor(
            source: .stress,
            title: title,
            summary: String(localized: "压力 \(rounded)"),
            detail: stressDetail(snapshot: snapshot),
            primaryMetricTitle: String(localized: "压力"),
            primaryMetricValue: "\(rounded)",
            secondaryMetricTitle: String(localized: "趋势"),
            secondaryMetricValue: snapshot.stressTrend ?? String(localized: "稳定"),
            tertiaryMetricTitle: "HRV",
            tertiaryMetricValue: intText(snapshot.hrv),
            tone: tone,
            symbolName: "wind",
            progress: progress(stress, max: 100)
        )
    }

    private static func stressDetail(snapshot: SharedOverallWidgetSnapshot) -> String {
        switch snapshot.stressExplanationCode {
        case "physical_workout_load":
            return String(localized: "当前更像运动负荷")
        case "recovery_debt_elevated":
            return String(localized: "昨夜恢复不足")
        case "hrv_below_baseline":
            return String(localized: "HRV 低于近期基线")
        case "heart_rate_above_baseline":
            return String(localized: "当前心率高于平时")
        case "hrv_trending_down":
            return String(localized: "HRV 正在继续走低")
        case "heart_rate_trending_up":
            return String(localized: "心率还在继续上升")
        case "circadian_load_window":
            return String(localized: "当前处在更易承压时段")
        default:
            return snapshot.stressTrend.map { String(localized: "趋势 \($0)") } ?? String(localized: "关注今日波动")
        }
    }

    private static func activityDescriptor(snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        guard snapshot.activityCompletionRate != nil || snapshot.steps != nil || snapshot.activeEnergy != nil else { return emptyDescriptor }
        let completion = snapshot.activityCompletionRate ?? 0
        let tone: SharedWidgetDescriptorTone
        let title: String
        switch completion {
        case 0.85...:
            tone = .relaxed
            title = String(localized: "节奏很稳")
        case 0.65..<0.85:
            tone = .steady
            title = String(localized: "持续保持")
        case 0.35..<0.65:
            tone = .mild
            title = String(localized: "再动一动")
        default:
            tone = .caution
            title = String(localized: "先起身活动")
        }

        return SharedWidgetResolvedDescriptor(
            source: .activity,
            title: title,
            summary: String(localized: "活动完成度 \(percentText(completion))"),
            detail: String(localized: "优先看步数和活跃能量"),
            primaryMetricTitle: String(localized: "完成度"),
            primaryMetricValue: percentText(completion),
            secondaryMetricTitle: String(localized: "步数"),
            secondaryMetricValue: intText(snapshot.steps),
            tertiaryMetricTitle: String(localized: "能量"),
            tertiaryMetricValue: snapshot.activeEnergy.map { "\($0)" } ?? "--",
            tone: tone,
            symbolName: "figure.walk",
            progress: max(0.08, min(1.0, completion))
        )
    }

    private static func hydrationDescriptor(snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        guard snapshot.waterCompletionRate != nil || snapshot.waterIntakeMl != nil else { return emptyDescriptor }
        let completion = snapshot.waterCompletionRate ?? 0
        let tone: SharedWidgetDescriptorTone
        let title: String
        switch completion {
        case 0.9...:
            tone = .relaxed
            title = String(localized: "补水充足")
        case 0.65..<0.9:
            tone = .steady
            title = String(localized: "补水平稳")
        case 0.35..<0.65:
            tone = .mild
            title = String(localized: "记得补水")
        default:
            tone = .caution
            title = String(localized: "补水不足")
        }

        return SharedWidgetResolvedDescriptor(
            source: .hydration,
            title: title,
            summary: String(localized: "补水完成度 \(percentText(completion))"),
            detail: String(localized: "优先补足今日饮水量"),
            primaryMetricTitle: String(localized: "补水"),
            primaryMetricValue: snapshot.waterIntakeMl.map { "\(Int($0.rounded()))ml" } ?? "--",
            secondaryMetricTitle: String(localized: "完成度"),
            secondaryMetricValue: percentText(completion),
            tertiaryMetricTitle: String(localized: "目标"),
            tertiaryMetricValue: snapshot.waterTargetMl.map { "\($0)ml" } ?? "--",
            tone: tone,
            symbolName: "drop.fill",
            progress: max(0.08, min(1.0, completion))
        )
    }

    private static func staleDescriptor(snapshot: SharedOverallWidgetSnapshot) -> SharedWidgetResolvedDescriptor {
        let fallback = recoveryDescriptor(snapshot: snapshot)
        if fallback.source != .empty {
            return SharedWidgetResolvedDescriptor(
                source: .stale,
                title: fallback.title,
                summary: fallback.summary,
                detail: String(localized: "数据较旧"),
                primaryMetricTitle: fallback.primaryMetricTitle,
                primaryMetricValue: fallback.primaryMetricValue,
                secondaryMetricTitle: fallback.secondaryMetricTitle,
                secondaryMetricValue: fallback.secondaryMetricValue,
                tertiaryMetricTitle: fallback.tertiaryMetricTitle,
                tertiaryMetricValue: fallback.tertiaryMetricValue,
                tone: .caution,
                symbolName: fallback.symbolName,
                progress: fallback.progress
            )
        }
        return SharedWidgetResolvedDescriptor(
            source: .stale,
            title: String(localized: "数据较旧"),
            summary: String(localized: "最近同步已过期"),
            detail: String(localized: "打开 App 后会刷新"),
            primaryMetricTitle: String(localized: "状态"),
            primaryMetricValue: "--",
            secondaryMetricTitle: String(localized: "同步"),
            secondaryMetricValue: String(localized: "较旧"),
            tertiaryMetricTitle: String(localized: "建议"),
            tertiaryMetricValue: String(localized: "刷新"),
            tone: .caution,
            symbolName: "clock.badge.exclamationmark",
            progress: 0.12
        )
    }

    private static let emptyDescriptor = SharedWidgetResolvedDescriptor(
        source: .empty,
        title: String(localized: "等待同步"),
        summary: String(localized: "暂无共享数据"),
        detail: String(localized: "打开 App 后会显示健康概览"),
        primaryMetricTitle: String(localized: "状态"),
        primaryMetricValue: "--",
        secondaryMetricTitle: String(localized: "同步"),
        secondaryMetricValue: String(localized: "待同步"),
        tertiaryMetricTitle: String(localized: "来源"),
        tertiaryMetricValue: "App",
        tone: .waiting,
        symbolName: "circle.dashed",
        progress: 0.10
    )

    private static func recoveryScore(hrv: Double?, stress: Double?) -> Int {
        let hrvScore = min(max((hrv ?? 35) / 70.0, 0), 1) * 60
        let stressPenalty = min(max((stress ?? 45) / 100.0, 0), 1) * 40
        return max(0, min(100, Int((hrvScore + (40 - stressPenalty)).rounded())))
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private static func intText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }

    private static func intText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }

    private static func durationText(_ minutes: Int?) -> String {
        guard let minutes else { return "--" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private static func progress(_ value: Double, max: Double) -> Double {
        Swift.max(0.08, Swift.min(1.0, value / max))
    }
}
