/// Complete Recovery Action Intent 定义 Widget 相关的共享能力或辅助逻辑，负责支撑小组件的数据读取、样式组织与交互行为。
import AppIntents
import WidgetKit

/// 在小组件上直接把今日计划的某项行动标记为完成：
/// 先乐观更新 App Group 快照让小组件即时反馈，再写入出站队列等待主 App 落库。
struct CompleteRecoveryActionIntent: AppIntent {
    static let title: LocalizedStringResource = "完成今日行动"

    @Parameter(title: "计划标识")
    var planID: String

    @Parameter(title: "行动标识")
    var actionID: String

    init() {
        planID = ""
        actionID = ""
    }

    init(planID: String, actionID: String) {
        self.planID = planID
        self.actionID = actionID
    }

    func perform() async throws -> some IntentResult {
        guard !planID.isEmpty, !actionID.isEmpty,
              let snapshot = AppGroupSnapshotStore.load(),
              let plan = snapshot.recoveryPlan,
              plan.planID == planID,
              let index = plan.actions.firstIndex(where: { $0.actionID == actionID }),
              !plan.actions[index].state.isTerminal else {
            return .result()
        }

        let now = Date()
        var actions = plan.actions
        actions[index] = SharedWidgetRecoveryAction(
            actionID: actions[index].actionID,
            title: actions[index].title,
            role: actions[index].role,
            state: .completed
        )
        let updatedPlan = SharedWidgetRecoveryPlan(
            planID: plan.planID,
            dayStart: plan.dayStart,
            updatedAt: now,
            actions: actions
        )
        AppGroupSnapshotStore.save(snapshot.replacingRecoveryPlan(updatedPlan))

        RecoveryActionOutbox.append(RecoveryActionOutboxEntry(
            planID: planID,
            actionID: actionID,
            stateRawValue: SharedWidgetRecoveryActionState.completed.rawValue,
            updatedAt: now
        ))

        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupSchema.Kind.overall)
        return .result()
    }
}
