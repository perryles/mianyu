import Foundation
import SwiftData

/// 持久化每日恢复编排和用户对行动项的处理状态。
final class DailyRecoveryOrchestrationStore {
    static let shared = DailyRecoveryOrchestrationStore()

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let cooldownStore: DailyRecoverySuggestionCooldownStore
    private let key = "daily.recovery.orchestration.v1"
    private let actionStatesKey = "daily.recovery.orchestration.action-states.v1"
    private let domain = "daily-recovery-orchestration"
    private let planKind = "plan"
    private let actionKind = "action-state"

    init(
        defaults: UserDefaults = .standard,
        cooldownStore: DailyRecoverySuggestionCooldownStore? = nil,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.cooldownStore = cooldownStore ?? DailyRecoverySuggestionCooldownStore(defaults: defaults, container: container)
        migrateLegacyDataIfNeeded()
    }

    func save(_ plan: DailyRecoveryOrchestrationPlan) {
        let previousPlan = loadStoredPlan()
        guard let data = try? JSONEncoder().encode(plan) else { return }
        guard records.upsert(LocalDataRecordSeed(
            domain: domain,
            recordID: plan.planID,
            kind: planKind,
            occurredAt: plan.date,
            updatedAt: plan.generatedAt,
            payload: data
        ), keepingNewest: 1) else { return }
        ensureActionStateRecords(for: plan)
        guard previousPlan.map({ !hasSameProjection($0, plan) }) ?? true else { return }
        NotificationCenter.default.post(
            name: .dailyRecoveryPlanDidChange,
            object: nil,
            userInfo: ["planID": plan.planID]
        )
    }

    func load(for date: Date = Date(), calendar: Calendar = .current) -> DailyRecoveryOrchestrationPlan? {
        guard let plan = loadStoredPlan(),
              calendar.isDate(plan.date, inSameDayAs: date) else {
            return nil
        }
        return plan
    }

    func actionState(for actionID: String) -> DailyRecoveryActionStateRecord? {
        loadActionStates()[actionID]
    }

    @discardableResult
    func setActionState(
        _ state: DailyRecoveryActionState,
        actionID: String,
        planID: String,
        reason: String? = nil,
        actionTitle: String? = nil,
        plannedFor: Date? = nil,
        updatedAt: Date = Date()
    ) -> DailyRecoveryActionStateRecord {
        let existing = loadActionStates()[actionID]
        let resolvedProjection = actionProjection(actionID: actionID, planID: planID)
        let keepsFeedback = state == .completed
        let record = DailyRecoveryActionStateRecord(
            planID: planID,
            actionID: actionID,
            state: state,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            actionTitle: actionTitle ?? existing?.actionTitle ?? resolvedProjection?.title,
            plannedFor: plannedFor ?? existing?.plannedFor ?? resolvedProjection?.date,
            feedback: keepsFeedback ? existing?.feedback : nil,
            feedbackUpdatedAt: keepsFeedback ? existing?.feedbackUpdatedAt : nil,
            updatedAt: updatedAt
        )
        var states = loadActionStates()
        states[actionID] = record
        persistActionStates(states)
        if state == .skipped, let actionTitle {
            cooldownStore.recordSkip(actionID: actionID, title: actionTitle, now: updatedAt)
        } else if state != .skipped {
            cooldownStore.remove(actionID: actionID, now: updatedAt)
        }
        NotificationCenter.default.post(
            name: .dailyRecoveryActionStateDidChange,
            object: nil,
            userInfo: ["planID": planID, "actionID": actionID]
        )
        return record
    }

    @discardableResult
    func setFeedback(
        _ feedback: DailyRecoveryActionFeedback?,
        actionID: String,
        updatedAt: Date = Date()
    ) -> DailyRecoveryActionStateRecord? {
        var states = loadActionStates()
        guard let existing = states[actionID], existing.state == .completed else { return nil }
        let record = DailyRecoveryActionStateRecord(
            planID: existing.planID,
            actionID: existing.actionID,
            state: existing.state,
            reason: existing.reason,
            actionTitle: existing.actionTitle,
            plannedFor: existing.plannedFor,
            feedback: feedback,
            feedbackUpdatedAt: feedback == nil ? nil : updatedAt,
            updatedAt: max(existing.updatedAt, updatedAt)
        )
        states[actionID] = record
        persistActionStates(states)
        NotificationCenter.default.post(
            name: .dailyRecoveryActionStateDidChange,
            object: nil,
            userInfo: ["planID": existing.planID, "actionID": actionID]
        )
        return record
    }

    func undoActionState(for actionID: String, updatedAt: Date = Date()) {
        var states = loadActionStates()
        guard let existing = states[actionID] else { return }
        let pending = DailyRecoveryActionStateRecord(
            planID: existing.planID,
            actionID: existing.actionID,
            state: .pending,
            reason: nil,
            actionTitle: existing.actionTitle,
            plannedFor: existing.plannedFor,
            feedback: nil,
            feedbackUpdatedAt: nil,
            updatedAt: max(existing.updatedAt, updatedAt)
        )
        states[actionID] = pending
        persistActionStates(states)
        cooldownStore.remove(actionID: actionID, now: updatedAt)
        NotificationCenter.default.post(
            name: .dailyRecoveryActionStateDidChange,
            object: nil,
            userInfo: ["planID": existing.planID, "actionID": actionID]
        )
    }

    func actionStates(for plan: DailyRecoveryOrchestrationPlan) -> [String: DailyRecoveryActionStateRecord] {
        let actionIDs = Set(plan.allActionIDs)
        return loadActionStates().filter { actionIDs.contains($0.key) }
    }

    func allActionStateRecords() -> [DailyRecoveryActionStateRecord] {
        loadActionStates().values.sorted {
            ($0.plannedFor ?? $0.updatedAt) > ($1.plannedFor ?? $1.updatedAt)
        }
    }

    private func loadActionStates() -> [String: DailyRecoveryActionStateRecord] {
        let stored: [DailyRecoveryActionStateRecord]
        if let rows = records.records(domain: domain, kind: actionKind) {
            stored = rows.compactMap { try? JSONDecoder().decode(DailyRecoveryActionStateRecord.self, from: $0.payload) }
        } else if let data = defaults.data(forKey: actionStatesKey),
                  let decoded = try? JSONDecoder().decode([DailyRecoveryActionStateRecord].self, from: data) {
            stored = decoded
        } else {
            stored = []
        }
        // 兼容旧版本或损坏数据中的重复 ID；同一行动以更新时间较新的记录为准。
        return Dictionary(stored.map { ($0.actionID, $0) }) { lhs, rhs in
            lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
    }

    private func persistActionStates(_ states: [String: DailyRecoveryActionStateRecord]) {
        let bounded = states.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(240)
        let seeds = bounded.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: record.actionID,
                kind: actionKind,
                occurredAt: record.plannedFor ?? record.updatedAt,
                updatedAt: record.updatedAt,
                payload: data
            )
        }
        guard seeds.count == bounded.count else { return }
        _ = records.replace(domain: domain, kind: actionKind, with: seeds)
    }

    private func loadStoredPlan() -> DailyRecoveryOrchestrationPlan? {
        if let row = records.records(domain: domain, kind: planKind)?.first {
            return try? JSONDecoder().decode(DailyRecoveryOrchestrationPlan.self, from: row.payload)
        }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailyRecoveryOrchestrationPlan.self, from: data)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "daily.recovery.orchestration.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: actionStatesKey)
            return
        }
        var seeds: [LocalDataRecordSeed] = []
        if let planData = defaults.data(forKey: key) {
            guard let plan = try? JSONDecoder().decode(DailyRecoveryOrchestrationPlan.self, from: planData) else { return }
            seeds.append(LocalDataRecordSeed(domain: domain, recordID: plan.planID, kind: planKind, occurredAt: plan.date, updatedAt: plan.generatedAt, payload: planData))
        }
        if let actionData = defaults.data(forKey: actionStatesKey) {
            guard let actions = try? JSONDecoder().decode([DailyRecoveryActionStateRecord].self, from: actionData) else { return }
            let actionSeeds = actions.compactMap { record -> LocalDataRecordSeed? in
                guard let data = try? JSONEncoder().encode(record) else { return nil }
                return LocalDataRecordSeed(domain: domain, recordID: record.actionID, kind: actionKind, occurredAt: record.updatedAt, updatedAt: record.updatedAt, payload: data)
            }
            guard actionSeeds.count == actions.count else { return }
            seeds.append(contentsOf: actionSeeds)
        }
        guard records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: actionStatesKey)
    }

    private func hasSameProjection(
        _ lhs: DailyRecoveryOrchestrationPlan,
        _ rhs: DailyRecoveryOrchestrationPlan
    ) -> Bool {
        lhs.planID == rhs.planID
            && lhs.mainGoal == rhs.mainGoal
            && lhs.mainGoalDetail == rhs.mainGoalDetail
            && lhs.supportingActions == rhs.supportingActions
            && lhs.deferredSuggestions == rhs.deferredSuggestions
            && lhs.readinessBand == rhs.readinessBand
            && lhs.reason == rhs.reason
    }

    private func ensureActionStateRecords(for plan: DailyRecoveryOrchestrationPlan) {
        var states = loadActionStates()
        let projections = [(plan.mainActionID, plan.mainGoal)] + Array(zip(plan.supportingActionIDs, plan.supportingActions))
        var changed = false
        for (actionID, title) in projections where states[actionID] == nil {
            states[actionID] = DailyRecoveryActionStateRecord(
                planID: plan.planID,
                actionID: actionID,
                state: .pending,
                reason: nil,
                actionTitle: title,
                plannedFor: plan.date,
                updatedAt: plan.generatedAt
            )
            changed = true
        }
        if changed {
            persistActionStates(states)
        }
    }

    private func actionProjection(actionID: String, planID: String) -> (title: String, date: Date)? {
        guard let plan = loadStoredPlan(), plan.planID == planID else { return nil }
        if plan.mainActionID == actionID {
            return (plan.mainGoal, plan.date)
        }
        guard let index = plan.supportingActionIDs.firstIndex(of: actionID),
              plan.supportingActions.indices.contains(index) else { return nil }
        return (plan.supportingActions[index], plan.date)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
