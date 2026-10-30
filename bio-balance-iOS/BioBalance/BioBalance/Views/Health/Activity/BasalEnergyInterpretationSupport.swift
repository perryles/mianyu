/// BasalEnergyInterpretationViewModel 作为基础代谢详情页的视图模型，负责管理加载状态与解读数据。
/// 负责提供每日摘要、异常天数、手动档案与解读卡片的状态与数据加载。

import SwiftUI

@MainActor
@Observable
final class BasalEnergyInterpretationViewModel {
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
            case .loading: return "正在整理最近的基础代谢说明"
            case .ready: return "基础代谢说明已经整理完成"
            case .needsAuthorization: return "还没有形成足够的健康读取授权"
            case .empty: return "最近样本还不够形成稳妥判断"
            }
        }

        var detail: String {
            switch self {
            case .loading: return "先把端上可读到的睡眠、活动、心率与体温线索整理出来。"
            case .ready: return "最近的底盘消耗状态已经开始能拼出一张更完整的说明图。"
            case .needsAuthorization: return "授权健康 App 后，这里会开始形成基础代谢说明与波动解释。"
            case .empty: return "继续同步几天或补一点生活记录后，再回来会更完整。"
            }
        }
    }

    private(set) var state: LoadState = .loading
    private(set) var dailySummary: BasalEnergyDailySummary?
    private(set) var abnormalDays: [BasalEnergyAbnormalDay] = []
    private(set) var manualProfile: BasalEnergyManualProfile?
    private(set) var signalLanguageCard: BasalEnergyInterpretationCard?
    private(set) var interpretationCards: [BasalEnergyInterpretationCard] = []

    private let habitViewModel = HabitViewModel()

    func load() async {
        state = .loading
        habitViewModel.loadData(for: Date())

        let hk = HealthKitManager.shared
        let hasHealthAccess = hk.isLikelyAuthorized()
        let currentDate = Calendar.current.startOfDay(for: Date())

        async let basal7Task = try? hk.fetchDailyBasalEnergySums(days: 7)
        async let basal14Task = try? hk.fetchDailyBasalEnergySums(days: 14)
        async let basal30Task = try? hk.fetchDailyBasalEnergySums(days: 30)
        async let sleep14Task = try? hk.fetchSleepDurationSeries(days: 14)
        async let sleep30Task = try? hk.fetchSleepDurationSeries(days: 30)
        async let consistency14Task = try? hk.fetchSleepConsistencySeries(days: 14)
        async let hrv14Task = try? hk.fetchDailyHRVAverages(days: 14)
        async let rhr14Task = try? hk.fetchDailyRestingHeartRateAverages(days: 14)
        async let rhr30Task = try? hk.fetchDailyRestingHeartRateAverages(days: 30)
        async let steps14Task = try? hk.fetchDailyStepSums(days: 14)
        async let steps30Task = try? hk.fetchDailyStepSums(days: 30)
        async let vo2Max14Task = HealthFactorKey.vo2Max.loadSeries(days: 14)
        async let wrist14Task = try? hk.fetchDailySleepingWristTemperatureAverages(days: 14)
        async let bodyFat14Task = HealthFactorKey.bodyFat.loadSeries(days: 14)

        let snapshot = BasalEnergyInterpretationSnapshot(
            basal7: await basal7Task ?? [],
            basal14: await basal14Task ?? [],
            basal30: await basal30Task ?? [],
            sleep14: await sleep14Task ?? [],
            sleep30: await sleep30Task ?? [],
            sleepConsistency14: await consistency14Task ?? [],
            hrv14: await hrv14Task ?? [],
            restingHeartRate14: await rhr14Task ?? [],
            restingHeartRate30: await rhr30Task ?? [],
            steps14: await steps14Task ?? [],
            steps30: await steps30Task ?? [],
            vo2Max14: await vo2Max14Task,
            wristTemperature14: await wrist14Task ?? [],
            bodyFat14: await bodyFat14Task,
            waterMlToday: max(habitViewModel.waterAmount, 0),
            caffeineMgToday: habitViewModel.caffeineAmount
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

        let engine = BasalEnergyInsightEngine()
        let result = engine.analyze(snapshot: snapshot, today: currentDate)
        dailySummary = result.dailySummary
        abnormalDays = result.abnormalDays
        manualProfile = result.manualProfile
        signalLanguageCard = result.signalLanguageCard
        interpretationCards = result.interpretationCards
        state = .ready
    }
}

struct BasalEnergyInterpretationCard: Identifiable {
    let id: String
    let title: String
    let badge: String
    let summary: String
    let detail: String
    let tint: Color
}

struct BasalEnergyDailySummary {
    enum StabilityLevel: String {
        case stable
        case mild
        case caution
        case high

        var displayName: String {
            switch self {
            case .stable: return String(localized: "底盘稳定")
            case .mild: return String(localized: "轻度波动")
            case .caution: return String(localized: "需留意")
            case .high: return String(localized: "明显偏移")
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

struct BasalEnergyAbnormalDay: Identifiable {
    let id: String
    let date: Date
    let dateText: String
    let reason: String
    let triggerSummary: String
    let actionSuggestion: String
    let levelText: String
    let tint: Color
}

struct BasalEnergyManualProfile {
    enum Kind: String {
        case recoveryTight
        case rhythmDrift
        case stimulationAccumulation
        case steadyMaintenance
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

private struct BasalEnergyInterpretationSnapshot {
    let basal7: [TimeSeriesPointDouble]
    let basal14: [TimeSeriesPointDouble]
    let basal30: [TimeSeriesPointDouble]
    let sleep14: [TimeSeriesPointDouble]
    let sleep30: [TimeSeriesPointDouble]
    let sleepConsistency14: [TimeSeriesPointDouble]
    let hrv14: [TimeSeriesPointDouble]
    let restingHeartRate14: [TimeSeriesPointDouble]
    let restingHeartRate30: [TimeSeriesPointDouble]
    let steps14: [TimeSeriesPointDouble]
    let steps30: [TimeSeriesPointDouble]
    let vo2Max14: [TimeSeriesPointDouble]
    let wristTemperature14: [TimeSeriesPointDouble]
    let bodyFat14: [TimeSeriesPointDouble]
    let waterMlToday: Int
    let caffeineMgToday: Int

    var availableSignalCount: Int {
        [
            !basal7.isEmpty,
            !sleep14.isEmpty,
            !sleepConsistency14.isEmpty,
            !hrv14.isEmpty,
            !restingHeartRate14.isEmpty,
            !steps14.isEmpty,
            !vo2Max14.isEmpty,
            waterMlToday > 0,
            caffeineMgToday > 0
        ]
        .filter { $0 }
        .count
    }
}

private struct BasalEnergyInterpretationResult {
    let dailySummary: BasalEnergyDailySummary
    let abnormalDays: [BasalEnergyAbnormalDay]
    let manualProfile: BasalEnergyManualProfile
    let signalLanguageCard: BasalEnergyInterpretationCard
    let interpretationCards: [BasalEnergyInterpretationCard]
}

private struct BasalEnergyInsightEngine {
    func analyze(snapshot: BasalEnergyInterpretationSnapshot, today: Date) -> BasalEnergyInterpretationResult {
        let calendar = Calendar.current
        let basalToday = latestValue(on: today, from: snapshot.basal7)
        let basalBaseline = averageExcludingLatest(snapshot.basal14)
        let basal7Average = averageRaw(snapshot.basal7)
        let basal30Average = averageRaw(snapshot.basal30)
        let sleepToday = latestValue(on: today, from: snapshot.sleep14)
        let sleepBaseline = averageExcludingLatest(snapshot.sleep14)
        let hrvToday = latestValue(on: today, from: snapshot.hrv14)
        let hrvBaseline = averageExcludingLatest(snapshot.hrv14)
        let rhrToday = latestValue(on: today, from: snapshot.restingHeartRate14)
        let rhrBaseline = averageExcludingLatest(snapshot.restingHeartRate14)
        let stepsToday = latestValue(on: today, from: snapshot.steps14)
        let sleepConsistencyToday = latestValue(on: today, from: snapshot.sleepConsistency14)
        let vo2Recent = latestPositiveValue(from: snapshot.vo2Max14)
        let wristToday = latestValue(on: today, from: snapshot.wristTemperature14)
        let wristBaseline = averageRawExcludingLatest(snapshot.wristTemperature14)

        var cautionSignals: [String] = []
        var strongSignals: [String] = []
        var score = 84

        // 基础能量稳定性检查
        if let basalToday, let basalBaseline, basalBaseline > 0 {
            let delta = basalToday - basalBaseline
            let ratio = abs(delta) / basalBaseline
            if ratio >= 0.12 {
                strongSignals.append(basalToday > basalBaseline ? "基础代谢连续抬高" : "基础代谢连续走低")
                score -= 12
            } else if ratio >= 0.06 {
                cautionSignals.append("基础代谢有轻微偏移")
                score -= 6
            }
        }

        // 七日基础能量变异系数
        let cv = coefficientOfVariation(snapshot.basal7)
        if cv > 0.15 {
            strongSignals.append("近 7 天底盘波动偏大")
            score -= 10
        } else if cv > 0.08 {
            cautionSignals.append("近 7 天底盘有轻波动")
            score -= 5
        }

        if let sleepToday, let sleepBaseline, sleepToday < max(300, sleepBaseline * 0.88) {
            strongSignals.append("睡眠时长低于近一周基线")
            score -= 10
        }
        if let sleepConsistencyToday, sleepConsistencyToday < 72 {
            cautionSignals.append("作息稳定度偏低")
            score -= 6
        }
        if let hrvToday, let hrvBaseline, hrvToday < hrvBaseline * 0.84 {
            strongSignals.append("HRV 明显低于近一周")
            score -= 10
        }
        if let rhrToday, let rhrBaseline, rhrToday > rhrBaseline + 4 {
            strongSignals.append("静息心率高于近一周")
            score -= 10
        }
        if let stepsToday, let stepsBaseline = averageExcludingLatest(snapshot.steps14), stepsToday < stepsBaseline * 0.7 {
            cautionSignals.append("活动量较近一周回落")
            score -= 5
        }
        if snapshot.caffeineMgToday >= 180 {
            cautionSignals.append("今天刺激输入偏高")
            score -= 5
        }
        if snapshot.waterMlToday > 0 && snapshot.waterMlToday < 1200 {
            cautionSignals.append("补水还没补齐")
            score -= 3
        }

        score = max(36, min(95, score))

        let stabilityLevel: BasalEnergyDailySummary.StabilityLevel
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
            dailyHeadline = "今天的底盘消耗整体比较稳定。"
        case .mild:
            dailyHeadline = "今天出现了轻微波动，但还没有到明显失衡。"
        case .caution:
            dailyHeadline = "今天的恢复和代谢信号已经开始互相拉扯。"
        case .high:
            dailyHeadline = "今天更像是多条状态线索一起在提醒你关注底盘。"
        }

        let dailyNarrative = buildDailyNarrative(strongSignals: strongSignals, cautionSignals: cautionSignals)
        let dailyExplanation = buildExplanation(
            basalToday: basalToday,
            basalBaseline: basalBaseline,
            basal7Average: basal7Average,
            basal30Average: basal30Average,
            sleepToday: sleepToday,
            hrvToday: hrvToday,
            rhrToday: rhrToday,
            vo2Recent: vo2Recent,
            snapshot: snapshot
        )
        let dailySummary = BasalEnergyDailySummary(
            stabilityLevel: stabilityLevel,
            score: score,
            headline: dailyHeadline,
            narrative: dailyNarrative,
            explanation: dailyExplanation,
            signalPills: signalPills(
                basalToday: basalToday,
                sleepToday: sleepToday,
                hrvToday: hrvToday,
                rhrToday: rhrToday,
                vo2Recent: vo2Recent,
                stepsToday: stepsToday,
                snapshot: snapshot
            ),
            accentColor: tint(for: stabilityLevel)
        )

        let shortTermCard = BasalEnergyInterpretationCard(
            id: "single-day",
            title: "单日解释",
            badge: shortTermBadge(for: stabilityLevel),
            summary: shortTermSummary(
                score: score,
                strongSignals: strongSignals,
                cautionSignals: cautionSignals,
                snapshot: snapshot
            ),
            detail: shortTermDetail(snapshot: snapshot, stabilityLevel: stabilityLevel),
            tint: tint(for: stabilityLevel)
        )
        let weeklyCard = BasalEnergyInterpretationCard(
            id: "week",
            title: "7 天解释",
            badge: weeklyBadge(snapshot: snapshot),
            summary: weeklySummary(snapshot: snapshot),
            detail: weeklyDetail(snapshot: snapshot),
            tint: Color(hex: "5B8CFF")
        )
        let monthlyCard = BasalEnergyInterpretationCard(
            id: "month",
            title: "30 天解释",
            badge: monthlyBadge(snapshot: snapshot),
            summary: monthlySummary(snapshot: snapshot),
            detail: monthlyDetail(snapshot: snapshot),
            tint: Color(hex: "E29A63")
        )

        let abnormalDays = buildAbnormalDays(snapshot: snapshot, calendar: calendar)
        let manualProfile = buildManualProfile(snapshot: snapshot, stabilityLevel: stabilityLevel, strongSignals: strongSignals, cautionSignals: cautionSignals)
        let signalLanguageCard = buildSignalLanguageCard(
            basalToday: basalToday,
            basalBaseline: basalBaseline,
            hrvToday: hrvToday,
            hrvBaseline: hrvBaseline,
            rhrToday: rhrToday,
            rhrBaseline: rhrBaseline,
            wristToday: wristToday,
            wristBaseline: wristBaseline,
            vo2Recent: vo2Recent,
            snapshot: snapshot
        )

        return BasalEnergyInterpretationResult(
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
        return String(localized: "基础代谢、恢复和活动输入暂时没有出现明显冲突。")
    }

    private func buildExplanation(
        basalToday: Double?,
        basalBaseline: Double?,
        basal7Average: Double,
        basal30Average: Double,
        sleepToday: Double?,
        hrvToday: Double?,
        rhrToday: Double?,
        vo2Recent: Double?,
        snapshot: BasalEnergyInterpretationSnapshot
    ) -> String {
        var parts: [String] = []
        if let basalToday, basalToday > 0 {
            parts.append("今日基础代谢 \(Int(basalToday.rounded())) kcal")
        }
        if let basalBaseline, basalBaseline > 0 {
            parts.append("近 14 天均值 \(Int(basalBaseline.rounded())) kcal")
        }
        if basal7Average > 0 {
            parts.append("7 天均值 \(Int(basal7Average.rounded())) kcal")
        }
        if basal30Average > 0 {
            parts.append("30 天均值 \(Int(basal30Average.rounded())) kcal")
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
        if snapshot.caffeineMgToday > 0 {
            parts.append("咖啡因 \(snapshot.caffeineMgToday) mg")
        }
        if let vo2Recent, vo2Recent > 0 {
            parts.append("VO2Max \(String(format: "%.1f", vo2Recent))")
        }
        if parts.isEmpty {
            return String(localized: "当前更多还是依据活动和你手动补充的行为记录做保守阅读。")
        }
        return "这次判断主要综合了 \(parts.joined(separator: "、")) 这些信号。"
    }

    private func signalPills(
        basalToday: Double?,
        sleepToday: Double?,
        hrvToday: Double?,
        rhrToday: Double?,
        vo2Recent: Double?,
        stepsToday: Double?,
        snapshot: BasalEnergyInterpretationSnapshot
    ) -> [BasalEnergyDailySummary.SignalPill] {
        [
            .init(
                id: "basal",
                title: "基础代谢",
                value: basalToday.map { "\(Int($0.rounded())) kcal" } ?? "--",
                note: "今日底盘",
                tint: Color(hex: "E89B3B")
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
                id: "vo2max",
                title: "VO2Max",
                value: vo2Recent.map { String(format: "%.1f", $0) } ?? "--",
                note: "体能底盘",
                tint: Color(hex: "8D7AFF")
            ),
            .init(
                id: "steps",
                title: "活动",
                value: stepsToday.map { "\(Int($0.rounded())) 步" } ?? "--",
                note: "行动节律",
                tint: Color(hex: "32ADE6")
            ),
            .init(
                id: "context",
                title: "上下文",
                value: contextValue(snapshot: snapshot),
                note: "行为线索",
                tint: Color(hex: "8D7AFF")
            )
        ]
    }

    private func contextValue(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        if snapshot.caffeineMgToday >= 180 {
            return "刺激偏高"
        }
        if snapshot.waterMlToday > 0 && snapshot.waterMlToday < 1200 {
            return "补水偏少"
        }
        return String(localized: "暂无明显偏移")
    }

    private func shortTermBadge(for level: BasalEnergyDailySummary.StabilityLevel) -> String {
        switch level {
        case .stable: return "今天偏稳"
        case .mild: return "轻微偏移"
        case .caution: return "恢复拉扯"
        case .high: return "多信号共振"
        }
    }

    private func shortTermSummary(
        score: Int,
        strongSignals: [String],
        cautionSignals: [String],
        snapshot: BasalEnergyInterpretationSnapshot
    ) -> String {
        if !strongSignals.isEmpty {
            return "单日层面更像是 \(strongSignals.prefix(2).joined(separator: "、")) 一起把今天的底盘消耗往上或往下拉。"
        }
        if snapshot.caffeineMgToday > 0 {
            return String(localized: "单日层面更像是外部刺激和恢复底盘正在互相影响。")
        }
        return score >= 80 ? "今天更接近正常波动。" : "今天更适合先按轻负荷日理解。"
    }

    private func shortTermDetail(snapshot: BasalEnergyInterpretationSnapshot, stabilityLevel: BasalEnergyDailySummary.StabilityLevel) -> String {
        switch stabilityLevel {
        case .stable:
            return String(localized: "当前没有看到明显需要放大的单日异常，更适合继续维持节律，而不是过度解读单个数字。")
        case .mild:
            return String(localized: "这类波动更像是恢复和日常输入的轻微错位，通常先把睡眠、补水和白天节律拉稳，会比立刻追问某个单点数值更有帮助。")
        case .caution:
            return String(localized: "今天已经出现恢复不足、刺激累积或活动回落的组合迹象，更适合把节奏往轻一点调，避免继续堆刺激。")
        case .high:
            return String(localized: "今天更像是多条核心信号都在同方向偏移，说明身体正在明确提醒你先照顾恢复，而不是继续往上加码。")
        }
    }

    private func weeklyBadge(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.hrv14) < -1.2 || slope(of: snapshot.restingHeartRate14) > 1.0 {
            return "恢复走低"
        }
        return String(localized: "近一周观察")
    }

    private func weeklySummary(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.hrv14) < -1.2 && slope(of: snapshot.restingHeartRate14) > 0.8 {
            return String(localized: "最近 7 天更像是恢复基线在慢慢走低，连带基础代谢也在偏移。")
        }
        if average(snapshot.sleepConsistency14) < 75 {
            return String(localized: "最近 7 天更像是作息稳定度在下滑，底盘消耗也会跟着波动。")
        }
        if average(snapshot.steps14) < 4500 {
            return String(localized: "最近 7 天更像是活动底盘偏低。")
        }
        return String(localized: "最近 7 天整体更接近轻度波动，而不是持续恶化。")
    }

    private func weeklyDetail(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        if snapshot.caffeineMgToday >= 180 {
            return String(localized: "这周如果继续叠加高刺激输入，后面几天更容易把轻波动拖成连续疲惫感。")
        }
        if average(snapshot.sleepConsistency14) < 75 {
            return String(localized: "这一周更适合优先把睡觉和起床时点拉回稳定，再回头看基础代谢是不是一起回稳。")
        }
        return String(localized: "一周维度更适合看方向，不适合拿单日高低做硬判断。")
    }

    private func monthlyBadge(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.basal30) != 0 && abs(slope(of: snapshot.basal30)) > 15 {
            return String(localized: "月内偏移")
        }
        return String(localized: "长期画像")
    }

    private func monthlySummary(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        if slope(of: snapshot.hrv14) < -1.0 && slope(of: snapshot.restingHeartRate30) > 0.6 {
            return String(localized: "最近 30 天更像是恢复资源被持续消耗，底盘消耗也在跟着调整。")
        }
        if average(snapshot.steps30) < 5000 {
            return String(localized: "最近 30 天整体活动底盘偏低，更像是慢变量层面的回落。")
        }
        return String(localized: "最近 30 天还没有形成很强的单方向迁移。")
    }

    private func monthlyDetail(snapshot: BasalEnergyInterpretationSnapshot) -> String {
        return String(localized: "月度层面更适合拿来理解你更像哪一类底盘消耗模式，而不是判断某一天是不是异常。")
    }

    private func buildSignalLanguageCard(
        basalToday: Double?,
        basalBaseline: Double?,
        hrvToday: Double?,
        hrvBaseline: Double?,
        rhrToday: Double?,
        rhrBaseline: Double?,
        wristToday: Double?,
        wristBaseline: Double?,
        vo2Recent: Double?,
        snapshot: BasalEnergyInterpretationSnapshot
    ) -> BasalEnergyInterpretationCard {
        var alignedSignals: [String] = []
        var softSignals: [String] = []

        if let basalToday, let basalBaseline, basalBaseline > 0 {
            let ratio = abs(basalToday - basalBaseline) / basalBaseline
            if ratio >= 0.12 {
                alignedSignals.append(basalToday > basalBaseline ? "底盘消耗抬高" : "底盘消耗走低")
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

        if let wristToday, let wristBaseline, abs(wristToday - wristBaseline) >= 0.35 {
            alignedSignals.append("腕温背景有偏移")
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
            tint = Color(hex: "E89B3B")
            summary = "多条信号暂时没有形成同向偏移，单个数字轻微变化更像普通波动。"
        }

        let supportingText = softSignals.prefix(2).joined(separator: "；")
        let detailPrefix = supportingText.isEmpty ? "" : "\(supportingText)。"
        return BasalEnergyInterpretationCard(
            id: "signal-language",
            title: "底盘信号合读",
            badge: badge,
            summary: summary,
            detail: "\(detailPrefix)基础代谢更像底盘消耗的快变量，HRV 更像恢复弹性，静息心率更像负荷线索，腕温适合提示夜间扰动或身体背景，VO2Max 是体能底盘的慢变量；只有连续几天、两三条信号同向偏移时，才值得提高关注。",
            tint: tint
        )
    }

    private func buildAbnormalDays(snapshot: BasalEnergyInterpretationSnapshot, calendar: Calendar) -> [BasalEnergyAbnormalDay] {
        let hrvBaseline = averageExcludingLatest(snapshot.hrv14)
        let rhrBaseline = averageExcludingLatest(snapshot.restingHeartRate14)
        let sleepBaseline = averageExcludingLatest(snapshot.sleep14)
        let stepsBaseline = averageExcludingLatest(snapshot.steps14)
        let basalBaseline = averageExcludingLatest(snapshot.basal14)

        let dates = Set(snapshot.basal14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.hrv14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.restingHeartRate14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.sleep14.map { calendar.startOfDay(for: $0.date) })
            .union(snapshot.steps14.map { calendar.startOfDay(for: $0.date) })
            .sorted(by: >)

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")

        return dates.prefix(5).compactMap { date in
            let basal = value(on: date, from: snapshot.basal14, calendar: calendar)
            let hrv = value(on: date, from: snapshot.hrv14, calendar: calendar)
            let rhr = value(on: date, from: snapshot.restingHeartRate14, calendar: calendar)
            let sleep = value(on: date, from: snapshot.sleep14, calendar: calendar)
            let steps = value(on: date, from: snapshot.steps14, calendar: calendar)

            var strongCount = 0
            var triggers: [String] = []

            if let basal, let basalBaseline, basalBaseline > 0, abs(basal - basalBaseline) / basalBaseline >= 0.12 {
                strongCount += 1
                triggers.append(basal > basalBaseline ? "底盘抬高" : "底盘走低")
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
            if let steps, let stepsBaseline, steps < stepsBaseline * 0.6 {
                triggers.append("活动回落")
            }

            guard strongCount >= 2 else { return nil }

            let tint = strongCount >= 3 ? Color(hex: "F46B5A") : Color(hex: "FF9F0A")
            return BasalEnergyAbnormalDay(
                id: "abnormal-\(Int(date.timeIntervalSince1970))",
                date: date,
                dateText: formatter.string(from: date),
                reason: strongCount >= 3 ? "这一天更像是明显的共振偏移日。" : "这一天出现了值得单独留意的信号叠加。",
                triggerSummary: "触发信号：\(triggers.joined(separator: "、"))",
                actionSuggestion: strongCount >= 3 ? "回看当天的睡眠、刺激输入和活动记录，优先按恢复日理解。" : "把它放回前后几天一起看，判断是不是连续在偏移。",
                levelText: strongCount >= 3 ? "高扰动日" : "需留意日",
                tint: tint
            )
        }
    }

    private func buildManualProfile(
        snapshot: BasalEnergyInterpretationSnapshot,
        stabilityLevel: BasalEnergyDailySummary.StabilityLevel,
        strongSignals: [String],
        cautionSignals: [String]
    ) -> BasalEnergyManualProfile {
        let avgSleepConsistency = average(snapshot.sleepConsistency14)

        if strongSignals.contains(where: { $0.contains("HRV") || $0.contains("静息心率") }) {
            return BasalEnergyManualProfile(
                kind: .recoveryTight,
                title: "恢复偏紧型",
                badge: "恢复优先",
                definition: "最近更像是恢复底盘不够宽裕，身体对负荷和刺激的缓冲能力在变紧，基础代谢也会跟着出现偏移。",
                triggers: "常见于睡眠回落、HRV 下探、静息心率抬高一起出现时。",
                priorities: "优先看睡眠时长、HRV、静息心率和今天有没有继续叠刺激。",
                action: "适合把训练和任务强度先压轻一点，优先补睡、补水和白天节律。",
                dontOverread: "不要只盯某一次高心率或一次差睡眠，而要看这几条恢复信号是不是连续一起偏移。",
                tint: Color(hex: "F46B5A")
            )
        }

        if avgSleepConsistency < 75 {
            return BasalEnergyManualProfile(
                kind: .rhythmDrift,
                title: "节律漂移型",
                badge: "节律优先",
                definition: "最近更像是夜间作息稳定度变弱，身体时钟有点漂，底盘消耗也会跟着波动。",
                triggers: "常见于作息时间不稳、睡眠一致性下降时。",
                priorities: "优先看日照、睡眠一致性、入睡/起床时点和白天活动节律。",
                action: "适合先把起床时间和上午清醒信号拉稳，再观察基础代谢会不会回正。",
                dontOverread: "不要把所有波动都理解成代谢问题，很多时候先是节律底盘在松。",
                tint: Color(hex: "5B8CFF")
            )
        }

        if snapshot.caffeineMgToday >= 180 || cautionSignals.contains(where: { $0.contains("刺激") }) {
            return BasalEnergyManualProfile(
                kind: .stimulationAccumulation,
                title: "刺激累积型",
                badge: "刺激偏多",
                definition: "最近更像是外部刺激或输入节奏偏满，身体一直在顶着走，底盘消耗也会被推高。",
                triggers: "常见于咖啡因偏高、补水不足或睡眠恢复没跟上的组合里。",
                priorities: "优先看咖啡因、补水和当天晚间的收尾节奏。",
                action: "适合先减少额外刺激输入，给身体留一点真正松下来的窗口。",
                dontOverread: "不要把这种波动直接理解成身体突然变差，很多时候只是刺激还没退出场。",
                tint: Color(hex: "FF9F0A")
            )
        }

        return BasalEnergyManualProfile(
            kind: .steadyMaintenance,
            title: "稳态维护型",
            badge: stabilityLevel == .stable ? "整体平稳" : "可维护",
            definition: "最近整体更像是处在可维护的稳定区间，没有看到很强的连续偏移。",
            triggers: "通常出现在睡眠、恢复、活动和日常输入没有明显对冲时。",
            priorities: "优先看是否还能把节律继续保持，而不是急着寻找问题。",
            action: "适合继续维持当前作息和活动习惯，只在出现连续偏移时再提高警觉。",
            dontOverread: "不要因为某个单日数字轻微变化就打破整体节奏，趋势比单点更重要。",
            tint: Color(hex: "E89B3B")
        )
    }

    // MARK: - 数学辅助

    private func latestValue(on date: Date, from points: [TimeSeriesPointDouble]) -> Double? {
        value(on: date, from: points, calendar: .current)
    }

    private func average(_ points: [TimeSeriesPointDouble]) -> Double {
        BasalEnergyMetricMath.average(points)
    }

    private func averageExcludingLatest(_ points: [TimeSeriesPointDouble]) -> Double? {
        let values = BasalEnergyMetricMath.positiveValues(from: points)
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

    private func averageRawExcludingLatest(_ points: [TimeSeriesPointDouble]) -> Double? {
        let values = points.map(\.value)
        guard values.count >= 2 else { return values.first }
        let prefix = Array(values.dropLast())
        guard !prefix.isEmpty else { return values.last }
        return prefix.reduce(0, +) / Double(prefix.count)
    }

    private func latestPositiveValue(from points: [TimeSeriesPointDouble]) -> Double? {
        points.sorted { $0.date > $1.date }.first(where: { $0.value > 0 })?.value
    }

    private func coefficientOfVariation(_ points: [TimeSeriesPointDouble]) -> Double {
        let values = BasalEnergyMetricMath.positiveValues(from: points)
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance) / mean
    }

    private func slope(of points: [TimeSeriesPointDouble]) -> Double {
        let values = BasalEnergyMetricMath.positiveValues(from: points)
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

    private func tint(for level: BasalEnergyDailySummary.StabilityLevel) -> Color {
        switch level {
        case .stable: return Color(hex: "E89B3B")
        case .mild: return Color(hex: "5B8CFF")
        case .caution: return Color(hex: "FF9F0A")
        case .high: return Color(hex: "F46B5A")
        }
    }
}

private enum BasalEnergyMetricMath {
    static func positiveValues(from points: [TimeSeriesPointDouble]) -> [Double] {
        points.map(\.value).filter { $0 > 0 }
    }

    static func average(_ points: [TimeSeriesPointDouble]) -> Double {
        let values = positiveValues(from: points)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
