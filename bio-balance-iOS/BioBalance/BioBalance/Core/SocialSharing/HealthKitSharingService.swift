import Foundation
import HealthKit

enum SharedHealthSnapshotSource: Sendable {
    case fresh
    case cacheFallback
    case none
}

struct SharedHealthSnapshotBuildResult: Sendable {
    let permissionState: SharedHealthPermissionState
    let sleepAccess: HealthMetricAccessState
    let walkingAccess: HealthMetricAccessState
    let locationAccess: HealthMetricAccessState
    let snapshot: SharedHealthSnapshot?
    let syncState: SharedHealthSyncState
    let source: SharedHealthSnapshotSource
    let detailText: String
}

@MainActor
final class HealthKitSharingService {
    static let shared = HealthKitSharingService()

    private enum CacheKeys {
        static let snapshot = "social.sharing.health.snapshot.v1"
        static let permission = "social.sharing.friend-permission.v1"
    }

    private let manager: HealthKitManager
    private let locationService: LocationSharingService
    private let extrasBuilder: SocialShareExtrasBuilder
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        manager: HealthKitManager? = nil,
        locationService: LocationSharingService? = nil,
        extrasBuilder: SocialShareExtrasBuilder? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.manager = manager ?? .shared
        self.locationService = locationService ?? .shared
        self.extrasBuilder = extrasBuilder ?? SocialShareExtrasBuilder()
        self.defaults = defaults
        HealthAuthorizationPreferences.migrateIfNeeded(defaults: defaults)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func permissionSummary() -> (permission: SharedHealthPermissionState, sleep: HealthMetricAccessState, walking: HealthMetricAccessState, location: HealthMetricAccessState) {
        let location = locationService.accessState
        guard manager.isHealthDataSupported() else {
            return (.unavailable, .unavailable, .unavailable, location)
        }

        let hasRequestedReadAuthorization = HealthAuthorizationPreferences.hasCompletedFlow(defaults: defaults)
        let sleep: HealthMetricAccessState = hasRequestedReadAuthorization ? .authorized : .unauthorized
        let walking: HealthMetricAccessState = hasRequestedReadAuthorization ? .authorized : .unauthorized
        let permission: SharedHealthPermissionState
        switch (sleep, walking) {
        case (.authorized, .authorized):
            permission = .ready
        case (.unauthorized, .unauthorized):
            permission = .needsPermission
        default:
            permission = .partialPermission
        }

        return (permission, sleep, walking, location)
    }

    func requestAuthorization() async throws {
        try await manager.requestAuthorization()
        HealthAuthorizationPreferences.markFlowCompleted(defaults: defaults)
        if defaults.bool(forKey: SocialSharingDataPolicy.approximateLocationSharingEnabledKey) {
            _ = await locationService.requestAuthorizationIfNeeded()
        }
    }

    func lastCachedSnapshot() -> SharedHealthSnapshot? {
        guard let data = defaults.data(forKey: CacheKeys.snapshot) else {
            return nil
        }
        return try? decoder.decode(SharedHealthSnapshot.self, from: data)
    }

    func clearCachedSnapshot() {
        defaults.removeObject(forKey: CacheKeys.snapshot)
    }

    func sharePermission() -> FriendSharePermission {
        guard let data = defaults.data(forKey: CacheKeys.permission),
              let permission = try? decoder.decode(FriendSharePermission.self, from: data) else {
            return .conservativeDefault
        }
        return permission
    }

    func saveSharePermission(_ permission: FriendSharePermission) {
        guard let data = try? encoder.encode(permission) else { return }
        defaults.set(data, forKey: CacheKeys.permission)
        if let cached = lastCachedSnapshot() {
            persist(permission.filtering(cached))
        }
    }

    func buildMyShareSnapshot(days: Int = 7, displayName: String? = nil) async -> SharedHealthSnapshotBuildResult {
        let summary = permissionSummary()
        guard summary.permission != .unavailable else {
            return SharedHealthSnapshotBuildResult(
                permissionState: .unavailable,
                sleepAccess: summary.sleep,
                walkingAccess: summary.walking,
                locationAccess: summary.location,
                snapshot: nil,
                syncState: .failed,
                source: .none,
                detailText: "当前设备不支持 HealthKit，暂时无法生成可共享摘要。"
            )
        }

        guard summary.sleep == .authorized || summary.walking == .authorized else {
            let cached = sanitizeCachedSnapshotForCurrentPolicy()
            return SharedHealthSnapshotBuildResult(
                permissionState: .needsPermission,
                sleepAccess: summary.sleep,
                walkingAccess: summary.walking,
                locationAccess: summary.location,
                snapshot: cached,
                syncState: cached == nil ? .idle : .stale,
                source: cached == nil ? .none : .cacheFallback,
                detailText: "需要允许读取睡眠或步速，才能生成好友可见的健康摘要；粗略位置是独立的可选共享。"
            )
        }

        async let sleepResult = loadSleepSummaries(days: days, authorized: summary.sleep == .authorized)
        async let walkingResult = loadWalkingPoints(days: days, authorized: summary.walking == .authorized)
        let shouldShareApproximateLocation = defaults.bool(
            forKey: SocialSharingDataPolicy.approximateLocationSharingEnabledKey
        )
        async let locationResult: SharedLocationSummary? = shouldShareApproximateLocation
            ? locationService.fetchCurrentSummaryIfAuthorized()
            : nil

        let resolvedSleep = await sleepResult
        let resolvedWalking = await walkingResult
        let resolvedLocation = await locationResult

        let snapshot = Self.makeSnapshot(
            ownerDisplayName: Self.resolveDisplayName(override: displayName),
            sleepSummaries: resolvedSleep.values,
            walkingPoints: resolvedWalking.values,
            location: resolvedLocation,
            permissionState: summary.permission,
            days: max(days, 1),
            extras: extrasBuilder.build(referenceDate: Date())
        ).map { sharePermission().filtering($0) }

        if let snapshot {
            persist(snapshot)
            return SharedHealthSnapshotBuildResult(
                permissionState: summary.permission,
                sleepAccess: summary.sleep,
                walkingAccess: summary.walking,
                locationAccess: summary.location,
                snapshot: snapshot,
                syncState: .synced,
                source: .fresh,
                detailText: Self.detailText(for: snapshot)
            )
        }

        let hadReadFailure = resolvedSleep.failed || resolvedWalking.failed
        let cached = sanitizeCachedSnapshotForCurrentPolicy()
        let syncState: SharedHealthSyncState = hadReadFailure ? (cached == nil ? .failed : .stale) : (cached == nil ? .failed : .stale)
        let detailText: String
        if hadReadFailure {
            detailText = cached == nil ? "这次没能从健康数据读取成功，请稍后再试。" : "当前显示的是上次摘要，这次没能重新读取健康数据。"
        } else {
            detailText = cached == nil ? "最近没有可共享的睡眠、步速或位置摘要。" : "当前显示的是最近一次缓存的共享摘要。"
        }

        return SharedHealthSnapshotBuildResult(
            permissionState: summary.permission,
            sleepAccess: summary.sleep,
            walkingAccess: summary.walking,
            locationAccess: summary.location,
            snapshot: cached,
            syncState: syncState,
            source: cached == nil ? .none : .cacheFallback,
            detailText: detailText
        )
    }

    private func loadSleepSummaries(days: Int, authorized: Bool) async -> (values: [SleepTrendNightSummary], failed: Bool) {
        guard authorized else { return ([], false) }
        do {
            return (try await manager.fetchSleepNightSummaries(days: days), false)
        } catch {
            return ([], true)
        }
    }

    private func loadWalkingPoints(days: Int, authorized: Bool) async -> (values: [TimeSeriesPointDouble], failed: Bool) {
        guard authorized else { return ([], false) }
        do {
            return (try await manager.fetchDailyWalkingSpeedAverages(days: days), false)
        } catch {
            return ([], true)
        }
    }

    /// 读取本地摘要缓存时按当前位置共享偏好做隐私净化：位置共享关闭后，
    /// 任何缓存降级路径都不能再携带旧粗略位置，否则邀请 payload 或本地预览
    /// 会在用户已撤回位置同意后继续使用旧坐标。
    private func sanitizeCachedSnapshotForCurrentPolicy() -> SharedHealthSnapshot? {
        guard let cached = lastCachedSnapshot() else { return nil }
        let permissionFiltered = sharePermission().filtering(cached)
        let locationSharingEnabled = defaults.bool(
            forKey: SocialSharingDataPolicy.approximateLocationSharingEnabledKey
        )
        guard !locationSharingEnabled, permissionFiltered.location != nil else { return permissionFiltered }
        return permissionFiltered.removingLocation()
    }

    /// 位置共享关闭时立即清理本地摘要缓存中的旧粗略位置，作为防御性兜底：
    /// 即使后续健康读取失败、只能走缓存降级，也不会再次读到已撤回的位置。
    func clearCachedLocationIfSharingDisabled() {
        guard !defaults.bool(forKey: SocialSharingDataPolicy.approximateLocationSharingEnabledKey) else {
            return
        }
        guard let cached = lastCachedSnapshot(), cached.location != nil else { return }
        persist(cached.removingLocation())
    }

    private func persist(_ snapshot: SharedHealthSnapshot) {
        // 双保险：即使调用方意外传入带位置的快照，只要位置共享已关闭就剥离后再落缓存。
        let snapshotToPersist: SharedHealthSnapshot
        if !defaults.bool(forKey: SocialSharingDataPolicy.approximateLocationSharingEnabledKey),
           snapshot.location != nil {
            snapshotToPersist = snapshot.removingLocation()
        } else {
            snapshotToPersist = snapshot
        }
        guard let data = try? encoder.encode(snapshotToPersist) else { return }
        defaults.set(data, forKey: CacheKeys.snapshot)
    }

    static func resolveDisplayName(override: String?) -> String {
        if let override, !override.isEmpty {
            return override
        }

        let userInfo = UserInfoStore.load()
        if let nickname = userInfo.nickname, !nickname.isEmpty {
            return nickname
        }
        if let username = userInfo.username, !username.isEmpty {
            return username
        }
        return String(localized: "我")
    }

    nonisolated static func makeSnapshot(
        ownerDisplayName: String,
        sleepSummaries: [SleepTrendNightSummary],
        walkingPoints: [TimeSeriesPointDouble],
        location: SharedLocationSummary?,
        permissionState: SharedHealthPermissionState,
        days: Int,
        extras: SocialShareExtras
    ) -> SharedHealthSnapshot? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return nil
        }

        let sleepByDay = Dictionary(
            uniqueKeysWithValues: sleepSummaries.map { (calendar.startOfDay(for: $0.day), $0.asleepMinutes > 0 ? $0.asleepMinutes : nil) }
        )
        let walkingByDay = Dictionary(
            uniqueKeysWithValues: walkingPoints.map { (calendar.startOfDay(for: $0.date), $0.value > 0 ? $0.value : nil) }
        )

        let resolvedDays: [SharedHealthDay] = (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let normalized = calendar.startOfDay(for: day)
            return SharedHealthDay(
                date: normalized,
                sleepMinutes: sleepByDay[normalized] ?? nil,
                walkingSpeedMps: walkingByDay[normalized] ?? nil
            )
        }

        let sleepValues = resolvedDays.compactMap(\.sleepMinutes)
        let walkingValues = resolvedDays.compactMap(\.walkingSpeedMps)

        let highlights = SharedHealthHighlights(
            averageSleepMinutes: sleepValues.isEmpty ? nil : Int((Double(sleepValues.reduce(0, +)) / Double(sleepValues.count)).rounded()),
            averageWalkingSpeedMps: walkingValues.isEmpty ? nil : walkingValues.reduce(0, +) / Double(walkingValues.count),
            validSleepDays: sleepValues.count,
            validWalkingSpeedDays: walkingValues.count
        )

        return SharedHealthSnapshot(
            ownerUserID: nil,
            ownerDisplayName: ownerDisplayName,
            generatedAt: Date(),
            days: resolvedDays,
            highlights: highlights,
            location: location,
            payloadVersion: 3,
            sharedActionRecords: extras.actionRecords,
            sharedCountdownItems: extras.countdownItems,
            sharedTodoListSummary: extras.todoListSummary
        )
    }

    private static func detailText(for snapshot: SharedHealthSnapshot) -> String {
        let extrasText: String
        let hasAction = !snapshot.sharedActionRecords.isEmpty
        let hasCountdown = !snapshot.sharedCountdownItems.isEmpty
        let hasTodo = (snapshot.sharedTodoListSummary?.itemCount ?? 0) > 0
        let sharedComponents = [
            hasAction ? "行动记录" : nil,
            hasCountdown ? "倒数日" : nil,
            hasTodo ? "共享待办" : nil
        ].compactMap { $0 }
        extrasText = sharedComponents.isEmpty ? "" : "，以及你手动共享的" + sharedComponents.joined(separator: "、")

        if snapshot.highlights.validSleepDays == 0 && snapshot.highlights.validWalkingSpeedDays == 0 {
            return String(localized: "健康共享已准备好，最近 7 天暂时没有睡眠或步速样本；邀请仍可发送，后续数据会自动补充。")
        }
        if snapshot.highlights.validWalkingSpeedDays > 0 && snapshot.highlights.validWalkingSpeedDays < 3 {
            return String(localized: "近 7 天步速样本较少，展示结果更适合看趋势而不是做精确比较。共享内容仍只包含健康摘要\(extrasText)。")
        }
        if snapshot.highlights.validSleepDays == 0 {
            return String(localized: "当前只同步到步速摘要，睡眠摘要会在 Health 中有可读记录后补上。")
        }
        if snapshot.highlights.validWalkingSpeedDays == 0 {
            return String(localized: "当前只同步到睡眠摘要，步速没有样本时不会用 0 代替。")
        }
        if snapshot.location != nil {
            return String(localized: "我们只共享最近 7 天的睡眠、步速摘要、你确认后的粗略位置\(extrasText)，不包含原始 Health 明细或位置轨迹。")
        }
        return String(localized: "我们只共享最近 7 天的睡眠、步速摘要和可选粗略位置\(extrasText)，不包含原始 Health 明细或位置轨迹。")
    }
}
