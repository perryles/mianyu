import Foundation

enum SharedComplicationTemplate: String, CaseIterable, Sendable {
    case overview
    case recovery
    case sleep
    case activity
    case hydration
    case bodyAge

    var title: String {
        switch self {
        case .overview: return String(localized: "综合状态")
        case .recovery: return String(localized: "恢复")
        case .sleep: return String(localized: "睡眠")
        case .activity: return String(localized: "活动")
        case .hydration: return String(localized: "补水")
        case .bodyAge: return String(localized: "体龄")
        }
    }

    var shortTitle: String {
        switch self {
        case .overview: return String(localized: "综合")
        case .recovery: return String(localized: "恢复")
        case .sleep: return String(localized: "睡眠")
        case .activity: return String(localized: "活动")
        case .hydration: return String(localized: "补水")
        case .bodyAge: return String(localized: "体龄")
        }
    }

    var cornerLabel: String {
        switch self {
        case .overview: return String(localized: "综")
        case .recovery: return String(localized: "恢")
        case .sleep: return String(localized: "眠")
        case .activity: return String(localized: "动")
        case .hydration: return String(localized: "水")
        case .bodyAge: return String(localized: "龄")
        }
    }

    var detail: String {
        switch self {
        case .overview: return String(localized: "优先看今日整体状态")
        case .recovery: return String(localized: "优先看 HRV 与恢复分数")
        case .sleep: return String(localized: "优先看睡眠时长与得分")
        case .activity: return String(localized: "优先看步数与活动完成度")
        case .hydration: return String(localized: "优先看饮水和咖啡因")
        case .bodyAge: return String(localized: "优先看体龄与建议")
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .recovery: return "leaf.fill"
        case .sleep: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .hydration: return "drop.fill"
        case .bodyAge: return "person.text.rectangle"
        }
    }
}

struct SharedComplicationVitals: Sendable, Hashable {
    let heartRate: Double?
    let hrv: Double?
    let stress: Double?
    let stressState: String?
    let stressExplanationCode: String?
    let stressConfidence: Double?
    let stressTrend: String?
    let recoveryScore: Int?
    let recoveryStatus: String?
    let recoveryTrend: String?
    let sleepDurationMinutes: Int?
    let sleepScore: Int?
    let sleepCompletionRate: Double?
    let sleepSnoreIntensity: String?
    let sleepSnoreDurationMinutes: Double?
    let steps: Int?
    let activeEnergy: Int?
    let exerciseMinutes: Int?
    let standHours: Int?
    let activityCompletionRate: Double?
    let waterIntakeMl: Double?
    let waterTargetMl: Int?
    let waterCompletionRate: Double?
    let caffeineRemainedMg: Double?
    let bodyAgeValueYears: Double?
    let bodyAgeStatusText: String?
    let vo2MaxValue: Double?
    let vo2MaxConfidence: Int?
    let vo2MaxTrend: String?
    let vo2MaxFitnessLevel: String?
    let vo2MaxSource: String?
    let vo2MaxDriverSummary: String?
    let healthSummary: String?
    let lastSyncTime: Date?
}

struct SharedComplicationPresentation: Sendable, Hashable {
    let template: SharedComplicationTemplate
    let hasVitals: Bool
    let isStale: Bool
    let freshnessText: String
    let statusTitle: String
    let headline: String
    let subheadline: String
    let inlineText: String
    let primaryMetricTitle: String
    let primaryMetricValue: String
    let secondaryMetricTitle: String
    let secondaryMetricValue: String
    let tertiaryMetricTitle: String
    let tertiaryMetricValue: String
    let gaugeValue: Double?
    let gaugeRangeLower: Double
    let gaugeRangeUpper: Double

    static func resolve(
        template: SharedComplicationTemplate,
        vitals: SharedComplicationVitals,
        now: Date = .now,
        staleAfter: TimeInterval = AppGroupSchema.Freshness.vitalsStaleAfter,
        isStaleOverride: Bool? = nil
    ) -> SharedComplicationPresentation {
        let recoveryScore = vitals.recoveryScore ?? derivedRecoveryScore(hrv: vitals.hrv, stress: vitals.stress)
        let sleepScore = vitals.sleepScore ?? vitals.sleepCompletionRate.map { Int(($0 * 100).rounded()) }
        let activityScore = vitals.activityCompletionRate.map { Int(($0 * 100).rounded()) }
        let hydrationScore = vitals.waterCompletionRate.map { Int(($0 * 100).rounded()) }
        let overviewScore = averageScore([recoveryScore, sleepScore, activityScore])
        let hasVitals = hasData(
            for: template,
            vitals: vitals,
            recoveryScore: recoveryScore,
            sleepScore: sleepScore,
            activityScore: activityScore,
            hydrationScore: hydrationScore
        )
        let isStale = isStaleOverride ?? {
            guard hasVitals, let lastSyncTime = vitals.lastSyncTime else { return hasVitals }
            return now.timeIntervalSince(lastSyncTime) > staleAfter
        }()
        let freshness = freshnessText(lastSyncTime: vitals.lastSyncTime, now: now, hasVitals: hasVitals)
        let status = statusTitle(
            template: template,
            vitals: vitals,
            recoveryScore: recoveryScore,
            overviewScore: overviewScore,
            sleepScore: sleepScore,
            activityScore: activityScore,
            hydrationScore: hydrationScore,
            hasVitals: hasVitals
        )
        let metrics = metrics(
            template: template,
            vitals: vitals,
            recoveryScore: recoveryScore,
            sleepScore: sleepScore,
            activityScore: activityScore,
            hydrationScore: hydrationScore,
            status: status
        )
        let headline = headlineText(
            template: template,
            vitals: vitals,
            recoveryScore: recoveryScore,
            sleepScore: sleepScore,
            activityScore: activityScore,
            hydrationScore: hydrationScore
        )
        let subheadline = subheadlineText(template: template, vitals: vitals, freshness: freshness, isStale: isStale)
        let inline = inlineText(
            template: template,
            status: status,
            freshness: freshness,
            hasVitals: hasVitals,
            isStale: isStale
        )
        let gauge = gaugeValue(
            template: template,
            recoveryScore: recoveryScore,
            overviewScore: overviewScore,
            sleepScore: sleepScore,
            activityScore: activityScore,
            hydrationScore: hydrationScore,
            vitals: vitals
        )
        let range = gaugeRange(template: template)

        return SharedComplicationPresentation(
            template: template,
            hasVitals: hasVitals,
            isStale: isStale,
            freshnessText: freshness,
            statusTitle: status,
            headline: headline,
            subheadline: subheadline,
            inlineText: inline,
            primaryMetricTitle: metrics.0.title,
            primaryMetricValue: metrics.0.value,
            secondaryMetricTitle: metrics.1.title,
            secondaryMetricValue: metrics.1.value,
            tertiaryMetricTitle: metrics.2.title,
            tertiaryMetricValue: metrics.2.value,
            gaugeValue: gauge,
            gaugeRangeLower: range.lowerBound,
            gaugeRangeUpper: range.upperBound
        )
    }

    private static func derivedRecoveryScore(hrv: Double?, stress: Double?) -> Int? {
        guard hrv != nil || stress != nil else { return nil }
        let hrvScore = min(max((hrv ?? 35) / 70.0, 0), 1) * 60
        let stressPenalty = min(max((stress ?? 45) / 100.0, 0), 1) * 40
        return max(0, min(100, Int((hrvScore + (40 - stressPenalty)).rounded())))
    }

    private static func averageScore(_ scores: [Int?]) -> Int? {
        let availableScores = scores.compactMap { $0 }
        guard !availableScores.isEmpty else { return nil }
        return Int((Double(availableScores.reduce(0, +)) / Double(availableScores.count)).rounded())
    }

    private static func hasData(
        for template: SharedComplicationTemplate,
        vitals: SharedComplicationVitals,
        recoveryScore: Int?,
        sleepScore: Int?,
        activityScore: Int?,
        hydrationScore: Int?
    ) -> Bool {
        switch template {
        case .overview:
            return recoveryScore != nil || sleepScore != nil || activityScore != nil
        case .recovery:
            return recoveryScore != nil || vitals.hrv != nil || vitals.stress != nil || sleepScore != nil
        case .sleep:
            return vitals.sleepDurationMinutes != nil
                || sleepScore != nil
                || vitals.sleepCompletionRate != nil
                || vitals.sleepSnoreIntensity != nil
                || vitals.sleepSnoreDurationMinutes != nil
        case .activity:
            return vitals.steps != nil
                || vitals.activeEnergy != nil
                || vitals.exerciseMinutes != nil
                || vitals.standHours != nil
                || activityScore != nil
        case .hydration:
            return vitals.waterIntakeMl != nil
                || vitals.caffeineRemainedMg != nil
                || hydrationScore != nil
        case .bodyAge:
            return vitals.bodyAgeValueYears != nil
                || vitals.bodyAgeStatusText != nil
                || vitals.healthSummary != nil
        }
    }

    private static func intText(_ value: Double?, suffix: String = "") -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))\(suffix)"
    }

    private static func intText(_ value: Int?, suffix: String = "") -> String {
        guard let value else { return "--" }
        return "\(value)\(suffix)"
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private static func durationText(_ minutes: Int?) -> String {
        guard let minutes else { return "--" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(remainingMinutes)m" }
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h\(remainingMinutes)m"
    }

    private static func snoreText(intensity: String?, durationMinutes: Double?) -> String {
        switch intensity?.lowercased() {
        case "none": return String(localized: "未检出")
        case "low": return String(localized: "轻度")
        case "medium": return String(localized: "中等")
        case "high": return String(localized: "偏强")
        default:
            guard let durationMinutes else { return "--" }
            return durationMinutes > 0 ? "\(Int(durationMinutes.rounded()))m" : String(localized: "未检出")
        }
    }

    private static func freshnessText(lastSyncTime: Date?, now: Date, hasVitals: Bool) -> String {
        guard hasVitals else { return String(localized: "待同步") }
        guard let lastSyncTime else { return String(localized: "时间未知") }
        let delta = max(0, Int(now.timeIntervalSince(lastSyncTime)))
        if delta < 60 { return String(localized: "刚刚") }
        if delta < 3600 { return String(localized: "\(delta / 60)分钟前") }
        if delta < 24 * 3600 { return String(localized: "\(delta / 3600)小时前") }
        return String(localized: "\(delta / (24 * 3600))天前")
    }

    private static func statusTitle(
        template: SharedComplicationTemplate,
        vitals: SharedComplicationVitals,
        recoveryScore: Int?,
        overviewScore: Int?,
        sleepScore: Int?,
        activityScore: Int?,
        hydrationScore: Int?,
        hasVitals: Bool
    ) -> String {
        guard hasVitals else { return String(localized: "待同步") }
        switch template {
        case .overview:
            guard let overviewScore else { return String(localized: "待同步") }
            if overviewScore >= 80 { return String(localized: "状态很稳") }
            if overviewScore >= 60 { return String(localized: "状态平稳") }
            return String(localized: "需要关注")
        case .recovery:
            guard let recoveryScore else { return String(localized: "待恢复数据") }
            if recoveryScore >= 80 { return String(localized: "不错") }
            if recoveryScore >= 60 { return String(localized: "回升中") }
            return String(localized: "偏弱")
        case .sleep:
            guard let sleepScore else { return String(localized: "已同步") }
            if sleepScore >= 85 { return String(localized: "充足") }
            if sleepScore >= 70 { return String(localized: "平稳") }
            return String(localized: "偏少")
        case .activity:
            guard let activityScore else { return String(localized: "进行中") }
            if activityScore >= 85 { return String(localized: "在线") }
            if activityScore >= 65 { return String(localized: "不错") }
            return String(localized: "该动了")
        case .hydration:
            guard let hydrationScore else { return String(localized: "已同步") }
            if hydrationScore >= 85 { return String(localized: "充足") }
            if hydrationScore >= 60 { return String(localized: "记得喝水") }
            return String(localized: "不足")
        case .bodyAge:
            if let age = vitals.bodyAgeValueYears, age <= 28 { return String(localized: "年轻") }
            if vitals.bodyAgeValueYears != nil { return String(localized: "可优化") }
            return String(localized: "待生成")
        }
    }

    private static func headlineText(
        template: SharedComplicationTemplate,
        vitals: SharedComplicationVitals,
        recoveryScore: Int?,
        sleepScore: Int?,
        activityScore: Int?,
        hydrationScore: Int?
    ) -> String {
        switch template {
        case .overview:
            return String(localized: "恢复 \(intText(recoveryScore)) · 睡眠 \(intText(sleepScore))")
        case .recovery:
            return String(localized: "恢复 \(intText(recoveryScore))")
        case .sleep:
            return String(localized: "睡眠 \(intText(vitals.sleepDurationMinutes, suffix: "m"))")
        case .activity:
            return String(localized: "步数 \(intText(vitals.steps))")
        case .hydration:
            return String(localized: "饮水 \(intText(vitals.waterIntakeMl, suffix: "ml"))")
        case .bodyAge:
            return String(localized: "体龄 \(intText(vitals.bodyAgeValueYears, suffix: String(localized: "岁")))")
        }
    }

    private static func subheadlineText(
        template: SharedComplicationTemplate,
        vitals: SharedComplicationVitals,
        freshness: String,
        isStale: Bool
    ) -> String {
        if isStale { return String(localized: "数据较旧 · \(freshness)") }
        switch template {
        case .overview:
            return vitals.healthSummary ?? String(localized: "综合查看今日状态")
        case .recovery:
            return vitals.recoveryTrend.map { String(localized: "趋势 \($0)") } ?? String(localized: "恢复参考 \(freshness)")
        case .sleep:
            return String(localized: "得分 \(intText(vitals.sleepScore)) · \(freshness)")
        case .activity:
            return String(localized: "完成度 \(percentText(vitals.activityCompletionRate)) · \(freshness)")
        case .hydration:
            return String(localized: "完成度 \(percentText(vitals.waterCompletionRate)) · \(freshness)")
        case .bodyAge:
            return vitals.bodyAgeStatusText ?? String(localized: "查看体龄建议")
        }
    }

    private static func inlineText(
        template: SharedComplicationTemplate,
        status: String,
        freshness: String,
        hasVitals: Bool,
        isStale: Bool
    ) -> String {
        guard hasVitals else { return String(localized: "眠屿 · 待同步") }
        let state = isStale ? String(localized: "数据较旧") : status
        return "\(template.shortTitle) \(state) · \(freshness)"
    }

    private static func metrics(
        template: SharedComplicationTemplate,
        vitals: SharedComplicationVitals,
        recoveryScore: Int?,
        sleepScore: Int?,
        activityScore: Int?,
        hydrationScore: Int?,
        status: String
    ) -> ((title: String, value: String), (title: String, value: String), (title: String, value: String)) {
        switch template {
        case .overview:
            return ((String(localized: "恢复"), intText(recoveryScore)), (String(localized: "睡眠"), intText(sleepScore)), (String(localized: "活动"), percentText(vitals.activityCompletionRate)))
        case .recovery:
            return (("HRV", intText(vitals.hrv, suffix: "ms")), (String(localized: "压力"), intText(vitals.stress)), (String(localized: "睡眠"), intText(sleepScore)))
        case .sleep:
            return ((String(localized: "时长"), durationText(vitals.sleepDurationMinutes)), (String(localized: "得分"), intText(sleepScore)), (String(localized: "鼾声"), snoreText(intensity: vitals.sleepSnoreIntensity, durationMinutes: vitals.sleepSnoreDurationMinutes)))
        case .activity:
            return ((String(localized: "步数"), intText(vitals.steps)), (String(localized: "能量"), intText(vitals.activeEnergy, suffix: "kcal")), (String(localized: "运动"), intText(vitals.exerciseMinutes, suffix: "m")))
        case .hydration:
            return ((String(localized: "饮水"), intText(vitals.waterIntakeMl, suffix: "ml")), (String(localized: "完成度"), percentText(vitals.waterCompletionRate)), (String(localized: "咖啡因"), intText(vitals.caffeineRemainedMg, suffix: "mg")))
        case .bodyAge:
            return ((String(localized: "体龄"), intText(vitals.bodyAgeValueYears, suffix: String(localized: "岁"))), (String(localized: "状态"), vitals.bodyAgeStatusText ?? status), (String(localized: "摘要"), vitals.healthSummary ?? "--"))
        }
    }

    private static func gaugeValue(
        template: SharedComplicationTemplate,
        recoveryScore: Int?,
        overviewScore: Int?,
        sleepScore: Int?,
        activityScore: Int?,
        hydrationScore: Int?,
        vitals: SharedComplicationVitals
    ) -> Double? {
        switch template {
        case .overview:
            return overviewScore.map(Double.init)
        case .recovery:
            return recoveryScore.map(Double.init)
        case .sleep:
            return sleepScore.map(Double.init)
        case .activity:
            return activityScore.map(Double.init)
        case .hydration:
            return hydrationScore.map(Double.init)
        case .bodyAge:
            return vitals.bodyAgeValueYears.map { max(18, min($0, 60)) }
        }
    }

    private static func gaugeRange(template: SharedComplicationTemplate) -> ClosedRange<Double> {
        switch template {
        case .overview, .recovery, .sleep, .activity, .hydration:
            return 0...100
        case .bodyAge:
            return 18...60
        }
    }
}
