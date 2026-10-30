/// Health Authorization Coordinator 负责应用启动阶段的 HealthKit 授权检测与统一调度，
/// 把「弹窗是否可用、数据是否可读、是否需要刷新」收敛成一个可观察状态供各页面消费。
import Foundation
import HealthKit
import UIKit

/// 健康授权流程的本地状态只记录“系统授权流程已完成”，不推断具体读取权限。
/// HealthKit 为保护隐私不会公开读取权限结果。
enum HealthAuthorizationPreferences {
    static let flowCompletedKey = "health.authorization.flow-completed.v2"

    private static let oldOnboardingKey = "onboarding_permission_health"
    private static let oldSocialRequestKey = "social.sharing.health.authorizationRequested.v1"

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: flowCompletedKey) == nil,
           defaults.bool(forKey: oldOnboardingKey) || defaults.bool(forKey: oldSocialRequestKey) {
            defaults.set(true, forKey: flowCompletedKey)
        }
        defaults.removeObject(forKey: oldOnboardingKey)
        defaults.removeObject(forKey: oldSocialRequestKey)
    }

    static func markFlowCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: flowCompletedKey)
        defaults.removeObject(forKey: oldOnboardingKey)
        defaults.removeObject(forKey: oldSocialRequestKey)
    }

    static func hasCompletedFlow(defaults: UserDefaults = .standard) -> Bool {
        migrateIfNeeded(defaults: defaults)
        return defaults.bool(forKey: flowCompletedKey)
    }
}

/// 健康授权阶段枚举 作为健康数据能力层里的状态与分类定义。
/// 负责描述启动检测后授权与数据可用性的组合状态。
enum HealthAuthorizationPhase: Equatable {
    /// 尚未完成首次评估。
    case unknown
    /// 设备不支持 HealthKit（例如部分模拟器）。
    case unavailable
    /// 系统授权弹窗仍然可用（首次授权，或版本更新新增了数据类型需要补授权）。
    case promptAvailable
    /// 已授权且数据在刷新窗口内，可直接使用。
    case authorizedFresh
    /// 已授权但数据超过刷新阈值，需要重新同步。
    case authorizedNeedsRefresh
    /// 已完成授权流程但读探针取不到任何样本（读权限被关或数据源为空）。
    case authorizedNoData
    /// 是否可以按「已授权」对待（数据管线可以继续跑）。
    var isAuthorizedLike: Bool {
        switch self {
        case .authorizedFresh, .authorizedNeedsRefresh, .authorizedNoData:
            return true
        case .unknown, .unavailable, .promptAvailable:
            return false
        }
    }
}

/// 健康授权协调器 作为健康数据能力层里的服务或调度入口。
/// 负责启动时授权状态评估、回前台重评估、授权发起去重与设置页跳转引导。
@MainActor
@Observable
final class HealthAuthorizationCoordinator {
    static let shared = HealthAuthorizationCoordinator()

    private(set) var phase: HealthAuthorizationPhase = .unknown
    private(set) var lastEvaluatedAt: Date?
    /// 是否正在走系统授权弹窗，用于防止重复触发授权请求。
    private(set) var isRequestingAuthorization = false

    private let healthKit = HealthKitManager.shared
    /// 数据刷新阈值：超过该间隔视为「已授权但数据需要刷新」。
    private let dataRefreshInterval: TimeInterval = 15 * 60
    /// 回前台重评估的节流间隔，避免频繁探针查询。
    private let foregroundEvaluateThrottle: TimeInterval = 60
    private var pendingSettingsReturn = false
    private var isEvaluating = false

    private static let lastDataRefreshAtKey = "health_auth_last_data_refresh_at"

    private init() {
        HealthAuthorizationPreferences.migrateIfNeeded()
    }

    // MARK: - 入口

    /// 应用启动时调用：完成一次完整的授权 + 数据可用性评估。
    func evaluateAtLaunch() async {
        await evaluate()
    }

    /// 回到前台时调用：默认按节流间隔重评估；
    /// 从系统设置/健康 App 返回时立即重评，保证用户改动权限后状态第一时间纠正。
    func handleScenePhaseActive() async {
        if pendingSettingsReturn {
            pendingSettingsReturn = false
            // 用户可能在健康 App/系统设置中改过权限，旧派生缓存一律不得命中。
            HealthKitRepositoryCache.shared.invalidateAll()
            await evaluate()
            return
        }
        if let lastEvaluatedAt, Date().timeIntervalSince(lastEvaluatedAt) < foregroundEvaluateThrottle {
            return
        }
        await evaluate()
    }

    // MARK: - 状态评估

    /// 完整评估流程：
    /// 1. 设备是否支持 HealthKit；
    /// 2. 系统弹窗是否还能触发（shouldRequest / unnecessary）；
    /// 3. 弹窗已消耗时用读探针区分「数据可读 / 取不到数据」，
    ///    读取权限状态不可查询，因此无样本统一按「授权流程完成但暂无数据」处理。
    func evaluate() async {
        guard !isEvaluating else { return }
        isEvaluating = true
        defer {
            isEvaluating = false
            lastEvaluatedAt = Date()
        }

        guard healthKit.isHealthDataSupported() else {
            phase = .unavailable
            return
        }

        let requestStatus = await healthKit.fullAuthorizationRequestStatus()
        switch requestStatus {
        case .shouldRequest:
            // 首次启动或版本更新新增了数据类型，系统弹窗仍然可用。
            phase = .promptAvailable
        case .unnecessary:
            phase = await resolveDeterminedPhase()
        case .unknown:
            // 状态查询失败时保守处理：能读到数据就按已授权继续；
            // 探针也失败则维持原状态等下次评估，不强判 authorizedNoData，
            // 避免把临时查询失败误报成“已授权但无数据”。
            if await healthKit.probeReadableSampleExists(withinDays: 7) {
                phase = isDataStale ? .authorizedNeedsRefresh : .authorizedFresh
            }
        @unknown default:
            break
        }

        applySideEffects(for: phase)
    }

    // MARK: - 授权发起

    /// 从页面发起授权，返回评估后的最新阶段。
    /// - 弹窗可用时才真正调起系统弹窗（isRequestingAuthorization 防止重复触发）；
    /// - 弹窗已消耗时不再空调 requestAuthorization（系统不会再显示任何界面），
    ///   而是重新评估一次并把结果交回调用方。
    @discardableResult
    func requestAuthorizationIfNeeded() async -> HealthAuthorizationPhase {
        guard !isRequestingAuthorization else { return phase }

        if phase == .unknown {
            await evaluate()
        }

        switch phase {
        case .promptAvailable:
            isRequestingAuthorization = true
            do {
                try await healthKit.requestAuthorization()
                healthKit.registerObserversIfNeeded()
            } catch {
                // 用户取消或系统错误：不中断流程，靠随后的评估纠正状态。
            }
            isRequestingAuthorization = false
            await evaluate()
        case .authorizedNeedsRefresh, .authorizedNoData:
            // 覆盖用户刚在健康 App 里改完权限又回到页面重试的场景。
            await evaluate()
        case .unknown, .unavailable, .authorizedFresh:
            break
        }

        return phase
    }

    /// 打开系统授权设置：优先跳健康 App，失败时退回本 App 的系统设置页。
    /// 标记 pendingSettingsReturn，回前台时立即重评估。
    func openHealthSettings() {
        pendingSettingsReturn = true
        Task { @MainActor in
            if let healthURL = URL(string: "x-apple-health://") {
                let opened = await UIApplication.shared.open(healthURL)
                if opened { return }
            }
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                _ = await UIApplication.shared.open(settingsURL)
            }
        }
    }

    // MARK: - 内部实现

    /// 弹窗已消耗后的细分判定。
    private func resolveDeterminedPhase() async -> HealthAuthorizationPhase {
        let hasReadableSample = await healthKit.probeReadableSampleExists(withinDays: 7)
        if hasReadableSample {
            return isDataStale ? .authorizedNeedsRefresh : .authorizedFresh
        }

        // HealthKit 为保护隐私不公开读取授权结果。没有样本既可能是用户拒绝读取，
        // 也可能只是设备尚未产生数据，不能用无关的写入权限反推读取权限。
        return .authorizedNoData
    }

    /// 按评估结果落地处理机制：已授权时注册观察者并按需触发同步。
    private func applySideEffects(for phase: HealthAuthorizationPhase) {
        switch phase {
        case .authorizedFresh:
            healthKit.registerObserversIfNeeded()
            HealthDataManager.shared.syncAllDataIfNeeded()
        case .authorizedNeedsRefresh:
            // 已授权但数据超期：强制同步一次，并记录刷新时间避免重复强刷。
            healthKit.registerObserversIfNeeded()
            HealthDataManager.shared.syncAllDataIfNeeded(force: true)
            markDataRefreshed()
        case .authorizedNoData:
            // 授权流程已完成但读不到数据：保持观察者注册，等数据源出现后自动恢复。
            healthKit.registerObserversIfNeeded()
        case .unknown, .unavailable, .promptAvailable:
            break
        }
    }

    private var isDataStale: Bool {
        guard let lastRefreshAt = UserDefaults.standard.object(forKey: Self.lastDataRefreshAtKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastRefreshAt) > dataRefreshInterval
    }

    private func markDataRefreshed() {
        UserDefaults.standard.set(Date(), forKey: Self.lastDataRefreshAtKey)
    }
}
