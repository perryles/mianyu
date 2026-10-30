/// BodyRecoveryPersonalization 作为今日页的支撑类型，负责定义身体恢复展示色调与因子种类。
/// 负责描述恢复状态分级（正面/中性/警示/严重）与因子分类（夜间恢复/日间压力/HRV/心率/活动负荷）。

import Foundation

nonisolated enum BodyRecoveryPresentationTone: String, Sendable, Hashable {
    case positive
    case neutral
    case caution
    case critical
}

nonisolated enum BodyRecoveryFactorKind: String, Sendable, CaseIterable, Hashable {
    case overnightRecovery
    case daytimeStress
    case hrv
    case heartRate
    case activityLoad
}

nonisolated struct BodyRecoveryFactorPresentation: Equatable, Sendable, Identifiable {
    let kind: BodyRecoveryFactorKind
    let title: String
    let valueText: String
    let detailText: String
    let symbol: String
    let tone: BodyRecoveryPresentationTone

    var id: BodyRecoveryFactorKind { kind }
}

nonisolated enum BodyRecoveryActionKind: String, Sendable, Hashable {
    case restoreFirst
    case protectSleep
    case decompress
    case reduceTraining
    case keepLoadLight
    case focusPriority
    case segmentTasks
    case recoveryBreak
    case reduceStimulation
}

nonisolated struct BodyRecoveryActionPresentation: Equatable, Sendable, Identifiable {
    let kind: BodyRecoveryActionKind
    let title: String
    let detailText: String
    let symbol: String
    let tone: BodyRecoveryPresentationTone

    var id: BodyRecoveryActionKind { kind }
}

nonisolated struct BodyRecoveryPersonalizationInput: Equatable, Sendable {
    let currentBodyBattery: Int?
    let overnightRecoveryScore: Int?
    let stressScore: Int?
    let nightlyHrv: Double?
    let baselineHrv: Double?
    let overnightHeartRate: Double?
    let baselineOvernightHeartRate: Double?
    let restingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let physicalEffortSampleCount: Int
    let workoutEventCount: Int
    let isCurrentDay: Bool
}

nonisolated struct BodyRecoveryPersonalization: Equatable, Sendable {
    let statusTitle: String
    let summary: String
    let budgetBadge: String
    let budgetSummary: String
    let tone: BodyRecoveryPresentationTone
    let factors: [BodyRecoveryFactorPresentation]
    let actions: [BodyRecoveryActionPresentation]
    let hasHealthData: Bool
    let shouldReturnToToday: Bool
}

/// 将身体电量引擎已经使用的真实信号整理成页面展示，不重复计算身体电量本身。
nonisolated enum BodyRecoveryPersonalizationEngine {
    static func make(input: BodyRecoveryPersonalizationInput) -> BodyRecoveryPersonalization {
        guard input.isCurrentDay else {
            return BodyRecoveryPersonalization(
                statusTitle: String(localized: "历史恢复趋势"),
                summary: String(localized: "当前展示的是所选周期的身体电量变化。个性化恢复建议只使用今天的实时健康信号。"),
                budgetBadge: String(localized: "历史周期"),
                budgetSummary: String(localized: "返回今天后可查看基于最新睡眠、压力和活动负荷生成的恢复安排。"),
                tone: .neutral,
                factors: [],
                actions: [],
                hasHealthData: false,
                shouldReturnToToday: true
            )
        }

        let factors = makeFactors(input: input)
        let hasHealthData = input.currentBodyBattery != nil
            || input.overnightRecoveryScore != nil
            || input.stressScore != nil
            || !factors.isEmpty

        guard hasHealthData else {
            return BodyRecoveryPersonalization(
                statusTitle: String(localized: "等待恢复数据"),
                summary: String(localized: "保持设备佩戴并同步健康数据后，这里会结合睡眠、HRV、心率、压力和活动负荷生成个人恢复建议。"),
                budgetBadge: String(localized: "等待同步"),
                budgetSummary: String(localized: "当前没有足够的真实信号，因此暂不生成具体的能量安排。"),
                tone: .neutral,
                factors: [],
                actions: [],
                hasHealthData: false,
                shouldReturnToToday: false
            )
        }

        let status = statusPresentation(bodyBattery: input.currentBodyBattery)
        return BodyRecoveryPersonalization(
            statusTitle: status.title,
            summary: personalizedSummary(input: input, fallback: status.summary),
            budgetBadge: budgetBadge(bodyBattery: input.currentBodyBattery),
            budgetSummary: budgetSummary(bodyBattery: input.currentBodyBattery),
            tone: status.tone,
            factors: factors,
            actions: makeActions(input: input),
            hasHealthData: true,
            shouldReturnToToday: false
        )
    }
}

nonisolated private extension BodyRecoveryPersonalizationEngine {
    static func statusPresentation(
        bodyBattery: Int?
    ) -> (title: String, summary: String, tone: BodyRecoveryPresentationTone) {
        guard let bodyBattery else {
            return (
                String(localized: "恢复线索已建立"),
                String(localized: "已经取得部分恢复信号；继续同步后，页面会补齐今天的身体电量和节奏判断。"),
                .neutral
            )
        }
        switch bodyBattery {
        case 80...:
            return (
                String(localized: "恢复余量充足"),
                String(localized: "今天的可用余量较充足，可以正常推进重点事项，同时给高消耗任务留出恢复间隔。"),
                .positive
            )
        case 55..<80:
            return (
                String(localized: "恢复状态可用"),
                String(localized: "今天仍有可用余量，更适合分段推进，避免把训练、深度工作和密集安排连续堆叠。"),
                .neutral
            )
        case 30..<55:
            return (
                String(localized: "恢复余量偏紧"),
                String(localized: "当前可用余量已经被压缩，先完成必要事项，并把补水、进食和轻活动安排得更靠前。"),
                .caution
            )
        default:
            return (
                String(localized: "优先恢复"),
                String(localized: "当前更接近恢复窗口，今天应减少额外刺激和高强度输出，把状态先拉回稳定区。"),
                .critical
            )
        }
    }

    static func personalizedSummary(
        input: BodyRecoveryPersonalizationInput,
        fallback: String
    ) -> String {
        if let stress = input.stressScore, stress >= 65,
           let recovery = input.overnightRecoveryScore, recovery < 60 {
            return String(localized: "昨夜恢复偏弱，同时今天的压力已经抬升；当前建议先降载，再保护今晚的睡眠窗口。")
        }
        if input.workoutEventCount > 0 || input.physicalEffortSampleCount > 0,
           let battery = input.currentBodyBattery, battery < 55 {
            return String(localized: "今天已经出现活动或训练负荷，当前身体电量偏紧；继续加量的收益有限，更适合转入轻恢复。")
        }
        if isHrvBelowBaseline(input), let battery = input.currentBodyBattery, battery < 70 {
            return String(localized: "HRV 低于个人恢复基线，且当前余量不算充足；今天把任务切短、减少连续输出会更稳。")
        }
        if isHeartRateAboveBaseline(input), let battery = input.currentBodyBattery, battery < 70 {
            return String(localized: "夜间或静息心率高于个人基线，当前更适合保守安排强度，并继续观察后续回落情况。")
        }
        return fallback
    }

    static func makeFactors(
        input: BodyRecoveryPersonalizationInput
    ) -> [BodyRecoveryFactorPresentation] {
        var factors: [BodyRecoveryFactorPresentation] = []

        if let recovery = input.overnightRecoveryScore {
            let tone: BodyRecoveryPresentationTone = recovery >= 75 ? .positive : recovery >= 55 ? .neutral : .caution
            let detail: String
            switch recovery {
            case 75...:
                detail = String(localized: "昨夜的睡眠与夜间生命体征为今天提供了较好的恢复起点。")
            case 55..<75:
                detail = String(localized: "昨夜恢复处在中段，今天仍需要给高消耗事项保留间隔。")
            default:
                detail = String(localized: "昨夜恢复起点偏低，今天的安排应更重视补偿和降载。")
            }
            factors.append(BodyRecoveryFactorPresentation(
                kind: .overnightRecovery,
                title: String(localized: "夜间恢复"),
                valueText: "\(recovery)/100",
                detailText: detail,
                symbol: "moon.stars.fill",
                tone: tone
            ))
        }

        if let stress = input.stressScore {
            let tone: BodyRecoveryPresentationTone = stress < 35 ? .positive : stress < 65 ? .neutral : .critical
            let detail = stress < 35
                ? String(localized: "当前压力较低，是维持身体电量的主要有利因素。")
                : stress < 65
                    ? String(localized: "当前压力处在中段，会持续消耗一部分可用余量。")
                    : String(localized: "当前压力偏高，是今天身体电量下降的主要拖累。")
            factors.append(BodyRecoveryFactorPresentation(
                kind: .daytimeStress,
                title: String(localized: "日内压力"),
                valueText: "\(stress)/100",
                detailText: detail,
                symbol: "brain.head.profile",
                tone: tone
            ))
        }

        if let hrv = input.nightlyHrv ?? input.baselineHrv, hrv > 0 {
            let comparison = comparisonText(
                current: input.nightlyHrv,
                baseline: input.baselineHrv,
                higherIsBetter: true,
                stableText: String(localized: "接近个人恢复基线。"),
                highText: String(localized: "高于个人恢复基线，为今天的恢复提供支撑。"),
                lowText: String(localized: "低于个人恢复基线，提示恢复弹性有所收紧。")
            )
            factors.append(BodyRecoveryFactorPresentation(
                kind: .hrv,
                title: input.nightlyHrv != nil ? String(localized: "夜间 HRV") : String(localized: "HRV 基线"),
                valueText: String(format: "%.0f ms", hrv),
                detailText: comparison.text,
                symbol: "waveform.path.ecg",
                tone: comparison.tone
            ))
        }

        let currentHeartRate = input.overnightHeartRate ?? input.restingHeartRate
        let baselineHeartRate = input.baselineOvernightHeartRate ?? input.baselineRestingHeartRate
        if let heartRate = currentHeartRate, heartRate > 0 {
            let comparison = comparisonText(
                current: currentHeartRate,
                baseline: baselineHeartRate,
                higherIsBetter: false,
                stableText: String(localized: "接近个人心率基线。"),
                highText: String(localized: "低于个人心率基线，对恢复较友好。"),
                lowText: String(localized: "高于个人心率基线，建议保守安排今天的负荷。")
            )
            factors.append(BodyRecoveryFactorPresentation(
                kind: .heartRate,
                title: input.overnightHeartRate != nil ? String(localized: "夜间心率") : String(localized: "静息心率"),
                valueText: String(format: "%.0f bpm", heartRate),
                detailText: comparison.text,
                symbol: "heart.fill",
                tone: comparison.tone
            ))
        }

        if input.workoutEventCount > 0 || input.physicalEffortSampleCount > 0 {
            let value = input.workoutEventCount > 0
                ? String(localized: "\(input.workoutEventCount) 次训练")
                : String(localized: "\(input.physicalEffortSampleCount) 段活动")
            factors.append(BodyRecoveryFactorPresentation(
                kind: .activityLoad,
                title: String(localized: "活动负荷"),
                valueText: value,
                detailText: String(localized: "今天的活动负荷已经计入身体电量消耗，后续加量应结合当前余量判断。"),
                symbol: "figure.run",
                tone: .caution
            ))
        }

        return Array(factors.prefix(5))
    }

    static func makeActions(
        input: BodyRecoveryPersonalizationInput
    ) -> [BodyRecoveryActionPresentation] {
        var actions: [BodyRecoveryActionPresentation] = []

        func append(_ action: BodyRecoveryActionPresentation) {
            guard !actions.contains(where: { $0.kind == action.kind }) else { return }
            actions.append(action)
        }

        if let battery = input.currentBodyBattery, battery < 30 {
            append(action(.restoreFirst))
        }
        if let stress = input.stressScore, stress >= 65 {
            append(action(.decompress))
        }
        if let recovery = input.overnightRecoveryScore, recovery < 60 {
            append(action(.protectSleep))
        }
        if input.workoutEventCount > 0 || input.physicalEffortSampleCount > 0 {
            append(action(.reduceTraining))
        }
        if isHrvBelowBaseline(input) || isHeartRateAboveBaseline(input) {
            append(action(.keepLoadLight))
        }

        switch input.currentBodyBattery ?? input.overnightRecoveryScore ?? 50 {
        case 80...:
            append(action(.focusPriority))
            append(action(.recoveryBreak))
            append(action(.protectSleep))
        case 55..<80:
            append(action(.segmentTasks))
            append(action(.recoveryBreak))
            append(action(.reduceStimulation))
        case 30..<55:
            append(action(.keepLoadLight))
            append(action(.recoveryBreak))
            append(action(.reduceStimulation))
        default:
            append(action(.restoreFirst))
            append(action(.reduceTraining))
            append(action(.protectSleep))
        }

        return Array(actions.prefix(3))
    }

    static func action(_ kind: BodyRecoveryActionKind) -> BodyRecoveryActionPresentation {
        switch kind {
        case .restoreFirst:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "先把恢复放到第一位"),
                detailText: String(localized: "优先休息、补水、正常进食和轻走动，复杂任务与高强度输出尽量后移。"),
                symbol: "bed.double.fill",
                tone: .critical
            )
        case .protectSleep:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "保护今晚的睡眠窗口"),
                detailText: String(localized: "提前结束高刺激活动，尽量保持完整睡眠时长，为明天补回恢复起点。"),
                symbol: "moon.zzz.fill",
                tone: .neutral
            )
        case .decompress:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "先安排一次短恢复"),
                detailText: String(localized: "离屏、补水或轻走动 5 到 10 分钟，再决定是否继续当前任务。"),
                symbol: "pause.circle.fill",
                tone: .caution
            )
        case .reduceTraining:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "不要继续叠加训练负荷"),
                detailText: String(localized: "今天已有活动消耗，后续优先轻拉伸或散步，避免临时追加高强度训练。"),
                symbol: "figure.cooldown",
                tone: .caution
            )
        case .keepLoadLight:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "把任务保持在低负荷"),
                detailText: String(localized: "先处理必要且低阻力的事项，减少长时间连续输出，并观察信号是否回稳。"),
                symbol: "leaf.fill",
                tone: .caution
            )
        case .focusPriority:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "只选一到两个重点"),
                detailText: String(localized: "当前余量允许正常推进，但不要把训练、深度工作和密集社交全部堆在一起。"),
                symbol: "target",
                tone: .positive
            )
        case .segmentTasks:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "把任务分段推进"),
                detailText: String(localized: "用 30 到 45 分钟完成一段，中间留出缓冲，避免身体电量一路下滑。"),
                symbol: "rectangle.stack.fill",
                tone: .neutral
            )
        case .recoveryBreak:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "主动保留恢复间隔"),
                detailText: String(localized: "每完成一段高消耗事项，留 5 到 10 分钟补水、走动或安静休息。"),
                symbol: "cup.and.saucer.fill",
                tone: .neutral
            )
        case .reduceStimulation:
            return BodyRecoveryActionPresentation(
                kind: kind,
                title: String(localized: "减少额外刺激"),
                detailText: String(localized: "减少临时加码、密集通知和过晚的咖啡因，让后半天的消耗更可控。"),
                symbol: "bell.slash.fill",
                tone: .caution
            )
        }
    }

    static func budgetBadge(bodyBattery: Int?) -> String {
        guard let bodyBattery else { return String(localized: "部分数据") }
        switch bodyBattery {
        case 80...: return String(localized: "可安排重点")
        case 55..<80: return String(localized: "适合分配")
        case 30..<55: return String(localized: "控制消耗")
        default: return String(localized: "保留电量")
        }
    }

    static func budgetSummary(bodyBattery: Int?) -> String {
        guard let bodyBattery else {
            return String(localized: "已根据当前可用信号生成保守建议；身体电量补齐后会自动更新优先级。")
        }
        switch bodyBattery {
        case 80...:
            return String(localized: "今天可以推进重点事项，但仍要给高消耗安排留出恢复间隔。")
        case 55..<80:
            return String(localized: "把最重要的事情放在状态较好的时段，并通过分段节奏维持后半天余量。")
        case 30..<55:
            return String(localized: "今天优先必要事项和低负荷活动，非必要的高强度内容尽量缩短或后移。")
        default:
            return String(localized: "今天的目标是先稳住状态；暂停额外加码，把恢复动作安排在任务之前。")
        }
    }

    static func comparisonText(
        current: Double?,
        baseline: Double?,
        higherIsBetter: Bool,
        stableText: String,
        highText: String,
        lowText: String
    ) -> (text: String, tone: BodyRecoveryPresentationTone) {
        guard let current, current > 0, let baseline, baseline > 0 else {
            return (String(localized: "已取得当前读数，个人基线样本仍在建立。"), .neutral)
        }
        let ratio = current / baseline
        if (0.92...1.08).contains(ratio) {
            return (stableText, .neutral)
        }
        let isFavorable = higherIsBetter ? ratio > 1.08 : ratio < 0.92
        return isFavorable ? (highText, .positive) : (lowText, .caution)
    }

    static func isHrvBelowBaseline(_ input: BodyRecoveryPersonalizationInput) -> Bool {
        guard let current = input.nightlyHrv, current > 0,
              let baseline = input.baselineHrv, baseline > 0 else { return false }
        return current < baseline * 0.92
    }

    static func isHeartRateAboveBaseline(_ input: BodyRecoveryPersonalizationInput) -> Bool {
        let current = input.overnightHeartRate ?? input.restingHeartRate
        let baseline = input.baselineOvernightHeartRate ?? input.baselineRestingHeartRate
        guard let current, current > 0, let baseline, baseline > 0 else { return false }
        return current > baseline * 1.08
    }
}
