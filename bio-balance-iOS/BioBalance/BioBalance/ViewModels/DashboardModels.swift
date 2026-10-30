import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import OSLog


/// Dashboard 展示模型与状态载体。
/// 从原 DashboardViewModel.swift 拆出：与 VM 行为无关的纯数据模型保持独立，便于复用与单测。

import SwiftUI
import HealthKit
import WidgetKit
import OSLog

/// 仪表盘Other指标枚举 作为视图模型层里的状态与分类定义。
/// 负责描述界面状态管理与业务编排过程中会用到的状态、分类或分支。
enum DashboardOtherMetricDestination: String, CaseIterable, Identifiable, Sendable {
    case hrv
    case restingHeartRate
    case vo2Max
    case wristTemperature
    case sunlight
    case walkingAsymmetry
    case heartRhythm

    var id: String { rawValue }

}

/// 仪表盘Other指标状态色调枚举 作为视图模型层里的状态与分类定义。
/// 负责描述界面状态管理与业务编排过程中会用到的状态、分类或分支。
enum DashboardOtherMetricStatusTone: Equatable, Sendable {
    case positive
    case normal
    case caution
    case muted
}

/// 仪表盘Other指标数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct DashboardOtherMetricCardModel: Identifiable, Sendable {
    let id: String
    let title: String
    let valueText: String
    let unitText: String
    let statusText: String
    let statusTone: DashboardOtherMetricStatusTone
    let deltaText: String
    let lastUpdatedText: String
    let trendPoints: [TimeSeriesPointDouble]
    let isInteractive: Bool
    let destination: DashboardOtherMetricDestination?
}

/// 久坐Break进度结构体 作为视图模型层里的辅助类型。
/// 负责承载一次久坐打断流程的进行中或完成反馈状态。
struct SedentaryBreakProgressState: Equatable {
    enum Mode: Equatable {
        case idle
        case active
        case completed
    }

    let mode: Mode
    let targetMinutes: Int
    let startedAt: Date?
    let completedMinutes: Int?
    let completedAt: Date?

    static let idle = SedentaryBreakProgressState(
        mode: .idle,
        targetMinutes: 0,
        startedAt: nil,
        completedMinutes: nil,
        completedAt: nil
    )

    static func active(targetMinutes: Int, startedAt: Date) -> SedentaryBreakProgressState {
        SedentaryBreakProgressState(
            mode: .active,
            targetMinutes: max(1, targetMinutes),
            startedAt: startedAt,
            completedMinutes: nil,
            completedAt: nil
        )
    }

    static func completed(minutes: Int, completedAt: Date = Date()) -> SedentaryBreakProgressState {
        SedentaryBreakProgressState(
            mode: .completed,
            targetMinutes: 0,
            startedAt: nil,
            completedMinutes: max(1, minutes),
            completedAt: completedAt
        )
    }

    var isActive: Bool { mode == .active }
    var isCompletedFeedbackVisible: Bool { mode == .completed }

    func elapsedMinutes(now: Date) -> Int {
        guard mode == .active, let startedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(startedAt) / 60))
    }

    func hasReachedGoal(now: Date) -> Bool {
        isActive && elapsedMinutes(now: now) >= targetMinutes
    }

    static func defaultTargetMinutes(for state: DashboardSedentaryState) -> Int {
        switch state.sourceStatus {
        case .needsAuthorization, .sleeping, .autoStartDisabled, .noActivitySamples, .unavailable:
            return 3
        case .ready:
            if state.elapsedMinutes >= 90 { return 5 }
            if state.elapsedMinutes >= 60 { return 3 }
            return 2
        }
    }
}

struct SedentaryGuidanceItem: Equatable, Identifiable {
    let title: String
    let detail: String
    let symbol: String

    var id: String { "\(title)-\(symbol)" }
}

/// 久坐解读内容结构体 作为视图模型层里的辅助类型。
/// 负责把久坐状态、摘要与交互状态整合成可直接给视图消费的文案。
struct SedentaryInsightContent: Equatable {
    let cardTitle: String
    let cardSummary: String
    let cardValueText: String
    let cardValueUnit: String
    let dashboardActionTitle: String
    let dashboardActionDetail: String
    let breakSectionTitle: String
    let breakSectionDetail: String
    let historySummary: String
    let guidanceTitle: String
    let guidanceItems: [SedentaryGuidanceItem]
}

enum WorkRhythmPhase: String, Equatable, Sendable {
    case focus
    case reset
    case protect
    case windDown

    var title: String {
        switch self {
        case .focus:
            return String(localized: "专注节律")
        case .reset:
            return "恢复切换"
        case .protect:
            return "压力保护"
        case .windDown:
            return String(localized: "收尾节律")
        }
    }
}

enum WorkRhythmIntensity: Equatable, Sendable {
    case light
    case steady
    case highRisk
}

struct WorkRhythmAction: Identifiable, Equatable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    let tintHex: String
    let priority: Int

    var id: String { "\(priority)-\(title)-\(symbol)" }
}

struct WorkRhythmDaypartPlanItem: Identifiable, Equatable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    let tintHex: String
    let isHighlighted: Bool

    var id: String { title }
}

struct WorkRhythmCardContent: Equatable, Sendable {
    let headline: String
    let subheadline: String
    let phase: WorkRhythmPhase
    let intensity: WorkRhythmIntensity
    let energyWindowTitle: String
    let suggestedActions: [WorkRhythmAction]
    let avoidItems: [String]
    let focusBlockMinutesText: String
    let recoverySwitchText: String
    let pressureProtectionText: String
    let daypartPlans: [WorkRhythmDaypartPlanItem]
}

/// 仪表盘久坐结构体 作为视图模型层里的辅助类型。
/// 负责界面状态管理与业务编排。
struct DashboardSedentaryState: Equatable {
    /// Source Status 枚举，作为内部辅助类型，用于细分外层界面状态管理与业务编排中的状态或分支。
    enum SourceStatus: Equatable {
        case ready
        case sleeping
        case autoStartDisabled
        case needsAuthorization
        case noActivitySamples
        case unavailable
    }

    static let reminderMinutes = [30, 45, 60, 75, 90, 120]

    static func nextReminderMinute(elapsedMinutes: Int, intervalMinutes: Int) -> Int {
        let interval = max(1, intervalMinutes)
        let elapsed = max(0, elapsedMinutes)
        return ((elapsed / interval) + 1) * interval
    }

    let seatedStartAt: Date?
    let lastActivityAt: Date?
    let elapsedMinutes: Int
    let isCounting: Bool
    let pausedBySleep: Bool
    let sourceStatus: SourceStatus

    static let waiting = DashboardSedentaryState(seatedStartAt: nil, lastActivityAt: nil, elapsedMinutes: 0, isCounting: false, pausedBySleep: false, sourceStatus: .ready)

    var nextReminderMinute: Int? {
        Self.reminderMinutes.first { $0 > elapsedMinutes }
    }

    var recommendedBreakText: String {
        if sourceStatus == .needsAuthorization {
            return String(localized: "先授权")
        }
        if sourceStatus == .sleeping {
            return "睡眠优先"
        }
        if sourceStatus == .autoStartDisabled {
            return String(localized: "先开启")
        }
        if sourceStatus == .noActivitySamples {
            return String(localized: "等样本")
        }
        if sourceStatus == .unavailable {
            return String(localized: "稍后重试")
        }
        if elapsedMinutes >= 90 { return "5 分钟" }
        if elapsedMinutes >= 60 { return "3 分钟" }
        return "2 分钟"
    }

    func reminderSummaryText(remindersEnabled: Bool) -> String {
        if !remindersEnabled { return "已关闭" }
        if sourceStatus == .sleeping { return "睡眠中暂停" }
        if sourceStatus == .needsAuthorization { return "授权后开启" }
        if sourceStatus == .autoStartDisabled { return "先开自动" }
        if sourceStatus == .noActivitySamples { return "继续累积样本" }
        if sourceStatus == .unavailable { return "检查权限" }
        guard isCounting else { return "坐下后开启" }
        guard let nextReminderMinute else { return "持续提醒" }
        return String(localized: "\(nextReminderMinute) 分钟")
    }

    var statusFootnote: String {
        if sourceStatus == .needsAuthorization {
            return String(localized: "授权后会根据步数、运动与站立样本自动判断。")
        }
        if sourceStatus == .sleeping {
            return String(localized: "检测到你正在睡眠，久坐计时和提醒已暂停。")
        }
        if sourceStatus == .autoStartDisabled {
            return String(localized: "打开自动开始后，久坐计时和提醒会重新接管。")
        }
        if sourceStatus == .noActivitySamples {
            return String(localized: "继续佩戴 Apple Watch 或保持健康同步，样本补齐后会自动恢复判断。")
        }
        if sourceStatus == .unavailable {
            return String(localized: "稍后会自动重试，也可以返回页面后重新进入。")
        }
        if isCounting {
            return elapsedMinutes >= 60 ? "现在适合做一次短打断，先走动或拉伸 2 到 5 分钟。" : "已经进入久坐计时，记得在提醒前主动起身活动一下。"
        }
        return String(localized: "最近有活动，久坐计时已暂停，坐下安静一会儿会重新开始。")
    }

    var statusTitle: String {
        if sourceStatus == .needsAuthorization {
            return String(localized: "需要健康权限")
        }
        if sourceStatus == .sleeping {
            return "睡眠中"
        }
        if sourceStatus == .autoStartDisabled {
            return String(localized: "久坐自动开始已关闭")
        }
        if sourceStatus == .noActivitySamples {
            return String(localized: "继续累积样本")
        }
        if sourceStatus == .unavailable {
            return String(localized: "无法读取健康数据")
        }
        if isCounting {
            return elapsedMinutes >= 60 ? "久坐中" : "坐下计时中"
        }
        return "活动中"
    }

    var statusDetail: String {
        if sourceStatus == .needsAuthorization {
            return String(localized: "请在健康权限中允许读取步数、运动时间和站立数据")
        }
        if sourceStatus == .sleeping {
            return String(localized: "检测到当前处于睡眠阶段，久坐计时和提醒已自动暂停")
        }
        if sourceStatus == .autoStartDisabled {
            return String(localized: "开启自动开始后，会根据步数、运动和站立数据判断久坐状态")
        }
        if sourceStatus == .noActivitySamples {
            return String(localized: "还没有读取到今天的步数、运动和站立样本，补齐后会自动恢复久坐判断")
        }
        if sourceStatus == .unavailable {
            return String(localized: "请确认健康权限已开启，并保持 Apple Watch 或健康 App 正常同步")
        }
        if isCounting {
            if let nextReminderMinute {
                return String(localized: "距离 \(nextReminderMinute) 分钟提醒还有 \(max(1, nextReminderMinute - elapsedMinutes)) 分钟")
            }
            return String(localized: "已经超过 120 分钟，建议现在起身活动")
        }
        return String(localized: "检测到活动后会暂停计时，坐下安静一会儿会自动开始")
    }
}

extension DashboardSedentaryState.SourceStatus {
    init(_ status: SedentaryHealthState.SourceStatus) {
        switch status {
        case .ready:
            self = .ready
        case .sleeping:
            self = .sleeping
        case .needsAuthorization:
            self = .needsAuthorization
        case .noActivitySamples:
            self = .noActivitySamples
        case .unavailable:
            self = .unavailable
        }
    }
}
