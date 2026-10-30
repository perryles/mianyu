import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import OSLog


/// DashboardViewModel 工作节律卡片构建（纯静态计算）。
/// 从原 DashboardViewModel.swift 拆出，对外接口不变。

@MainActor
extension DashboardViewModel {

    static func makeWorkRhythmContent(
        state: DashboardSedentaryState,
        summary: SedentaryDaySummary,
        assessment: StressPresentationAssessment,
        context: HealthAIContext,
        now: Date
    ) -> WorkRhythmCardContent {
        let phase = resolvedWorkRhythmPhase(
            state: state,
            assessment: assessment,
            context: context,
            now: now
        )
        let focusMinutes = recommendedFocusBlockMinutes(for: context.recoveryScriptPlan?.readinessBand)
        let focusBlockMinutesText = "\(max(20, focusMinutes - 5))-\(focusMinutes) 分钟"
        let breakMinutes = SedentaryBreakProgressState.defaultTargetMinutes(for: state)
        let preferredBreakKind = preferredBreakKind(summary: summary, historySummaries: [summary])
        let breakTitle = preferredBreakKind?.title ?? "起身"
        let currentDaypart = daypartLabel(for: now)
        let intensity: WorkRhythmIntensity
        switch phase {
        case .protect:
            intensity = .highRisk
        case .reset:
            intensity = state.elapsedMinutes >= 90 ? .highRisk : .steady
        case .windDown:
            intensity = .light
        case .focus:
            intensity = assessment.band == .mild ? .steady : .light
        }

        let recoverySwitchText: String
        if phase == .protect {
            recoverySwitchText = "先\(breakTitle) \(breakMinutes) 分钟，再把后面的工作密度降一档。"
        } else if state.isCounting && state.elapsedMinutes >= 60 {
            recoverySwitchText = "先\(breakTitle) \(breakMinutes) 分钟，再决定要不要继续推进。"
        } else if phase == .windDown {
            recoverySwitchText = "这会儿更适合收尾而不是硬顶下一段工作。"
        } else {
            recoverySwitchText = "这一段先按 \(focusBlockMinutesText) 推进，中间预留一次短恢复会更稳。"
        }

        let pressureProtectionText: String
        if phase == .protect {
            pressureProtectionText = "今天恢复偏紧，重要任务只保留一段，其余尽量降载。"
        } else if intensity == .highRisk {
            pressureProtectionText = "当前已经有点顶满了，先做短恢复再看后半段。"
        } else if phase == .windDown {
            pressureProtectionText = "晚上尽量别再临时加码，把收尾和入睡窗口守住。"
        } else {
            pressureProtectionText = "当前工作密度还能维持，但别把恢复窗口全部挤掉。"
        }

        let headline: String
        let subheadline: String
        switch phase {
        case .focus:
            headline = "现在适合推进一段"
            subheadline = "状态更适合按 \(focusBlockMinutesText) 做一段专注，再插一次轻恢复。"
        case .reset:
            headline = "先做一次短恢复"
            subheadline = recoverySwitchText
        case .protect:
            headline = "今天先保护工作密度"
            subheadline = pressureProtectionText
        case .windDown:
            headline = "这会儿适合开始收尾"
            subheadline = context.recoveryScriptPlan?.eveningScript ?? "把重要事情收口后，尽量别继续拉长晚间工作。"
        }

        let suggestedActions = makeWorkRhythmActions(
            phase: phase,
            focusBlockMinutesText: focusBlockMinutesText,
            recoverySwitchText: recoverySwitchText,
            pressureProtectionText: pressureProtectionText,
            context: context,
            breakMinutes: breakMinutes
        )
        let avoidItems = (context.recoveryScriptPlan?.avoidList ?? []).isEmpty
            ? defaultAvoidItems(for: phase)
            : (context.recoveryScriptPlan?.avoidList ?? [])

        return WorkRhythmCardContent(
            headline: headline,
            subheadline: subheadline,
            phase: phase,
            intensity: intensity,
            energyWindowTitle: "\(currentDaypart)更适合\(phase == .focus ? "推进" : phase == .reset ? "补光和起身" : phase == .protect ? "降载保护" : "收尾")",
            suggestedActions: suggestedActions.sorted(by: { $0.priority < $1.priority }),
            avoidItems: avoidItems,
            focusBlockMinutesText: focusBlockMinutesText,
            recoverySwitchText: recoverySwitchText,
            pressureProtectionText: pressureProtectionText,
            daypartPlans: makeDaypartPlans(context: context, phase: phase, now: now)
        )
    }

    static func daypartLabel(for date: Date) -> String {
        SedentaryDaySummary.sedentaryDaypartTitle(for: date)
    }

    static func preferredBreakKind(
        summary: SedentaryDaySummary,
        historySummaries: [SedentaryDaySummary]
    ) -> SedentaryBreakKind? {
        if let current = summary.dominantBreakKind {
            return current
        }

        let history = historySummaries.filter { $0.sourceStatus == .ready }
        guard !history.isEmpty else { return nil }

        let walking = history.reduce(0) { $0 + $1.walkingBreakCount }
        let exercise = history.reduce(0) { $0 + $1.exerciseBreakCount }
        let standing = history.reduce(0) { $0 + $1.standingBreakCount }
        let buckets: [(SedentaryBreakKind, Int)] = [
            (.walking, walking),
            (.exercise, exercise),
            (.standing, standing)
        ]
        return buckets.max(by: { $0.1 < $1.1 })?.1 == 0 ? nil : buckets.max(by: { $0.1 < $1.1 })?.0
    }

    static func preferredFocusBucket(
        summary: SedentaryDaySummary,
        historySummaries: [SedentaryDaySummary]
    ) -> String {
        if let todayBucket = SedentaryDaySummary.preferredSedentaryDaypart(in: [summary]) {
            return todayBucket.title
        }

        let history = historySummaries
            .filter { !Calendar.current.isDateInToday($0.date) && $0.sourceStatus == .ready }
        guard !history.isEmpty else { return "白天" }

        return SedentaryDaySummary.preferredSedentaryDaypart(in: history)?.title ?? "白天"
    }

    static func resolvedWorkRhythmPhase(
        state: DashboardSedentaryState,
        assessment: StressPresentationAssessment,
        context: HealthAIContext,
        now: Date
    ) -> WorkRhythmPhase {
        let hour = Calendar.current.component(.hour, from: now)
        let readinessBand = context.recoveryScriptPlan?.readinessBand
        let stressProtect = assessment.band == .caution || assessment.band == .high
        let afternoonNeedsReset = (14..<18).contains(hour)
            && ((context.daylightMinutesToday ?? 0) < 10 || state.elapsedMinutes >= 60)

        if stressProtect || readinessBand == .protect {
            return .protect
        }
        if hour >= 19 {
            return .windDown
        }
        if state.elapsedMinutes >= 60 || afternoonNeedsReset || readinessBand == .recover {
            return .reset
        }
        return .focus
    }

    static func recommendedFocusBlockMinutes(for band: RecoveryReadinessBand?) -> Int {
        switch band {
        case .protect:
            return 20
        case .recover:
            return 25
        case .balanced:
            return 35
        case .pushLight:
            return 45
        case .none:
            return 30
        }
    }

    static func makeWorkRhythmActions(
        phase: WorkRhythmPhase,
        focusBlockMinutesText: String,
        recoverySwitchText: String,
        pressureProtectionText: String,
        context: HealthAIContext,
        breakMinutes: Int
    ) -> [WorkRhythmAction] {
        let afternoonText = context.recoveryScriptPlan?.afternoonScript ?? "午后优先补一点自然光和轻步行，再继续后半段。"
        let eveningText = context.recoveryScriptPlan?.eveningScript ?? "晚上尽量提前收尾，把睡前节奏放缓。"
        let morningText = context.recoveryScriptPlan?.morningScript ?? "上午先推进最重要的一件事，中间记得插一次短恢复。"

        switch phase {
        case .focus:
            return [
                WorkRhythmAction(title: "先推进一段", detail: "\(morningText) 建议窗口 \(focusBlockMinutesText)。", symbol: "bolt.fill", tintHex: "007F79", priority: 0),
                WorkRhythmAction(title: "中途留恢复点", detail: "中间插一次 \(breakMinutes) 分钟短走动，会比硬顶到疲劳更稳。", symbol: "figure.walk.motion", tintHex: "75C7E8", priority: 1),
                WorkRhythmAction(title: "午后别堆太满", detail: afternoonText, symbol: "sun.max.fill", tintHex: "F4A259", priority: 2)
            ]
        case .reset:
            return [
                WorkRhythmAction(title: "先做恢复切换", detail: recoverySwitchText, symbol: "figure.stand", tintHex: "63D471", priority: 0),
                WorkRhythmAction(title: "补一点自然光", detail: afternoonText, symbol: "sun.max.fill", tintHex: "F4C430", priority: 1),
                WorkRhythmAction(title: "回来再决定强度", detail: "短恢复后再判断是继续推进，还是把这段改成轻任务。", symbol: "arrow.triangle.2.circlepath", tintHex: "7C8CFF", priority: 2)
            ]
        case .protect:
            return [
                WorkRhythmAction(title: "先降工作密度", detail: pressureProtectionText, symbol: "shield.lefthalf.filled", tintHex: "FF7A70", priority: 0),
                WorkRhythmAction(title: "今天只保留一段重点", detail: "最耗神的事情保留一段就够了，其余尽量改成轻任务或后移。", symbol: "list.bullet.clipboard", tintHex: "FF946E", priority: 1),
                WorkRhythmAction(title: "晚上尽量早收尾", detail: eveningText, symbol: "moon.stars.fill", tintHex: "5E5CE6", priority: 2)
            ]
        case .windDown:
            return [
                WorkRhythmAction(title: "开始收尾", detail: eveningText, symbol: "moon.stars.fill", tintHex: "5E5CE6", priority: 0),
                WorkRhythmAction(title: "别再开新重任务", detail: "现在更适合处理收口、整理和明天的预留，而不是继续拉长工作。", symbol: "checklist", tintHex: "7C8CFF", priority: 1),
                WorkRhythmAction(title: "给睡前留缓冲", detail: "工作结束和入睡之间尽量留出 1 到 2 小时，让身体有机会慢慢收下来。", symbol: "bed.double.fill", tintHex: "75C7E8", priority: 2)
            ]
        }
    }

    static func defaultAvoidItems(for phase: WorkRhythmPhase) -> [String] {
        switch phase {
        case .focus:
            return ["连续坐太久不打断", "把后半天所有重任务都挤在一起"]
        case .reset:
            return ["起身几十秒就立刻坐回去", "午后继续缺光和久坐叠加"]
        case .protect:
            return ["把晚间任务继续拉满", "临时加练高强度运动", "继续补高咖啡因饮品"]
        case .windDown:
            return ["晚上临时再开高耗神任务", "收尾前继续补刺激性饮品"]
        }
    }

    static func makeDaypartPlans(
        context: HealthAIContext,
        phase: WorkRhythmPhase,
        now: Date
    ) -> [WorkRhythmDaypartPlanItem] {
        let highlighted = daypartLabel(for: now)
        let scripts = [
            ("上午", context.recoveryScriptPlan?.morningScript ?? "上午先推进最重要的一件事，中间记得插一次短恢复。", "sunrise.fill", "007F79"),
            ("中午", "中午先补水、起身或走一小段，把前半段工作从身体里缓出来。", "sun.min.fill", "75C7E8"),
            ("下午", context.recoveryScriptPlan?.afternoonScript ?? "午后优先补一点自然光和轻步行，再继续后半段。", "sun.max.fill", "F4A259"),
            ("晚上", context.recoveryScriptPlan?.eveningScript ?? "晚上尽量提前收尾，把睡前节奏放缓。", "moon.stars.fill", "5E5CE6")
        ]

        return scripts.map { item in
            WorkRhythmDaypartPlanItem(
                title: item.0,
                detail: item.1,
                symbol: item.2,
                tintHex: item.3,
                isHighlighted: item.0 == highlighted || (phase == .windDown && item.0 == "晚上")
            )
        }
    }

}
