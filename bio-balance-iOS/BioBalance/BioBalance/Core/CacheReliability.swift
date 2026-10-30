import Foundation

/// Widget/Watch 共享投影的可复用恢复与回退逻辑。
/// 只清理可重建的派生投影，不触碰本地业务真值。
enum CacheReliability {
    private static let minimumSchemaVersion = 1

    static func loadSnapshot() -> AppGroupHealthSnapshot? {
        guard let defaults = AppGroupManager.userDefaults() else { return nil }
        return loadSnapshot(defaults: defaults)
    }

    static func loadSnapshot(defaults: UserDefaults) -> AppGroupHealthSnapshot? {
        let primaryKey = AppGroupSnapshotStore.widgetSnapshotV2Key
        if let data = defaults.data(forKey: primaryKey) {
            if let snapshot = decode(data) {
                return validated(snapshot)
            }
            defaults.removeObject(forKey: primaryKey)
        }

        let legacyKey = AppGroupSnapshotStore.legacyWidgetSnapshotV2Key
        if let data = defaults.data(forKey: legacyKey) {
            if let snapshot = decode(data) {
                defaults.set(data, forKey: primaryKey)
                defaults.removeObject(forKey: legacyKey)
                return validated(snapshot)
            }
            defaults.removeObject(forKey: legacyKey)
        }
        return nil
    }

    static func validated(
        _ snapshot: AppGroupHealthSnapshot,
        now: Date = Date()
    ) -> AppGroupHealthSnapshot {
        guard let plan = snapshot.recoveryPlan else { return snapshot }
        if plan.isValid(at: now) { return snapshot }
        return snapshot.replacingRecoveryPlan(nil)
    }

    /// Apple ID 切换或缓存重置后清理 Widget/Watch 派生投影，本地业务记录保持不变。
    @MainActor
    static func resetForUserSwitch() {
        WatchConnectivitySyncService.shared.clearCachedState()
        _ = AppDataCacheManager.shared.clear(categories: [
            .sharedWidgetSnapshots,
            .watchTransportSnapshots
        ])
    }

    private static func decode(_ data: Data) -> AppGroupHealthSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(AppGroupHealthSnapshot.self, from: data) else {
            return nil
        }
        guard snapshot.schemaVersion >= minimumSchemaVersion else { return nil }
        let interval = snapshot.generatedAt.timeIntervalSince1970
        guard interval > 0, interval <= Date().timeIntervalSince1970 + 24 * 60 * 60 else {
            return nil
        }
        return snapshot
    }
}
