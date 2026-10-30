import Foundation
import WidgetKit

enum WidgetRefreshReason: String {
    case healthUpdate
    case settings
    case insight
    case appearance
    case reminders
    case orchestration
    case manual
}

enum WidgetRefreshDomain: CaseIterable, Sendable {
    case overall
    case sunlight
    case sleep
    case stress
    case vitals
    case activity
    case activityConfigurable
    case complication

    static let appVisibleDefaults: [WidgetRefreshDomain] = [.overall, .sunlight, .sleep, .stress, .vitals, .activity, .activityConfigurable, .complication]

    var widgetKind: String {
        switch self {
        case .overall:
            return AppGroupSchema.Kind.overall
        case .sunlight:
            return AppGroupSchema.Kind.sunlight
        case .sleep:
            return AppGroupSchema.Kind.sleep
        case .stress:
            return AppGroupSchema.Kind.stress
        case .vitals:
            return AppGroupSchema.Kind.vitals
        case .activity:
            return AppGroupSchema.Kind.activity
        case .activityConfigurable:
            return AppGroupSchema.Kind.activityConfigurable
        case .complication:
            return AppGroupSchema.Kind.complication
        }
    }

    var widgetKinds: [String] {
        switch self {
        case .complication:
            return AppGroupSchema.Kind.allComplicationKinds
        default:
            return [widgetKind]
        }
    }
}

enum RecoveryPlanWidgetSyncCoordinator {
    static func synchronize(
        now: Date = Date(),
        calendar: Calendar = .current,
        store: DailyRecoveryOrchestrationStore = .shared
    ) {
        // 先消费小组件端的行动变更出站队列，再用最新状态生成投影
        consumeWidgetOutbox(now: now, calendar: calendar, store: store)

        let plan = store.load(for: now, calendar: calendar)
        let projection = plan.map {
            makeProjection(
                plan: $0,
                actionStates: store.actionStates(for: $0),
                updatedAt: now
            )
        }

        guard let existing = CacheReliability.loadSnapshot() ?? plan.map({ _ in AppGroupHealthSnapshot.empty(generatedAt: now) }) else {
            return
        }
        guard existing.recoveryPlan != projection || existing.schemaVersion < AppGroupHealthSnapshot.currentSchemaVersion else {
            return
        }

        AppGroupSnapshotStore.save(existing.replacingRecoveryPlan(projection))
        WidgetRefreshCoordinator.refresh([.overall], reason: .orchestration, force: true)
    }

    static func makeProjection(
        plan: DailyRecoveryOrchestrationPlan,
        actionStates: [String: DailyRecoveryActionStateRecord],
        updatedAt: Date
    ) -> SharedWidgetRecoveryPlan {
        var actions = [
            SharedWidgetRecoveryAction(
                actionID: plan.mainActionID,
                title: plan.mainGoal,
                role: .main,
                state: sharedState(actionStates[plan.mainActionID]?.state)
            )
        ]
        actions.append(contentsOf: zip(plan.supportingActionIDs, plan.supportingActions).map { actionID, title in
            SharedWidgetRecoveryAction(
                actionID: actionID,
                title: title,
                role: .supporting,
                state: sharedState(actionStates[actionID]?.state)
            )
        })
        return SharedWidgetRecoveryPlan(
            planID: plan.planID,
            dayStart: Int(plan.date.timeIntervalSince1970),
            updatedAt: updatedAt,
            actions: Array(actions.prefix(3))
        )
    }

    private static func sharedState(_ state: DailyRecoveryActionState?) -> SharedWidgetRecoveryActionState {
        guard let state else { return .pending }
        return SharedWidgetRecoveryActionState(rawValue: state.rawValue) ?? .pending
    }

    /// 把小组件上“完成行动”的乐观变更落库到本地行动状态存储
    private static func consumeWidgetOutbox(
        now: Date,
        calendar: Calendar,
        store: DailyRecoveryOrchestrationStore
    ) {
        let entries = RecoveryActionOutbox.drain()
        guard !entries.isEmpty,
              let plan = store.load(for: now, calendar: calendar) else {
            return
        }

        for entry in entries {
            guard entry.planID == plan.planID,
                  plan.allActionIDs.contains(entry.actionID),
                  let state = DailyRecoveryActionState(rawValue: entry.stateRawValue) else {
                continue
            }
            // App 内更新的记录优先，只接受更新的小组件变更
            if let existing = store.actionState(for: entry.actionID),
               existing.updatedAt >= entry.updatedAt {
                continue
            }
            store.setActionState(
                state,
                actionID: entry.actionID,
                planID: entry.planID,
                updatedAt: entry.updatedAt
            )
        }
    }
}

enum WidgetRefreshCoordinator {
    private static let minimumRefreshInterval: TimeInterval = 4
    private static let minimumForcedRefreshInterval: TimeInterval = 1
    private static let snapshotPublishMinimumInterval: TimeInterval = 2
    private static let lock = NSLock()
    private static let snapshotPublishLock = NSLock()
    private static var lastRefreshAt: [String: Date] = [:]
    private static var lastSnapshotPublishAt: Date?

    static func refresh(
        _ domains: [WidgetRefreshDomain] = WidgetRefreshDomain.appVisibleDefaults,
        reason: WidgetRefreshReason = .healthUpdate,
        force: Bool = false
    ) {
        publishLatestHealthSnapshotIfNeeded(reason: reason, force: force)

        let kinds = Set(domains.flatMap(\.widgetKinds))
        let now = Date()

        for kind in kinds {
            guard shouldRefresh(kind: kind, now: now, force: force, reason: reason) else { continue }
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }

    private static func publishLatestHealthSnapshotIfNeeded(
        reason: WidgetRefreshReason,
        force: Bool = false
    ) {
        guard reason == .healthUpdate else { return }

        let now = Date()
        snapshotPublishLock.lock()
        if !force,
           let last = lastSnapshotPublishAt,
           now.timeIntervalSince(last) < snapshotPublishMinimumInterval {
            snapshotPublishLock.unlock()
            return
        }
        lastSnapshotPublishAt = now
        snapshotPublishLock.unlock()

        let source = WatchSyncSnapshotFactory(
            latestBodyAgeSummary: nil,
            realtimeHealth: nil,
            currentActivity: nil,
            currentSleep: nil,
            currentStress: nil
        ).makeSnapshot(realtime: nil)
        var snapshot = AppGroupHealthSnapshot.fromSource(
            source,
            healthSummary: AppGroupManager.shared.getHealthSummary()
        )

        if snapshot.recoveryPlan == nil,
           let recoveryPlan = CacheReliability.loadSnapshot()?.recoveryPlan {
            snapshot = snapshot.replacingRecoveryPlan(recoveryPlan)
        }

        AppGroupSnapshotStore.save(snapshot)
    }

    private static func shouldRefresh(
        kind: String,
        now: Date,
        force: Bool,
        reason: WidgetRefreshReason
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let minimum: TimeInterval
        if force {
            minimum = reason == .manual ? 0 : minimumForcedRefreshInterval
        } else {
            minimum = minimumRefreshInterval
        }

        if let last = lastRefreshAt[kind], now.timeIntervalSince(last) < minimum {
            return false
        }

        lastRefreshAt[kind] = now
        return true
    }
}
