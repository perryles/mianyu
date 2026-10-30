/// CareWritebackManager 负责 Care 任务完成后的跨模块数据回写。
///
/// 设计目的：
/// CareTaskEngine 是新建的统一任务引擎，但服药、习惯等模块各自已有成熟的 Store。
/// 如果 Care 的"快速打卡"只在 CareTaskEngine 内部记录 Outcome，会导致：
///   - MedicationStore 看不到这条服药记录 → 用药统计/时间线/体感提醒缺失
///   - HabitCheckinStore 看不到习惯打卡 → LongTermHabitEngine 完成率不准
///   - RecoveryChallengeEvaluator 看不到完成 → 挑战进度不更新
///
/// 因此在 CareTaskEngine.quickComplete 执行后，调用本 Manager 把数据回写到对应 Store。
/// 回写是"尽力而为"——失败不影响 Care 自身的记录，只记录日志。
///
/// 回写策略：
/// - medication → MedicationStore.save(entry)
/// - habit.linkedModule == "sunlight" → ActionRecordStore 更新 sunlightMinutes + completedActions
/// - habit.linkedModule == "breathing" → ActionRecordStore 更新 mindfulnessMinutes
/// - habit.linkedModule == "water" → ActionRecordStore 更新 waterMl
/// - rehabilitation → 暂无对应 Store，仅 CareTaskEngine 内部记录

import Foundation

final class CareWritebackManager {
    static let shared = CareWritebackManager()
    private let calendar = Calendar.current
    private init() {}

    // MARK: - 用药回写

    /// 把 Care 的快速打卡回写为 MedicationEntry，让 MedicationStore 记录实际用药。
    /// - Parameter event: 触发打卡的 CareTaskEvent（必须 category == .medication）
    func writebackMedication(for event: CareTaskEvent) {
        guard event.category == .medication else { return }

        // 查找对应的 MedicationPlan 版本，获取 name / amount / unit
        let plan = resolveMedicationPlan(for: event)
        let entry = MedicationEntry(
            id: UUID().uuidString,
            category: .medication,
            name: plan?.name ?? event.title,
            amount: plan?.amount ?? event.targetValue ?? 1,
            unit: plan?.unit ?? event.unit ?? String(localized: "次"),
            purpose: plan?.purpose,
            note: nil,
            takenAt: Date(),
            planID: event.taskID,
            logicalPlanID: event.logicalTaskID,
            planRevision: event.taskRevision
        )
        MedicationStore.shared.save(entry)
    }

    // MARK: - 习惯回写

    /// 把 Care 的习惯打卡回写到 ActionRecordStore。
    /// 只处理有 linkedModule 映射的习惯（sunlight/breathing/water）。
    /// - Parameter event: 触发打卡的 CareTaskEvent（必须 category == .habit）
    func writebackHabit(for event: CareTaskEvent) {
        guard event.category == .habit else { return }
        guard let linkedModule = event.linkedModule else { return }

        let date = calendar.startOfDay(for: event.scheduledAt)

        switch linkedModule {
        case "sunlight":
            let minutes = Int(event.targetValue ?? 20)
            ActionRecordStore.shared.updateRecord(for: date) { record in
                record.sunlightMinutes = max(record.sunlightMinutes, minutes)
                if !record.completedActions.contains(.sunlight) {
                    record.completedActions.append(.sunlight)
                }
            }
        case "breathing", "mindfulness":
            let minutes = Int(event.targetValue ?? 10)
            ActionRecordStore.shared.updateRecord(for: date) { record in
                record.mindfulnessMinutes = max(record.mindfulnessMinutes, minutes)
            }
        case "water":
            ActionRecordStore.shared.updateRecord(for: date) { record in
                if !record.completedActions.contains(.water) {
                    record.completedActions.append(.water)
                }
            }
        default:
            // 未映射的自定义习惯，仅在 CareTaskEngine 内部记录即可
            break
        }

        // 触发习惯数据刷新通知，让 DailyActionView 等页面感知
        NotificationCenter.default.post(name: .habitDataDidUpdate, object: nil)
    }

    // MARK: - 统一入口

    /// 统一回写入口：CareTaskEngine.quickComplete 完成后调用。
    /// 根据事件类别分发到对应 Store。
    func performWriteback(for event: CareTaskEvent) {
        switch event.category {
        case .medication:
            writebackMedication(for: event)
        case .habit:
            writebackHabit(for: event)
        case .rehabilitation, .symptom:
            // 康复和症状不需要回写到其他 Store
            break
        }
    }

    // MARK: - 私有实现

    private func resolveMedicationPlan(for event: CareTaskEvent) -> MedicationPlan? {
        let versions = MedicationStore.shared.allPlanVersions(logicalPlanID: event.logicalTaskID)
        return versions.first { $0.id == event.taskID } ?? versions.first
    }
}

// MARK: - 通知名称

extension Notification.Name {
    /// 习惯数据发生变更（Care 回写后触发，用于通知 DailyActionView / HabitViewModel 刷新）。
    static let habitDataDidUpdate = Notification.Name("habitDataDidUpdate")
}
