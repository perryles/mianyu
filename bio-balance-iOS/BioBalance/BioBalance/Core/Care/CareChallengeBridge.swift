/// CareChallengeBridge 把 RecoveryChallengeStore 的活跃挑战桥接到统一照护引擎。
///
/// 设计目的：
/// 现有 RecoveryChallenge（7天早睡/低咖啡因/日照挑战）和 Care 的 rehabilitation 类别任务
/// 在概念上高度重叠——都是"按周期编排、有完成判断、需进度跟踪"的任务。
///
/// 通过桥接，让 CareHubView 的统一列表也能展示活跃挑战的当日进度，
/// 而不需要在 CareTaskEngine 中重建一套挑战数据。
///
/// 映射规则：
/// - RecoveryChallengeRecord.status == .active → 一个 CareTaskEvent（当日）
/// - 完成状态由 dayProgress.status 决定
/// - 不创建重复的 CareTask —— 桥接是只读的，数据源仍是 RecoveryChallengeStore
/// - linkedModule 保持与挑战类型一致（sunlight 挑战 → linkedModule = "sunlight"）

import Foundation

final class CareChallengeBridge {
    static let shared = CareChallengeBridge()
    private let calendar = Calendar.current
    private init() {}

    // MARK: - 将进行中挑战桥接为事件

    /// 把所有活跃的 RecoveryChallenge 转为当日的 CareTaskEvent。
    /// 在 CareTaskEngine.events(on:) 中被合并到总事件列表。
    func bridgeEvents(on date: Date = Date()) -> [CareTaskEvent] {
        guard let active = RecoveryChallengeStore.shared.activeChallenge() else { return [] }

        let dayProgress = active.dayProgresses.first { calendar.isDate($0.date, inSameDayAs: date) }
        let bridgeStatus = mapStatus(dayProgress?.status)

        let definition = active.kind.definition
        let targetValue = extractTargetValue(for: active.kind)
        let linkedModule = extractLinkedModule(for: active.kind)

        return [
            CareTaskEvent(
                id: "challenge.\(active.id.uuidString).\(calendar.startOfDay(for: date).timeIntervalSince1970)",
                taskID: active.id.uuidString,
                logicalTaskID: "recovery.challenge.\(active.kind.rawValue)",
                taskRevision: 1,
                category: .rehabilitation,
                title: definition.title,
                icon: definition.symbol,
                slotIndex: 0,
                scheduledAt: date,
                durationMinutes: 0,
                targetValue: targetValue,
                unit: linkedModule == "sunlight" ? "分钟" : nil,
                instructions: definition.ruleText,
                linkedModule: linkedModule,
                status: bridgeStatus,
                outcome: nil
            )
        ]
    }

    // MARK: - 进行中挑战摘要

    /// 当前活跃挑战的进度摘要文本（用于 CareHubView 今日概览）。
    var activeChallengeSummary: (title: String, progress: Double, dayText: String)? {
        guard let active = RecoveryChallengeStore.shared.activeChallenge() else { return nil }
        let def = active.kind.definition
        return (
            title: def.title,
            progress: active.progressFraction,
            dayText: "第 \(active.currentDayIndex)/\(active.targetDays) 天"
        )
    }

    // MARK: - 私有实现

    private func mapStatus(_ dayStatus: RecoveryChallengeDayStatus?) -> CareTaskEventStatus {
        switch dayStatus {
        case .completed:
            return .completed
        case .failed:
            return .overdue
        case .pending, .none:
            return .scheduled
        }
    }

    private func extractTargetValue(for kind: RecoveryChallengeKind) -> Double? {
        switch kind {
        case .sunlight: return 20      // 日照挑战目标 20 分钟
        case .lowCaffeine: return 200  // 低咖啡因挑战目标 200mg
        case .sleepEarly: return nil   // 早睡挑战是时间规则，非数值
        }
    }

    private func extractLinkedModule(for kind: RecoveryChallengeKind) -> String? {
        switch kind {
        case .sunlight: return "sunlight"
        case .lowCaffeine: return "caffeine"
        case .sleepEarly: return "sleep"
        }
    }
}
