import Foundation
import SwiftUI

/// 缓存管理页的 UI 侧统计与操作适配层。
/// 只组合现有稳定公共 API，不改动 AppDataCacheManager 与 Core 数据层。
enum CacheManagementOperationTone: Equatable, Sendable {
    case success
    case failure
    case info
}

struct CacheManagementOperationResult: Equatable, Sendable {
    let tone: CacheManagementOperationTone
    let message: String
}

struct CacheWatchSyncState: Equatable, Sendable {
    let isPaired: Bool
    let isInstalled: Bool
    let isReachable: Bool
    let activationText: String
    let lastSyncAt: Date?

    static let placeholder = CacheWatchSyncState(
        isPaired: false,
        isInstalled: false,
        isReachable: false,
        activationText: String(localized: "未连接"),
        lastSyncAt: nil
    )
}

struct CacheManagementStatsSnapshot: Equatable, Sendable {
    let appDataSnapshot: AppDataCacheSnapshot
    let generatedAt: Date
    let memoryCacheCount: Int
    let databaseCacheCount: Int?
    let databaseCacheCorrupted: Bool
    let appGroupAvailable: Bool
    let appGroupItemCount: Int
    let appGroupBytes: Int
    let appGroupLastWriteAt: Date?
    let widgetLastSyncAt: Date?
    let watchState: CacheWatchSyncState
    let cacheHitStatsAvailable: Bool

    var totalBytes: Int { appDataSnapshot.totalBytes }
    var totalItemCount: Int { appDataSnapshot.totalItemCount }
    var detailItems: [AppDataCacheItem] { appDataSnapshot.categories.flatMap(\.items) }
}

@MainActor
@Observable
final class CacheManagementStats {
    private static let lastClearDateKey = "cache-management.last-clear-date.v1"

    private(set) var snapshot: CacheManagementStatsSnapshot
    private(set) var isRefreshing = false
    private(set) var isClearingAll = false
    private(set) var isClearingCategories: Set<AppDataCacheCategory> = []
    private(set) var lastOperation: CacheManagementOperationResult?
    private(set) var lastClearDate: Date?

    var isClearing: Bool { isClearingAll || !isClearingCategories.isEmpty }

    init(appSnapshot: AppDataCacheSnapshot? = nil) {
        let app = appSnapshot ?? AppDataCacheManager.shared.snapshot()
        let interval = UserDefaults.standard.double(forKey: Self.lastClearDateKey)
        let clearDate = interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        lastClearDate = clearDate
        snapshot = CacheManagementStatsSnapshot(
            appDataSnapshot: app,
            generatedAt: Date(),
            memoryCacheCount: 0,
            databaseCacheCount: nil,
            databaseCacheCorrupted: false,
            appGroupAvailable: AppGroupManager.userDefaults() != nil,
            appGroupItemCount: app.category(.sharedWidgetSnapshots).itemCount,
            appGroupBytes: app.category(.sharedWidgetSnapshots).totalBytes,
            appGroupLastWriteAt: nil,
            widgetLastSyncAt: nil,
            watchState: .placeholder,
            cacheHitStatsAvailable: false
        )
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        WatchConnectivitySyncService.shared.refreshSessionState()

        let base = Self.gatherBaseStats()

        snapshot = Self.makeSnapshot(
            base: base,
            memoryCacheCount: Self.currentMemoryCacheCount(),
            watchState: Self.currentWatchState()
        )
    }

    @discardableResult
    func clear(categories: Set<AppDataCacheCategory>) async -> CacheManagementOperationResult {
        guard !categories.isEmpty else {
            return fail(String(localized: "没有选择可清理的缓存类型。"))
        }
        guard !isClearing else {
            return fail(String(localized: "已有清理任务正在进行，请稍后再试。"))
        }

        if categories == Set(AppDataCacheCategory.allCases) {
            isClearingAll = true
        } else {
            isClearingCategories = categories
        }
        defer {
            isClearingAll = false
            isClearingCategories = []
        }

        try? await Task.sleep(for: .milliseconds(360))

        if categories.contains(.sharedWidgetSnapshots), AppGroupManager.userDefaults() == nil {
            let outcome = CacheManagementOperationResult(
                tone: .failure,
                message: String(localized: "App Group 暂不可用，共享快照未能清理。")
            )
            lastOperation = outcome
            return outcome
        }

        let result = AppDataCacheManager.shared.clear(categories: categories)
        lastClearDate = result.clearedAt
        UserDefaults.standard.set(result.clearedAt.timeIntervalSince1970, forKey: Self.lastClearDateKey)

        let outcome: CacheManagementOperationResult
        if result.removedItemCount == 0 {
            outcome = CacheManagementOperationResult(
                tone: .info,
                message: String(localized: "没有可清理的缓存，当前数据已经是最新状态。")
            )
        } else {
            outcome = CacheManagementOperationResult(
                tone: .success,
                message: String(localized: "已清理 \(result.removedItemCount) 项缓存（\(Self.sizeText(result.removedBytes))）。")
            )
        }
        lastOperation = outcome

        await refresh()
        return outcome
    }

    func setOperationFeedback(_ outcome: CacheManagementOperationResult) {
        lastOperation = outcome
    }

    var previewSummaryText: String {
        if isClearing {
            return String(localized: "清理中")
        }
        if snapshot.totalItemCount == 0 {
            return String(localized: "已清爽")
        }
        return String(localized: "\(snapshot.totalItemCount) 项")
    }

    var previewDetailText: String {
        if isClearing {
            return String(localized: "正在移除派生快照")
        }
        if snapshot.totalItemCount == 0 {
            return String(localized: "无需清理")
        }
        return Self.sizeText(snapshot.totalBytes)
    }

    static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }

    private func fail(_ message: String) -> CacheManagementOperationResult {
        let outcome = CacheManagementOperationResult(tone: .failure, message: message)
        lastOperation = outcome
        return outcome
    }

    private static func makeSnapshot(
        base: CacheBaseStats,
        memoryCacheCount: Int,
        watchState: CacheWatchSyncState
    ) -> CacheManagementStatsSnapshot {
        CacheManagementStatsSnapshot(
            appDataSnapshot: base.appSnapshot,
            generatedAt: Date(),
            memoryCacheCount: memoryCacheCount,
            databaseCacheCount: base.databaseCount,
            databaseCacheCorrupted: base.databaseCorrupted,
            appGroupAvailable: base.appGroupAvailable,
            appGroupItemCount: base.appGroupItemCount,
            appGroupBytes: base.appGroupBytes,
            appGroupLastWriteAt: base.appGroupLastWriteAt,
            widgetLastSyncAt: base.widgetLastSyncAt,
            watchState: watchState,
            cacheHitStatsAvailable: false
        )
    }

    @MainActor
    private static func currentMemoryCacheCount() -> Int {
        let manager = HealthDataManager.shared
        var count = 0
        if manager.currentActivity != nil { count += 1 }
        if manager.currentStress != nil { count += 1 }
        if manager.currentSleep != nil { count += 1 }
        if manager.realtimeHealth != nil { count += 1 }
        return count
    }

    @MainActor
    private static func currentWatchState() -> CacheWatchSyncState {
        let service = WatchConnectivitySyncService.shared
        let activationText: String
        switch service.watchActivationState {
        case .notSupported:
            activationText = String(localized: "不支持")
        case .notActivated:
            activationText = String(localized: "未激活")
        case .inactive:
            activationText = String(localized: "未连接")
        case .activated:
            activationText = String(localized: "已连接")
        }
        return CacheWatchSyncState(
            isPaired: service.isWatchPaired,
            isInstalled: service.isWatchAppInstalled,
            isReachable: service.isWatchReachable,
            activationText: activationText,
            lastSyncAt: service.lastWatchSyncDate
        )
    }

    private static func gatherBaseStats() -> CacheBaseStats {
        let appSnapshot = AppDataCacheManager.shared.snapshot()
        let sharedDefaults = AppGroupManager.userDefaults()
        let widgetCategory = appSnapshot.category(.sharedWidgetSnapshots)

        let lastWriteRaw = sharedDefaults?.object(forKey: AppGroupSnapshotStore.lastSnapshotWriteKey)
        let lastWriteAt: Date?
        switch lastWriteRaw {
        case let date as Date:
            lastWriteAt = date
        case let interval as TimeInterval:
            lastWriteAt = Date(timeIntervalSince1970: interval)
        case let number as NSNumber:
            lastWriteAt = Date(timeIntervalSince1970: number.doubleValue)
        default:
            lastWriteAt = nil
        }

        let outboxState = LocalSyncOutbox.shared.storageState()
        let databaseCount: Int?
        let databaseCorrupted: Bool
        switch outboxState {
        case .healthy(let count):
            databaseCount = count
            databaseCorrupted = false
        case .corrupted:
            databaseCount = nil
            databaseCorrupted = true
        }

        return CacheBaseStats(
            appSnapshot: appSnapshot,
            databaseCount: databaseCount,
            databaseCorrupted: databaseCorrupted,
            appGroupAvailable: sharedDefaults != nil,
            appGroupItemCount: widgetCategory.itemCount,
            appGroupBytes: widgetCategory.totalBytes,
            appGroupLastWriteAt: lastWriteAt,
            widgetLastSyncAt: AppGroupManager.shared.getLastSyncTime()
        )
    }

    private struct CacheBaseStats: Sendable {
        let appSnapshot: AppDataCacheSnapshot
        let databaseCount: Int?
        let databaseCorrupted: Bool
        let appGroupAvailable: Bool
        let appGroupItemCount: Int
        let appGroupBytes: Int
        let appGroupLastWriteAt: Date?
        let widgetLastSyncAt: Date?
    }
}
