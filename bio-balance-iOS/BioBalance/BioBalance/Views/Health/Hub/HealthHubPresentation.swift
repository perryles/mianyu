/// HealthHubPresentation 作为健康模块的支撑类型，负责定义健康能力域分类。
/// 负责描述身体基础、生活方式、专项照护三个域的标题与配色。

import Foundation

enum HealthHubReferenceLayout {
    static let featuredAction: HealthHubQuickAction = .sleep

    static func actionColumnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 1 : 2
    }

    static func toolColumnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 1 : 2
    }

    static func reviewColumnCount(availableWidth: CGFloat, isAccessibilitySize: Bool) -> Int {
        guard !isAccessibilitySize else { return 1 }
        return availableWidth >= 600 ? 3 : 1
    }

    static func toolRowCount(itemCount: Int, isAccessibilitySize: Bool) -> Int {
        let itemCount = max(0, itemCount)
        let columns = toolColumnCount(isAccessibilitySize: isAccessibilitySize)
        return (itemCount + columns - 1) / columns
    }
}

enum HealthQuickActionGridLayout {
    static func columnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 2 : 3
    }
}

enum HealthToolGridLayout {
    static let expandedColumnCount = 1

    static func expandedRowCount(itemCount: Int) -> Int {
        let itemCount = max(0, itemCount)
        return (itemCount + expandedColumnCount - 1) / expandedColumnCount
    }
}

enum HealthCapabilityDomain: String, CaseIterable, Identifiable, Sendable {
    case bodyFoundation
    case lifestyle
    case specialtyCare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyFoundation: return String(localized: "身体基础")
        case .lifestyle: return String(localized: "生活方式")
        case .specialtyCare: return String(localized: "专项照护")
        }
    }

    var subtitle: String {
        switch self {
        case .bodyFoundation: return String(localized: "身体数据、体能与长期画像")
        case .lifestyle: return String(localized: "每天可以记录和改善的生活习惯")
        case .specialtyCare: return String(localized: "阶段性照护、用药与健康协作")
        }
    }

    var tintHex: String {
        switch self {
        case .bodyFoundation: return "1B9266"
        case .lifestyle: return "5B8CFF"
        case .specialtyCare: return "8B5CF6"
        }
    }
}

enum HealthHubToolCategory: String, CaseIterable, Identifiable, Sendable {
    case common
    case exercise
    case body
    case metabolism
    case records
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common: return String(localized: "常用")
        case .exercise: return String(localized: "运动")
        case .body: return String(localized: "身体")
        case .metabolism: return String(localized: "代谢")
        case .records: return String(localized: "记录")
        case .other: return String(localized: "其他")
        }
    }

    var symbol: String {
        switch self {
        case .common: return "star.fill"
        case .exercise: return "figure.run"
        case .body: return "figure.arms.open"
        case .metabolism: return "flame.fill"
        case .records: return "list.clipboard"
        case .other: return "ellipsis"
        }
    }
}

enum HealthCapabilityGroupStyle: String, Sendable {
    case metricBand
    case portraitList
    case compactSignals
    case iconRail
    case editorialRows
}

enum HealthCapabilityItem: String, CaseIterable, Hashable, Identifiable, Sendable {
    case fitness
    case activeEnergy
    case basalEnergy
    case bodyAge
    case bodyProfile
    case healthProfile
    case wristTemperature
    case walkingAsymmetry
    case dailyAction
    case drink
    case meal
    case mood
    case sedentary
    case environmentNoise
    case medicationSymptoms
    case reproductiveHealth
    case friends

    var id: String { rawValue }

    /// Only the expanded tool grid uses these explanations; measurement and recording entries stay distinct.
    var toolExplanation: String? {
        switch self {
        case .activeEnergy: return String(localized: "活动产生的能量消耗，不含静息消耗")
        case .basalEnergy: return String(localized: "静息时的能量消耗，不是每日总消耗")
        case .bodyAge: return String(localized: "依据身体数据估算，仅供长期趋势参考")
        case .bodyProfile: return String(localized: "查看身高、体重与 BMI，补全身体资料")
        case .wristTemperature: return String(localized: "睡眠期间的手腕温度，并非体温计读数")
        case .walkingAsymmetry: return String(localized: "查看已同步的步态不对称比例")
        case .dailyAction: return String(localized: "查看今日计划与完成进度")
        case .sedentary: return String(localized: "回顾活动间隔与久坐提醒")
        case .environmentNoise: return String(localized: "查看已同步的环境声音暴露，并非实时测声")
        case .reproductiveHealth: return String(localized: "记录周期与身体变化，不作诊断或避孕依据")
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .fitness: return "健身"
        case .activeEnergy: return "活动消耗"
        case .basalEnergy: return "基础代谢"
        case .bodyAge: return "身体年龄"
        case .bodyProfile: return "身体档案"
        case .healthProfile: return "健康档案"
        case .wristTemperature: return "手腕温度"
        case .walkingAsymmetry: return "步态不对称"
        case .dailyAction: return "每日行动"
        case .drink: return "饮品"
        case .meal: return "餐食"
        case .mood: return "情绪"
        case .sedentary: return "久坐"
        case .environmentNoise: return "环境噪声"
        case .medicationSymptoms: return String(localized: "用药与症状")
        case .reproductiveHealth: return "周期健康"
        case .friends: return "健康共享"
        }
    }

    var symbol: String {
        switch self {
        case .fitness: return "figure.run"
        case .activeEnergy: return "flame.fill"
        case .basalEnergy: return "bolt.heart.fill"
        case .bodyAge: return "figure.arms.open"
        case .bodyProfile: return "ruler.fill"
        case .healthProfile: return "person.crop.circle.badge.checkmark"
        case .wristTemperature: return "thermometer.medium"
        case .walkingAsymmetry: return "figure.walk.motion"
        case .dailyAction: return "target"
        case .drink: return "drop.fill"
        case .meal: return "fork.knife"
        case .mood: return "face.smiling.inverse"
        case .sedentary: return "figure.seated.side.right"
        case .environmentNoise: return "ear"
        case .medicationSymptoms: return "pills.fill"
        case .reproductiveHealth: return "heart.circle.fill"
        case .friends: return "person.2.fill"
        }
    }

    var tintHex: String {
        switch self {
        case .fitness, .dailyAction: return "1B9266"
        case .activeEnergy: return "E26B4F"
        case .basalEnergy: return "F3A53B"
        case .bodyAge: return "6D7EF7"
        case .bodyProfile: return "91C783"
        case .healthProfile: return "3AA887"
        case .wristTemperature: return "8266C6"
        case .walkingAsymmetry: return "33A6DA"
        case .drink: return "58D5E5"
        case .meal: return "F46B5A"
        case .mood: return "39B98A"
        case .sedentary: return "F3A53B"
        case .environmentNoise: return "D3A72C"
        case .medicationSymptoms: return "6B7CFF"
        case .reproductiveHealth: return "F35F9B"
        case .friends: return "FF7A59"
        }
    }
}

struct HealthCapabilityGroup: Identifiable, Equatable, Sendable {
    let id: String
    let domain: HealthCapabilityDomain
    let title: String
    let subtitle: String
    let style: HealthCapabilityGroupStyle
    let items: [HealthCapabilityItem]
}

struct HealthCapabilityDomainSection: Identifiable, Equatable, Sendable {
    var id: HealthCapabilityDomain { domain }
    let domain: HealthCapabilityDomain
    let groups: [HealthCapabilityGroup]
}

enum HealthHubQuickAction: Identifiable, Equatable, Sendable {
    case capability(HealthCapabilityItem)
    case sleep

    var id: String {
        switch self {
        case .capability(let item): return item.id
        case .sleep: return "sleep"
        }
    }

    var title: String {
        switch self {
        case .capability(let item): return item.title
        case .sleep: return String(localized: "睡眠")
        }
    }

    var symbol: String {
        switch self {
        case .capability(let item): return item.symbol
        case .sleep: return "moon.zzz.fill"
        }
    }

    var tintHex: String {
        switch self {
        case .capability(let item): return item.tintHex
        case .sleep: return "8266C6"
        }
    }
}

struct HealthHubFocusItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case recommendation
        case risk
        case change
        case building
    }

    enum Emphasis: String, Sendable {
        case urgent
        case observe
        case maintain
        case building
    }

    let id: String
    let title: String
    let reason: String
    let detail: String
    let evidenceText: String
    let badgeText: String
    let module: HealthProfileModule
    let kind: Kind
    let emphasis: Emphasis
}

struct HealthHubFocusSectionCopy: Equatable, Sendable {
    let title: String
    let subtitle: String
}

struct HealthHubProfileMetric: Equatable, Sendable {
    let valueText: String
    let title: String
    let progress: Int
}

enum HealthHubPresentationBuilder {
    static func isMissingToolValue(_ value: String) -> Bool {
        ["", "--", "暂无", "暂无数据"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func toolValueText(value: String, unit: String) -> String {
        guard !isMissingToolValue(value) else { return String(localized: "暂无数据") }
        return [value, unit].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func profileExplanation(from summary: HealthProfileSummary?) -> String {
        guard let summary else {
            return String(localized: "长期档案尚未形成。先查看已同步的身体数据，也可以补充日常记录。")
        }
        return summary.isBuilding
            ? String(localized: "档案依据反映样本完整度，不是健康评分。继续积累记录后再观察长期变化。")
            : String(localized: "成长分用于回顾近期记录形成的长期变化，不代表今天的状态或医学诊断。")
    }

    static let referenceQuickActions: [HealthHubQuickAction] = [
        .capability(.dailyAction),
        .capability(.drink),
        .capability(.meal),
        .capability(.mood)
    ]

    static let quickActions: [HealthHubQuickAction] = [
        .capability(.dailyAction),
        .capability(.drink),
        .capability(.meal),
        .capability(.mood),
        .capability(.fitness),
        .sleep
    ]

    static let allCapabilities: [HealthCapabilityItem] = [
        .fitness,
        .activeEnergy,
        .basalEnergy,
        .bodyAge,
        .bodyProfile,
        .healthProfile,
        .wristTemperature,
        .walkingAsymmetry,
        .dailyAction,
        .drink,
        .meal,
        .mood,
        .sedentary,
        .environmentNoise,
        .medicationSymptoms,
        .reproductiveHealth,
        .friends
    ]

    /// 首页上方已有独立入口的功能，不在下方健康工具中重复展示。
    private static let featuredHealthCapabilities: Set<HealthCapabilityItem> = [
        .fitness, .healthProfile, .drink, .meal, .mood, .medicationSymptoms, .friends
    ]

    static let healthToolCapabilities = allCapabilities.filter {
        !featuredHealthCapabilities.contains($0)
    }

    static let collapsedCapabilities: [HealthCapabilityItem] = [
        .healthProfile,
        .activeEnergy,
        .bodyAge,
        .bodyProfile,
        .drink,
        .medicationSymptoms
    ]

    static func profileMetric(from summary: HealthProfileSummary?) -> HealthHubProfileMetric {
        guard let summary else {
            return HealthHubProfileMetric(
                valueText: "--",
                title: String(localized: "档案依据"),
                progress: 0
            )
        }

        let value = summary.isBuilding ? summary.dataQuality.score : summary.growthScore
        return HealthHubProfileMetric(
            valueText: summary.isBuilding && value == 0 ? "--" : String(value),
            title: summary.isBuilding ? String(localized: "档案依据") : String(localized: "成长分"),
            progress: min(max(value, 0), 100)
        )
    }

    static func capabilities(in category: HealthHubToolCategory) -> [HealthCapabilityItem] {
        switch category {
        case .common:
            return [.fitness, .activeEnergy, .basalEnergy, .bodyAge, .bodyProfile, .healthProfile, .wristTemperature, .walkingAsymmetry]
        case .exercise:
            return [.fitness, .activeEnergy, .walkingAsymmetry]
        case .body:
            return [.bodyAge, .bodyProfile, .healthProfile, .wristTemperature]
        case .metabolism:
            return [.activeEnergy, .basalEnergy, .meal, .drink]
        case .records:
            return [.dailyAction, .drink, .meal, .mood, .healthProfile, .medicationSymptoms, .reproductiveHealth]
        case .other:
            return [.sedentary, .environmentNoise, .medicationSymptoms, .reproductiveHealth, .friends]
        }
    }

    static let domainSections: [HealthCapabilityDomainSection] = [
        HealthCapabilityDomainSection(
            domain: .bodyFoundation,
            groups: [
                HealthCapabilityGroup(
                    id: "body-fitness-metabolism",
                    domain: .bodyFoundation,
                    title: "体能与代谢",
                    subtitle: "训练投入与全天能量节律",
                    style: .metricBand,
                    items: [.fitness, .activeEnergy, .basalEnergy]
                ),
                HealthCapabilityGroup(
                    id: "body-portrait",
                    domain: .bodyFoundation,
                    title: "身体画像",
                    subtitle: "从单次数值走向长期健康画像",
                    style: .portraitList,
                    items: [.bodyAge, .bodyProfile, .healthProfile]
                ),
                HealthCapabilityGroup(
                    id: "body-signals",
                    domain: .bodyFoundation,
                    title: "关键体征",
                    subtitle: "观察细微但值得持续跟踪的变化",
                    style: .compactSignals,
                    items: [.wristTemperature, .walkingAsymmetry]
                )
            ]
        ),
        HealthCapabilityDomainSection(
            domain: .lifestyle,
            groups: [
                HealthCapabilityGroup(
                    id: "lifestyle-daily-plan",
                    domain: .lifestyle,
                    title: "日常计划",
                    subtitle: "今天就能完成的健康记录",
                    style: .iconRail,
                    items: [.dailyAction, .drink, .meal]
                ),
                HealthCapabilityGroup(
                    id: "lifestyle-recovery",
                    domain: .lifestyle,
                    title: "恢复与行为",
                    subtitle: "情绪和久坐同样影响恢复质量",
                    style: .editorialRows,
                    items: [.mood, .sedentary]
                ),
                HealthCapabilityGroup(
                    id: "lifestyle-environment",
                    domain: .lifestyle,
                    title: "环境健康",
                    subtitle: "留意日常环境里的隐性负担",
                    style: .editorialRows,
                    items: [.environmentNoise]
                )
            ]
        ),
        HealthCapabilityDomainSection(
            domain: .specialtyCare,
            groups: [
                HealthCapabilityGroup(
                    id: "care-medication-symptoms",
                    domain: .specialtyCare,
                    title: "用药与症状",
                    subtitle: "把用药任务与身体感受放在一起看",
                    style: .editorialRows,
                    items: [.medicationSymptoms]
                ),
                HealthCapabilityGroup(
                    id: "care-reproductive",
                    domain: .specialtyCare,
                    title: "生殖健康",
                    subtitle: "记录周期和阶段性的身体变化",
                    style: .editorialRows,
                    items: [.reproductiveHealth]
                ),
                HealthCapabilityGroup(
                    id: "care-sharing",
                    domain: .specialtyCare,
                    title: "共享支持",
                    subtitle: "与可信任的人建立健康协作",
                    style: .editorialRows,
                    items: [.friends]
                )
            ]
        )
    ]

    static func focusItems(from summary: HealthProfileSummary?) -> [HealthHubFocusItem] {
        guard let summary else {
            return [
                HealthHubFocusItem(
                    id: "building-health-profile",
                    title: String(localized: "长期档案正在整理"),
                    reason: String(localized: "当前还没有形成足够稳定的长期样本。"),
                    detail: String(localized: "同步睡眠、心率、活动和日常记录后，会开始形成更可靠的健康重点。"),
                    evidenceText: String(localized: "等待本地健康样本"),
                    badgeText: String(localized: "建立中"),
                    module: .healthKit,
                    kind: .building,
                    emphasis: .building
                )
            ]
        }

        if summary.isBuilding {
            return [
                HealthHubFocusItem(
                    id: "building-health-profile",
                    title: summary.headline,
                    reason: summary.dataQuality.summary,
                    detail: buildingActionText(for: summary),
                    evidenceText: evidenceText(for: .healthKit, summary: summary),
                    badgeText: summary.dataQuality.confidence.title,
                    module: .healthKit,
                    kind: .building,
                    emphasis: .building
                )
            ]
        }

        let recommendationCandidates = summary.actionRecommendations.map { recommendation in
            FocusCandidate(
                item: HealthHubFocusItem(
                    id: "recommendation-\(recommendation.id)",
                    title: recommendation.title,
                    reason: recommendation.reason,
                    detail: recommendation.detail,
                    evidenceText: evidenceText(for: recommendation.module, summary: summary),
                    badgeText: recommendation.priority.title,
                    module: recommendation.module,
                    kind: .recommendation,
                    emphasis: recommendation.priority == .high ? .urgent : (recommendation.priority == .medium ? .observe : .maintain)
                ),
                score: recommendationWeight(recommendation.priority)
                    + dataAdjustment(for: recommendation.module, summary: summary),
                typeOrder: recommendationTypeOrder(recommendation.priority)
            )
        }
        let riskCandidates = summary.riskTendencies.map { risk in
            FocusCandidate(
                item: HealthHubFocusItem(
                    id: "risk-\(risk.id)",
                    title: risk.title,
                    reason: risk.detail,
                    detail: risk.suggestion,
                    evidenceText: evidenceText(for: risk.module, summary: summary),
                    badgeText: String(localized: "留意"),
                    module: risk.module,
                    kind: .risk,
                    emphasis: .urgent
                ),
                score: 110 + dataAdjustment(for: risk.module, summary: summary),
                typeOrder: 2
            )
        }
        let changeCandidates = summary.changes.map { change in
            FocusCandidate(
                item: HealthHubFocusItem(
                    id: "change-\(change.id)",
                    title: change.title,
                    reason: change.detail,
                    detail: nextStepText(for: change.relatedModule, kind: change.kind),
                    evidenceText: evidenceText(for: change.relatedModule, summary: summary),
                    badgeText: changeBadge(change.kind),
                    module: change.relatedModule,
                    kind: .change,
                    emphasis: changeEmphasis(change.kind)
                ),
                score: changeWeight(change.kind)
                    + dataAdjustment(for: change.relatedModule, summary: summary),
                typeOrder: changeTypeOrder(change.kind)
            )
        }

        let sortedCandidates = (recommendationCandidates + riskCandidates + changeCandidates)
            .sorted(by: candidateComesFirst)

        var seenModules: Set<HealthProfileModule> = []
        var seenTitles: Set<String> = []
        var result: [HealthHubFocusItem] = []
        for candidate in sortedCandidates {
            let item = candidate.item
            guard !seenModules.contains(item.module), !seenTitles.contains(item.title) else { continue }
            seenModules.insert(item.module)
            seenTitles.insert(item.title)
            result.append(item)
            if result.count == 3 { break }
        }

        if result.isEmpty {
            return [
                HealthHubFocusItem(
                    id: "stable-health-profile",
                    title: String(localized: "继续保持当前节律"),
                    reason: summary.headline,
                    detail: String(localized: "继续记录睡眠、活动和日常感受，等待下一次稳定变化出现。"),
                    evidenceText: evidenceText(for: .healthKit, summary: summary),
                    badgeText: summary.status.title,
                    module: .healthKit,
                    kind: .change,
                    emphasis: .maintain
                )
            ]
        }
        return result
    }

    static func focusSectionCopy(for items: [HealthHubFocusItem]) -> HealthHubFocusSectionCopy {
        if items.contains(where: { $0.emphasis == .urgent }) {
            return HealthHubFocusSectionCopy(
                title: String(localized: "现在最值得关注"),
                subtitle: String(localized: "先看影响更大、依据更完整的一项")
            )
        }
        if items.contains(where: { $0.emphasis == .observe }) {
            return HealthHubFocusSectionCopy(
                title: String(localized: "接下来值得观察"),
                subtitle: String(localized: "这些变化还需要连续记录，不根据单次结果下结论")
            )
        }
        if items.allSatisfy({ $0.emphasis == .building }) {
            return HealthHubFocusSectionCopy(
                title: String(localized: "档案正在形成"),
                subtitle: String(localized: "先补齐本地样本，重点会随着数据稳定下来")
            )
        }
        return HealthHubFocusSectionCopy(
            title: String(localized: "目前值得继续保持"),
            subtitle: String(localized: "暂时没有需要优先处理的变化，继续观察长期节律")
        )
    }

    static var allDomainItems: [HealthCapabilityItem] {
        domainSections.flatMap(\.groups).flatMap(\.items)
    }

    static func capabilities(in domain: HealthCapabilityDomain) -> [HealthCapabilityItem] {
        domainSections
            .first(where: { $0.domain == domain })?
            .groups
            .flatMap(\.items) ?? []
    }

    private struct FocusCandidate {
        let item: HealthHubFocusItem
        let score: Int
        let typeOrder: Int
    }

    private nonisolated static func candidateComesFirst(_ lhs: FocusCandidate, _ rhs: FocusCandidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.typeOrder != rhs.typeOrder { return lhs.typeOrder < rhs.typeOrder }
        if lhs.item.module.rawValue != rhs.item.module.rawValue {
            return lhs.item.module.rawValue < rhs.item.module.rawValue
        }
        return lhs.item.title < rhs.item.title
    }

    private static func recommendationWeight(_ priority: HealthProfileActionPriority) -> Int {
        switch priority {
        case .high: return 120
        case .medium: return 90
        case .low: return 55
        }
    }

    private static func recommendationTypeOrder(_ priority: HealthProfileActionPriority) -> Int {
        switch priority {
        case .high: return 0
        case .medium: return 3
        case .low: return 5
        }
    }

    private static func changeWeight(_ kind: HealthProfileChangeKind) -> Int {
        switch kind {
        case .risk: return 115
        case .observing: return 72
        case .stable: return 45
        case .positive: return 40
        }
    }

    private static func changeTypeOrder(_ kind: HealthProfileChangeKind) -> Int {
        switch kind {
        case .risk: return 1
        case .observing: return 4
        case .stable: return 6
        case .positive: return 7
        }
    }

    private static func dataAdjustment(
        for module: HealthProfileModule,
        summary: HealthProfileSummary
    ) -> Int {
        guard let completeness = completeness(for: module, in: summary.dataCompleteness) else { return 0 }
        switch completeness.state {
        case .synced: return 0
        case .generated: return -5
        case .insufficient: return -24
        case .unauthorized: return -36
        case .notEnabled, .notApplicable: return 0
        }
    }

    private static func evidenceText(
        for module: HealthProfileModule,
        summary: HealthProfileSummary
    ) -> String {
        let days = summary.range.dayCount
        guard let completeness = completeness(for: module, in: summary.dataCompleteness) else {
            return String(localized: "近 \(days) 天 · 等待更多模块依据")
        }
        switch completeness.state {
        case .synced:
            if completeness.sampleCount > 0 {
                return String(localized: "近 \(days) 天 · \(completeness.sampleCount) 个有效样本")
            }
            return String(localized: "近 \(days) 天 · 数据已同步")
        case .generated:
            return String(localized: "近 \(days) 天 · 本地推导结果")
        case .insufficient:
            return String(localized: "近 \(days) 天 · 仅 \(completeness.sampleCount) 个样本")
        case .unauthorized:
            return String(localized: "近 \(days) 天 · 授权尚未完整")
        case .notEnabled:
            return String(localized: "近 \(days) 天 · 记录尚未启用")
        case .notApplicable:
            return String(localized: "近 \(days) 天 · 当前不适用")
        }
    }

    private static func completeness(
        for module: HealthProfileModule,
        in rows: [HealthProfileDataCompleteness]
    ) -> HealthProfileDataCompleteness? {
        let title: String
        switch module {
        case .sleep: title = "睡眠"
        case .stress: title = "压力"
        case .activity: title = "活动"
        case .sedentary, .habits: title = "习惯记录"
        case .reproductive: title = "周期健康"
        case .symptoms: title = "症状观察"
        case .healthKit: title = "心率与 HRV"
        }
        return rows.first { $0.title == title }
    }

    private static func nextStepText(
        for module: HealthProfileModule,
        kind: HealthProfileChangeKind
    ) -> String {
        if kind == .positive || kind == .stable {
            return String(localized: "继续保持当前安排，并在详情里观察这项变化能否稳定延续。")
        }
        switch module {
        case .sleep: return String(localized: "进入睡眠页确认昨夜重点，并选择今晚最容易完成的一项调整。")
        case .stress: return String(localized: "进入压力详情，先确认波动时段，再安排一次短恢复。")
        case .activity: return String(localized: "进入健身记录，按今天的恢复状态调整活动强度。")
        case .sedentary: return String(localized: "进入久坐详情，先打断今天最长的一段连续久坐。")
        case .habits: return String(localized: "进入每日行动，先完成一项最小可执行动作。")
        case .reproductive: return String(localized: "进入周期健康记录，补充当前阶段与身体感受。")
        case .symptoms: return String(localized: "进入用药与症状回看，确认最近记录是否集中出现。")
        case .healthKit: return String(localized: "查看档案依据，补齐缺少的授权或样本。")
        }
    }

    private static func buildingActionText(for summary: HealthProfileSummary) -> String {
        if !summary.dataQuality.unauthorizedModules.isEmpty {
            return String(localized: "先检查健康权限，再继续积累可用样本。")
        }
        return String(localized: "继续同步睡眠、心率与活动，让长期重点逐步稳定。")
    }

    private static func changeBadge(_ kind: HealthProfileChangeKind) -> String {
        switch kind {
        case .positive: return String(localized: "改善")
        case .risk: return String(localized: "留意")
        case .stable: return String(localized: "稳定")
        case .observing: return String(localized: "观察中")
        }
    }

    private static func changeEmphasis(_ kind: HealthProfileChangeKind) -> HealthHubFocusItem.Emphasis {
        switch kind {
        case .risk: return .urgent
        case .observing: return .observe
        case .positive, .stable: return .maintain
        }
    }
}
