/// ActiveEnergyInterpretationViewModel 作为活动消耗详情页的视图模型，负责管理加载状态与解读数据。
/// 负责提供每日摘要、异常天数、行为档案与解读卡片的状态与数据加载。

import SwiftUI

@MainActor
@Observable
final class ActiveEnergyInterpretationViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case needsAuthorization
        case empty

        var title: String {
            switch self {
            case .loading: return "正在整理"
            case .ready: return "已生成"
            case .needsAuthorization: return "等待授权"
            case .empty: return "等待样本"
            }
        }

        var headline: String {
            switch self {
            case .loading: return "正在整理最近的活动消耗说明"
            case .ready: return "活动消耗说明已经整理完成"
            case .needsAuthorization: return "还没有形成足够的健康读取授权"
            case .empty: return "最近样本还不够形成稳妥判断"
            }
        }

        var detail: String {
            switch self {
            case .loading: return "先把端上可读到的活动、睡眠与心率线索整理出来。"
            case .ready: return "最近的活动负荷状态已经开始能拼出一张更完整的说明图。"
            case .needsAuthorization: return "授权健康 App 后，这里会开始形成活动消耗说明与波动解释。"
            case .empty: return "继续同步几天或补一点生活记录后，再回来会更完整。"
            }
        }
    }

    private(set) var state: LoadState = .loading
    private(set) var dailySummary: ActiveEnergyDailySummary?
    private(set) var abnormalDays: [ActiveEnergyAbnormalDay] = []
    private(set) var manualProfile: ActiveEnergyManualProfile?
    private(set) var signalLanguageCard: ActiveEnergyInterpretationCard?
    private(set) var interpretationCards: [ActiveEnergyInterpretationCard] = []

    private let habitViewModel = HabitViewModel()

    func load() async {
        state = .loading
        habitViewModel.loadData(for: Date())

        let hk = HealthKitManager.shared
        let hasHealthAccess = hk.isLikelyAuthorized()
        let currentDate = Calendar.current.startOfDay(for: Date())

        async let active7Task = try? hk.fetchDailyActiveEnergySums(days: 7)
        async let active14Task = try? hk.fetchDailyActiveEnergySums(days: 14)
        async let active30Task = try? hk.fetchDailyActiveEnergySums(days: 30)
        async let sleep14Task = try? hk.fetchSleepDurationSeries(days: 14)
        async let consistency14Task = try? hk.fetchSleepConsistencySeries(days: 14)
        async let hrv14Task = try? hk.fetchDailyHRVAverages(days: 14)
        async let rhr14Task = try? hk.fetchDailyRestingHeartRateAverages(days: 14)
        async let rhr30Task = try? hk.fetchDailyRestingHeartRateAverages(days: 30)
        async let steps14Task = try? hk.fetchDailyStepSums(days: 14)
        async let steps30Task = try? hk.fetchDailyStepSums(days: 30)
        async let aerobic14Task = try? hk.fetchDailyExerciseTimeSums(days: 14)
        async let vo2Max14Task = HealthFactorKey.vo2Max.loadSeries(days: 14)

        let snapshot = ActiveEnergyInterpretationSnapshot(
            active7: await active7Task ?? [],
            active14: await active14Task ?? [],
            active30: await active30Task ?? [],
            sleep14: await sleep14Task ?? [],
            sleepConsistency14: await consistency14Task ?? [],
            hrv14: await hrv14Task ?? [],
            restingHeartRate14: await rhr14Task ?? [],
            restingHeartRate30: await rhr30Task ?? [],
            steps14: await steps14Task ?? [],
            steps30: await steps30Task ?? [],
            aerobicTraining14: await aerobic14Task ?? [],
            vo2Max14: await vo2Max14Task
        )

        let totalAvailableSignals = snapshot.availableSignalCount

        if !hasHealthAccess && totalAvailableSignals == 0 {
            state = .needsAuthorization
            return
        }

        if totalAvailableSignals < 2 {
            state = .empty
            return
        }

        let engine = ActiveEnergyInsightEngine()
        let result = engine.analyze(snapshot: snapshot, today: currentDate)
        dailySummary = result.dailySummary
        abnormalDays = result.abnormalDays
        manualProfile = result.manualProfile
        signalLanguageCard = result.signalLanguageCard
        interpretationCards = result.interpretationCards
        state = .ready
    }
}

struct ActiveEnergyInterpretationCard: Identifiable {
    let id: String
    let title: String
    let badge: String
    let summary: String
    let detail: String
    let tint: Color
}

struct ActiveEnergyDailySummary {
    enum StabilityLevel: String {
        case stable
        case mild
        case caution
        case high

        var displayName: String {
            switch self {
            case .stable: return String(localized: "负荷平稳")
            case .mild: return String(localized: "轻度波动")
            case .caution: return String(localized: "负荷集中")
            case .high: return String(localized: "明显失衡")
            }
        }
    }

    struct SignalPill: Identifiable {
        let id: String
        let title: String
        let value: String
        let note: String
        let tint: Color
    }

    let stabilityLevel: StabilityLevel
    let score: Int
    let headline: String
    let narrative: String
    let explanation: String
    let signalPills: [SignalPill]
    let accentColor: Color

    var riskTitle: String { stabilityLevel.displayName }
    var scoreText: String { "\(score)" }
}

struct ActiveEnergyAbnormalDay: Identifiable {
    let id: String
    let date: Date
    let dateText: String
    let reason: String
    let triggerSummary: String
    let actionSuggestion: String
    let levelText: String
    let tint: Color
}

struct ActiveEnergyManualProfile {
    enum Kind: String {
        case steadyRhythm
        case spikeFragmented
        case recoveryTight
        case rhythmDriftEcho
    }

    let kind: Kind
    let title: String
    let badge: String
    let definition: String
    let triggers: String
    let priorities: String
    let action: String
    let dontOverread: String
    let tint: Color
}

private struct ActiveEnergyInterpretationSnapshot {
    let active7: [TimeSeriesPointDouble]
    let active14: [TimeSeriesPointDouble]
    let active30: [TimeSeriesPointDouble]
    let sleep14: [TimeSeriesPointDouble]
    let sleepConsistency14: [TimeSeriesPointDouble]
    let hrv14: [TimeSeriesPointDouble]
    let restingHeartRate14: [TimeSeriesPointDouble]
    let restingHeartRate30: [TimeSeriesPointDouble]
    let steps14: [TimeSeriesPointDouble]
    let steps30: [TimeSeriesPointDouble]
    let aerobicTraining14: [TimeSeriesPointDouble]
    let vo2Max14: [TimeSeriesPointDouble]

    var availableSignalCount: Int {
        [
            !active7.isEmpty,
            !sleep14.isEmpty,
            !sleepConsistency14.isEmpty,
            !hrv14.isEmpty,
            !restingHeartRate14.isEmpty,
            !steps14.isEmpty,
            !aerobicTraining14.isEmpty
        ]
        .filter { $0 }
        .count
    }
}

private struct ActiveEnergyInterpretationResult {
    let dailySummary: ActiveEnergyDailySummary
    let abnormalDays: [ActiveEnergyAbnormalDay]
    let manualProfile: ActiveEnergyManualProfile
    let signalLanguageCard: ActiveEnergyInterpretationCard
    let interpretationCards: [ActiveEnergyInterpretationCard]
}

private struct ActiveEnergyInsightEngine {
    func analyze(snapshot: ActiveEnergyInterpretationSnapshot, today: Date) -> ActiveEnergyInterpretationResult {
        let calendar = Calendar.current
        let activeToday = latestValue(on: today, from: snapshot.active7)
        let activeBaseline = averageExcludingLatest(snapshot.active14)
        let active7Average = averageRaw(snapshot.active7)
        let active30Average = averageRaw(snapshot.active30)
        let sleepToday = latestValue(on: today, from: snapshot.sleep14)
        let sleepBaseline = averageExcludingLatest(snapshot.sleep14)
        let hrvToday = latestValue(on: today, from: snapshot.hrv14)
        let hrvBaseline = averageExcludingLatest(snapshot.hrv14)
        let rhrToday = latestValue(on: today, from: snapshot.restingHeartRate14)
        let rhrBaseline = averageExcludingLatest(snapshot.restingHeartRate14)
        let stepsToday = latestValue(on: today, from: snapshot.steps14)
        let stepsBaseline = averageExcludingLatest(snapshot.steps14)
        let vo2Recent = latestPositiveValue(from: snapshot.vo2Max14)
        let aerobicToday = latestValue(on: today, from: snapshot.aerobicTraining14)

        var cautionSignals: [String] = []
        var strongSignals: [String] = []
        var score = 84

        // 活动能量连续性检查
        if let activeToday, let activeBaseline, activeBaseline > 0 {
            let delta = activeToday - activeBaseline
            let ratio = abs(delta) / activeBaseline
            if ratio >= 0.35 {
                strongSignals.append(activeToday > activeBaseline ? "活动消耗远高于基线" : "活动消耗断档回落")
                score -= 12
            } else if ratio >= 0.18 {
                cautionSignals.append("活动消耗有较明显偏移")
                score -= 6
            }
        }

        // 峰值集中度：单日是否主导七日总量
        let spikeRatio = maxShare(of: snapshot.active7)
        if spikeRatio > 0.45 {
            strongSignals.append("活动负荷集中在少数几天")
            score -= 10
        } else if spikeRatio > 0.32 {
            cautionSignals.append("活动负荷分布偏集中")
            score -= 5
        }

        // 最近七日中的零值或极低值天数
        let lowDays = snapshot.active7.filter { $0.value > 0 && $0.value < 120 }.count
        let zeroDays = snapshot.active7.filter { $0.value <= 0 }.count
        if zeroDays >= 3 || lowDays >= 4 {
            strongSignals.append("近 7 天断档天数偏多")
            score -= 10
        } else if zeroDays >= 2 || lowDays >= 3 {
            cautionSignals.append("近 7 天活动连续性一般")
            score -= 5
        }

        if let sleepToday, let sleepBaseline, sleepToday < max(300, sleepBaseline * 0.88) {
            strongSignals.append("睡眠时长低于近一周基线")
            score -= 10
        }
        if let hrvToday, let hrvBaseline, hrvToday < hrvBaseline * 0.84 {
            strongSignals.append("HRV 明显低于近一周")
            score -= 10
        }
        if let rhrToday, let rhrBaseline, rhrToday > rhrBaseline + 4 {
            cautionSignals.append("静息心率高于近一周")
            score -= 6
        }
        if let stepsToday, let stepsBaseline, stepsBaseline > 0, stepsToday < stepsBaseline * 0.7 {
            cautionSignals.append("日常活动量较近一周回落")
            score -= 5
        }

        score = max(36, min(95, score))

        let stabilityLevel: ActiveEnergyDailySummary.StabilityLevel
        if score >= 80 {
            stabilityLevel = .stable
        } else if score >= 68 {
            stabilityLevel = .mild
        } else if score >= 52 {
            stabilityLevel = .caution
        } else {
            stabilityLevel = .high
        }

        let dailyHeadline: String
        switch stabilityLevel {
        case .stable:
            dailyHeadline = "今天的活动负荷整体比较连贯。"
        case .mild:
            dailyHeadline = "今天出现了轻微波动，但还没有到明显失衡。"
        case .caution:
            dailyHeadline = "今天的活动负荷开始出现集中或断档的迹象。"
        case .high:
            dailyHeadline = "今天更像是多条线索一起在提醒你重新分配负荷。"
        }

        let dailyNarrative = buildDailyNarrative(strongSignals: strongSignals, cautionSignals: cautionSignals)
        let dailyExplanation = buildExplanation(
            activeToday: activeToday,
            activeBaseline: activeBaseline,
            active7Average: active7Average,
            active30Average: active30Average,
            sleepToday: sleepToday,
            hrvToday: hrvToday,
            rhrToday: rhrToday,
            vo2Recent: vo2Recent,
            stepsToday: stepsToday,
            aerobicToday: aerobicToday,
            snapshot: snapshot
        )
        let dailySummary = ActiveEnergyDailySummary(
            stabilityLevel: stabilityLevel,
            score: score,
            headline: dailyHeadline,
            narrative: dailyNarrative,
            explanation: dailyExplanation,
            signalPills: signalPills(
                activeToday: activeToday,
                sleepToday: sleepToday,
                hrvToday: hrvToday,
                rhrToday: rhrToday,
                vo2Recent: vo2Recent,
                stepsToday: stepsToday,
                aerobicToday: aerobicToday
            ),
            accentColor: tint(for: stabilityLevel)
        )

        let shortTermCard = ActiveEnergyInterpretationCard(
            id: "single-day",
            title: "单日解释",
            badge: shortTermBadge(for: stabilityLevel),
            summary: shortTermSummary(
                score: score,
                strongSignals: strongSignals,
                cautionSignals: cautionSignals,
                snapshot: snapshot
            ),
            detail: shortTermDetail(stabilityLevel: stabilityLevel),
            tint: tint(for: stabilityLevel)
        )
        let weeklyCard = ActiveEnergyInterpretationCard(
            id: "week",
            title: "7 天解释",
            badge: weeklyBadge(snapshot: snapshot),
            summary: weeklySummary(snapshot: snapshot),
            detail: weeklyDetail(snapshot: snapshot),
            tint: Color(hex: "5B8CFF")
        )
        let monthlyCard = ActiveEnergyInterpretationCard(
            id: "month",
            title: "30 天解释",
            badge: monthlyBadge(snapshot: snapshot),
            summary: monthlySummary(snapshot: snapshot),
            detail: monthlyDetail(),
            tint: Color(hex: "E29A63")
        )

        let abnormalDays = buildAbnormalDays(snapshot: snapshot, calendar: calendar)
        let manualProfile = buildManualProfile(snapshot: snapshot, stabilityLevel: stabilityLevel, strongSignals: strongSignals, cautionSignals: cautionSignals)
        let signalLanguageCard = buildSignalLanguageCard(
            activeToday: activeToday,
            activeBaseline: activeBaseline,
            hrvToday: hrvToday,
            hrvBaseline: hrvBaseline,
            rhrToday: rhrToday,
            rhrBaseline: rhrBaseline,
            vo2Recent: vo2Recent,
            snapshot: snapshot
        )

        return ActiveEnergyInterpretationResult(
            dailySummary: dailySummary,
            abnormalDays: abnormalDays,
            manualProfile: manualProfile,
            signalLanguageCard: signalLanguageCard,
            interpretationCards: [shortTermCard, weeklyCard, monthlyCard]
        )
    }

    private func buildDailyNarrative(strongSignals: [String], cautionSignals: [String]) -> String {
        if !strongSignals.isEmpty {
            return "今天最值得优先看的，是\(strongSignals.prefix(2).joined(separator: "、"))。"
        }
        if !cautionSignals.isEmpty {
            return "目前更像是\(cautionSignals.prefix(2).joined(separator: "、"))在轻微偏移。"
        }
        return String(localized: "活动消耗、恢复和日常节律暂时没有出现明显冲突。")
    }

    private func buildExplanation(
        activeToday: Double?,
        activeBaseline: Double?,
        active7Average: Double,
        active30Average: Double,
        sleepToday: Double?,
        hrvToday: Double?,
        rhrToday: Double?,
        vo2Recent: Double?,
        stepsToday: Double?,
        aerobicToday: Double?,
        snapshot: ActiveEnergyInterpretationSnapshot
    ) -> String {
        var parts: [String] = []
        if let activeToday, activeToday > 0 {
            parts.append("今日活动消耗 \(Int(activeToday.rounded())) kcal")
        }
        if let activeBaseline, activeBaseline > 0 {
            parts.append("近 14 天均值 \(Int(activeBaseline.rounded())) kcal")
        }
        if active7Average > 0 {
            parts.append("7 天均值 \(Int(active7Average.rounded())) kcal")
        }
        if active30Average > 0 {
            parts.append("30 天均值 \(Int(active30Average.rounded())) kcal")
        }
        if let sleepToday, sleepToday > 0 {
            parts.append("睡眠约 \(Int((sleepToday / 60.0).rounded())) 小时")
        }
        if let hrvToday, hrvToday > 0 {
            parts.append("HRV \(Int(hrvToday.rounded())) ms")
        }
        if let rhrToday, rhrToday > 0 {
            parts.append("静息心率 \(Int(rhrToday.rounded())) 次/分")
        }
        if let aerobicToday, aerobicToday > 0 {
            parts.append("训练约 \(Int(aerobicToday.rounded())) 分钟")
        }
        if let vo2Recent, vo2Recent > 0 {
            parts.append("VO2Max \(String(format: "%.1f", vo2Recent))")
        }
        if parts.isEmpty {
            return String(localized: "当前更多还是依据可读到的活动线索做保守阅读。")
        }
        return "这次判断主要综合了 \(parts.joined(separator: "、")) 这些信号。"
    }

    private func signalPills(
        activeToday: Double?,
        sleepToday: Double?,
        hrvToday: Double?,
        rhrToday: Double?,
        vo2Recent: Double?,
        stepsToday: Double?,
        aerobicToday: Double?
    ) -> [ActiveEnergyDailySummary.SignalPill] {
        [
            .init(
                id: "active",
                title: "活动消耗",
                value: activeToday.map { "\(Int($0.rounded())) kcal" } ?? "--",
                note: "今日负荷",
                tint: Color(hex: "F06A7B")
            ),
            .init(
                id: "sleep",
                title: "睡眠",
                value: sleepToday.map { String(format: "%.1f h", $0 / 60.0) } ?? "--",
                note: "恢复底盘",
                tint: Color(hex: "5B8CFF")
            ),
            .init(
                id: "hrv",
                title: "HRV",
                value: hrvToday.map { "\(Int($0.rounded())) ms" } ?? "--",
                note: "恢复信号",
                tint: Color(hex: "38C793")
            ),
            .init(
                id: "rhr",
                title: "静息心率",
                value: rhrToday.map { "\(Int($0.rounded())) 次/分" } ?? "--",
                note: "负荷线索",
                tint: Color(hex: "F46B5A")
            ),
            .init(
                id: "steps",
                title: "活动",
                value: stepsToday.map { "\(Int($0.rounded())) 步" } ?? "--",
                note: "行动节律",
                tint: Color(hex: "32ADE6")
            ),
            .init(
                id: "vo2max",
                title: "VO2Max",
                value: vo2Recent.map { String(format: "%.1f", $0) } ?? "--",
                note: "体能底盘",
                tint: Color(hex: "8D7AFF")
            )
        ]
    }

    private func shortTermBadge(for level: ActiveEnergyDailySummary.StabilityLevel) -> String {
        switch level {
        case .stable: return "今天偏稳"
        case .mild: return "轻微偏移"
        case .caution: return "负荷集中"
        case .high: return "多信号共振"
        }
    }

    private func shortTermSummary(
        score: Int,
        strongSignals: [String],
        cautionSignals: [String],
        snapshot: ActiveEnergyInterpretationSnapshot
    ) -> String {
        if !strongSignals.isEmpty {
            return "单日层面更像是 \(strongSignals.prefix(2).joined(separator: "、")) 一起把今天的活动负荷往上或往下拉。"
        }
        if average(snapshot.sleepConsistency14) < 75 {
            return String(localized: "单日层面更像是作息漂移连带活动节律一起在波动。")
        }
        return score >= 80 ? "今天更接近正常波动。" : "今天更适合先按轻负荷日理解。"
    }

    private func shortTermDetail(stabilityLevel: ActiveEnergyDailySummary.StabilityLevel) -> String {
        switch stabilityLevel {
        case .stable:
            return String(localized: "当前没有看到明显需要放大的单日异常，更适合继续维持节律，而不是过度解读单个数字。")
        case .mild:
            return String(localized: "这类波动更像是恢复和日常输入的轻微错位，通常先把睡眠、补水和白天节律拉稳，会比立刻追问某个单点数值更有帮助。")
        case .caution:
            return String(localized: "今天已经出现活动断档或负荷集中叠加恢复不足的迹象，更适合把节奏往匀一点调，避免继续堆在某几天。")
        case .high:
            return String(localized: "今天更像是多条核心信号都在同方向偏移，说明身体正在明确提醒你先照顾恢复，而不是继续往上加码。")
        }
    }

    private func weeklyBadge(snapshot: ActiveEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.hrv14) < -1.2 || slope(of: snapshot.restingHeartRate14) > 1.0 {
            return "恢复走低"
        }
        return String(localized: "近一周观察")
    }

    private func weeklySummary(snapshot: ActiveEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.hrv14) < -1.2 && slope(of: snapshot.restingHeartRate14) > 0.8 {
            return String(localized: "最近 7 天更像是恢复基线在慢慢走低，活动负荷也在跟着收缩。")
        }
        if average(snapshot.sleepConsistency14) < 75 {
            return String(localized: "最近 7 天更像是作息稳定度在下滑，活动节律也会跟着波动。")
        }
        if average(snapshot.steps14) < 4500 {
            return String(localized: "最近 7 天更像是日常活动底盘偏低。")
        }
        return String(localized: "最近 7 天整体更接近轻度波动，而不是持续恶化。")
    }

    private func weeklyDetail(snapshot: ActiveEnergyInterpretationSnapshot) -> String {
        if average(snapshot.sleepConsistency14) < 75 {
            return String(localized: "这一周更适合优先把睡觉和起床时点拉回稳定，再回头看活动负荷是不是一起回稳。")
        }
        return String(localized: "一周维度更适合看方向和分布，不适合拿单日高低做硬判断。")
    }

    private func monthlyBadge(snapshot: ActiveEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.active30) != 0 && abs(slope(of: snapshot.active30)) > 60 {
            return String(localized: "月内偏移")
        }
        return String(localized: "长期画像")
    }

    private func monthlySummary(snapshot: ActiveEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.hrv14) < -1.0 && slope(of: snapshot.restingHeartRate30) > 0.6 {
            return String(localized: "最近 30 天更像是恢复资源被持续消耗，活动负荷也在跟着调整。")
        }
        if average(snapshot.steps30) < 5000 {
            return String(localized: "最近 30 天整体活动底盘偏低，更像是慢变量层面的回落。")
        }
        return String(localized: "最近 30 天还没有形成很强的单方向迁移。")
    }

    private func monthlyDetail() -> String {
        return String(localized: "月度层面更适合拿来理解你更像哪一类活动负荷模式，而不是判断某一天是不是异常。")
    }

    private func buildSignalLanguageCard(
        activeToday: Double?,
        activeBaseline: Double?,
        hrvToday: Double?,
        hrvBaseline: Double?,
        rhrToday: Double?,
        rhrBaseline: Double?,
        vo2Recent: Double?,
        snapshot: ActiveEnergyInterpretationSnapshot
    ) -> ActiveEnergyInterpretationCard {
        var alignedSignals: [String] = []
        var softSignals: [String] = []

        if let activeToday, let activeBaseline, activeBaseline > 0 {
            let ratio = abs(activeToday - activeBaseline) / activeBaseline
            if ratio >= 0.35 {
                alignedSignals.append(activeToday > activeBaseline ? "活动负荷冲高" : "活动负荷断档")
            }
        }

        if let hrvToday, let hrvBaseline, hrvToday < hrvBaseline * 0.84 {
            alignedSignals.append("恢复弹性偏紧")
        } else if hrvToday != nil {
            softSignals.append("HRV 暂时没有单独拉响警报")
        }

        if let rhrToday, let rhrBaseline, rhrToday > rhrBaseline + 4 {
            alignedSignals.append("负荷线索抬头")
        } else if rhrToday != nil {
            softSignals.append("静息心率未形成明显上冲")
        }

        if maxShare(of: snapshot.active7) > 0.45 {
            alignedSignals.append("负荷集中度高")
        }

        if vo2Recent != nil {
            softSignals.append("VO2Max 作为体能底盘慢看")
        }

        let summary: String
        let badge: String
        let tint: Color
        if alignedSignals.count >= 2 {
            badge = "多信号同向"
            tint = Color(hex: "FF9F0A")
            summary = "今天更适合按 \(alignedSignals.prefix(2).joined(separator: " + ")) 来读，而不是把某一个数字单独放大。"
        } else if let first = alignedSignals.first {
            badge = "单点待复核"
            tint = Color(hex: "5B8CFF")
            summary = "\(first) 目前还需要和睡眠、HRV、静息心率、后续几天一起看，先不把它当成结论。"
        } else {
            badge = "看组合"
            tint = Color(hex: "F06A7B")
            summary = "多条信号暂时没有形成同向偏移，单个数字轻微变化更像普通波动。"
        }

        let supportingText = softSignals.prefix(2).joined(separator: "；")
        let detailPrefix = supportingText.isEmpty ? "" : "\(supportingText)。"
        return ActiveEnergyInterpretationCard(
            id: "signal-language",
            title: "负荷信号合读",
            badge: badge,
            summary: summary,
            detail: "\(detailPrefix)活动消耗更像负荷的快变量，HRV 更像恢复弹性，静息心率更像负荷线索，VO2Max 是体能底盘的慢变量；只有连续几天、两三条信号同向偏移时，才值得提高关注。",
            tint: tint
        )
    }

    private func buildAbnormalDays(snapshot: ActiveEnergyInterpretationSnapshot, calendar: Calendar) -> [ActiveEnergyAbnormalDay] {
        let hrvBaseline = averageExcludingLatest(snapshot.hrv14)
        let rhrBaseline = averageExcludingLatest(snapshot.restingHeartRate14)
        let sleepBaseline = averageExcludingLatest(snapshot.sleep14)
        let activeBaseline = averageExcludingLatest(snapshot.active14)

        let dates = Set(snapshot.active14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.hrv14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.restingHeartRate14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.sleep14.map { calendar.startOfDay(for: $0.date) })
            .sorted(by: >)

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")

        return dates.prefix(5).compactMap { date in
            let active = value(on: date, from: snapshot.active14, calendar: calendar)
            let hrv = value(on: date, from: snapshot.hrv14, calendar: calendar)
            let rhr = value(on: date, from: snapshot.restingHeartRate14, calendar: calendar)
            let sleep = value(on: date, from: snapshot.sleep14, calendar: calendar)

            var strongCount = 0
            var triggers: [String] = []

            if let active, let activeBaseline, activeBaseline > 0, abs(active - activeBaseline) / activeBaseline >= 0.35 {
                strongCount += 1
                triggers.append(active > activeBaseline ? "负荷冲高" : "负荷断档")
            }
            if let hrv, let hrvBaseline, hrv < hrvBaseline * 0.82 {
                strongCount += 1
                triggers.append("HRV 下探")
            }
            if let rhr, let rhrBaseline, rhr > rhrBaseline + 5 {
                strongCount += 1
                triggers.append("静息心率抬高")
            }
            if let sleep, let sleepBaseline, sleep < max(300, sleepBaseline * 0.85) {
                strongCount += 1
                triggers.append("睡眠回落")
            }

            guard strongCount >= 2 else { return nil }

            let tint = strongCount >= 3 ? Color(hex: "F46B5A") : Color(hex: "FF9F0A")
            return ActiveEnergyAbnormalDay(
                id: "abnormal-\(Int(date.timeIntervalSince1970))",
                date: date,
                dateText: formatter.string(from: date),
                reason: strongCount >= 3 ? "这一天更像是明显的共振偏移日。" : "这一天出现了值得单独留意的信号叠加。",
                triggerSummary: "触发信号：\(triggers.joined(separator: "、"))",
                actionSuggestion: strongCount >= 3 ? "回看当天的睡眠、训练和活动记录，优先按恢复日理解。" : "把它放回前后几天一起看，判断是不是连续在偏移。",
                levelText: strongCount >= 3 ? "高扰动日" : "需留意日",
                tint: tint
            )
        }
    }

    private func buildManualProfile(
        snapshot: ActiveEnergyInterpretationSnapshot,
        stabilityLevel: ActiveEnergyDailySummary.StabilityLevel,
        strongSignals: [String],
        cautionSignals: [String]
    ) -> ActiveEnergyManualProfile {
        let avgSleepConsistency = average(snapshot.sleepConsistency14)
        let spikeRatio = maxShare(of: snapshot.active7)

        if strongSignals.contains(where: { $0.contains("HRV") || $0.contains("静息心率") }) {
            return ActiveEnergyManualProfile(
                kind: .recoveryTight,
                title: "恢复偏紧型",
                badge: "恢复优先",
                definition: "最近更像是恢复底盘不够宽裕，身体对负荷和刺激的缓冲能力在变紧，活动负荷也会跟着收缩。",
                triggers: "常见于睡眠回落、HRV 下探、静息心率抬高一起出现时。",
                priorities: "优先看睡眠时长、HRV、静息心率和今天有没有继续叠刺激。",
                action: "适合把训练和任务强度先压轻一点，优先补睡、补水和白天节律。",
                dontOverread: "不要只盯某一次高心率或一次差睡眠，而要看这几条恢复信号是不是连续一起偏移。",
                tint: Color(hex: "F46B5A")
            )
        }

        if spikeRatio > 0.38 {
            return ActiveEnergyManualProfile(
                kind: .spikeFragmented,
                title: "脉冲集中型",
                badge: "分布优先",
                definition: "最近更像是活动负荷集中在少数几天冲高，其他时间断档，整体分布不够匀。",
                triggers: "常见于周末集中训练、工作日久坐或偶尔爆发式活动的组合里。",
                priorities: "优先看断档天数和单日峰值占比，而不是只看总量。",
                action: "适合把大负荷拆小、匀到更多天，先把连续性补起来。",
                dontOverread: "不要因为总量达标就认为活动底盘良好，分布比总量更值得先看。",
                tint: Color(hex: "FF9F0A")
            )
        }

        if avgSleepConsistency < 75 {
            return ActiveEnergyManualProfile(
                kind: .rhythmDriftEcho,
                title: "节律漂移型",
                badge: "节律优先",
                definition: "最近更像是夜间作息稳定度变弱，身体时钟有点漂，活动节律也会跟着波动。",
                triggers: "常见于作息时间不稳、睡眠一致性下降时。",
                priorities: "优先看日照、睡眠一致性、入睡/起床时点和白天活动节律。",
                action: "适合先把起床时间和上午清醒信号拉稳，再观察活动负荷会不会回正。",
                dontOverread: "不要把所有波动都理解成训练问题，很多时候先是节律底盘在松。",
                tint: Color(hex: "5B8CFF")
            )
        }

        return ActiveEnergyManualProfile(
            kind: .steadyRhythm,
            title: "稳步推进型",
            badge: stabilityLevel == .stable ? "整体平稳" : "可维护",
            definition: "最近整体更像是处在可维护的稳定区间，活动负荷的连续性和分布都没有明显失衡。",
            triggers: "通常出现在睡眠、恢复、活动和日常输入没有明显对冲时。",
            priorities: "优先看是否还能把节律继续保持，而不是急着寻找问题。",
            action: "适合继续维持当前作息和活动习惯，只在出现连续偏移时再提高警觉。",
            dontOverread: "不要因为某个单日数字轻微变化就打破整体节奏，趋势比单点更重要。",
            tint: Color(hex: "F06A7B")
        )
    }

    // MARK: - 数学辅助

    private func latestValue(on date: Date, from points: [TimeSeriesPointDouble]) -> Double? {
        value(on: date, from: points, calendar: .current)
    }

    private func average(_ points: [TimeSeriesPointDouble]) -> Double {
        ActiveEnergyMetricMath.average(points)
    }

    private func averageExcludingLatest(_ points: [TimeSeriesPointDouble]) -> Double? {
        let values = ActiveEnergyMetricMath.positiveValues(from: points)
        guard values.count >= 2 else { return values.first }
        let prefix = Array(values.dropLast())
        guard !prefix.isEmpty else { return values.last }
        return prefix.reduce(0, +) / Double(prefix.count)
    }

    private func averageRaw(_ points: [TimeSeriesPointDouble]) -> Double {
        let values = points.map(\.value).filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func latestPositiveValue(from points: [TimeSeriesPointDouble]) -> Double? {
        points.sorted { $0.date > $1.date }.first(where: { $0.value > 0 })?.value
    }

    private func maxShare(of points: [TimeSeriesPointDouble]) -> Double {
        let values = ActiveEnergyMetricMath.positiveValues(from: points)
        guard !values.isEmpty else { return 0 }
        let total = values.reduce(0, +)
        guard total > 0 else { return 0 }
        return (values.max() ?? 0) / total
    }

    private func slope(of points: [TimeSeriesPointDouble]) -> Double {
        let values = ActiveEnergyMetricMath.positiveValues(from: points)
        guard values.count >= 2 else { return 0 }
        let start = values.prefix(max(1, values.count / 2))
        let end = values.suffix(max(1, values.count / 2))
        let lhs = start.reduce(0, +) / Double(start.count)
        let rhs = end.reduce(0, +) / Double(end.count)
        return rhs - lhs
    }

    private func value(on date: Date, from points: [TimeSeriesPointDouble], calendar: Calendar) -> Double? {
        let normalized = calendar.startOfDay(for: date)
        return points.first(where: { calendar.startOfDay(for: $0.date) == normalized })?.value
    }

    private func tint(for level: ActiveEnergyDailySummary.StabilityLevel) -> Color {
        switch level {
        case .stable: return Color(hex: "F06A7B")
        case .mild: return Color(hex: "5B8CFF")
        case .caution: return Color(hex: "FF9F0A")
        case .high: return Color(hex: "F46B5A")
        }
    }
}

private enum ActiveEnergyMetricMath {
    static func positiveValues(from points: [TimeSeriesPointDouble]) -> [Double] {
        points.map(\.value).filter { $0 > 0 }
    }

    static func average(_ points: [TimeSeriesPointDouble]) -> Double {
        let values = positiveValues(from: points)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
