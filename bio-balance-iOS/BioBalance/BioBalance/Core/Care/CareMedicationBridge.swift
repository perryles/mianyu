/// CareMedicationBridge 把 MedicationStore 的版本化任务桥接到统一照护引擎。
///
/// 设计：
/// - 只读代理：不修改 MedicationStore 的数据
/// - 把 MedicationPlan 映射为 CareTask（category = .medication）
/// - 把 MedicationTaskEvent 映射为 CareTaskEvent
/// - 服药结果（MedicationEntry）映射为 CareOutcome
///
/// 这样 CareHubView 可以和康复/习惯模块使用同一套 UI，同时不影响现有药症联动链路。

import Foundation

final class CareMedicationBridge {
    static let shared = CareMedicationBridge()
    private let calendar = Calendar.current

    private init() {}

    // MARK: - 任务桥接

    func bridgeTasks(referenceDate: Date = Date()) -> [CareTask] {
        MedicationStore.shared.allPlans(referenceDate: referenceDate).map { plan in
            CareTask(
                id: plan.id,
                category: .medication,
                title: plan.name,
                subtitle: plan.purpose,
                icon: plan.category.symbol,
                schedule: bridgeSchedule(from: plan),
                targetValue: plan.amount,
                unit: plan.unit,
                instructions: plan.note,
                linkedModule: nil,
                logicalTaskID: plan.logicalPlanID,
                revision: plan.revision,
                effectiveFrom: plan.effectiveFrom,
                effectiveUntil: plan.effectiveUntil,
                sourceImportID: nil
            )
        }
    }

    // MARK: - 事件桥接

    func bridgeEvents(on date: Date = Date(), referenceDate: Date = Date()) -> [CareTaskEvent] {
        MedicationStore.shared.taskEvents(on: date, referenceDate: referenceDate).map { medicationEvent in
            CareTaskEvent(
                id: medicationEvent.id,
                taskID: medicationEvent.planID,
                logicalTaskID: medicationEvent.logicalPlanID,
                taskRevision: medicationEvent.planRevision,
                category: .medication,
                title: medicationEvent.outcome?.name ?? resolveTaskTitle(logicalPlanID: medicationEvent.logicalPlanID),
                icon: MedicationEntryCategory.medication.symbol,
                slotIndex: 0,
                scheduledAt: medicationEvent.scheduledAt,
                durationMinutes: 0,
                targetValue: nil,
                unit: nil,
                instructions: nil,
                linkedModule: nil,
                status: bridgeStatus(medicationEvent.status),
                outcome: medicationEvent.outcome.map(bridgeOutcome)
            )
        }
    }

    // MARK: - 结果桥接

    func bridgeOutcome(_ entry: MedicationEntry) -> CareOutcome {
        var values: [CareOutcome.Value] = [
            CareOutcome.Value(kind: .numeric, label: "剂量", numericValue: entry.amount)
        ]
        if let reaction = entry.reactionState {
            values.append(CareOutcome.Value(kind: .reaction, label: "体感", textValue: reaction.shortTitle))
        }
        return CareOutcome(
            id: entry.id,
            logicalTaskID: entry.logicalPlanID,
            taskID: entry.planID,
            taskRevision: entry.planRevision,
            category: .medication,
            completedAt: entry.takenAt,
            scheduledDate: entry.takenAt,
            values: values,
            note: entry.note,
            linkedMedicationEntryID: entry.id,
            linkedSelfObservationID: nil,
            linkedHabitCheckinKey: nil
        )
    }

    // MARK: - 症状记录桥接

    func bridgeSymptomOutcome(_ record: SelfObservationRecord) -> CareOutcome {
        var values: [CareOutcome.Value] = []
        if record.symptomCount > 0 {
            let symptomText = record.selectedSymptoms.map(\.title).joined(separator: ", ")
            values.append(CareOutcome.Value(kind: .symptom, label: "症状", textValue: symptomText))
        }
        values.append(CareOutcome.Value(kind: .rating, label: "强度", ratingValue: record.symptomSeverity))

        return CareOutcome(
            id: record.id,
            logicalTaskID: nil,
            taskID: nil,
            taskRevision: nil,
            category: .symptom,
            completedAt: record.recordedAt,
            scheduledDate: record.recordedAt,
            values: values,
            note: record.note,
            linkedMedicationEntryID: nil,
            linkedSelfObservationID: record.id,
            linkedHabitCheckinKey: nil
        )
    }

    // MARK: - 私有实现

    private func bridgeSchedule(from plan: MedicationPlan) -> CareSchedule {
        CareSchedule(
            isEnabled: plan.reminder.isEnabled,
            slots: [.init(hour: plan.reminder.hour, minute: plan.reminder.minute)],
            weekdays: [],
            frequency: .daily,
            customIntervalDays: 1,
            startDate: plan.effectiveFrom,
            endDate: plan.effectiveUntil
        )
    }

    private func bridgeStatus(_ status: MedicationTaskEventStatus) -> CareTaskEventStatus {
        switch status {
        case .scheduled: return .scheduled
        case .completed: return .completed
        case .overdue: return .overdue
        }
    }

    private func resolveTaskTitle(logicalPlanID: String) -> String {
        let versions = MedicationStore.shared.allPlanVersions(logicalPlanID: logicalPlanID)
        return versions.first?.name ?? String(localized: "用药")
    }
}
