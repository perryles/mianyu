import Foundation

/// 心律稳定性卡片/详情页的展示语气，UI 层再映射到具体色板。
nonisolated enum HeartRhythmStabilityTone: String, Sendable {
    case positive
    case normal
    case caution
    case muted
}

/// 详情页三分类分布项。
nonisolated struct HeartRhythmDistributionItem: Sendable, Identifiable {
    let id: String
    let title: String
    let count: Int
    let tone: HeartRhythmStabilityTone
}

nonisolated struct HeartRhythmOverviewMetric: Sendable, Equatable {
    let title: String
    let value: String
    let detail: String
}

/// 心律稳定性文案与展示辅助，纯值输出、无 UI 依赖，定位为"参考、非医疗诊断"。
nonisolated enum HeartRhythmStabilityPresentation {
    static let title = "心律稳定性"
    static let subtitle = "综合房颤负担、心律不齐通知与 ECG 结论，给出心律稳定性参考。"
    static let referenceBadge = "参考指标 · 非医疗诊断"

    // MARK: 卡片状态

    /// 卡片主状态文案：未见异常 / 疑似早搏 / 疑似房颤 / 暂无。
    static func statusText(for result: HeartRhythmStabilityResult) -> String {
        guard result.hasData else { return "暂无" }
        if result.suspectedAtrialFibrillationCount > 0 { return "疑似房颤" }
        if result.suspectedEctopicCount > 0 { return "疑似早搏" }
        return "未见异常"
    }

    static func tone(for result: HeartRhythmStabilityResult) -> HeartRhythmStabilityTone {
        guard result.hasData else { return .muted }
        switch result.band {
        case .steady: return .positive
        case .watch: return .caution
        case .elevated: return .caution
        case .unavailable: return .muted
        }
    }

    /// 卡片主数值：有分数显示分数，否则回退状态文案。
    static func valueText(for result: HeartRhythmStabilityResult) -> String {
        guard let score = result.score else { return "--" }
        return "\(score)"
    }

    static func unitText(for result: HeartRhythmStabilityResult) -> String {
        "分"
    }

    static func overviewMetrics(for result: HeartRhythmStabilityResult) -> [HeartRhythmOverviewMetric] {
        let abnormalClueCount = result.suspectedAtrialFibrillationCount + result.suspectedEctopicCount
        return [
            .init(title: "稳定评分", value: result.score.map(String.init) ?? "暂无", detail: "综合当前心律证据得到的参考分数"),
            .init(title: "分类记录", value: "\(result.classifiedTotal) 次", detail: "纳入判断的房颤、通知与 ECG 记录"),
            .init(title: "异常线索", value: "\(abnormalClueCount) 次", detail: "疑似房颤与异常搏动线索合计"),
            .init(title: "心率事件", value: "\(result.heartRateEventCount) 次", detail: "观察窗口内的高低心率事件")
        ]
    }

    // MARK: 详情摘要

    static func summary(for result: HeartRhythmStabilityResult) -> String {
        guard result.hasData else {
            return String(localized: "尚未读取到房颤负担、心律不齐通知或 ECG 结论。佩戴支持心律监测的 Apple Watch 并开启相关功能后，这里会显示心律稳定性参考。")
        }
        switch result.band {
        case .steady:
            return String(localized: "观察窗口内未见明显心律异常线索，心律相对平稳。继续保持规律作息与佩戴监测即可。")
        case .watch:
            return String(localized: "观察窗口内出现少量心律异常线索，建议持续留意后续变化。如伴随心悸、胸闷等不适，请及时就医核实。")
        case .elevated:
            return String(localized: "观察窗口内出现较多心律异常线索，建议尽快就医核实，并携带 Apple 健康中的 ECG 与心律记录供医生参考。")
        case .unavailable:
            return String(localized: "心律证据不足，暂不给出结论。")
        }
    }

    // MARK: 风险提示 bullets

    static func riskBullets(for result: HeartRhythmStabilityResult) -> [String] {
        guard result.hasData else {
            return [String(localized: "证据不足，暂无风险提示。")]
        }
        var bullets: [String] = []
        if result.suspectedAtrialFibrillationCount > 0 {
            bullets.append(String(localized: "疑似房颤线索 \(result.suspectedAtrialFibrillationCount) 次（含心律不齐通知与 ECG 房颤结论），房颤可能增加卒中风险，建议就医评估。"))
        }
        if result.suspectedEctopicCount > 0 {
            bullets.append(String(localized: "异常搏动线索 \(result.suspectedEctopicCount) 次（ECG 结果不确定），偶发早搏多为良性，但频繁出现建议就医。"))
        }
        if result.heartRateEventCount > 0 {
            bullets.append(String(localized: "高/低心率事件 \(result.heartRateEventCount) 次，可能与运动、情绪或睡眠有关，如反复出现请留意。"))
        }
        if bullets.isEmpty {
            bullets.append(String(localized: "观察窗口内未见明显异常线索，保持规律作息与佩戴监测。"))
        }
        return bullets
    }

    // MARK: 就医建议与免责声明

    static let medicalAdvice = "本指标为事件聚合的参考估算，不能替代医生诊断。如出现持续心悸、胸痛、晕厥或呼吸困难，请立即就医。"

    static let disclaimer = "心律稳定性基于 Apple 健康中的房颤负担、心律不齐通知、高/低心率事件与 ECG 结论聚合估算，用于健康参考，不构成医疗诊断或治疗建议。数据主要来自 Apple Watch，未佩戴时可能无数据。"

    // MARK: 三分类分布

    static func distributionItems(for result: HeartRhythmStabilityResult) -> [HeartRhythmDistributionItem] {
        [
            HeartRhythmDistributionItem(
                id: "normal",
                title: "未见异常",
                count: result.normalCount,
                tone: .positive
            ),
            HeartRhythmDistributionItem(
                id: "ectopic",
                title: "疑似早搏",
                count: result.suspectedEctopicCount,
                tone: .caution
            ),
            HeartRhythmDistributionItem(
                id: "afib",
                title: "疑似房颤",
                count: result.suspectedAtrialFibrillationCount,
                tone: .caution
            )
        ]
    }

    /// 主要异常来源文案，用于详情页解释扣分依据。
    static func signalDescription(_ kind: HeartRhythmSignalKind) -> String {
        switch kind {
        case .atrialFibrillationBurden:
            return String(localized: "房颤负担百分比偏高")
        case .irregularRhythmEvent:
            return String(localized: "心律不齐通知")
        case .ecgAtrialFibrillation:
            return String(localized: "ECG 房颤结论")
        case .ecgInconclusive:
            return String(localized: "ECG 结果不确定")
        case .highHeartRateEvent:
            return String(localized: "高心率事件")
        case .lowHeartRateEvent:
            return String(localized: "低心率事件")
        }
    }
}
