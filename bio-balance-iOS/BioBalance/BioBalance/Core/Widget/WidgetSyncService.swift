import Foundation

enum WidgetSyncService {
    static func refresh(
        _ domains: [WidgetRefreshDomain] = WidgetRefreshDomain.appVisibleDefaults,
        reason: WidgetRefreshReason = .healthUpdate,
        force: Bool = false
    ) {
        WidgetRefreshCoordinator.refresh(domains, reason: reason, force: force)
    }

    /// 用户切换或缓存重置后清理 Widget/Watch 派生投影，业务真值保持不变。
    @MainActor
    static func resetForUserSwitch() {
        CacheReliability.resetForUserSwitch()
    }
}
